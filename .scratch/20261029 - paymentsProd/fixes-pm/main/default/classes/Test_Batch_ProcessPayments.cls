@IsTest
private class Test_Batch_ProcessPayments {

    // The Stripe callout can't be mocked: the stripeGC package validates the Stripe account before it ever reaches
    // Http.send() (see Test_Ctrl_Payment / Test_Ctrl_PaymentMandate). A selected payment therefore always ends up
    // on the Stripe-error path in a test, which is what proves it was picked up.

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        Account acc = Test_Data.createAccount('Process Payments BV', '9041', 'B2B', false);
        insert acc;
        // rbb_Account wipes PayProv_* ids on a brand-new Account - set them with a separate update
        acc.PayProv_CustomerId__c      = 'cus_pp001';
        acc.PayProv_PaymentMethodId__c = 'pm_pp001';
        acc.PayProv_MandateId__c       = 'mandate_pp001';
        update acc;

        Account noMandate = Test_Data.createAccount('No Mandate BV', '9042', 'B2B', false);
        insert noMandate;
        noMandate.PayProv_CustomerId__c = 'cus_pp002';
        update noMandate;

        Database.insert(new Subscription25__Schedulable_Class__c(
            Name = 'Batch_ProcessPayments',
            Subscription25__Unique_Name__c = 'Batch_ProcessPayments'
        ), AccessLevel.SYSTEM_MODE);
    }

    private static Payment__c newPayment(Id accountId, String method, Date dueDate) {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        return new Payment__c(
            Account__c        = accountId,
            Administration__c = admin.Id,
            Method__c         = method,
            Type__c           = method == 'I0' ? 'fs-dd' : 'psp-recurring',
            Status__c         = 'New',
            CurrencyIsoCode   = 'EUR',
            Amount_Gross__c   = 13.50,
            Request_Date__c   = Date.today(),
            Due_Date__c       = dueDate
        );
    }

    private static void insertBusinessEntity(Boolean withStripeAccount) {
        Business_Entities__c be = new Business_Entities__c(
            Name                                 = 'Netherlands (test)',
            Reseller__c                          = '1',
            PayProv_DirectDebit_PaymentMethod__c = 'sepa_debit'
        );
        if (withStripeAccount) {
            stripeGC__Stripe_Account__c sa = new stripeGC__Stripe_Account__c(Name = 'Test Stripe');
            Database.insert(sa, AccessLevel.SYSTEM_MODE);
            be.PayProv_Account__c = sa.Id;
        }
        Database.insert(be, AccessLevel.SYSTEM_MODE);
    }

    private static Payment__c reload(Id paymentId) {
        return [SELECT Name, Status__c, Collection_Date__c FROM Payment__c WHERE Id = :paymentId];
    }

    private static List<Case> casesFor(Id accountId) {
        return [SELECT Subject, Description FROM Case WHERE AccountId = :accountId];
    }

    // ── due recurring payment is picked up: Stripe call fails in test → Failed + Case ──
    @IsTest
    static void testDuePaymentIsCollected() {
        insertBusinessEntity(true);
        Account acc = [SELECT Id FROM Account WHERE Name = 'Process Payments BV'];
        Payment__c p = newPayment(acc.Id, 'I8', Date.today());
        insert p;
        System.assertEquals('New', reload(p.Id).Status__c, 'Account has a mandate, so rbb_Payment leaves the payment New');

        Test.startTest();
        Database.executeBatch(new Batch_ProcessPayments(), 20);
        Test.stopTest();

        Payment__c after = reload(p.Id);
        System.assertEquals('Failed', after.Status__c, 'Selected and sent to Stripe (unmocked → error path)');
        List<Case> cases = casesFor(acc.Id);
        System.assertEquals(1, cases.size(), 'Failure Case created');
        System.assert(cases[0].Subject.endsWith(after.Name), 'Case subject names the payment: ' + cases[0].Subject);
        System.assert(cases[0].Description.startsWith('Stripe error:'), cases[0].Description);
    }

    // ── the customer has the invoice first: not collected while the invoice email is pending, from the day after it was sent ──
    @IsTest
    static void testWaitsForInvoiceEmail() {
        insertBusinessEntity(true);
        Account acc = [SELECT Id FROM Account WHERE Name = 'Process Payments BV'];
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__Invoice__c pending = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', true);
        Subscription25__Invoice__c sent    = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', true);
        Database.update(new List<Subscription25__Invoice__c>{
            new Subscription25__Invoice__c(Id = pending.Id, Subscription25__Email_Status__c = 'PENDING'),
            new Subscription25__Invoice__c(Id = sent.Id,    Subscription25__Email_Status__c = 'SENT')
        }, AccessLevel.SYSTEM_MODE);
        // rbu_Subscription25_Invoice_c stamps today on SENT: move the send date back separately
        Database.update(new Subscription25__Invoice__c(Id = sent.Id, Email_SendDate__c = Date.today().addDays(-1)), AccessLevel.SYSTEM_MODE);
        Payment__c waiting = newPayment(acc.Id, 'I8', Date.today());
        waiting.Invoice__c = pending.Id;
        Payment__c due = newPayment(acc.Id, 'I8', Date.today());
        due.Invoice__c = sent.Id;
        insert new List<Payment__c>{ waiting, due };

        Test.startTest();
        Database.executeBatch(new Batch_ProcessPayments(), 20);
        Test.stopTest();

        System.assertEquals('New',    reload(waiting.Id).Status__c, 'invoice email still pending: not collected');
        System.assertEquals('Failed', reload(due.Id).Status__c,     'invoice emailed yesterday: collected (unmocked → error path)');
    }

    // ── saved card without mandate is picked up; the failure Case names a card payment, not a Direct Debit ──
    @IsTest
    static void testDueCardPaymentCaseSubject() {
        insertBusinessEntity(true);
        Account acc = [SELECT Id FROM Account WHERE Name = 'No Mandate BV'];
        acc.PayProv_PaymentMethodId__c   = 'pm_card001';
        acc.PayProv_PaymentMethodType__c = 'card';
        Database.update(acc, AccessLevel.SYSTEM_MODE);
        Payment__c p = newPayment(acc.Id, 'pr', Date.today());
        insert p;

        Test.startTest();
        Database.executeBatch(new Batch_ProcessPayments(), 20);
        Test.stopTest();

        System.assertEquals('Failed', reload(p.Id).Status__c, 'Card without mandate selected and sent to Stripe');
        List<Case> cases = casesFor(acc.Id);
        System.assertEquals(1, cases.size(), 'Failure Case created');
        System.assert(cases[0].Subject.startsWith('Card payment failed – '), cases[0].Subject);
    }

    // ── no Stripe account on the Business Entity → Failed + Case, no callout ──
    @IsTest
    static void testMissingStripeAccountFails() {
        insertBusinessEntity(false);
        Account acc = [SELECT Id FROM Account WHERE Name = 'Process Payments BV'];
        Payment__c p = newPayment(acc.Id, 'I8', Date.today());
        insert p;

        Test.startTest();
        Database.executeBatch(new Batch_ProcessPayments(), 20);
        Test.stopTest();

        System.assertEquals('Failed', reload(p.Id).Status__c);
        List<Case> cases = casesFor(acc.Id);
        System.assertEquals(1, cases.size());
        System.assert(cases[0].Description.startsWith('No Stripe account configured'), cases[0].Description);
    }

    // ── not due yet, not a Stripe direct debit, or no mandate → left alone ──
    @IsTest
    static void testIneligiblePaymentsAreSkipped() {
        insertBusinessEntity(false);
        Account acc       = [SELECT Id FROM Account WHERE Name = 'Process Payments BV'];
        Account noMandate = [SELECT Id FROM Account WHERE Name = 'No Mandate BV'];
        Payment__c future    = newPayment(acc.Id, 'I8', Date.today().addDays(30));
        Payment__c bottomline = newPayment(acc.Id, 'I0', Date.today());
        Payment__c noMandateP = newPayment(noMandate.Id, 'I8', Date.today());
        insert new List<Payment__c>{ future, bottomline, noMandateP };
        Map<Id, String> before = new Map<Id, String>();
        for (Payment__c p : [SELECT Status__c FROM Payment__c]) before.put(p.Id, p.Status__c);

        Test.startTest();
        Database.executeBatch(new Batch_ProcessPayments(), 20);
        Test.stopTest();

        for (Payment__c p : [SELECT Name, Status__c FROM Payment__c]) {
            System.assertEquals(before.get(p.Id), p.Status__c, p.Name + ' must not be touched');
        }
        System.assertEquals(0, [SELECT COUNT() FROM Case], 'No Cases for skipped payments');
    }

    // ── started by the dispatcher: finishBatch hands over without error when it is the last step ──
    @IsTest
    static void testDispatcherStep() {
        Batch_ProcessPayments b = new Batch_ProcessPayments();
        b.setDispatcher('Minut');

        Test.startTest();
        Database.executeBatch(b, 20);
        Test.stopTest();

        System.assertEquals(20, b.getBatchSize());
    }
}
