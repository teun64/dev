@IsTest
private class Test_Batch_ReconcileProcessingPayments {
    // LastModifiedDate can't be backdated in a test, so executeBatch is called directly with the scope;
    // the Stripe lookups come from Svc_PaymentIntent.mockResponses (stripeGC's callout can't be mocked)

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
        Account acc = Test_Data.createAccount('Reconcile Processing BV', '9051', 'B2B', false);
        insert acc;
        acc.PayProv_CustomerId__c = 'cus_rc001';
        update acc;
        Database.insert(new Subscription25__Schedulable_Class__c(
            Name = 'Batch_ReconcileProcessingPayments',
            Subscription25__Unique_Name__c = 'Batch_ReconcileProcessingPayments'
        ), AccessLevel.SYSTEM_MODE);
        List<Payment__c> payments = new List<Payment__c>();
        for (String pi : new List<String>{ 'pi_rc_paid', 'pi_rc_failed', 'pi_rc_open' }) {
            payments.add(new Payment__c(
                Account__c                 = acc.Id,
                Administration__c          = admin.Id,
                Method__c                  = 'pr',
                Type__c                    = 'psp-recurring',
                Status__c                  = 'Processing',
                CurrencyIsoCode            = 'GBP',
                Amount_Gross__c            = 15,
                PayProv_PaymentIntentId__c = pi
            ));
        }
        Database.insert(payments, AccessLevel.SYSTEM_MODE);
    }

    private static String intent(String id, Id paymentId, String status, Boolean failed) {
        Map<String, Object> pi = new Map<String, Object>{
            'id' => id, 'status' => status, 'customer' => 'cus_rc001', 'payment_method' => 'pm_rc001',
            'metadata' => new Map<String, Object>{ 'PaymentID' => paymentId }
        };
        if (failed) pi.put('last_payment_error', new Map<String, Object>{ 'code' => 'insufficient_funds', 'message' => 'insufficient funds' });
        return JSON.serialize(pi);
    }

    @IsTest
    static void testFinalStatesAreFedBack() {
        Map<String, Payment__c> byIntent = new Map<String, Payment__c>();
        for (Payment__c p : (List<Payment__c>) Database.queryWithBinds(
                'SELECT Id, Name, Status__c, PayProv_PaymentIntentId__c, LastModifiedDate, Administration__r.Reseller__c FROM Payment__c',
                new Map<String, Object>(), AccessLevel.SYSTEM_MODE)) {
            byIntent.put(p.PayProv_PaymentIntentId__c, p);
        }
        List<Payment__c> scope = new List<Payment__c>{ byIntent.get('pi_rc_paid'), byIntent.get('pi_rc_failed'), byIntent.get('pi_rc_open') };
        Svc_PaymentIntent.mockResponses = new List<String>{
            intent('pi_rc_paid',   byIntent.get('pi_rc_paid').Id,   'succeeded',               false),
            intent('pi_rc_failed', byIntent.get('pi_rc_failed').Id, 'requires_payment_method', true),
            intent('pi_rc_open',   byIntent.get('pi_rc_open').Id,   'processing',              false)
        };

        Test.startTest();
        new Batch_ReconcileProcessingPayments().executeBatch(null, scope);
        Test.stopTest();

        Map<String, String> status = new Map<String, String>();
        for (Payment__c p : (List<Payment__c>) Database.queryWithBinds('SELECT Status__c, PayProv_PaymentIntentId__c FROM Payment__c',
                new Map<String, Object>(), AccessLevel.SYSTEM_MODE)) {
            status.put(p.PayProv_PaymentIntentId__c, p.Status__c);
        }
        System.assertEquals('Paid',       status.get('pi_rc_paid'),   'succeeded at Stripe → Paid');
        System.assertEquals('Failed',     status.get('pi_rc_failed'), 'failed at Stripe → Failed');
        System.assertEquals('Processing', status.get('pi_rc_open'),   'still processing → unchanged');
        System.assertEquals(2, [SELECT COUNT() FROM stripeGC__Stripe_Event__c], 'one fed-back event per final intent');
    }

    @IsTest
    static void testEventFor() {
        System.assertEquals('payment_intent.succeeded', Batch_ReconcileProcessingPayments.eventFor(new Map<String, Object>{ 'status' => 'succeeded' }));
        System.assertEquals(null, Batch_ReconcileProcessingPayments.eventFor(new Map<String, Object>{ 'status' => 'processing' }));
        System.assertEquals(null, Batch_ReconcileProcessingPayments.eventFor(new Map<String, Object>{ 'status' => 'requires_payment_method' }),
            'requires_payment_method without an error is not a failure');
        System.assertEquals(null, Batch_ReconcileProcessingPayments.eventFor(null));
    }

    @IsTest
    static void testStartAndFinish() {
        Test.startTest();
        Database.executeBatch(new Batch_ReconcileProcessingPayments(), 20);
        Test.stopTest();
        // nothing is older than 3 days in a test: the run selects nothing and changes nothing
        System.assertEquals(0, [SELECT COUNT() FROM stripeGC__Stripe_Event__c]);
    }
}
