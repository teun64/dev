public class Queue_DataRetentionCleanup implements Queueable {
    private static final Integer MAX_RECORDS_PER_RUN = 9000;

    private DataRetentionPolicy__mdt policy;
    private String parentGuid;

    public Queue_DataRetentionCleanup(
        DataRetentionPolicy__mdt policy,
        String parentGuid
    ) {
        this.policy = policy;
        this.parentGuid = parentGuid;
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

        DateTime cutoff = System.now().addDays(-retentionDays);

        String cutoffFormatted =
            cutoff.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        String baseQuery =
            'SELECT Id FROM ' + objectName +
            ' WHERE ' + dateField +
            ' < ' + cutoffFormatted;

        if (deleteMode == 'SOFT') {
            baseQuery +=
                ' AND ((' + fieldName + '= false ) OR (' + fieldName + ' = null ))';
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
            result.failedCount = applySoftDelete(objectName, records, fieldName);
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
        String fieldName
    ) {
        for (SObject rec : records) {
            rec.put(fieldName, true);
        }
        List<Database.SaveResult> saveResults = Database.update(records, false);
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