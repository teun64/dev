@IsTest
private class Test_Ctrl_PaymentCase {

    // ── Shared test data ──────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        CustomerHub__c hubConfig = new CustomerHub__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Base_URL__c  = 'https://hub.example.com/customer-hub'
        );
        insert hubConfig;

        Account acc = Test_Data.createAccount('ACME BV', '9003', 'B2B', false);
        acc.Reseller_Name__c = '1';
        insert acc;

        Contact c = new Contact(
            AccountId = acc.Id,
            FirstName = 'Piet',
            LastName  = 'Tester',
            Email     = 'piet.tester@acme.nl'
        );
        insert c;

        // Set main contact role via Roles (isMainContact__c formula reads 'Main')
        AccountContactRelation acr = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :c.Id LIMIT 1
        ];
        acr.Roles = 'Main';
        update acr;

        Payment__c pmt = new Payment__c(
            Account__c         = acc.Id,
            Administration__c  = admin.Id,
            externalId__c      = 'REF-CASE-001',
            Status__c          = 'Pending',
            CurrencyIsoCode    = 'EUR',
            Amount_Gross__c    = 250.00
        );
        insert pmt;

        // Queue for reseller '1' — setup objects (Group + QueueSObject) must be inserted in a
        // separate runAs block to avoid the mixed-DML rule with non-setup objects above
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Group q = new Group(
                Name          = 'Payment NL',
                DeveloperName = 'gqPayment1',
                Type          = 'Queue'
            );
            insert q;
            insert new QueueSObject(QueueId = q.Id, SObjectType = 'Case');
        }
    }

    // ── createPaymentFailureCase – happy path ─────────────────────────────────

    @IsTest
    static void testCreateCase_queueAssigned() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        String caseId = Ctrl_PaymentCase.createPaymentFailureCase(
            pmt.Id,
            'SEPA debit declined – insufficient funds'
        );
        Test.stopTest();

        System.assertNotEquals(null, caseId, 'Case Id returned');

        Case c = [
            SELECT AccountId, ContactId, Subject, Description, Origin, Status, OwnerId
            FROM Case
            WHERE Id = :caseId
        ];

        Account acc = [SELECT Name FROM Account WHERE Id = :c.AccountId LIMIT 1];
        System.assertEquals('ACME BV', acc.Name, 'Case linked to correct account');

        Contact con = [SELECT Email FROM Contact WHERE Id = :c.ContactId LIMIT 1];
        System.assertEquals('piet.tester@acme.nl', con.Email, 'Main contact resolved');

        System.assertEquals('Direct Debit failure – REF-CASE-001', c.Subject, 'Subject format');
        System.assert(c.Description.contains('insufficient funds'), 'Reason in description');
        System.assert(c.Description.contains('REF-CASE-001'),       'Reference in description');
        System.assert(c.Description.contains('hub.example.com'),    'Support URL in description');
        System.assertEquals('Direct Debit', c.Origin);
        System.assertEquals('New',          c.Status);

        Group q = [SELECT Id FROM Group WHERE DeveloperName = 'gqPayment1' LIMIT 1];
        System.assertEquals(q.Id, c.OwnerId, 'Case owned by gqPayment1 queue');
    }

    @IsTest
    static void testCreateCase_paymentContactTakesPriority() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACME BV' LIMIT 1];

        // Add a second contact as payment contact — should be preferred over main
        Contact payC = new Contact(
            AccountId = acc.Id,
            FirstName = 'Anna',
            LastName  = 'Payment',
            Email     = 'anna.payment@acme.nl'
        );
        insert payC;

        AccountContactRelation payAcr = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :payC.Id LIMIT 1
        ];
        payAcr.Roles = 'Payment';
        update payAcr;

        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        String caseId = Ctrl_PaymentCase.createPaymentFailureCase(pmt.Id, 'Test');
        Test.stopTest();

        Case c = [SELECT ContactId FROM Case WHERE Id = :caseId];
        Contact assigned = [SELECT Email FROM Contact WHERE Id = :c.ContactId LIMIT 1];
        System.assertEquals('anna.payment@acme.nl', assigned.Email,
            'Payment contact preferred over main contact');
    }

    // ── createPaymentFailureCase – no queue ───────────────────────────────────

    @IsTest
    static void testCreateCase_noQueueStillCreates() {
        Subscription25__Administration__c admin = [
            SELECT Id FROM Subscription25__Administration__c LIMIT 1
        ];
        Account acc = Test_Data.createAccount('Beta Corp', '9004', 'B2B', false);
        acc.Reseller_Name__c = '6'; // no queue created for reseller 6
        insert acc;

        Payment__c pmt = new Payment__c(
            Account__c        = acc.Id,
            Administration__c = admin.Id,
            externalId__c     = 'REF-NOQUEUE',
            Status__c         = 'Pending',
            CurrencyIsoCode   = 'EUR',
            Amount_Gross__c   = 50.00
        );
        insert pmt;

        Test.startTest();
        String caseId = Ctrl_PaymentCase.createPaymentFailureCase(pmt.Id, 'No queue test');
        Test.stopTest();

        System.assertNotEquals(null, caseId, 'Case created even when queue not found');
        Case c = [SELECT Status FROM Case WHERE Id = :caseId];
        System.assertEquals('New', c.Status);
    }

    // ── createPaymentFailureCase – support URL fallback ───────────────────────

    @IsTest
    static void testCreateCase_supportUrlFallback() {
        // Remove the hub config so the fallback URL path is exercised
        CustomerHub__c cfg = CustomerHub__c.getOrgDefaults();
        if (cfg.Id != null) delete cfg;

        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        String caseId = Ctrl_PaymentCase.createPaymentFailureCase(pmt.Id, 'Fallback test');
        Test.stopTest();

        Case c = [SELECT Description FROM Case WHERE Id = :caseId];
        System.assert(c.Description.contains('Support portal:'),
            'Support portal line present even with fallback URL');
    }

    // ── createPaymentFailureCase – error cases ────────────────────────────────

    @IsTest
    static void testCreateCase_blankPaymentId() {
        Test.startTest();
        try {
            Ctrl_PaymentCase.createPaymentFailureCase('', 'Test');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateCase_nullPaymentId() {
        Test.startTest();
        try {
            Ctrl_PaymentCase.createPaymentFailureCase(null, 'Test');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateCase_unknownPaymentId() {
        Test.startTest();
        try {
            Ctrl_PaymentCase.createPaymentFailureCase('000000000000000AAA', 'Test');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }
}
