@IsTest
private class Test_Batch_DataRetentionCleanup {

    @IsTest
    private static void testGetBatchSizeIsAlwaysOne() {
        insert new Subscription25__Schedulable_Class__c(Name = 'Batch_DataRetentionCleanup');

        Batch_DataRetentionCleanup batch = new Batch_DataRetentionCleanup();
        Assert.areEqual(1, batch.getBatchSize(), 'Batch size must stay 1 - each execute() enqueues its own Queueable');
    }

    @IsTest
    private static void testFullBatchRunLogsAndCompletesWithNoMatchingData() {
        insert new Subscription25__Schedulable_Class__c(Name = 'Batch_DataRetentionCleanup');

        List<DataRetentionPolicy__mdt> activePolicies = [
            SELECT Id FROM DataRetentionPolicy__mdt WHERE IsActive__c = true
        ];
        Assert.isTrue(!activePolicies.isEmpty(), 'Expected the deployed active retention policies to be visible in tests');

        Test.startTest();
        Database.executeBatch(new Batch_DataRetentionCleanup());
        Test.stopTest();

        List<IntegrationTransaction__c> parentLogs = [
            SELECT Id, Status__c
            FROM IntegrationTransaction__c
            WHERE Action__c = 'Generic Data Retention Cleanup'
        ];
        Assert.areEqual(1, parentLogs.size(), 'Expected one parent log for the batch run');
    }

    @IsTest
    private static void testExecuteBatchHookDelegatesToQueueable() {
        insert new Subscription25__Schedulable_Class__c(Name = 'Batch_DataRetentionCleanup');

        Account oldAccount = Test_Data.createAccount('Old Account', 'RETBATCH1', 'B2B', false);
        oldAccount.CreatedDate = System.now().addDays(-100);
        Database.insert(oldAccount);

        DataRetentionPolicy__mdt policy = new DataRetentionPolicy__mdt(
            DeveloperName = 'Test_Batch_Hard',
            MasterLabel = 'Test_Batch_Hard',
            Object__c = 'Account',
            RetentionDays__c = 30,
            FilterField__c = 'CreatedDate',
            DeleteMode__c = 'HARD'
        );

        Logger log = Logger.getInstance();
        log.saveAll();

        Batch_DataRetentionCleanup batch = new Batch_DataRetentionCleanup();

        Test.startTest();
        batch.executeBatch(null, new List<SObject>{ policy }, log.getParentGuid());
        Test.stopTest();

        Assert.isTrue(
            [SELECT Id FROM Account WHERE Id = :oldAccount.Id].isEmpty(),
            'The batch hook should enqueue the cleanup Queueable, which hard deletes the matched record'
        );
    }
}
