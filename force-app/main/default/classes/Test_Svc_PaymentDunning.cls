@IsTest
private class Test_Svc_PaymentDunning {

    // Stripe answers come from Svc_PaymentIntent.mockResponses (stripeGC's callout can't be mocked). The batches'
    // executeBatch is called directly so the mocks of this transaction apply.

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        Account acc = Test_Data.createAccount('Dunning Test BV', '9071', 'B2B', false);
        insert acc;
        // rbb_Account wipes PayProv_* ids on a brand-new Account - set them with a separate update;
        // a saved card keeps rbb_Payment from turning the payment into Setup
        acc.PayProv_CustomerId__c        = 'cus_dun001';
        acc.PayProv_PaymentMethodId__c   = 'pm_dun001';
        acc.PayProv_PaymentMethodType__c = 'card';
        Database.update(acc, AccessLevel.SYSTEM_MODE);

        Contact c = new Contact(AccountId = acc.Id, FirstName = 'Dirk', LastName = 'Dunning', Email = 'dirk.dunning@example.com');
        insert c;
        AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :c.Id];
        acr.Roles = 'Payment';
        update acr;

        stripeGC__Stripe_Account__c sa = new stripeGC__Stripe_Account__c(Name = 'Dunning Stripe');
        Database.insert(sa, AccessLevel.SYSTEM_MODE);
        Database.insert(new Business_Entities__c(Name = 'Netherlands (dunning test)', Reseller__c = '1',
            PayProv_Account__c = sa.Id, PayProv_DirectDebit_PaymentMethod__c = 'sepa_debit'), AccessLevel.SYSTEM_MODE);

        Database.insert(new List<Subscription25__Schedulable_Class__c>{
            new Subscription25__Schedulable_Class__c(Name = 'Batch_ProcessPayments', Subscription25__Unique_Name__c = 'Batch_ProcessPayments'),
            new Subscription25__Schedulable_Class__c(Name = 'Batch_CardExpiryCheck', Subscription25__Unique_Name__c = 'Batch_CardExpiryCheck')
        }, AccessLevel.SYSTEM_MODE);

        Payment__c p = new Payment__c(
            Account__c         = acc.Id,
            Administration__c  = admin.Id,
            Method__c          = 'pr',
            Type__c            = 'psp-recurring',
            Status__c          = 'Processing',
            externalId__c      = 'tok_dun',
            PayProv_PaymentIntentId__c = 'pi_dun001',
            CurrencyIsoCode    = 'EUR',
            Amount_Gross__c    = 30.00,
            Request_Date__c    = Date.today(),
            // rbb_Payment derives Collection_Date__c from the due date (minus the processing days)
            Due_Date__c        = Date.today()
        );
        Database.insert(p, AccessLevel.SYSTEM_MODE);
    }

    // ── helpers ───────────────────────────────────────────────────────────────
    private static Payment__c payment() {
        return [SELECT Id, Name, Status__c, Type__c, externalId__c, Account__c, Dunning_Step__c, Dunning_Action__c,
                       Retry_Date__c, Suspension_Date__c, Failure_Code__c, PayProv_PaymentIntentId__c, Card_Renewal_Requested__c
                FROM Payment__c WHERE externalId__c = 'tok_dun' OR Type__c = 'psp-recurring' WITH SYSTEM_MODE LIMIT 1];
    }

    private static Account account() {
        return [SELECT Id, PayProv_PaymentMethodId__c, PayProv_MandateId__c, PayProv_CardExpiry__c, PayProv_CardWallet__c
                FROM Account WHERE Name = 'Dunning Test BV' WITH SYSTEM_MODE];
    }

    private static void setPayment(Map<String, Object> values) {
        Payment__c u = new Payment__c(Id = payment().Id);
        for (String f : values.keySet()) u.put(f, values.get(f));
        Database.update(u, AccessLevel.SYSTEM_MODE);
    }

    private static stripeGC__Stripe_Event__c failedEvent(Id paymentId, String intentId, String code, String declineCode, String methodId) {
        Map<String, Object> err = new Map<String, Object>{ 'code' => code, 'message' => 'declined' };
        if (declineCode != null) err.put('decline_code', declineCode);
        return new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'payment_intent.payment_failed',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id' => intentId, 'status' => 'requires_payment_method', 'customer' => 'cus_dun001',
                        'payment_method' => methodId, 'metadata' => new Map<String, Object>{ 'PaymentID' => paymentId },
                        'last_payment_error' => err
                    }
                }
            })
        );
    }

    private static Svc_PaymentDunning.Request request(Id paymentId, String mode, String step) {
        Svc_PaymentDunning.Request r = new Svc_PaymentDunning.Request();
        r.paymentId = paymentId;
        r.mode      = mode;
        r.step      = step;
        return r;
    }

    // ── classification ────────────────────────────────────────────────────────
    @IsTest
    static void testFailureCodeAndPermanence() {
        System.assertEquals('insufficient_funds', Svc_PaymentDunning.failureCode('card_declined', 'insufficient_funds'));
        System.assertEquals('insufficient_funds', Svc_PaymentDunning.failureCode('insufficient_funds', 'generic_decline'), 'Bacs: the code is the reason');
        System.assertEquals('expired_card', Svc_PaymentDunning.failureCode('expired_card', null));
        System.assert(Svc_PaymentDunning.isPermanent('card_declined', 'lost_card'));
        System.assert(Svc_PaymentDunning.isPermanent('account_closed', null));
        System.assert(!Svc_PaymentDunning.isPermanent('card_declined', 'insufficient_funds'));
        System.assert(!Svc_PaymentDunning.isPermanent('authentication_required', 'authentication_required'));
    }

    @IsTest
    static void testNextStepSequence() {
        Payment__c p = payment();
        Payment__c first = Svc_PaymentDunning.next(p, 'card_declined', 'insufficient_funds', false, 'pi_x');
        System.assertEquals(Svc_PaymentDunning.STEP_RETRY, first.Dunning_Step__c);
        System.assertEquals(Date.today().addDays(Svc_PaymentDunning.RETRY_DAYS), first.Retry_Date__c);

        p.Dunning_Step__c = Svc_PaymentDunning.STEP_RETRY;
        Payment__c second = Svc_PaymentDunning.next(p, 'card_declined', 'insufficient_funds', false, 'pi_x');
        System.assertEquals(Svc_PaymentDunning.STEP_REQUESTED, second.Dunning_Step__c);
        System.assertEquals(Svc_PaymentDunning.ACTION_PAY, second.Dunning_Action__c);
        System.assertEquals(null, second.Retry_Date__c);

        p.Dunning_Step__c = Svc_PaymentDunning.STEP_REQUESTED;
        Payment__c third = Svc_PaymentDunning.next(p, 'insufficient_funds', null, false, 'pi_x');
        System.assertEquals(Svc_PaymentDunning.STEP_FINAL, third.Dunning_Step__c);
        System.assertEquals(Date.today().addDays(Svc_PaymentDunning.SUSPENSION_DAYS), third.Suspension_Date__c);

        p.Dunning_Step__c = null;
        System.assertEquals(Svc_PaymentDunning.STEP_REQUESTED, Svc_PaymentDunning.next(p, null, null, true, 'pi_x').Dunning_Step__c, 'A reversal is not retried');

        p.Type__c = 'psp-immediate';
        System.assertEquals(null, Svc_PaymentDunning.next(p, 'card_declined', 'insufficient_funds', false, 'pi_x'), 'Only collected payments');
    }

    // ── webhook: temporary failure → retry planned, no Case, the method stays ──
    @IsTest
    static void testTemporaryFailurePlansRetry() {
        Payment__c p = payment();
        Test.startTest();
        insert failedEvent(p.Id, 'pi_dun001', 'card_declined', 'insufficient_funds', 'pm_dun001');
        Test.stopTest();

        Payment__c after = payment();
        System.assertEquals('Failed', after.Status__c);
        System.assertEquals(Svc_PaymentDunning.STEP_RETRY, after.Dunning_Step__c);
        System.assertEquals(Date.today().addDays(4), after.Retry_Date__c);
        System.assertEquals('insufficient_funds', after.Failure_Code__c);
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE AccountId = :p.Account__c], 'No Case: the customer is mailed');
        System.assertEquals('pm_dun001', account().PayProv_PaymentMethodId__c);
    }

    // ── webhook: the same failure again (redelivery) does not move the step ──
    @IsTest
    static void testRepeatedFailureKeepsStep() {
        Payment__c p = payment();
        insert failedEvent(p.Id, 'pi_dun001', 'card_declined', 'insufficient_funds', 'pm_dun001');
        Test.startTest();
        insert failedEvent(p.Id, 'pi_dun001', 'card_declined', 'insufficient_funds', 'pm_dun001');
        Test.stopTest();
        System.assertEquals(Svc_PaymentDunning.STEP_RETRY, payment().Dunning_Step__c);
    }

    // ── webhook: permanent failure → no retry, method cleared, not restored by the event ──
    @IsTest
    static void testPermanentFailureClearsMethod() {
        Payment__c p = payment();
        Test.startTest();
        insert failedEvent(p.Id, 'pi_dun001', 'expired_card', null, 'pm_dun001');
        Test.stopTest();

        Payment__c after = payment();
        System.assertEquals(Svc_PaymentDunning.STEP_REQUESTED, after.Dunning_Step__c);
        System.assertEquals(Svc_PaymentDunning.ACTION_RENEW, after.Dunning_Action__c);
        System.assertEquals(null, account().PayProv_PaymentMethodId__c, 'The refused card is cleared');
    }

    // ── webhook: the retry fails → Payment Requested ──
    @IsTest
    static void testRetryFailureRequestsPayment() {
        // the batch stored the retry's PaymentIntent on the payment
        setPayment(new Map<String, Object>{ 'Dunning_Step__c' => Svc_PaymentDunning.STEP_RETRY, 'Status__c' => 'Processing',
            'PayProv_PaymentIntentId__c' => 'pi_dun002' });
        Payment__c p = payment();
        Test.startTest();
        insert failedEvent(p.Id, 'pi_dun002', 'insufficient_funds', 'generic_decline', 'pm_dun001');
        Test.stopTest();
        Payment__c after = payment();
        System.assertEquals(Svc_PaymentDunning.STEP_REQUESTED, after.Dunning_Step__c);
        System.assertEquals(Svc_PaymentDunning.ACTION_PAY, after.Dunning_Action__c);
    }

    // ── a failed first checkout on the payment page (setup_future_usage) or a failed setup: no dunning, the Case stays ──
    @IsTest
    static void testFirstCheckoutFailureKeepsCase() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'New' });
        Payment__c p = payment();
        stripeGC__Stripe_Event__c checkout = failedEvent(p.Id, 'pi_dun001', 'card_declined', 'insufficient_funds', 'pm_new');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(checkout.stripeGC__Request_Body__c);
        ((Map<String, Object>) ((Map<String, Object>) body.get('data')).get('object')).put('setup_future_usage', 'off_session');
        checkout.stripeGC__Request_Body__c = JSON.serialize(body);
        stripeGC__Stripe_Event__c setup = new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'setup_intent.setup_failed',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{ 'data' => new Map<String, Object>{
                'object' => new Map<String, Object>{ 'id' => 'seti_dun', 'status' => 'requires_payment_method', 'customer' => 'cus_dun001',
                    'metadata' => new Map<String, Object>{ 'PaymentID' => p.Id },
                    'last_setup_error' => new Map<String, Object>{ 'code' => 'card_declined', 'message' => 'declined' } } } })
        );
        Test.startTest();
        insert checkout;
        Test.stopTest();

        Payment__c after = payment();
        System.assertEquals('Failed', after.Status__c);
        System.assertEquals(null, after.Dunning_Step__c, 'No saved method to retry with: not a collection');
        System.assertEquals(1, [SELECT COUNT() FROM Case WHERE AccountId = :p.Account__c], 'The failure Case as before');

        setPayment(new Map<String, Object>{ 'Status__c' => 'New' });
        insert setup;
        System.assertEquals(null, payment().Dunning_Step__c, 'A failed setup is no collection either');
    }

    // ── an accepted debit from the payment page that fails days later is a collection failure ──
    @IsTest
    static void testAcceptedPageDebitFailureStartsDunning() {
        Payment__c p = payment();
        stripeGC__Stripe_Event__c e = failedEvent(p.Id, 'pi_dun001', 'insufficient_funds', 'generic_decline', 'pm_dun001');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(e.stripeGC__Request_Body__c);
        ((Map<String, Object>) ((Map<String, Object>) body.get('data')).get('object')).put('setup_future_usage', 'off_session');
        e.stripeGC__Request_Body__c = JSON.serialize(body);
        Test.startTest();
        insert e;   // the payment is Processing
        Test.stopTest();
        System.assertEquals(Svc_PaymentDunning.STEP_RETRY, payment().Dunning_Step__c);
    }

    // ── flow steps: advance only while still open and on the expected step; the Case once ──
    @IsTest
    static void testAdvanceAndSuspensionCase() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_REQUESTED,
            'Dunning_Action__c' => Svc_PaymentDunning.ACTION_PAY });
        Payment__c p = payment();

        Test.startTest();
        // outdated interview: the payment is not on Retry Planned
        Svc_PaymentDunning.run(new List<Svc_PaymentDunning.Request>{ request(p.Id, Svc_PaymentDunning.MODE_ADVANCE, Svc_PaymentDunning.STEP_RETRY) });
        System.assertEquals(Svc_PaymentDunning.STEP_REQUESTED, payment().Dunning_Step__c);

        Svc_PaymentDunning.run(new List<Svc_PaymentDunning.Request>{ request(p.Id, Svc_PaymentDunning.MODE_ADVANCE, Svc_PaymentDunning.STEP_REQUESTED) });
        System.assertEquals(Svc_PaymentDunning.STEP_FINAL, payment().Dunning_Step__c);
        System.assertEquals(Date.today().addDays(5), payment().Suspension_Date__c);

        Svc_PaymentDunning.run(new List<Svc_PaymentDunning.Request>{ request(p.Id, Svc_PaymentDunning.MODE_ADVANCE, Svc_PaymentDunning.STEP_FINAL) });
        System.assertEquals(Svc_PaymentDunning.STEP_SUSPENSION, payment().Dunning_Step__c);

        for (Integer i = 0; i < 2; i++) {
            Svc_PaymentDunning.run(new List<Svc_PaymentDunning.Request>{ request(p.Id, Svc_PaymentDunning.MODE_MAIL, Svc_PaymentDunning.STEP_SUSPENSION) });
        }
        Test.stopTest();

        List<Case> cases = [SELECT Subject, Description, ContactId FROM Case WHERE Subject = :Svc_PaymentDunning.suspensionSubject(p)];
        System.assertEquals(1, cases.size(), 'One suspension Case');
        System.assert(cases[0].Description.contains('still has to pay'), cases[0].Description);
        System.assertNotEquals(null, cases[0].ContactId);

        // paid afterwards: the agent is told on the Case
        Svc_PaymentDunning.notePaid(new List<Payment__c>{ payment() }, 'Paid');
        System.assert([SELECT Description FROM Case WHERE Id = :cases[0].Id].Description.contains('PAID: the customer has paid'));
    }

    // ── a paid payment is left alone ──
    @IsTest
    static void testPaidPaymentIgnored() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Paid', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_FINAL });
        Payment__c p = payment();
        Test.startTest();
        Svc_PaymentDunning.run(new List<Svc_PaymentDunning.Request>{
            request(p.Id, Svc_PaymentDunning.MODE_ADVANCE, Svc_PaymentDunning.STEP_FINAL),
            request(p.Id, Svc_PaymentDunning.MODE_MAIL, Svc_PaymentDunning.STEP_FINAL)
        });
        Test.stopTest();
        System.assertEquals(Svc_PaymentDunning.STEP_FINAL, payment().Dunning_Step__c);
        System.assertEquals(null, [SELECT AlertMessage__c FROM Payment__c WHERE Id = :p.Id WITH SYSTEM_MODE].AlertMessage__c, 'No mail attempt');
    }

    // ── mail: sent, or the reason on the payment ──
    @IsTest
    static void testMailStep() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_RETRY,
            'Dunning_Action__c' => Svc_PaymentDunning.ACTION_PAY, 'Retry_Date__c' => Date.today().addDays(4) });
        Payment__c p = payment();
        Test.startTest();
        Svc_PaymentDunning.run(new List<Svc_PaymentDunning.Request>{ request(p.Id, Svc_PaymentDunning.MODE_MAIL, Svc_PaymentDunning.STEP_RETRY) });
        Test.stopTest();
        String alert = [SELECT AlertMessage__c FROM Payment__c WHERE Id = :p.Id WITH SYSTEM_MODE].AlertMessage__c;
        System.assert(alert == null || alert.startsWith('Dunning email not sent'), alert);
    }

    // ── batch: the retry is collected with its own idempotency key; a decline moves it on, no Case ──
    @IsTest
    static void testBatchRetryDeclined() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_RETRY,
            'Dunning_Action__c' => Svc_PaymentDunning.ACTION_PAY, 'Retry_Date__c' => Date.today(), 'PayProv_PaymentIntentId__c' => null });
        Batch_ProcessPayments batch = new Batch_ProcessPayments();
        Database.QueryLocatorIterator it = batch.startBatch(null).iterator();
        List<Payment__c> scope = new List<Payment__c>();
        while (it.hasNext()) scope.add((Payment__c) it.next());
        System.assertEquals(1, scope.size(), 'The retry is selected');

        String decline = 'Stripe callout error: {"error":{"code":"card_declined","decline_code":"lost_card",'
            + '"payment_intent":{"id":"pi_retry"},"message":"Your card was declined."}}';
        Svc_PaymentIntent.mockResponses = new List<String>{ JSON.serialize(new Map<String, Object>{
            'error' => new Map<String, Object>{ 'message' => decline } }) };

        Test.startTest();
        batch.executeBatch(null, scope);
        Test.stopTest();

        System.assert(Svc_PaymentIntent.sentBodies[0].contains('POST /v1/payment_intents'), Svc_PaymentIntent.sentBodies[0]);
        Payment__c after = payment();
        System.assertEquals('Failed', after.Status__c);
        System.assertEquals(Svc_PaymentDunning.STEP_REQUESTED, after.Dunning_Step__c);
        System.assertEquals(Svc_PaymentDunning.ACTION_RENEW, after.Dunning_Action__c, 'lost card: renew');
        System.assertEquals('pi_retry', after.PayProv_PaymentIntentId__c);
        System.assertEquals(null, account().PayProv_PaymentMethodId__c);
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE AccountId = :after.Account__c]);
    }

    // ── payment page: waiting for the retry ──
    @IsTest
    static void testPageRetryScheduled() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_RETRY,
            'Retry_Date__c' => Date.newInstance(2030, 1, 5) });
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();
        System.assert(d.alreadyScheduled);
        System.assertEquals('retry', d.dunning);
        System.assertEquals('2030-01-05', d.collectionDate);
    }

    // ── payment page: pay now - the declined off-session intent is canceled, a pay-now intent created and stored ──
    @IsTest
    static void testPagePayNow() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_REQUESTED,
            'Dunning_Action__c' => Svc_PaymentDunning.ACTION_RENEW, 'Suspension_Date__c' => Date.newInstance(2030, 1, 10) });
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"pi_dun001","status":"requires_payment_method","metadata":{"PaymentID":"x"}}',
            '{"id":"pi_dun001","status":"canceled"}',
            '{"id":"pi_paynow","client_secret":"cs_paynow"}'
        };
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();

        System.assertEquals(null, d.errorMessage);
        System.assertEquals('renew', d.dunning);
        System.assertEquals('payment', d.mode);
        System.assertEquals('cs_paynow', d.clientSecret);
        System.assertEquals('2030-01-10', d.suspensionDate);
        System.assert(Svc_PaymentIntent.sentBodies[1].startsWith('POST /v1/payment_intents/pi_dun001/cancel'), Svc_PaymentIntent.sentBodies[1]);
        String create = Svc_PaymentIntent.sentBodies[2];
        // Renew: a renewal of the recurring method - direct debit + card, saved; no iDEAL or bank transfer
        System.assert(create.contains('setup_future_usage=off_session') && create.contains('metadata[Checkout]=paynow')
            && create.contains('payment_method_types[]=sepa_debit') && create.contains('payment_method_types[]=card'), create);
        System.assert(!create.contains('ideal') && !create.contains('customer_balance'), create);
        System.assertEquals('card', d.paymentMethodType, 'The customer had a card');
        System.assertEquals('pi_paynow', payment().PayProv_PaymentIntentId__c);
    }

    // ── payment page, Pay: card and iDEAL | Wero (its SEPA mandate) are saved, a bank transfer is one-off ──
    @IsTest
    static void testPagePayNowPaySavesCardAndIdeal() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_REQUESTED,
            'Dunning_Action__c' => Svc_PaymentDunning.ACTION_PAY, 'PayProv_PaymentIntentId__c' => null });
        Account acc = account();
        acc.BillingCountryCode = 'NL';
        Database.update(acc, AccessLevel.SYSTEM_MODE);
        Svc_PaymentIntent.mockResponses = new List<String>{ '{"id":"pi_paynow","client_secret":"cs_paynow"}' };
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();
        System.assertEquals('pay', d.dunning, 'Error: ' + d.errorMessage);
        String create = Svc_PaymentIntent.sentBodies[Svc_PaymentIntent.sentBodies.size() - 1];
        System.assert(create.contains('payment_method_types[]=ideal') && create.contains('payment_method_types[]=customer_balance'), create);
        System.assert(create.contains('payment_method_options[card][setup_future_usage]=off_session'), create);
        System.assert(create.contains('payment_method_options[ideal][setup_future_usage]=off_session'), create);
        System.assert(!create.contains('&setup_future_usage='), 'No top-level saving: the bank transfer stays one-off');
    }

    // ── a payment method the live Stripe account has not activated is left out, the link still works ──
    @IsTest
    static void testPayNowLeavesOutInactiveMethod() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_REQUESTED,
            'Dunning_Action__c' => Svc_PaymentDunning.ACTION_PAY, 'PayProv_PaymentIntentId__c' => null });
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"error":{"type":"invalid_request_error","message":"The payment method type \\"customer_balance\\" is invalid. Please ensure the provided type is activated in your dashboard."}}',
            '{"id":"pi_paynow","client_secret":"cs_paynow"}'
        };
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();
        System.assertEquals('cs_paynow', d.clientSecret, 'Error: ' + d.errorMessage);
        Integer n = Svc_PaymentIntent.sentBodies.size();
        System.assert(Svc_PaymentIntent.sentBodies[n - 2].contains('payment_method_types[]=customer_balance'), Svc_PaymentIntent.sentBodies[n - 2]);
        String retry = Svc_PaymentIntent.sentBodies[n - 1];
        System.assert(!retry.contains('customer_balance'), 'Type and its options left out: ' + retry);
        System.assert(retry.contains('payment_method_types[]=card'), retry);
    }

    // ── payment page: a second visit reuses the pay-now intent ──
    @IsTest
    static void testPagePayNowReused() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_FINAL,
            'PayProv_PaymentIntentId__c' => 'pi_paynow' });
        Payment__c withAccount = [SELECT CurrencyIsoCode, Dunning_Action__c, Account__r.BillingCountryCode FROM Payment__c WHERE Id = :payment().Id WITH SYSTEM_MODE];
        Svc_PaymentIntent.mockResponses = new List<String>{ JSON.serialize(new Map<String, Object>{
            'id' => 'pi_paynow', 'status' => 'requires_payment_method', 'client_secret' => 'cs_again',
            'metadata' => new Map<String, Object>{ 'Checkout' => 'paynow' },
            'payment_method_types' => Svc_PaymentIntent.payNowTypes(withAccount, 'sepa_debit'),
            'payment_method_options' => new Map<String, Object>{ 'ideal' => new Map<String, Object>{ 'setup_future_usage' => 'off_session' } } }) };
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();
        System.assertEquals('pay', d.dunning);
        System.assertEquals('cs_again', d.clientSecret);
        System.assertEquals(1, Svc_PaymentIntent.sentBodies.size(), 'Only the lookup');
    }

    // ── payment page: a pay-now intent waiting for the bank transfer shows the instructions, nothing new is created ──
    @IsTest
    static void testPagePayNowBankTransferWaiting() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_REQUESTED,
            'PayProv_PaymentIntentId__c' => 'pi_transfer' });
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"pi_transfer","status":"requires_action","metadata":{"Checkout":"paynow"},'
            + '"next_action":{"type":"display_bank_transfer_instructions","display_bank_transfer_instructions":{"hosted_instructions_url":"https://pay.stripe.com/instr"}}}'
        };
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();
        System.assertEquals('https://pay.stripe.com/instr', d.bankTransferUrl);
        System.assertEquals(1, Svc_PaymentIntent.sentBodies.size(), 'Only the lookup');
    }

    @IsTest
    static void testPayNowTypes() {
        Payment__c p = new Payment__c(CurrencyIsoCode = 'EUR', Account__r = new Account(BillingCountryCode = 'NL'));
        System.assertEquals(new List<String>{ 'card', 'ideal', 'customer_balance' }, Svc_PaymentIntent.payNowTypes(p, 'sepa_debit'));
        p = new Payment__c(CurrencyIsoCode = 'EUR', Account__r = new Account(BillingCountryCode = 'DE'));
        System.assertEquals(new List<String>{ 'card', 'customer_balance' }, Svc_PaymentIntent.payNowTypes(p, 'sepa_debit'));
        p = new Payment__c(CurrencyIsoCode = 'GBP', Account__r = new Account(BillingCountryCode = 'GB'));
        System.assertEquals(new List<String>{ 'card', 'customer_balance' }, Svc_PaymentIntent.payNowTypes(p, 'bacs_debit'));
        p = new Payment__c(CurrencyIsoCode = 'GBP', Dunning_Action__c = 'Renew', Account__r = new Account(BillingCountryCode = 'GB'));
        System.assertEquals(new List<String>{ 'bacs_debit', 'card' }, Svc_PaymentIntent.payNowTypes(p, 'bacs_debit'), 'Renew: no iDEAL or bank transfer');
    }

    // ── pay-now saves: a renewed direct debit with its mandate; iDEAL and a bank transfer save nothing ──
    @IsTest
    static void testPayNowRenewSavesDirectDebit() {
        Account acc = account();
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"pm_sepa_renew","type":"sepa_debit"}',
            '{"id":"pi_paynow","latest_charge":{"payment_method_details":{"type":"sepa_debit","sepa_debit":{"mandate":"mandate_renew"}}}}'
        };
        Test.startTest();
        new Svc_PaymentIntent.TypeJob(new Map<Id, String>{ acc.Id => 'pm_sepa_renew' }, new Map<Id, String>{ acc.Id => null },
            new Map<Id, String>{ acc.Id => 'pi_paynow' }, new Set<Id>{ acc.Id }).execute(null);
        Test.stopTest();
        Account after = [SELECT PayProv_PaymentMethodId__c, PayProv_MandateId__c, PayProv_PaymentMethodType__c FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE];
        System.assertEquals('pm_sepa_renew', after.PayProv_PaymentMethodId__c);
        System.assertEquals('mandate_renew', after.PayProv_MandateId__c);
        System.assertEquals('sepa_debit', after.PayProv_PaymentMethodType__c);
    }

    // iDEAL | Wero comes with a SEPA direct debit approval: its generated SEPA method + mandate collect the next invoices
    @IsTest
    static void testPayNowIdealSavesGeneratedSepa() {
        Account acc = account();
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"pm_ideal","type":"ideal"}',
            '{"id":"pi_paynow","latest_charge":{"payment_method_details":{"type":"ideal","ideal":{"generated_sepa_debit":"pm_gen_sepa","generated_sepa_debit_mandate":"mandate_gen"}}}}'
        };
        Test.startTest();
        new Svc_PaymentIntent.TypeJob(new Map<Id, String>{ acc.Id => 'pm_ideal' }, new Map<Id, String>{ acc.Id => null },
            new Map<Id, String>{ acc.Id => 'pi_paynow' }, new Set<Id>{ acc.Id }).execute(null);
        Test.stopTest();
        Account after = [SELECT PayProv_PaymentMethodId__c, PayProv_MandateId__c, PayProv_PaymentMethodType__c FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE];
        System.assertEquals('pm_gen_sepa', after.PayProv_PaymentMethodId__c);
        System.assertEquals('mandate_gen', after.PayProv_MandateId__c);
        System.assertEquals('sepa_debit', after.PayProv_PaymentMethodType__c);
    }

    @IsTest
    static void testPayNowIdealWithoutMandateSavesNothing() {
        Account acc = account();
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"pm_ideal","type":"ideal"}',
            '{"id":"pi_paynow","latest_charge":{"payment_method_details":{"type":"ideal","ideal":{}}}}'
        };
        Test.startTest();
        new Svc_PaymentIntent.TypeJob(new Map<Id, String>{ acc.Id => 'pm_ideal' }, new Map<Id, String>{ acc.Id => null },
            new Map<Id, String>{ acc.Id => 'pi_paynow' }, new Set<Id>{ acc.Id }).execute(null);
        Test.stopTest();
        System.assertEquals('pm_dun001', account().PayProv_PaymentMethodId__c, 'No generated SEPA: the saved method stays');
    }

    @IsTest
    static void testPayNowBankTransferSavesNothing() {
        Account acc = account();
        Svc_PaymentIntent.mockResponses = new List<String>{ '{"id":"pm_cb","type":"customer_balance"}' };
        Test.startTest();
        new Svc_PaymentIntent.TypeJob(new Map<Id, String>{ acc.Id => 'pm_cb' }, new Map<Id, String>{ acc.Id => null },
            new Map<Id, String>{ acc.Id => 'pi_paynow' }, new Set<Id>{ acc.Id }).execute(null);
        Test.stopTest();
        System.assertEquals('pm_dun001', account().PayProv_PaymentMethodId__c, 'The saved card stays');
    }

    // ── webhook: a pay-now payment never writes its method onto the Account directly ──
    @IsTest
    static void testPayNowEventDoesNotStoreMethodDirectly() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'Failed', 'Dunning_Step__c' => Svc_PaymentDunning.STEP_REQUESTED,
            'PayProv_PaymentIntentId__c' => 'pi_paynow' });
        Payment__c p = payment();
        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'payment_intent.succeeded',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{ 'data' => new Map<String, Object>{
                'object' => new Map<String, Object>{ 'id' => 'pi_paynow', 'status' => 'succeeded', 'customer' => 'cus_dun001',
                    'payment_method' => 'pm_cb', 'metadata' => new Map<String, Object>{ 'PaymentID' => p.Id, 'Checkout' => 'paynow' } } } })
        );
        Test.stopTest();
        System.assertEquals('Paid', payment().Status__c);
        System.assertEquals('pm_dun001', account().PayProv_PaymentMethodId__c);
    }

    // ── card details from Stripe ──
    @IsTest
    static void testApplyCardDetails() {
        Account u = new Account();
        Svc_PaymentIntent.applyCardDetails(u, (Map<String, Object>) JSON.deserializeUntyped(
            '{"type":"card","card":{"exp_month":2,"exp_year":2028}}'));
        System.assertEquals(Date.newInstance(2028, 2, 29), u.PayProv_CardExpiry__c);
        System.assertEquals(null, u.PayProv_CardWallet__c);

        Svc_PaymentIntent.applyCardDetails(u, (Map<String, Object>) JSON.deserializeUntyped(
            '{"type":"card","card":{"exp_month":2,"exp_year":2028,"wallet":{"type":"apple_pay"}}}'));
        System.assertEquals(null, u.PayProv_CardExpiry__c, 'A wallet card is renewed by the network');
        System.assertEquals('apple_pay', u.PayProv_CardWallet__c);
    }

    // ── a SEPA method saved by the pay-now payment: its mandate comes from the charge, not the previous method's ──
    @IsTest
    static void testTypeJobReadsMandateFromCharge() {
        Account acc = account();
        Database.update(new Account(Id = acc.Id, PayProv_PaymentMethodId__c = 'pm_sepa_new', PayProv_MandateId__c = 'mandate_old'), AccessLevel.SYSTEM_MODE);
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"pm_sepa_new","type":"sepa_debit"}',
            '{"id":"pi_paynow","latest_charge":{"id":"py_1","payment_method_details":{"type":"sepa_debit","sepa_debit":{"mandate":"mandate_new"}}}}'
        };
        Test.startTest();
        new Svc_PaymentIntent.TypeJob(new Map<Id, String>{ acc.Id => 'pm_sepa_new' }, new Map<Id, String>{ acc.Id => null },
            new Map<Id, String>{ acc.Id => 'pi_paynow' }).execute(null);
        Test.stopTest();
        System.assertEquals('mandate_new', account().PayProv_MandateId__c);
        System.assert(Svc_PaymentIntent.sentBodies[1].contains('/v1/payment_intents/pi_paynow?expand[]=latest_charge'), Svc_PaymentIntent.sentBodies[1]);
    }

    // ── card expiry check: a card that still expires before the collection date → renewal mail ──
    @IsTest
    static void testCardExpiryCheckRequestsRenewal() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'New', 'Due_Date__c' => Date.today().addMonths(2), 'PayProv_PaymentIntentId__c' => null });
        Batch_CardExpiryCheck batch = new Batch_CardExpiryCheck();
        Database.QueryLocatorIterator it = batch.startBatch(null).iterator();
        List<Payment__c> scope = new List<Payment__c>();
        while (it.hasNext()) scope.add((Payment__c) it.next());
        System.assertEquals(1, scope.size(), 'Card expiry not known yet: selected');

        Date thisMonth = Date.today();
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"type":"card","card":{"exp_month":' + thisMonth.month() + ',"exp_year":' + thisMonth.year() + '}}'
        };
        Test.startTest();
        batch.executeBatch(null, scope);
        Test.stopTest();

        System.assertEquals(Date.newInstance(thisMonth.year(), thisMonth.month(), 1).addMonths(1).addDays(-1), account().PayProv_CardExpiry__c);
        System.assertEquals(Date.today(), payment().Card_Renewal_Requested__c);
    }

    // ── card expiry check: renewed by Stripe's card updater → no mail ──
    @IsTest
    static void testCardExpiryCheckRenewedCard() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'New', 'Due_Date__c' => Date.today().addMonths(2) });
        Svc_PaymentIntent.mockResponses = new List<String>{ '{"type":"card","card":{"exp_month":12,"exp_year":2040}}' };
        Batch_CardExpiryCheck batch = new Batch_CardExpiryCheck();
        Test.startTest();
        batch.executeBatch(null, [SELECT Id, Name, Status__c, Type__c, externalId__c, Collection_Date__c, Account__c, Contact__c,
            PayProv_PaymentIntentId__c, Account__r.PayProv_PaymentMethodId__c, Account__r.PayProv_CardExpiry__c,
            Administration__r.Reseller__c, Administration__r.Subscription25__Organization_Wide_Email__c FROM Payment__c WITH SYSTEM_MODE]);
        Test.stopTest();
        System.assertEquals(null, payment().Card_Renewal_Requested__c);
        System.assertEquals(Date.newInstance(2040, 12, 31), account().PayProv_CardExpiry__c);
    }

    // ── payment page: renew the expiring card - a SetupIntent, nothing charged ──
    @IsTest
    static void testPageRenewCard() {
        setPayment(new Map<String, Object>{ 'Status__c' => 'New', 'Due_Date__c' => Date.today().addMonths(2),
            'Card_Renewal_Requested__c' => Date.today() });
        Database.update(new Account(Id = account().Id, PayProv_CardExpiry__c = Date.today()), AccessLevel.SYSTEM_MODE);
        Svc_PaymentIntent.mockResponses = new List<String>{ '{"id":"seti_renew","client_secret":"cs_renew"}' };
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('tok_dun', 'en');
        Test.stopTest();
        System.assertEquals(null, d.errorMessage);
        System.assertEquals('renewCard', d.dunning);
        System.assertEquals('setup', d.mode);
        System.assertEquals('cs_renew', d.clientSecret);
        String create = Svc_PaymentIntent.sentBodies[0];
        System.assert(create.startsWith('POST /v1/setup_intents') && create.contains('metadata[Checkout]=renewal'), create);
    }
}
