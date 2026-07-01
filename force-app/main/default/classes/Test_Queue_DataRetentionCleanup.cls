@IsTest
private class Test_Queue_DataRetentionCleanup {

    private static DataRetentionPolicy__mdt buildPolicy(
        String developerName,
        String objectName,
        Decimal retentionDays,
        String filterField,
        String deleteMode,
        String softField,
        String additionalFilter
    ) {
        return new DataRetentionPolicy__mdt(
            DeveloperName = developerName,
            MasterLabel = developerName,
            Object__c = objectName,
            RetentionDays__c = retentionDays,
            FilterField__c = filterField,
            DeleteMode__c = deleteMode,
            DeleteModeSoftField__c = softField,
            AdditionalFilter__c = additionalFilter
        );
    }

    @IsTest
    private static void testHardDeleteRemovesOldRecords() {
        Account oldAccount = Test_Data.createAccount('Old Account', 'RETTEST1', 'B2B', false);
        oldAccount.CreatedDate = System.now().addDays(-100);
        Database.insert(oldAccount);

        Account recentAccount = Test_Data.createAccount('Recent Account', 'RETTEST2', 'B2B', true);

        DataRetentionPolicy__mdt policy = buildPolicy(
            'Test_Hard', 'Account', 30, 'CreatedDate', 'HARD', null, null
        );

        Test.startTest();
        new Queue_DataRetentionCleanup(policy, null).execute(null);
        Test.stopTest();

        List<Account> remaining = [
            SELECT Id FROM Account WHERE Id IN :new List<Id>{ oldAccount.Id, recentAccount.Id }
        ];
        Assert.areEqual(1, remaining.size(), 'Only the recent account should remain');
        Assert.areEqual(recentAccount.Id, remaining[0].Id, 'The old account should have been hard deleted');
    }

    @IsTest
    private static void testSoftDeleteMarksFieldInsteadOfDeleting() {
        Account oldAccount = Test_Data.createAccount('Old Account', 'RETTEST3', 'B2B', false);
        oldAccount.CreatedDate = System.now().addDays(-100);
        Database.insert(oldAccount);

        DataRetentionPolicy__mdt policy = buildPolicy(
            'Test_Soft', 'Account', 30, 'CreatedDate', 'SOFT', 'Deactivated__c', null
        );

        Test.startTest();
        new Queue_DataRetentionCleanup(policy, null).execute(null);
        Test.stopTest();

        Account result = [SELECT Id, Deactivated__c FROM Account WHERE Id = :oldAccount.Id];
        Assert.isTrue(result.Deactivated__c, 'Old account should be soft deleted (Deactivated__c = true), not removed');
    }

    @IsTest
    private static void testSoftDeleteExcludesAlreadyDeactivatedRecords() {
        Account alreadyDeactivated = Test_Data.createAccount('Already Deactivated', 'RETTEST4', 'B2B', false);
        alreadyDeactivated.CreatedDate = System.now().addDays(-100);
        alreadyDeactivated.Deactivated__c = true;
        Database.insert(alreadyDeactivated);

        DataRetentionPolicy__mdt policy = buildPolicy(
            'Test_Soft_Skip', 'Account', 30, 'CreatedDate', 'SOFT', 'Deactivated__c', null
        );

        Test.startTest();
        new Queue_DataRetentionCleanup(policy, null).execute(null);
        Test.stopTest();

        List<IntegrationTransaction__c> logs = [
            SELECT Message__c FROM IntegrationTransaction__c WHERE Action__c = 'Retention Cleanup - Test_Soft_Skip'
        ];
        Assert.areEqual(1, logs.size(), 'Expected one process log for the run');
        Assert.isTrue(
            logs[0].Message__c.contains('Processed: 0'),
            'Already-deactivated records must be excluded from the retention query, not reprocessed'
        );
    }

    @IsTest
    private static void testUnsupportedDeleteModeDoesNotDeleteRecords() {
        // DeleteMode__c allows 'ARCHIVE' as a picklist value, but no archive logic exists yet.
        // Regression guard: an unimplemented mode must never silently fall back to a hard delete.
        Account oldAccount = Test_Data.createAccount('Old Account', 'RETTEST5', 'B2B', false);
        oldAccount.CreatedDate = System.now().addDays(-100);
        Database.insert(oldAccount);

        DataRetentionPolicy__mdt policy = buildPolicy(
            'Test_Archive', 'Account', 30, 'CreatedDate', 'ARCHIVE', null, null
        );

        Test.startTest();
        new Queue_DataRetentionCleanup(policy, null).execute(null);
        Test.stopTest();

        List<Account> result = [SELECT Id FROM Account WHERE Id = :oldAccount.Id];
        Assert.areEqual(1, result.size(), 'ARCHIVE mode is not implemented - the record must not be hard deleted as a fallback');

        List<IntegrationTransaction__c> errorLogs = [
            SELECT Status__c, Message__c
            FROM IntegrationTransaction__c
            WHERE Action__c = 'Retention Cleanup - Test_Archive'
        ];
        Assert.areEqual(1, errorLogs.size(), 'Expected one process log for the failed run');
        Assert.areEqual(
            Util_Event.LogResultStatus.ERROR.name(),
            errorLogs[0].Status__c,
            'Unsupported delete mode should be logged as an error, not silently hard-deleted'
        );
    }

    @IsTest
    private static void testAdditionalFilterIsApplied() {
        Account matching = Test_Data.createAccount('Matching', 'RETTEST6', 'B2B', false);
        matching.CreatedDate = System.now().addDays(-100);
        Database.insert(matching);

        Account nonMatching = Test_Data.createAccount('Non Matching', 'RETTEST7', 'B2B', false);
        nonMatching.CreatedDate = System.now().addDays(-100);
        nonMatching.Relation_Type__c = 'Dealer';
        Database.insert(nonMatching);

        DataRetentionPolicy__mdt policy = buildPolicy(
            'Test_Filtered', 'Account', 30, 'CreatedDate', 'HARD', null,
            'Relation_Type__c = \'End User\''
        );

        Test.startTest();
        new Queue_DataRetentionCleanup(policy, null).execute(null);
        Test.stopTest();

        List<Account> remaining = [
            SELECT Id FROM Account WHERE Id IN :new List<Id>{ matching.Id, nonMatching.Id }
        ];
        Assert.areEqual(1, remaining.size(), 'Only the account not matching the AdditionalFilter should remain');
        Assert.areEqual(nonMatching.Id, remaining[0].Id);
    }

    @IsTest
    private static void testDefaultsAreAppliedWhenPolicyFieldsAreBlank() {
        Account oldAccount = Test_Data.createAccount('Old Account', 'RETTEST8', 'B2B', false);
        oldAccount.CreatedDate = System.now().addDays(-40); // older than the 30-day default
        Database.insert(oldAccount);

        // RetentionDays__c, FilterField__c and DeleteMode__c left blank - should default to
        // 30 days / CreatedDate / HARD respectively.
        DataRetentionPolicy__mdt policy = buildPolicy(
            'Test_Defaults', 'Account', null, null, null, null, null
        );

        Test.startTest();
        new Queue_DataRetentionCleanup(policy, null).execute(null);
        Test.stopTest();

        Assert.isTrue(
            [SELECT Id FROM Account WHERE Id = :oldAccount.Id].isEmpty(),
            'Default 30-day HARD delete should have removed the old account'
        );
    }
}
