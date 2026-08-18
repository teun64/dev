@IsTest
private class Test_Ctrl_PreferenceCenterGuest {

    @TestSetup
    static void makeData() {
        insert new PreferenceTokenConfig__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Secret__c    = 'unit-test-secret',
            Base_Url__c  = 'https://example.my.site.com/customerhub'
        );

        insert new Contact(
            FirstName = 'Jane',
            LastName  = 'Tester',
            Email     = 'jane.guest@example.com'
        ); // Trigger_Contact stamps Preference_Token_Key__c from Email

        // CommunicationPreferenceConfig__c is a real object, not visible in tests by default
        // the way the CommunicationTypeCategory__mdt it replaced was.
        insert new CommunicationPreferenceConfig__c(
            Brand__c = 'M', CommunicationType__c = 'NEWSLETTER', Channel__c = 'EMAIL', Category__c = 'MARKETING'
        );
    }

    @IsTest
    static void testGetPreferences_validTokenResolvesContact() {
        Contact c = [SELECT Id, Preference_Token_Key__c FROM Contact LIMIT 1];
        String token = c.Preference_Token_Key__c;

        Test.startTest();
        Ctrl_PreferenceCenter.PreferencePageData page =
            Ctrl_PreferenceCenterGuest.getPreferences(token);
        Test.stopTest();

        System.assertEquals('Jane Tester', page.contactName, 'Should resolve to the seeded contact');
    }

    @IsTest
    static void testGetPreferences_invalidTokenRejected() {
        try {
            Ctrl_PreferenceCenterGuest.getPreferences('garbage');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testGetPreferences_unknownHashRejected() {
        try {
            Ctrl_PreferenceCenterGuest.getPreferences('no-such-hash');
            System.assert(false, 'Expected AuraHandledException for unmatched hash');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('No contact found'));
        }
    }

    @IsTest
    static void testGetBrandTheme_passesThroughToPreferenceCenter() {
        Test.startTest();
        Ctrl_PreferenceCenter.BrandThemeData theme = Ctrl_PreferenceCenterGuest.getBrandTheme('M');
        Test.stopTest();

        System.assertEquals('M', theme.brand, 'Guest passthrough should return the same brand it was asked for');
    }

    @IsTest
    static void testGetMCBrandAssets_blankIdReturnsNull() {
        Test.startTest();
        Ctrl_PreferenceCenter.BrandThemeData assets = Ctrl_PreferenceCenterGuest.getMCBrandAssets(null);
        Test.stopTest();

        System.assertEquals(null, assets, 'No MC brand id means no callout — should return null, not throw');
    }

    @IsTest
    static void testSavePreferences_persistsUnderResolvedContact() {
        Contact c = [SELECT Id, Preference_Token_Key__c FROM Contact LIMIT 1];
        String token = c.Preference_Token_Key__c;
        CommunicationPreferenceConfig__c cfg = [
            SELECT Id FROM CommunicationPreferenceConfig__c
            WHERE Brand__c = 'M' AND CommunicationType__c = 'NEWSLETTER' AND Channel__c = 'EMAIL'
            LIMIT 1
        ];

        CommunicationPreference__c pref = new CommunicationPreference__c(
            Config__c            = cfg.Id,
            IsEnabled__c         = true,
            LegalBasis__c        = 'CONSENT',
            CompositeKey__c      = c.Id + '_M_MARKETING_EMAIL_NEWSLETTER'
        );

        Test.startTest();
        Integer auditCount = Ctrl_PreferenceCenterGuest.savePreferences(
            token, new List<CommunicationPreference__c>{ pref }, 'sess', 'req'
        );
        Test.stopTest();

        System.assertEquals(1, auditCount, 'One audit record expected');
        CommunicationPreference__c saved = [
            SELECT Contact__c, IsEnabled__c FROM CommunicationPreference__c
            WHERE CompositeKey__c = :pref.CompositeKey__c
        ];
        System.assertEquals(
            c.Id, saved.Contact__c,
            'Preference must be saved under the token-resolved contact, never a client-supplied one'
        );
    }
}
