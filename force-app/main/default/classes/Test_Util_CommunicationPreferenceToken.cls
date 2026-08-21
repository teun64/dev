@IsTest
private class Test_Util_CommunicationPreferenceToken {

    @TestSetup
    static void makeData() {
        insert new PreferenceTokenConfig__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Secret__c    = 'unit-test-secret',
            Base_Url__c  = 'https://example.my.site.com/customerhub'
        );
    }

    @IsTest
    static void testHashEmail_consistentAndCaseInsensitive() {
        String h1 = Util_CommunicationPreferenceToken.hashEmail('Jane@Example.com');
        String h2 = Util_CommunicationPreferenceToken.hashEmail('jane@example.com');
        System.assertEquals(h1, h2, 'Hash should be case-insensitive on the email');
    }

    @IsTest
    static void testHashEmail_blankReturnsNull() {
        System.assertEquals(null, Util_CommunicationPreferenceToken.hashEmail(null));
        System.assertEquals(null, Util_CommunicationPreferenceToken.hashEmail(''));
    }

    @IsTest
    static void testBuildPreferenceCenterUrl_wellFormed() {
        String url = Util_CommunicationPreferenceToken.buildPreferenceCenterUrl('hash123');

        System.assertEquals(
            'https://example.my.site.com/customerhub/preferences?token=hash123&brand=M',
            url,
            'Url should be the configured base + /preferences?token=<keyHash>&brand=M, with no extra wrapping'
        );
    }

    @IsTest
    static void testBuildPreferenceCenterUrl_blankHashReturnsNull() {
        System.assertEquals(null, Util_CommunicationPreferenceToken.buildPreferenceCenterUrl(null));
    }

    @IsTest
    static void testBuildPreferenceCenterUrl_missingBaseUrlThrows() {
        update new PreferenceTokenConfig__c(
            Id          = PreferenceTokenConfig__c.getOrgDefaults().Id,
            Base_Url__c = null
        );

        try {
            Util_CommunicationPreferenceToken.buildPreferenceCenterUrl('hash123');
            System.assert(false, 'Expected TokenConfigException');
        } catch (Util_CommunicationPreferenceToken.TokenConfigException e) {
            System.assert(true);
        }
    }
}
