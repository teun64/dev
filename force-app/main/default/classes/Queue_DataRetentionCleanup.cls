public class Queue_DataRetentionCleanup implements Queueable {
    private static final Integer MAX_RECORDS_PER_RUN = 9000;
    // safety cap: reruns of the same policy within one batch run (100 x 9000 = 900k records)
    private static final Integer MAX_RUNS_PER_POLICY = 100;

    private DataRetentionPolicy__mdt policy;
    private String parentGuid;
    // policies still to process after this one: chained one job at a time (only one queueable may be enqueued
    // from a batch or queueable context)
    private List<DataRetentionPolicy__mdt> nextPolicies = new List<DataRetentionPolicy__mdt>();
    // a full run (MAX_RECORDS_PER_RUN records) means more old records may remain: the same policy runs again first
    @TestVisible
    private Boolean moreRemaining = false;
    private Integer runNumber = 1;

    public Queue_DataRetentionCleanup(
        DataRetentionPolicy__mdt policy,
        String parentGuid
    ) {
        this.policy = policy;
        this.parentGuid = parentGuid;
    }

    public Queue_DataRetentionCleanup(
        DataRetentionPolicy__mdt policy,
        String parentGuid,
        List<DataRetentionPolicy__mdt> nextPolicies
    ) {
        this(policy, parentGuid);
        if (nextPolicies != null) {
            this.nextPolicies = nextPolicies;
        }
    }

    // first policy now, the rest chained after it
    public static Id enqueueChain(List<DataRetentionPolicy__mdt> policies, String parentGuid) {
        if ((policies == null) || policies.isEmpty()) {
            return null;
        }
        List<DataRetentionPolicy__mdt> rest = new List<DataRetentionPolicy__mdt>(policies);
        DataRetentionPolicy__mdt first = rest.remove(0);
        return System.enqueueJob(new Queue_DataRetentionCleanup(first, parentGuid, rest));
    }

    public void execute(QueueableContext context) {

        Logger log = Logger.getInstance(parentGuid);

        String processGuid = log.startProcess(
            'Retention Cleanup - ' + policy.MasterLabel,
            'S',
            null
        );

        try {

            RetentionResult result = processRetention();
            // only when the run was full AND removed records (records failing every run must not loop forever)
            this.moreRemaining = (result.processedCount >= MAX_RECORDS_PER_RUN)
                && (result.failedCount < result.processedCount)
                && (this.runNumber < MAX_RUNS_PER_POLICY);

            log.finalizeProcess(
                processGuid,
                'Retention completed successfully. ' +
                'Object: ' + result.objectName +
                ', Mode: ' + result.mode +
                ', Processed: ' + result.processedCount +
                ', Failed: ' + result.failedCount
            );

        } catch (Exception e) {

            log.finalizeProcess(
                processGuid,
                e
            );

        } finally {

            //completeWorker(log);

            log.saveAll();

            // continue in its own job (tests can't chain queueables): the same policy again while more old records
            // remain, otherwise the next policy
            if (!Test.isRunningTest()) {
                if (this.moreRemaining) {
                    Queue_DataRetentionCleanup again = new Queue_DataRetentionCleanup(this.policy, this.parentGuid, this.nextPolicies);
                    again.runNumber = this.runNumber + 1;
                    System.enqueueJob(again);
                } else if (!this.nextPolicies.isEmpty()) {
                    Queue_DataRetentionCleanup.enqueueChain(this.nextPolicies, this.parentGuid);
                }
            }
        }

    }

    // =====================================================
    // RETENTION EXECUTION
    // =====================================================
    private RetentionResult processRetention() {

        RetentionResult result = new RetentionResult();

        Integer retentionDays =
            (policy.RetentionDays__c == null)
            ? 30
            : Integer.valueOf(policy.RetentionDays__c);

        String objectName = policy.Object__c;
        result.objectName = objectName;

        String dateField = String.isBlank(policy.FilterField__c)
            ? 'CreatedDate'
            : policy.FilterField__c;

        String deleteMode = String.isBlank(policy.DeleteMode__c)
            ? 'HARD'
            : policy.DeleteMode__c;
        result.mode = deleteMode;

        String fieldName = String.isBlank(policy.DeleteModeSoftField__c)
            ? 'Archived__c'
            : policy.DeleteModeSoftField__c;

        // soft delete value: blank = checkbox (true), otherwise the value to write (e.g. Status__c = 'deactivated')
        String softValue = policy.DeleteModeSoftValue__c;

        DateTime cutoff = System.now().addDays(-retentionDays);

        String cutoffFormatted =
            cutoff.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        String baseQuery =
            'SELECT Id FROM ' + objectName +
            ' WHERE ' + dateField +
            ' < ' + cutoffFormatted;

        if (deleteMode == 'SOFT') {
            baseQuery += String.isBlank(softValue)
                ? ' AND ((' + fieldName + '= false ) OR (' + fieldName + ' = null ))'
                : ' AND ((' + fieldName + ' != \'' + String.escapeSingleQuotes(softValue) + '\') OR (' + fieldName + ' = null ))';
        }

        if (!String.isBlank(policy.AdditionalFilter__c)) {
            baseQuery +=
                ' AND (' + policy.AdditionalFilter__c + ')';
        }

        // Cap the result set so a single run can never exceed the per-transaction
        // DML row limit (10,000) - the Logger's own upserts in saveAll() also count
        // against that limit. Remaining records are picked up by the next scheduled run.
        baseQuery += ' LIMIT ' + MAX_RECORDS_PER_RUN;

        System.debug('Retention Query: ' + baseQuery);

        List<SObject> records = Database.query(baseQuery);

        result.processedCount = records.size();

        if (records.isEmpty()) {
            return result;
        }

        if (deleteMode == 'SOFT') {
            result.failedCount = applySoftDelete(objectName, records, fieldName, softValue);
        } else if (deleteMode == 'HARD') {
            result.failedCount = applyHardDelete(records);
        } else {
            throw new System.IllegalArgumentException(
                'Unsupported DeleteMode__c value \'' + deleteMode +
                '\' on policy ' + policy.DeveloperName + '. Expected HARD or SOFT.'
            );
        }

        return result;

    }

    // =========================
    // HARD DELETE
    // =========================
    private Integer applyHardDelete(List<SObject> records) {
        List<Database.DeleteResult> deleteResults = Database.delete(records, false);
        return countFailures(deleteResults);
    }

    // =========================
    // SOFT DELETE
    // =========================
    private Integer applySoftDelete(
        String objectName,
        List<SObject> records,
        String fieldName,
        String softValue
    ) {
        for (SObject rec : records) {
            rec.put(fieldName, String.isBlank(softValue) ? (Object) true : (Object) softValue);
        }
        // system job: soft delete fields (e.g. Status__c) are not editable for regular users
        List<Database.SaveResult> saveResults = Database.update(records, false, AccessLevel.SYSTEM_MODE);
        return countFailures(saveResults);
    }

    private Integer countFailures(List<Database.DeleteResult> deleteResults) {
        Integer failures = 0;
        for (Database.DeleteResult dr : deleteResults) {
            if (!dr.isSuccess()) {
                failures++;
                for (Database.Error err : dr.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Retention hard delete failed: ' + err.getMessage());
                }
            }
        }
        return failures;
    }

    private Integer countFailures(List<Database.SaveResult> saveResults) {
        Integer failures = 0;
        for (Database.SaveResult sr : saveResults) {
            if (!sr.isSuccess()) {
                failures++;
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Retention soft delete failed: ' + err.getMessage());
                }
            }
        }
        return failures;
    }


    private class RetentionResult {
        Integer processedCount = 0;
        Integer failedCount = 0;
        String mode;
        String objectName;
    }

}