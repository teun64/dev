@IsTest
private class Test_Svc_PaymentIntent {

    // stripeGC validates the Stripe account before any Http.send(), so callouts can't be mocked
    // (see Test_Ctrl_Payment). The decision, request bodies and response parsing are tested directly;
    // the callout paths are exercised up to the (caught) Stripe error.

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
        Account acc = Test_Data.createAccount('Intent Test BV', '9051', 'B2B', false);
        insert acc;
        acc.PayProv_CustomerId__c = 'cus_intent001';
        update acc;
        Database.insert(new Payment__c(
            Account__c        = acc.Id,
            Administration__c = admin.Id,
            externalId__c     = 'TOKEN-INTENT',
            Status__c         = 'Setup',
            CurrencyIsoCode   = 'GBP',
            Amount_Gross__c   = 13.50,
            Request_Date__c   = Date.today()
        ), AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void testDecide() {
        System.assertEquals(Svc_PaymentIntent.Action.CREATE,    Svc_PaymentIntent.decide(null));
        System.assertEquals(Svc_PaymentIntent.Action.CREATE,    Svc_PaymentIntent.decide('canceled'));
        System.assertEquals(Svc_PaymentIntent.Action.REUSE,     Svc_PaymentIntent.decide('requires_payment_method'));
        System.assertEquals(Svc_PaymentIntent.Action.REUSE,     Svc_PaymentIntent.decide('requires_confirmation'));
        System.assertEquals(Svc_PaymentIntent.Action.REUSE,     Svc_PaymentIntent.decide('requires_action'));
        System.assertEquals(Svc_PaymentIntent.Action.PROCESSED, Svc_PaymentIntent.decide('processing'));
        System.assertEquals(Svc_PaymentIntent.Action.PROCESSED, Svc_PaymentIntent.decide('succeeded'));
        System.assertEquals(Svc_PaymentIntent.Action.PROCESSED, Svc_PaymentIntent.decide('some_new_status'), 'Unknown status never creates a second intent');
    }

    @IsTest
    static void testMissingTypesUpdate() {
        Map<String, Object> ddOnly = new Map<String, Object>{ 'payment_method_types' => new List<Object>{ 'bacs_debit' } };
        System.assertEquals('payment_method_types[]=bacs_debit&payment_method_types[]=card',
            Svc_PaymentIntent.missingTypesUpdate(ddOnly, 'bacs_debit'), 'Pre-phase-2 intent gets card added');
        Map<String, Object> withCard = new Map<String, Object>{ 'payment_method_types' => new List<Object>{ 'sepa_debit', 'card' } };
        System.assertEquals(null, Svc_PaymentIntent.missingTypesUpdate(withCard, 'sepa_debit'), 'Intent with card stays as is');
        System.assertEquals(null, Svc_PaymentIntent.missingTypesUpdate(new Map<String, Object>(), 'sepa_debit'), 'No types in the response: no update');
    }

    @IsTest
    static void testBodies() {
        Id pid = [SELECT Id FROM Payment__c LIMIT 1].Id;
        String pi = Svc_PaymentIntent.paymentIntentBody(pid, 'cus_1', 1350, 'GBP', 'bacs_debit');
        System.assert(pi.contains('amount=1350') && pi.contains('currency=gbp') && pi.contains('setup_future_usage=off_session'), pi);
        System.assert(pi.contains('metadata[PaymentID]=' + pid), pi);
        System.assert(!pi.contains('confirm='), 'Customer-facing intent is never confirmed server-side');
        String si = Svc_PaymentIntent.setupIntentBody(pid, 'cus_1', 'sepa_debit');
        System.assert(si.contains('usage=off_session') && si.contains('payment_method_types[]=sepa_debit'), si);
        System.assertEquals(1350, Svc_PaymentIntent.amountCents(13.50));
        System.assertEquals(0, Svc_PaymentIntent.amountCents(null));
    }

    @IsTest
    static void testParse() {
        System.assertEquals('pi_1', Svc_PaymentIntent.parse('{"id":"pi_1","status":"processing"}').get('id'));
        try {
            Svc_PaymentIntent.parse('{"error":{"message":"No such payment_intent"}}');
            System.assert(false, 'Expected StripeException');
        } catch (Svc_PaymentIntent.StripeException e) {
            System.assertEquals('No such payment_intent', e.getMessage());
        }
    }

    @IsTest
    static void testStoreUpdate() {
        Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
        Svc_PaymentIntent.Checkout c = new Svc_PaymentIntent.Checkout();
        c.mode = 'setup'; c.intentId = 'seti_1'; c.isNew = true;
        System.assertEquals('seti_1', Svc_PaymentIntent.storeUpdate(p, c).PayProv_SetupIntentId__c);
        c.mode = 'payment'; c.intentId = 'pi_1';
        System.assertEquals('pi_1', Svc_PaymentIntent.storeUpdate(p, c).PayProv_PaymentIntentId__c);
        c.isNew = false;
        System.assertEquals(null, Svc_PaymentIntent.storeUpdate(p, c), 'Reused intent: nothing to store');
    }

    // ── reused pre-phase-2 intent: card added in one update, same intent returned ──
    @IsTest
    static void testGetOrCreateReuseAddsCard() {
        Payment__c p = Svc_PaymentIntent.queryPayments(new Set<Id>{ [SELECT Id FROM Payment__c LIMIT 1].Id })[0];
        p.PayProv_SetupIntentId__c = 'seti_old';
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"seti_old","status":"requires_payment_method","client_secret":"cs_old","payment_method_types":["sepa_debit"]}',
            '{"id":"seti_old","status":"requires_payment_method","client_secret":"cs_old","payment_method_types":["sepa_debit","card"]}'
        };

        Svc_PaymentIntent.Checkout c = Svc_PaymentIntent.getOrCreate(p, null);

        System.assertEquals('seti_old', c.intentId, 'Same intent reused');
        System.assertEquals('cs_old', c.clientSecret);
        System.assertEquals(2, Svc_PaymentIntent.sentBodies.size(), 'GET + one update');
        System.assertEquals('POST /v1/setup_intents/seti_old payment_method_types[]=sepa_debit&payment_method_types[]=card', Svc_PaymentIntent.sentBodies[1]);
    }

    @IsTest
    static void testGetOrCreateReuseWithCardNoUpdate() {
        Payment__c p = Svc_PaymentIntent.queryPayments(new Set<Id>{ [SELECT Id FROM Payment__c LIMIT 1].Id })[0];
        p.PayProv_SetupIntentId__c = 'seti_new';
        Svc_PaymentIntent.mockResponses = new List<String>{
            '{"id":"seti_new","status":"requires_payment_method","client_secret":"cs_new","payment_method_types":["sepa_debit","card"]}'
        };

        Svc_PaymentIntent.Checkout c = Svc_PaymentIntent.getOrCreate(p, null);

        System.assertEquals('seti_new', c.intentId);
        System.assertEquals(1, Svc_PaymentIntent.sentBodies.size(), 'Only the GET, no update');
    }

    @IsTest
    static void testGetOrCreateStripeErrorSurfaces() {
        Payment__c p = Svc_PaymentIntent.queryPayments(new Set<Id>{ [SELECT Id FROM Payment__c LIMIT 1].Id })[0];
        try {
            Svc_PaymentIntent.getOrCreate(p, null);
            System.assert(false, 'Unmocked Stripe call should fail');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }

    @IsTest
    static void testPrepareRunsJob() {
        Id pid = [SELECT Id FROM Payment__c LIMIT 1].Id;
        Test.startTest();
        Svc_PaymentIntent.prepare(new List<Id>{ pid, null });
        Test.stopTest();
        // Stripe call fails in test context and is caught: the payment stays as it was
        Payment__c p = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, PayProv_SetupIntentId__c FROM Payment__c WHERE Id = :pid',
            new Map<String, Object>{ 'pid' => pid }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Setup', p.Status__c);
        System.assertEquals(null, p.PayProv_SetupIntentId__c);
    }

    // ── 402 from stripeGC: code and intent read back out of the exception message ──
    @IsTest
    static void testStripeErrorParsesCalloutMessage() {
        String message = 'Stripe callout error: {"error": {"code": "authentication_required", "decline_code": "authentication_required",'
            + ' "payment_intent": {"id": "pi_3UV7qm", "status": "requires_payment_method"},'
            + ' "payment_method": {"id": "pm_1UUmqW", "type": "card"}, "type": "card_error"}}';
        Svc_PaymentIntent.StripeError se = Svc_PaymentIntent.stripeError(new Svc_PaymentIntent.StripeException(message));
        System.assertEquals('authentication_required', se.code);
        System.assertEquals('pi_3UV7qm', se.paymentIntentId);
        System.assertEquals('pm_1UUmqW', se.paymentMethodId);

        System.assertEquals(null, Svc_PaymentIntent.stripeError(new Svc_PaymentIntent.StripeException('No Stripe account')), 'No JSON');
        System.assertEquals(null, Svc_PaymentIntent.stripeError(new Svc_PaymentIntent.StripeException('Error: {not json')), 'Broken JSON');
    }

    @IsTest
    static void testNewTokenIsStablePerIntent() {
        Id paymentId = Payment__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        String t = Svc_PaymentIntent.newToken(paymentId, 'pi_1');
        System.assertEquals(32, t.length(), 'Same format as the setup token');
        System.assertEquals(t, Svc_PaymentIntent.newToken(paymentId, 'pi_1'), 'Batch and webhook derive the same token');
        System.assertNotEquals(t, Svc_PaymentIntent.newToken(paymentId, 'pi_2'));
    }
}
