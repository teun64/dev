global class Batch_DataRetentionCleanup extends Subscription25.Job_AbstractBatch2 {

    private static final String CONTEXT_NAME = 'Generic Data Retention Cleanup';

    private String mainLogGuid;

    // =========================
    // Constructor
    // =========================
    global Batch_DataRetentionCleanup() {
        super('Batch_DataRetentionCleanup');
    }

    // =========================
    // Batch size = 1 (queue-safe pattern)
    // =========================
    public override Integer getBatchSize() {
        return 1;
    }

    // =========================
    // START
    // =========================
    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {

        // ADD MAIN BATCH LOGGING CONTEXT
        Logger log = Logger.getNewInstance();

        log.setContext(
            'S',
            'S',
            CONTEXT_NAME,
            null,
            bc.getJobId()
        );

        log.saveAll();

        this.mainLogGuid = log.getParentGuid();


        // =========================
        // Query ALL required fields
        // =========================
        return Database.getQueryLocator([
            SELECT DeveloperName,
                MasterLabel,
                Object__c,
                RetentionDays__c,
                IsActive__c,
                FilterField__c,
                DeleteMode__c,
                DeleteModeSoftField__c,
                AdditionalFilter__c
            FROM DataRetentionPolicy__mdt
            WHERE IsActive__c = true
        ]);
    }

    // =========================
    // TEST HOOK
    // =========================
    @TestVisible
    private void executeBatch(
        Database.BatchableContext bc,
        List<SObject> scope,
        String logGuid
    ) {
        this.mainLogGuid = logGuid;
        this.executeBatch(bc, scope);
    }

    // =========================
    // EXECUTE
    // =========================
    public override void executeBatch(
        Database.BatchableContext bc,
        List<SObject> scope

    ) {
                
        System.debug('Start Batch');
        DataRetentionPolicy__mdt policy =(DataRetentionPolicy__mdt) scope[0];

        Queue_DataRetentionCleanup queue = new Queue_DataRetentionCleanup(policy, this.mainLogGuid);
        System.enqueueJob(queue);
    }

    // =========================
    // FINISH
    // =========================
    public override void finishBatch(Database.BatchableContext bc) {
        // optional: finalize logging, metrics, cleanup summary
    }
}