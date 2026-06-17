/**
 * Created by Gerbrand Spaans (Gen25) on 28/11/2023.
 * Starts Queueables (one per Administration) to retreive Account info from Exact and store updates in SF.
 * Extending the AbstractBatch2 allows the Batch to be scheduled by Subscription25.
 */

 global class Batch_FinancialSystemAccountSync extends Subscription25.Job_AbstractBatch2 {
    private static final String CONTEXT_NAME = 'Sync Accounts from the Financial System to Salesforce'; // Context (Name) of the Log

    private String mainLogGuid;
    // Extension Constructor
    global Batch_FinancialSystemAccountSync() {
        super('Batch_FinancialSystemAccountSync');
    }

    /**
     * Batch Size should be 1, regardless of the settings in Subs25. This is because each execute() will start
     * 1 Queueable. Any more is against Governor Limits.
     * @return 1
     */
    public override Integer getBatchSize() {
        return 1;
    }

    /**
     * Get a list of active Subs25.Administrations and start the sync for each of these admins.
     * @param bc BatchableContext.
     *
     * @return List of Subs25.Administrations
     */
    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        // generate initial log
        Logger2 log = Logger2.getInstance();
        log.setContext('S', 'E', Batch_FinancialSystemAccountSync.CONTEXT_NAME, new Account(), bc.getJobId());
        log.saveAll();
        this.mainLogGuid = log.getParentGuid();

        // Query the Admin and start a batch for each admin.
        List<String> adminFields = new List<String>(Subscription25__Administration__c.getSObjectType().getDescribe().fields.getMap().keySet());

        String adminQuery = String.format('SELECT {0} FROM Subscription25__Administration__c WHERE Subscription25__Active__c = TRUE AND Subscription25__Named_Credential__c != NULL', new List<String>{String.join(adminFields, ',')});
        return Database.getQueryLocator(adminQuery);
    }
    /**
     * Provided for test classes only
     * @param bc Batchable context
     * @param administrations List of Administrations to process
     * @param logGuid Identifier for the Parent Event Log record.
     */
    @TestVisible
    private void executeBatch(Database.BatchableContext bc, List<SObject> administrations, String logGuid) {
        this.mainLogGuid = logGuid;
        this.executeBatch(bc, administrations);
    }
    public override void executeBatch(Database.BatchableContext bc, List<SObject> administrations) {
        Queue_FinancialSystemAccountSync exactQueue = new Queue_FinancialSystemAccountSync((Subscription25__Administration__c)administrations[0], null, this.mainLogGuid);
        System.enqueueJob(exactQueue);
    }

    public override void finishBatch(Database.BatchableContext param0) {
    }
}