public class Queue_DataRetentionCleanup implements Queueable {
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
                ', Processed: ' + result.processedCount
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

        System.debug('Retention Query: ' + baseQuery);

        if (deleteMode == 'SOFT') {
            baseQuery += 
                ' AND ((' + fieldName + '= false ) OR (' + fieldName + ' = null ))';        
        }

        System.debug('Retention Query: ' + baseQuery);

        if (!String.isBlank(policy.AdditionalFilter__c)) {
            baseQuery +=
                ' AND (' + policy.AdditionalFilter__c + ')';
        }

        System.debug('Retention Query: ' + baseQuery);

        List<SObject> records = Database.query(baseQuery);

        System.debug('Retention Query: ' + baseQuery);
        System.debug(records);

        result.processedCount = records.size();

        if (records.isEmpty()) {
            return result;
        }

        if (deleteMode == 'SOFT') {
            applySoftDelete(objectName, records, fieldName);
        } else {
            applyHardDelete(records);
        }

        return result;

    }

    // =========================
    // HARD DELETE
    // =========================
    private void applyHardDelete(List<SObject> records) {
        delete records;
    }

    // =========================
    // SOFT DELETE
    // =========================
    private void applySoftDelete(
        String objectName,
        List<SObject> records,
        String fieldName
    ) {
        for (SObject rec : records) {
        
            rec.put(fieldName, true);
            System.debug('Soft deleting record: ' + rec);
        }
        System.debug('Before Update - Soft deleting record: ' + records);
        update records;
        System.debug('After Update - Soft deleting record: ' + records);
    }


    private class RetentionResult {
        Integer processedCount = 0;
        String mode;
        String objectName;
    }

}