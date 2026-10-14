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
}
