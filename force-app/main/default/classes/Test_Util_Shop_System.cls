@IsTest(SeeAllData=false)
private class Test_Util_Shop_System {

    private static final String PORTAL_USER_USERNAME = 'apex.test.utilshopsystem@mvsc.invalid.test';
    private static final String EMAIL_USER_USERNAME   = 'apex.test.utilshopsystem.email@mvsc.invalid.test';

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name                = 'Test Util Shop System Account',
            BillingCountryCode  = 'NL',
            RecordTypeId        = Schema.SObjectType.Account
                                    .getRecordTypeInfosByDeveloperName()
                                    .get('B2B')
                                    .getRecordTypeId()
        );
        acc.Reseller_Name__c = '1';
        insert acc;

        Contact conWithUser = new Contact(
            AccountId = acc.Id,
            FirstName = 'Apex',
            LastName  = 'Test Portal User',
            Email     = PORTAL_USER_USERNAME,
            Language__c = 'EN'
        );
        insert conWithUser;
        Contact conEmailOnly = new Contact(
            AccountId = acc.Id,
            FirstName = 'Apex',
            LastName  = 'Test Email User',
            Email     = EMAIL_USER_USERNAME,
            Language__c = 'EN'
        );
        insert conEmailOnly;

        Id portalProfileId = [SELECT Id FROM Profile WHERE Name = 'Partner Community User' LIMIT 1].Id;
        insert new User(
            ProfileId         = portalProfileId,
            ContactId         = conWithUser.Id,
            Username          = PORTAL_USER_USERNAME,
            Email             = PORTAL_USER_USERNAME,
            FirstName         = 'Apex',
            LastName          = 'Test Portal User',
            Alias             = 'atputest',
            LocaleSidKey      = 'nl_NL',
            LanguageLocaleKey = 'nl_NL',
            TimeZoneSidKey    = 'Europe/Amsterdam',
            EmailEncodingKey  = 'UTF-8',
            IsActive          = true
        );

        // Identity/internal-style user: no ContactId, must resolve via Email match instead.
        Id identityProfileId = [SELECT Id FROM Profile WHERE Name = 'Identity User' LIMIT 1].Id;
        insert new User(
            ProfileId         = identityProfileId,
            Username          = EMAIL_USER_USERNAME,
            Email             = EMAIL_USER_USERNAME,
            FirstName         = 'Apex',
            LastName          = 'Test Email User',
            Alias             = 'atetest',
            LocaleSidKey      = 'nl_NL',
            LanguageLocaleKey = 'nl_NL',
            TimeZoneSidKey    = 'Europe/Amsterdam',
            EmailEncodingKey  = 'UTF-8',
            IsActive          = true
        );

        insert new Subscription25__Administration__c(
            Name = 'Test Util Shop System Admin',
            Reseller__c = '1',
            Subscription25__Invoice_Number_Prefix__c = 'TUS',
            Subscription25__Billing_Country__c = 'NL'
        );
    }

    @IsTest
    static void testResolveDealerAccountId_viaContactId() {
        User portalUser = [SELECT Id FROM User WHERE Username = :PORTAL_USER_USERNAME LIMIT 1];
        Util_Shop_System.DealerAccountLookup lookup;
        System.runAs(portalUser) {
            lookup = Util_Shop_System.resolveDealerAccountId(UserInfo.getUserId());
        }
        System.assertNotEquals(null, lookup.accountId, 'Should resolve the Account via the User.ContactId path');
        System.assertNotEquals(null, lookup.contactId, 'Should carry the Contact Id through');
        System.assertEquals('EN', lookup.contactLanguage, 'Should carry the Contact language through');
    }

    @IsTest
    static void testResolveDealerAccountId_viaEmailFallback() {
        User emailUser = [SELECT Id FROM User WHERE Username = :EMAIL_USER_USERNAME LIMIT 1];
        Util_Shop_System.DealerAccountLookup lookup;
        System.runAs(emailUser) {
            lookup = Util_Shop_System.resolveDealerAccountId(UserInfo.getUserId());
        }
        System.assertNotEquals(null, lookup.accountId, 'A ContactId-less user should still resolve via Email match on Contact');
    }

    @IsTest
    static void testResolveDealerAccountId_noMatch() {
        Util_Shop_System.DealerAccountLookup lookup = Util_Shop_System.resolveDealerAccountId(UserInfo.getUserId());
        System.assertEquals(null, lookup.accountId, 'The running (internal admin) test user has no matching Contact, so this should resolve to nothing');
    }

    @IsTest
    static void testGetAdministrationsByReseller_blankCode() {
        List<Subscription25__Administration__c> result = Util_Shop_System.getAdministrationsByReseller(null, 'Id');
        System.assertEquals(0, result.size(), 'A blank reseller code must short-circuit to an empty list, not query the object');
    }

    @IsTest
    static void testGetAdministrationsByReseller_returnsMatch() {
        List<Subscription25__Administration__c> result = Util_Shop_System.getAdministrationsByReseller('1', 'Id, Reseller__c');
        System.assertEquals(1, result.size(), 'Should find the fixture Administration record for reseller 1');
    }
}
