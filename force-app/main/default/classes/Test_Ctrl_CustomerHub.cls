@IsTest(SeeAllData=false)
private class Test_Ctrl_CustomerHub {

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name                = 'Test Hub Account',
            BillingCountryCode  = 'NL',
            RecordTypeId        = Schema.SObjectType.Account
                                    .getRecordTypeInfosByDeveloperName()
                                    .get('B2B')
                                    .getRecordTypeId()
        );
        acc.Reseller_Name__c = '1';
        insert acc;

        Contact con = new Contact(
            AccountId = acc.Id,
            FirstName = 'Apex',
            LastName  = 'Test Hub Contact',
            Email     = 'apex.test.customerhub@mvsc.invalid.test'
        );
        insert con;

        insert new Subscription25__Administration__c(
            Name                                       = 'Test Administration',
            Reseller__c                                = '1',
            Subscription25__Active__c                  = true,
            Subscription25__Billing_Name__c            = 'Test Reseller B.V.',
            Subscription25__Phone__c                   = '+31 123456789',
            email_sales__c                              = 'contact@testreseller.example',
            Subscription25__Website__c                 = 'testreseller.example',
            Subscription25__Billing_Street__c          = 'Teststraat 1',
            Subscription25__Billing_Postal_Code__c     = '1234 AB',
            Subscription25__Billing_City__c            = 'Amsterdam',
            Subscription25__Billing_Country__c         = 'Netherlands',
            Subscription25__Chamber_Of_Commerce_Number__c = '12345678',
            Subscription25__VAT_Number__c              = 'NL123456789B01',
            Managing_directors__c                      = 'J. Doe',
            Subscription25__IBAN__c                    = 'NL91ABNA0417164300',
            Subscription25__BIC__c                     = 'ABNANL2A',
            Privacy_Policy_URL__c                      = 'https://testreseller.example/privacy',
            Terms_Conditions_URL__c                    = 'https://testreseller.example/terms',
            Subscription25__Invoice_Number_Prefix__c   = 'TST'
        );
    }

    @IsTest
    static void testGetAdminInfo_byContactId_returnsResellerAdministration() {
        Contact con = [SELECT Id FROM Contact WHERE Email = 'apex.test.customerhub@mvsc.invalid.test' LIMIT 1];

        Ctrl_CustomerHub.AdminInfo info;
        Test.startTest();
        info = Ctrl_CustomerHub.getAdminInfo(con.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, info, 'AdminInfo should be returned when the contact resolves to a reseller with an active Administration');
        System.assertEquals('Test Reseller B.V.', info.name, 'name should come from the matched Administration record');
        System.assertEquals('contact@testreseller.example', info.email, 'email should come from the matched Administration record');
        System.assertEquals('https://testreseller.example', info.website, 'website should be normalized to include https://');
        System.assertEquals('12345678', info.kvk, 'kvk should come from the matched Administration record');
        System.assertEquals('NL123456789B01', info.vatNumber, 'vatNumber should come from the matched Administration record');
        System.assertEquals('J. Doe', info.managingDirectors, 'managingDirectors should come from the matched Administration record');
        System.assertEquals('NL91ABNA0417164300', info.iban, 'iban should come from the matched Administration record');
        System.assertEquals('ABNANL2A', info.bic, 'bic should come from the matched Administration record');
        System.assertEquals('https://testreseller.example/privacy', info.privacyPolicyUrl, 'privacyPolicyUrl should come from the matched Administration record');
        System.assertEquals('https://testreseller.example/terms', info.termsConditionsUrl, 'termsConditionsUrl should come from the matched Administration record');
    }

    @IsTest
    static void testGetAdminInfo_noContactId_fallsBackToBrand() {
        Ctrl_CustomerHub.AdminInfo info;
        Test.startTest();
        info = Ctrl_CustomerHub.getAdminInfo(null, 'M');
        Test.stopTest();

        // Brand 'M' maps to reseller '1' internally, matching the fixture Administration's Reseller__c.
        System.assertNotEquals(null, info, 'Brand fallback should still resolve an Administration when no contact can be identified');
        System.assertEquals('Test Reseller B.V.', info.name, 'Brand fallback should resolve to the same reseller Administration');
    }

    @IsTest
    static void testGetAdminInfo_unknownBrandAndNoContact_returnsNull() {
        Ctrl_CustomerHub.AdminInfo info;
        Test.startTest();
        info = Ctrl_CustomerHub.getAdminInfo(null, 'ZZ');
        Test.stopTest();

        System.assertEquals(null, info, 'An unmapped brand with no resolvable contact should return null rather than throwing');
    }

    @IsTest
    static void testGetAdminInfo_nonIdContactId_fallsBackToBrand() {
        Ctrl_CustomerHub.AdminInfo info;
        Test.startTest();
        // Guest Preference Center links reuse the ?cid= param for a hashed token, not a Contact Id.
        info = Ctrl_CustomerHub.getAdminInfo('3386d7751d5881dad24e32108db0a7b537e0e2f79691505412257455858ef8d3', 'M');
        Test.stopTest();

        System.assertNotEquals(null, info, 'A non-Id contactId should fall back to the brand-derived reseller rather than throwing');
        System.assertEquals('Test Reseller B.V.', info.name, 'Fallback should resolve the same reseller Administration as the brand default');
    }

    @IsTest
    static void testGetAdminInfo_contactWithNoAccount_fallsBackToBrand() {
        Contact orphan = new Contact(FirstName = 'No', LastName = 'Account');
        insert orphan;

        Ctrl_CustomerHub.AdminInfo info;
        Test.startTest();
        info = Ctrl_CustomerHub.getAdminInfo(orphan.Id, 'M');
        Test.stopTest();

        System.assertNotEquals(null, info, 'A contact with no AccountId should fall back to the brand-derived reseller rather than returning null');
        System.assertEquals('Test Reseller B.V.', info.name, 'Fallback should resolve the same reseller Administration as the brand default');
    }
}
