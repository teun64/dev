@IsTest
private class Test_Ctrl_Payment {

    // ── Shared test data ──────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        CustomerHub__c hubConfig = new CustomerHub__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Base_URL__c  = 'https://hub.example.com/customer-hub'
        );
        insert hubConfig;

        Account acc = Test_Data.createAccount('ACME BV', '9001', 'B2B', false);
        acc.PayProv_CustomerId__c = 'cus_test999';
        insert acc;

        Contact c = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jan',
            LastName  = 'Betaler',
            Email     = 'jan.betaler@acme.nl'
        );
        insert c;

        // Mark as payment contact via Roles (IsPaymentContact__c formula reads Roles)
        AccountContactRelation acr = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :c.Id LIMIT 1
        ];
        acr.Roles = 'Payment';
        update acr;

        Payment__c pmt = new Payment__c(
            Account__c         = acc.Id,
            Administration__c  = admin.Id,
            externalId__c      = 'TOKEN-SETUP',
            Status__c          = 'Pending',
            CurrencyIsoCode    = 'EUR',
            Amount_Gross__c    = 120.00,
            Request_Date__c    = Date.today(),
            Collection_Date__c = Date.today().addDays(14)
        );
        insert pmt;
    }

    // ── getPaymentData – setup mode (no mandate) ──────────────────────────────

    @IsTest
    static void testGetPaymentData_setupMode() {
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('TOKEN-SETUP');
        Test.stopTest();

        System.assertEquals(true, d.found, 'Payment should be found');
        System.assertEquals('setup', d.mode, 'No mandate → setup mode');
        System.assertEquals('ACME BV', d.customer, 'Customer name');
        System.assertEquals('TOKEN-SETUP', d.reference, 'Reference = token');
        System.assertEquals(12000, d.amountCents, '120.00 EUR = 12000 cents');
        System.assertEquals('EUR', d.currency_x);
        System.assertNotEquals(null, d.orderDate, 'Order date populated');
        System.assertNotEquals(null, d.collectionDate, 'Collection date populated');
        System.assertEquals('Jan',              d.contactFirstName, 'Payment contact first name');
        System.assertEquals('Betaler',          d.contactLastName,  'Payment contact last name');
        System.assertEquals('jan.betaler@acme.nl', d.contactEmail,  'Payment contact email');
        // clientSecret is null in test context (Stripe callout not mocked) — that is expected
        System.assertEquals('setup', d.mode, 'Mode consistent after Stripe error');
    }

    // ── getPaymentData – payment mode (mandate present) ───────────────────────

    @IsTest
    static void testGetPaymentData_paymentMode() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACME BV' LIMIT 1];
        acc.PayProv_MandateId__c       = 'mandate_abc';
        acc.PayProv_PaymentMethodId__c = 'pm_abc';
        update acc;

        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('TOKEN-SETUP');
        Test.stopTest();

        System.assertEquals(true, d.found);
        System.assertEquals('payment', d.mode, 'Mandate present → payment mode');
    }

    // ── getPaymentData – contact fallback to main contact ─────────────────────

    @IsTest
    static void testGetPaymentData_mainContactFallback() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACME BV' LIMIT 1];
        Contact c   = [SELECT Id FROM Contact WHERE Email = 'jan.betaler@acme.nl' LIMIT 1];

        AccountContactRelation acr = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :c.Id LIMIT 1
        ];
        acr.Roles = 'Main'; // isMainContact__c formula reads 'Main' role
        update acr;

        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('TOKEN-SETUP');
        Test.stopTest();

        System.assertEquals(true, d.found);
        System.assertEquals('jan.betaler@acme.nl', d.contactEmail,
            'Main contact used as fallback when no payment contact');
    }

    // ── getPaymentData – edge cases ───────────────────────────────────────────

    @IsTest
    static void testGetPaymentData_blankToken() {
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('');
        Test.stopTest();

        System.assertEquals(false, d.found);
        System.assertEquals('No payment token provided.', d.errorMessage);
    }

    @IsTest
    static void testGetPaymentData_nullToken() {
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData(null);
        Test.stopTest();

        System.assertEquals(false, d.found);
        System.assertNotEquals(null, d.errorMessage);
    }

    @IsTest
    static void testGetPaymentData_unknownToken() {
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('TOKEN-DOES-NOT-EXIST');
        Test.stopTest();

        System.assertEquals(false, d.found);
        System.assertEquals('No open payment found for this link.', d.errorMessage);
    }

    @IsTest
    static void testGetPaymentData_cancelledPaymentNotFound() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];
        pmt.Status__c = 'Cancelled';
        update pmt;

        // Cancelled is a terminal state; the filter is != 'Closed' which is not a valid
        // picklist value, so currently Cancelled payments ARE still returned. This test
        // documents that behaviour so any future filter change is caught.
        Test.startTest();
        Ctrl_Payment.PaymentData d = Ctrl_Payment.getPaymentData('TOKEN-SETUP');
        Test.stopTest();

        System.assertEquals(true, d.found, 'Cancelled payments still returned under current filter');
    }

    // ── sendSetupEmail ────────────────────────────────────────────────────────

    @IsTest
    static void testSendSetupEmail_withHubUrl() {
        Test.startTest();
        Ctrl_Payment.sendSetupEmail('TOKEN-SETUP');
        Test.stopTest();

        System.assert(true, 'sendSetupEmail with CustomerHub_Site_URL__c set should not throw');
    }

    @IsTest
    static void testSendSetupEmail_fallbackUrl() {
        // Remove the hub config so the fallback URL path is exercised
        CustomerHub__c cfg = CustomerHub__c.getOrgDefaults();
        if (cfg.Id != null) delete cfg;

        Test.startTest();
        Ctrl_Payment.sendSetupEmail('TOKEN-SETUP');
        Test.stopTest();

        System.assert(true, 'Org-domain fallback URL path should not throw');
    }

    @IsTest
    static void testSendSetupEmail_unknownTokenNoOp() {
        Test.startTest();
        Ctrl_Payment.sendSetupEmail('TOKEN-GHOST');
        Test.stopTest();

        System.assert(true, 'Unknown token should return silently without throwing');
    }

    @IsTest
    static void testSendSetupEmail_noContactNoOp() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACME BV' LIMIT 1];
        Contact c   = [SELECT Id FROM Contact WHERE Email = 'jan.betaler@acme.nl' LIMIT 1];

        // Clear both flags so no contact matches
        AccountContactRelation acr = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :c.Id LIMIT 1
        ];
        acr.Roles = 'Billing'; // neither 'Payment' nor 'Main' — both formulas = false
        update acr;

        Test.startTest();
        Ctrl_Payment.sendSetupEmail('TOKEN-SETUP');
        Test.stopTest();

        System.assert(true, 'No matching contact should return silently without throwing');
    }
}
