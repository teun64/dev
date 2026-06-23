@IsTest
private class Test_Ctrl_PreferenceCenter {

    // ── Test data ─────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Contact c = new Contact(
            FirstName = 'Jane',
            LastName  = 'Tester',
            Email     = 'jane.tester@example.com'
        );
        insert c;

        // Seed two preference rows
        List<CommunicationPreference__c> prefs = new List<CommunicationPreference__c>{
            new CommunicationPreference__c(
                Contact__c          = c.Id,
                Brand__c            = 'E',
                Category__c         = 'MARKETING',
                Channel__c          = 'EMAIL',
                CommunicationType__c = 'NEWSLETTER',
                IsEnabled__c        = false,
                LegalBasis__c       = 'CONSENT',
                Source__c           = 'Support',
                CompositeKey__c     = c.Id + '_E_MARKETING_EMAIL_NEWSLETTER'
            ),
            new CommunicationPreference__c(
                Contact__c          = c.Id,
                Brand__c            = 'E',
                Category__c         = 'MARKETING',
                Channel__c          = 'SMS',
                CommunicationType__c = 'PROMOTIONS',
                IsEnabled__c        = true,
                LegalBasis__c       = 'CONSENT',
                Source__c           = 'Support',
                CompositeKey__c     = c.Id + '_E_MARKETING_SMS_PROMOTIONS'
            )
        };
        insert prefs;
    }

    // ── getPreferences ────────────────────────────────────────────────────────

    @IsTest
    static void testGetPreferences_returnsRows() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        Ctrl_PreferenceCenter.PreferencePageData page =
            Ctrl_PreferenceCenter.getPreferences(c.Id);
        Test.stopTest();

        System.assertEquals('Jane Tester', page.contactName, 'Contact name mismatch');
        System.assertEquals(2, page.preferences.size(), 'Should return 2 rows');
    }

    @IsTest
    static void testGetPreferences_nullId() {
        Test.startTest();
        try {
            Ctrl_PreferenceCenter.getPreferences(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Contact Id'));
        }
        Test.stopTest();
    }

    // ── savePreferences ───────────────────────────────────────────────────────

    @IsTest
    static void testSavePreferences_toggleCreatesAudit() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        CommunicationPreference__c pref = [
            SELECT Id, IsEnabled__c, Brand__c, Category__c, Channel__c,
                   CommunicationType__c, CompositeKey__c
            FROM CommunicationPreference__c
            WHERE CommunicationType__c = 'NEWSLETTER'
            LIMIT 1
        ];

        // Toggle: false → true
        pref.IsEnabled__c = true;
        List<CommunicationPreference__c> toSave =
            new List<CommunicationPreference__c>{ pref };

        Test.startTest();
        Integer auditCount = Ctrl_PreferenceCenter.savePreferences(
            c.Id, toSave, 'sess_001', 'req_001'
        );
        Test.stopTest();

        System.assertEquals(1, auditCount, 'One audit record should be written');

        CommunicationPreferenceAudit__c audit = [
            SELECT Old_Value__c, New_Value__c, Change_Source__c,
                   Change_Reason__c, Session_Id__c, Request_Id__c
            FROM CommunicationPreferenceAudit__c
            WHERE Contact__c = :c.Id
            LIMIT 1
        ];
        System.assertEquals(false,             audit.Old_Value__c,     'Old value wrong');
        System.assertEquals(true,              audit.New_Value__c,     'New value wrong');
        System.assertEquals('SUPPORT_CONSOLE', audit.Change_Source__c, 'Source wrong');
        System.assertEquals('USER_ACTION',     audit.Change_Reason__c, 'Reason wrong');
        System.assertEquals('sess_001',        audit.Session_Id__c,    'Session Id wrong');
        System.assertEquals('req_001',         audit.Request_Id__c,    'Request Id wrong');
    }

    @IsTest
    static void testSavePreferences_noChangeNoAudit() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        CommunicationPreference__c pref = [
            SELECT Id, IsEnabled__c, Brand__c, Category__c, Channel__c,
                   CommunicationType__c, CompositeKey__c
            FROM CommunicationPreference__c
            WHERE CommunicationType__c = 'NEWSLETTER'
            LIMIT 1
        ];
        // IsEnabled__c stays false — no change

        Test.startTest();
        Integer auditCount = Ctrl_PreferenceCenter.savePreferences(
            c.Id, new List<CommunicationPreference__c>{ pref }, null, null
        );
        Test.stopTest();

        System.assertEquals(0, auditCount, 'No audit record should be written when nothing changed');
    }

    @IsTest
    static void testSavePreferences_newRowAudited() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        // Insert a brand-new preference row (no Id)
        CommunicationPreference__c newPref = new CommunicationPreference__c(
            Brand__c            = 'M',
            Category__c         = 'PRODUCT',
            Channel__c          = 'PUSH',
            CommunicationType__c = 'APP_UPDATES',
            IsEnabled__c        = true,
            LegalBasis__c       = 'CONSENT',
            CompositeKey__c     = c.Id + '_M_PRODUCT_PUSH_APP_UPDATES'
        );

        Test.startTest();
        Integer auditCount = Ctrl_PreferenceCenter.savePreferences(
            c.Id, new List<CommunicationPreference__c>{ newPref }, null, null
        );
        Test.stopTest();

        System.assertEquals(1, auditCount, 'New row should generate one audit record');
        List<CommunicationPreferenceAudit__c> audits = [
            SELECT Old_Value__c, New_Value__c
            FROM CommunicationPreferenceAudit__c
            WHERE CommunicationType__c = 'APP_UPDATES'
        ];
        System.assertEquals(1,     audits.size(),          'One audit expected');
        System.assertEquals(false, audits[0].Old_Value__c, 'Old value should be false for new row');
        System.assertEquals(true,  audits[0].New_Value__c, 'New value should match IsEnabled__c');
    }

    @IsTest
    static void testSavePreferences_nullContactId() {
        Test.startTest();
        try {
            Ctrl_PreferenceCenter.savePreferences(null, new List<CommunicationPreference__c>(), null, null);
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // ── getAuditHistory ───────────────────────────────────────────────────────

    @IsTest
    static void testGetAuditHistory_empty() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        List<CommunicationPreferenceAudit__c> history =
            Ctrl_PreferenceCenter.getAuditHistory(c.Id, 10);
        Test.stopTest();

        System.assertEquals(0, history.size(), 'No audits should exist yet');
    }

    @IsTest
    static void testGetAuditHistory_afterSave() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        CommunicationPreference__c pref = [
            SELECT Id, IsEnabled__c, Brand__c, Category__c, Channel__c,
                   CommunicationType__c, CompositeKey__c
            FROM CommunicationPreference__c
            WHERE CommunicationType__c = 'NEWSLETTER'
            LIMIT 1
        ];
        pref.IsEnabled__c = true;
        Ctrl_PreferenceCenter.savePreferences(
            c.Id, new List<CommunicationPreference__c>{ pref }, null, null
        );

        Test.startTest();
        List<CommunicationPreferenceAudit__c> history =
            Ctrl_PreferenceCenter.getAuditHistory(c.Id, 50);
        Test.stopTest();

        System.assertEquals(1, history.size(), 'One audit record expected');
        System.assertNotEquals(null, history[0].EventTimestamp__c, 'Timestamp should be set');
    }
}
