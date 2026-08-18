@IsTest
private class Test_Ctrl_PreferenceCenter {

    // ── Test data ─────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        // CommunicationPreferenceConfig__c is a real object, not a custom metadata type — unlike
        // the CommunicationTypeCategory__mdt it replaced, its rows are NOT automatically visible
        // inside tests, so getPreferences()'s catalog query would otherwise see zero rows here.
        Map<String, Id> configIdByKey = new Map<String, Id>();
        List<CommunicationPreferenceConfig__c> configs = new List<CommunicationPreferenceConfig__c>{
            new CommunicationPreferenceConfig__c(Brand__c = 'E', CommunicationType__c = 'NEWSLETTER',  Channel__c = 'EMAIL', Category__c = 'MARKETING'),
            new CommunicationPreferenceConfig__c(Brand__c = 'E', CommunicationType__c = 'PROMOTIONS',  Channel__c = 'EMAIL', Category__c = 'MARKETING'),
            new CommunicationPreferenceConfig__c(Brand__c = 'M', CommunicationType__c = 'APP_UPDATES', Channel__c = 'PUSH',  Category__c = 'PRODUCT')
        };
        insert configs;
        for (CommunicationPreferenceConfig__c cfg : configs) {
            configIdByKey.put(cfg.Brand__c + '|' + cfg.CommunicationType__c + '|' + cfg.Channel__c, cfg.Id);
        }

        Contact c = new Contact(
            FirstName = 'Jane',
            LastName  = 'Tester',
            Email     = 'jane.tester@example.com'
        );
        insert c;

        // Seed two preference rows
        List<CommunicationPreference__c> prefs = new List<CommunicationPreference__c>{
            new CommunicationPreference__c(
                Contact__c      = c.Id,
                Config__c       = configIdByKey.get('E|NEWSLETTER|EMAIL'),
                IsEnabled__c    = false,
                LegalBasis__c   = 'CONSENT',
                Source__c       = 'Support',
                CompositeKey__c = c.Id + '_E_MARKETING_EMAIL_NEWSLETTER'
            ),
            new CommunicationPreference__c(
                Contact__c      = c.Id,
                Config__c       = configIdByKey.get('E|PROMOTIONS|EMAIL'),
                IsEnabled__c    = true,
                LegalBasis__c   = 'CONSENT',
                Source__c       = 'Support',
                CompositeKey__c = c.Id + '_E_MARKETING_EMAIL_PROMOTIONS'
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
        // The response is catalog-driven — one row per CommunicationPreferenceConfig__c entry,
        // not just the two rows this test seeded — so assert the seeded rows are present and
        // correct rather than asserting an exact total that drifts as the catalog grows.
        // Matched by Config__r.CommunicationType__c/Channel__c rather than CompositeKey__c — the
        // rbb_CommunicationPreference Before Save flow re-stamps CompositeKey__c on insert, so
        // it won't equal whatever literal string this test's @TestSetup assigned.
        Map<String, CommunicationPreference__c> byTypeChannel = new Map<String, CommunicationPreference__c>();
        for (CommunicationPreference__c p : page.preferences) {
            if (p.Config__r?.Brand__c == 'E') {
                byTypeChannel.put(p.Config__r.CommunicationType__c + '|' + p.Config__r.Channel__c, p);
            }
        }
        System.assert(
            byTypeChannel.containsKey('NEWSLETTER|EMAIL'), 'Seeded Newsletter row should be present'
        );
        System.assertEquals(
            false, byTypeChannel.get('NEWSLETTER|EMAIL').IsEnabled__c,
            'Seeded Newsletter row should keep its saved value'
        );
        System.assert(
            byTypeChannel.containsKey('PROMOTIONS|EMAIL'), 'Seeded Promotions row should be present'
        );
        System.assertEquals(
            true, byTypeChannel.get('PROMOTIONS|EMAIL').IsEnabled__c,
            'Seeded Promotions row should keep its saved value'
        );
    }

    @IsTest
    static void testGetPreferences_nullId() {
        Test.startTest();
        try {
            Ctrl_PreferenceCenter.getPreferences(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            // AuraHandledException.getMessage() only returns the constructor text if
            // setMessage() was also called, which this throw site doesn't do — so only the
            // exception type is reliably observable here (same pattern as
            // testSavePreferences_nullContactId below).
            System.assert(true);
        }
        Test.stopTest();
    }

    // ── savePreferences ───────────────────────────────────────────────────────

    @IsTest
    static void testSavePreferences_toggleCreatesAudit() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        CommunicationPreference__c pref = [
            SELECT Id, IsEnabled__c, Config__c, CompositeKey__c, BusinessLine__c,
                   Google_Ads_Eligible__c, Channel_Detail__c
            FROM CommunicationPreference__c
            WHERE Config__r.CommunicationType__c = 'NEWSLETTER'
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
            SELECT Id, IsEnabled__c, Config__c, CompositeKey__c, BusinessLine__c,
                   Google_Ads_Eligible__c, Channel_Detail__c
            FROM CommunicationPreference__c
            WHERE Config__r.CommunicationType__c = 'NEWSLETTER'
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
        Id appUpdatesConfigId = [
            SELECT Id FROM CommunicationPreferenceConfig__c
            WHERE Brand__c = 'M' AND CommunicationType__c = 'APP_UPDATES' AND Channel__c = 'PUSH'
            LIMIT 1
        ].Id;

        // Insert a brand-new preference row (no Id)
        CommunicationPreference__c newPref = new CommunicationPreference__c(
            Config__c       = appUpdatesConfigId,
            IsEnabled__c    = true,
            LegalBasis__c   = 'CONSENT',
            CompositeKey__c = c.Id + '_M_PRODUCT_PUSH_APP_UPDATES'
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
            SELECT Id, IsEnabled__c, Config__c, CompositeKey__c, BusinessLine__c,
                   Google_Ads_Eligible__c, Channel_Detail__c
            FROM CommunicationPreference__c
            WHERE Config__r.CommunicationType__c = 'NEWSLETTER'
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
