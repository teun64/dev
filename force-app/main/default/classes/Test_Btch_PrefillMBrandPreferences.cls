@IsTest
private class Test_Btch_PrefillMBrandPreferences {

    @TestSetup
    static void makeData() {
        // Config catalog - not visible in tests by default, seed our own.
        insert new List<CommunicationPreferenceConfig__c>{
            new CommunicationPreferenceConfig__c(Brand__c = 'M', CommunicationType__c = 'NEWSLETTER', Channel__c = 'EMAIL', Category__c = 'MARKETING'),
            new CommunicationPreferenceConfig__c(Brand__c = 'M', CommunicationType__c = 'PROMOTIONS', Channel__c = 'EMAIL', Category__c = 'MARKETING'),
            new CommunicationPreferenceConfig__c(Brand__c = 'M', CommunicationType__c = 'SECURITY_ALERTS', Channel__c = 'EMAIL', Category__c = 'SERVICE'),
            new CommunicationPreferenceConfig__c(Brand__c = 'E', CommunicationType__c = 'NEWSLETTER', Channel__c = 'EMAIL', Category__c = 'MARKETING')
        };

        // PrimaryBrand__c/Deactivated__c are new fields without broad Edit FLS yet (API v67
        // defaults Apex DML to User Mode) - use SYSTEM_MODE here since this is just test fixture
        // setup, not something that should depend on the running user's FLS grants.

        // Qualifying account: M-brand, active
        Account mActive = Test_Data.createAccount('Btch Prefill M Active', '9041', 'B2B', false);
        insert mActive;
        mActive.PrimaryBrand__c = 'M';
        mActive.Deactivated__c = false;
        Database.update(mActive, AccessLevel.SYSTEM_MODE);

        // Disqualifying account: M-brand, but deactivated
        Account mDeactivated = Test_Data.createAccount('Btch Prefill M Deactivated', '9042', 'B2B', false);
        insert mDeactivated;
        mDeactivated.PrimaryBrand__c = 'M';
        mDeactivated.Deactivated__c = true;
        Database.update(mDeactivated, AccessLevel.SYSTEM_MODE);

        // Disqualifying account: wrong brand
        Account eActive = Test_Data.createAccount('Btch Prefill E Active', '9043', 'B2B', false);
        insert eActive;
        eActive.PrimaryBrand__c = 'E';
        eActive.Deactivated__c = false;
        Database.update(eActive, AccessLevel.SYSTEM_MODE);

        // Contacts - inserted one at a time (bulk Contact DML faults the "rab - Contact" flow in this org)
        Contact marketingRole = new Contact(AccountId = mActive.Id, FirstName = 'Prefill', LastName = 'MarketingRole', Email = 'prefill.marketing@example.com');
        insert marketingRole;

        Contact blankRoleNoInfo = new Contact(AccountId = mActive.Id, FirstName = 'Prefill', LastName = 'BlankRoleNoInfo');
        insert blankRoleNoInfo;

        Contact billingOnly = new Contact(AccountId = mActive.Id, FirstName = 'Prefill', LastName = 'BillingOnly', Email = 'prefill.billing@example.com');
        insert billingOnly;

        Contact deactivatedAcctContact = new Contact(AccountId = mDeactivated.Id, FirstName = 'Prefill', LastName = 'DeactivatedAccount', Email = 'prefill.deactivated@example.com');
        insert deactivatedAcctContact;

        Contact wrongBrandContact = new Contact(AccountId = eActive.Id, FirstName = 'Prefill', LastName = 'WrongBrand', Email = 'prefill.wrongbrand@example.com');
        insert wrongBrandContact;

        // marketingRole: Roles = 'Main' -> Marketing__c formula true (has email + non-billing role)
        AccountContactRelation acr1 = [SELECT Id FROM AccountContactRelation WHERE ContactId = :marketingRole.Id LIMIT 1];
        acr1.Roles = 'Main';
        update acr1;

        // blankRoleNoInfo: Roles left blank, no email/phone -> Marketing__c formula would be false,
        // but the business rule says blank Roles should still count as qualifying.
        // (acr for this contact left untouched - Roles stays null)

        // billingOnly: Roles limited to Invoice -> Marketing__c formula false, not blank
        AccountContactRelation acr3 = [SELECT Id FROM AccountContactRelation WHERE ContactId = :billingOnly.Id LIMIT 1];
        acr3.Roles = 'Invoice';
        update acr3;

        // deactivatedAcctContact: Roles blank, but account is deactivated - should be excluded regardless
        // wrongBrandContact: Roles blank, but account brand is E - should be excluded regardless
    }

    @IsTest
    static void testBatch_prefillsOnlyQualifyingContactsAndConfigs() {
        Test.startTest();
        Database.executeBatch(new Btch_PrefillMBrandPreferences(), 50);
        Test.stopTest();

        Map<String, Integer> countByLastName = new Map<String, Integer>();
        for (CommunicationPreference__c pref : [
            SELECT Contact__r.LastName, Config__r.CommunicationType__c, IsEnabled__c, LegalBasis__c, Source__c
            FROM CommunicationPreference__c
        ]) {
            String key = pref.Contact__r.LastName;
            countByLastName.put(key, (countByLastName.containsKey(key) ? countByLastName.get(key) : 0) + 1);
            System.assertEquals(true, pref.IsEnabled__c, 'Prefilled rows are opted in by default');
            System.assertEquals(null, pref.LegalBasis__c, 'LegalBasis left blank for the prefill');
            System.assertEquals('Import', pref.Source__c);
            System.assertNotEquals('SECURITY_ALERTS', pref.Config__r.CommunicationType__c, 'SERVICE category must never be prefilled');
        }

        System.assertEquals(2, countByLastName.get('MarketingRole'), 'Qualifying contact gets both non-service M configs');
        System.assertEquals(2, countByLastName.get('BlankRoleNoInfo'), 'Blank Roles counts as qualifying even without email/phone');
        System.assertEquals(false, countByLastName.containsKey('BillingOnly'), 'Non-blank, non-marketable Roles is excluded');
        System.assertEquals(false, countByLastName.containsKey('DeactivatedAccount'), 'Deactivated account is excluded');
        System.assertEquals(false, countByLastName.containsKey('WrongBrand'), 'Non-M-brand account is excluded');
    }

    @IsTest
    static void testBatch_rerunIsIdempotent() {
        Test.startTest();
        // Both enqueued before stopTest() - Salesforce runs queued async Apex to completion,
        // in order, when stopTest() is called, so the second run sees the first run's inserts.
        Database.executeBatch(new Btch_PrefillMBrandPreferences(), 50);
        Database.executeBatch(new Btch_PrefillMBrandPreferences(), 50);
        Test.stopTest();

        Integer total = [SELECT COUNT() FROM CommunicationPreference__c];
        System.assertEquals(4, total, 'Re-running the batch does not create duplicates');
    }
}
