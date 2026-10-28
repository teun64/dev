@IsTest
private class Test_Svc_PaymentActionRequired {

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        Account acc = Test_Data.createAccount('Action Required BV', '9061', 'B2B', false);
        insert acc;
        // rbb_Account wipes PayProv_* ids on a brand-new Account - set them with a separate update;
        // a saved card keeps rbb_Payment from turning the payment into Setup
        acc.PayProv_CustomerId__c        = 'cus_ar001';
        acc.PayProv_PaymentMethodId__c   = 'pm_ar001';
        acc.PayProv_PaymentMethodType__c = 'card';
        Database.update(acc, AccessLevel.SYSTEM_MODE);

        Contact c = new Contact(AccountId = acc.Id, FirstName = 'Anna', LastName = 'Authenticatie', Email = 'anna.ar@example.com');
        insert c;
        AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :c.Id];
        acr.Roles = 'Payment';
        update acr;

        Database.insert(new List<Payment__c>{
            newPayment(acc.Id, admin.Id, 'Action Required', 'tok_ar_waiting'),
            newPayment(acc.Id, admin.Id, 'Paid', 'tok_ar_paid')
        }, AccessLevel.SYSTEM_MODE);
    }

    private static Payment__c newPayment(Id accountId, Id adminId, String status, String token) {
        return new Payment__c(
            Account__c         = accountId,
            Administration__c  = adminId,
            Method__c          = 'pr',
            Type__c            = 'psp-recurring',
            Status__c          = status,
            externalId__c      = token,
            CurrencyIsoCode    = 'EUR',
            Amount_Gross__c    = 25.00,
            Request_Date__c    = Date.today(),
            Collection_Date__c = Date.today()
        );
    }

    private static Payment__c byToken(String token) {
        return (Payment__c) Database.queryWithBinds(
            'SELECT Id, Name, Status__c, AlertMessage__c FROM Payment__c WHERE externalId__c = :token',
            new Map<String, Object>{ 'token' => token }, AccessLevel.SYSTEM_MODE)[0];
    }

    private static Svc_PaymentActionRequired.Request request(Id paymentId, String step) {
        Svc_PaymentActionRequired.Request r = new Svc_PaymentActionRequired.Request();
        r.paymentId = paymentId;
        r.step      = step;
        return r;
    }

    // ── mail: without a paymentAuthenticationRequired_* template the reason lands on the payment ──
    @IsTest
    static void testMailWithoutTemplateLeavesAlert() {
        Payment__c p = byToken('tok_ar_waiting');
        Boolean templateExists = [SELECT COUNT() FROM EmailTemplate WHERE Name LIKE 'paymentAuthenticationRequired_%'] > 0;

        Test.startTest();
        Svc_PaymentActionRequired.run(new List<Svc_PaymentActionRequired.Request>{ request(p.Id, Svc_PaymentActionRequired.STEP_MAIL) });
        Test.stopTest();

        Payment__c after = byToken('tok_ar_waiting');
        System.assertEquals('Action Required', after.Status__c, 'Mail does not change the status');
        if (!templateExists) {
            System.assert(after.AlertMessage__c != null && after.AlertMessage__c.startsWith('Authentication email not sent'), after.AlertMessage__c);
        }
    }

    // ── expire: Failed + exactly one Case naming a card payment ──
    @IsTest
    static void testExpireFailsAndCreatesOneCase() {
        Payment__c p = byToken('tok_ar_waiting');

        Test.startTest();
        Svc_PaymentActionRequired.run(new List<Svc_PaymentActionRequired.Request>{ request(p.Id, Svc_PaymentActionRequired.STEP_EXPIRE) });
        Test.stopTest();

        System.assertEquals('Failed', byToken('tok_ar_waiting').Status__c);
        List<Case> cases = [SELECT Subject, Description, ContactId FROM Case WHERE Subject LIKE 'Card payment failure%'];
        System.assertEquals(1, cases.size(), 'One Case per expired payment');
        System.assert(cases[0].Subject.endsWith(p.Name), cases[0].Subject);
        System.assertNotEquals(null, cases[0].ContactId, 'Payment contact on the Case');
    }

    // ── a payment that is no longer Action Required is left alone ──
    @IsTest
    static void testNotWaitingIsIgnored() {
        Payment__c paid = byToken('tok_ar_paid');

        Test.startTest();
        Svc_PaymentActionRequired.run(new List<Svc_PaymentActionRequired.Request>{
            request(paid.Id, Svc_PaymentActionRequired.STEP_EXPIRE),
            request(paid.Id, Svc_PaymentActionRequired.STEP_REMINDER)
        });
        Test.stopTest();

        Payment__c after = byToken('tok_ar_paid');
        System.assertEquals('Paid', after.Status__c);
        System.assertEquals(null, after.AlertMessage__c);
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Subject LIKE '%failure%']);
    }
}
