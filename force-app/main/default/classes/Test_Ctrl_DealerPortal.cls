@IsTest(SeeAllData=false)
private class Test_Ctrl_DealerPortal {

    private static final String PORTAL_USER_USERNAME = 'apex.test.dealerportal@mvsc.invalid.test';

    private static User portalUser() {
        return [SELECT Id FROM User WHERE Username = :PORTAL_USER_USERNAME LIMIT 1];
    }

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name                = 'Test Dealer Portal Account',
            BillingCountryCode  = 'NL',
            RecordTypeId        = Schema.SObjectType.Account
                                    .getRecordTypeInfosByDeveloperName()
                                    .get('B2B')
                                    .getRecordTypeId()
        );
        acc.BillingStreet     = 'Teststraat 1';
        acc.BillingPostalCode = '1234AB';
        acc.BillingCity       = 'Amsterdam';
        acc.Reseller_Name__c  = '1';
        insert acc;

        Contact con = new Contact(
            AccountId = acc.Id,
            FirstName = 'Apex',
            LastName  = 'Test Portal User',
            Email     = PORTAL_USER_USERNAME
        );
        insert con;

        Id portalProfileId = [SELECT Id FROM Profile WHERE Name = 'Partner Community User' LIMIT 1].Id;
        insert new User(
            ProfileId         = portalProfileId,
            ContactId         = con.Id,
            Username          = PORTAL_USER_USERNAME,
            Email             = PORTAL_USER_USERNAME,
            FirstName         = 'Apex',
            LastName          = 'Test Portal User',
            Alias             = 'atpuser',
            LocaleSidKey      = 'nl_NL',
            LanguageLocaleKey = 'nl_NL',
            TimeZoneSidKey    = 'Europe/Amsterdam',
            EmailEncodingKey  = 'UTF-8',
            IsActive          = true
        );

        insert new Subscription25__Administration__c(
            Name                                       = 'Test Administration',
            Reseller__c                                = '1',
            Subscription25__Billing_Name__c            = 'Test Reseller B.V.',
            Subscription25__Phone__c                   = '+31 123456789',
            Subscription25__Billing_Email_Address__c   = 'contact@testreseller.example',
            Subscription25__Website__c                 = 'www.testreseller.example',
            Subscription25__Billing_Street__c          = 'Teststraat 1',
            Subscription25__Billing_Postal_Code__c     = '1234 AB',
            Subscription25__Billing_City__c            = 'Amsterdam',
            Subscription25__Chamber_Of_Commerce_Number__c = '12345678',
            Subscription25__VAT_Number__c              = 'NL123456789B01',
            Managing_directors__c                      = 'J. Doe',
            Subscription25__IBAN__c                    = 'NL91ABNA0417164300',
            Subscription25__BIC__c                     = 'ABNANL2A',
            Privacy_Policy_URL__c                      = 'https://testreseller.example/privacy',
            Terms_Conditions_URL__c                    = 'https://testreseller.example/terms',
            Subscription25__Invoice_Number_Prefix__c   = 'TST',
            Subscription25__Billing_Country__c         = 'NL'
        );
    }

    @IsTest
    static void testGetFooterInfo_authenticatedUser_returnsAdministrationLinks() {
        Ctrl_DealerPortal.FooterDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerPortal.getFooterInfo();
        }
        Test.stopTest();

        System.assertEquals('Test Reseller B.V.', dto.companyName, 'companyName should come from the matched Administration record');
        System.assertEquals('1234 AB', dto.postalCode, 'postalCode should come from the matched Administration record');
        System.assertEquals('https://testreseller.example/privacy', dto.privacyPolicyUrl, 'privacyPolicyUrl should come from the matched Administration record');
        System.assertEquals('https://testreseller.example/terms', dto.termsConditionsUrl, 'termsConditionsUrl should come from the matched Administration record');
        System.assertEquals('12345678', dto.chamberOfCommerceNumber, 'chamberOfCommerceNumber should come from the matched Administration record');
        System.assertEquals('NL123456789B01', dto.vatNumber, 'vatNumber should come from the matched Administration record');
        System.assertEquals('J. Doe', dto.managingDirectors, 'managingDirectors should come from the matched Administration record');
        System.assertEquals('NL91ABNA0417164300', dto.iban, 'iban should come from the matched Administration record');
        System.assertEquals('ABNANL2A', dto.bic, 'bic should come from the matched Administration record');
        // Bank_6_Account_Number__c/Bank_6_Sort_Code__c are formula fields - can't be set directly in
        // a test fixture, so this only confirms the query/mapping doesn't throw, not a specific value.
        System.assertEquals(null, dto.bankAccountNumber, 'Formula field has no source value in this fixture, so it resolves to null - just checking the mapping runs');
    }

    @IsTest
    static void testGetFooterInfo_guestUser_returnsFallback() {
        Ctrl_DealerPortal.FooterDTO dto = Ctrl_DealerPortal.getFooterInfo();

        System.assertEquals('Moving Intelligence B.V.', dto.companyName, 'Guest/unmatched context should fall back to the default company info');
        System.assertEquals(null, dto.privacyPolicyUrl, 'Fallback context has no Administration record to source a privacy URL from');
    }

    @IsTest
    static void testGetBrandConfig_returnsAConfig() {
        Ctrl_DealerPortal.BrandConfigDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerPortal.getBrandConfig();
        }
        Test.stopTest();

        System.assertNotEquals(null, dto, 'A brand config (matched or fallback) should always be returned');
        System.assertNotEquals(null, dto.brandCode, 'brandCode should be populated from BrandThemeConfig__mdt');
    }

    @IsTest
    static void testSubmitSignupRequest_createsLead() {
        Test.startTest();
        Ctrl_DealerPortal.submitSignupRequest('Prospect Co', 'Jane Doe', 'jane@prospect.example', '+31 987654321', 'Netherlands', 'Interested in becoming a dealer');
        Test.stopTest();

        Lead l = [SELECT Company, Email, LeadSource FROM Lead WHERE Email = 'jane@prospect.example' LIMIT 1];
        System.assertEquals('Prospect Co', l.Company, 'Lead company should match the submitted value');
        System.assertEquals('Dealer Portal', l.LeadSource, 'Lead source should be tagged as Dealer Portal');
    }

    @IsTest
    static void testSubmitSignupRequest_missingRequiredFields_throws() {
        Test.startTest();
        try {
            Ctrl_DealerPortal.submitSignupRequest(null, 'Jane Doe', null, null, null, null);
            System.assert(false, 'Expected an exception when companyName/email are missing');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException expected for missing required fields');
        }
        Test.stopTest();
    }
}
