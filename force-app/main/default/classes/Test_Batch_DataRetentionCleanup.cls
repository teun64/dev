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

        // works with or without active policies in the org (prod deploys them inactive): the batch run always logs
        Test.startTest();
        Database.executeBatch(new Batch_DataRetentionCleanup());
        Test.stopTest();

        List<SObject> parentLogs = getLogs('Generic Data Retention Cleanup');
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

    // The Logger writes to IntegrationTransaction__c (dev) or Event_Log__c (acc/prod, older Logger),
    // both with Action__c / Status__c / Message__c - query whichever exists.
    private static List<SObject> getLogs(String action) {
        String logObject = Schema.getGlobalDescribe().containsKey('integrationtransaction__c') ? 'IntegrationTransaction__c' : 'Event_Log__c';
        return Database.query('SELECT Id, Status__c, Message__c FROM ' + logObject + ' WHERE Action__c = :action');
    }
}
