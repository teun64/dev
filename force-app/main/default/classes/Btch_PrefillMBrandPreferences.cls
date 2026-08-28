/**
 * One-time migration: prefill CommunicationPreference__c for M-brand current customers.
 *
 * Scope:
 *  - Account.PrimaryBrand__c = 'M' AND Account.Deactivated__c = false
 *  - Contact qualifies via its AccountContactRelation: Marketing__c = true,
 *    OR Roles is blank (per business rule: no roles set yet -> treat as marketable)
 *  - Config scope: Brand__c = 'M', Channel__c = 'EMAIL', Category__c != 'SERVICE'
 *    (SERVICE communications are informational-only, no preference needed)
 *
 * Each qualifying Contact x Config gets a new CommunicationPreference__c row,
 * IsEnabled__c = true (opt-in default), LegalBasis__c left blank, Source__c = 'Import'.
 * Rows that already exist (same Contact/Config) fail on the CompositeKey__c unique
 * constraint and are safely skipped - this makes the batch idempotent on re-run.
 */
public with sharing class Btch_PrefillMBrandPreferences implements Database.Batchable<SObject>, Database.Stateful {
    private Integer insertedCount = 0;
    private Integer skippedCount = 0;
    private List<Id> configIds;

    public Btch_PrefillMBrandPreferences() {
        configIds = new List<Id>();
        for (CommunicationPreferenceConfig__c cfg : Database.query(
            'SELECT Id FROM CommunicationPreferenceConfig__c' +
            ' WHERE Brand__c = \'M\' AND Channel__c = \'EMAIL\' AND Category__c != \'SERVICE\'',
            AccessLevel.SYSTEM_MODE
        )) {
            configIds.add(cfg.Id);
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocatorWithBinds(
            'SELECT ContactId FROM AccountContactRelation' +
            ' WHERE Account.PrimaryBrand__c = \'M\'' +
            '   AND Account.Deactivated__c = false' +
            '   AND (Marketing__c = true OR Roles = null)',
            new Map<String, Object>(),
            AccessLevel.SYSTEM_MODE
        );
    }

    public void execute(Database.BatchableContext bc, List<AccountContactRelation> scope) {
        Set<Id> contactIds = new Set<Id>();
        for (AccountContactRelation acr : scope) {
            contactIds.add(acr.ContactId);
        }

        List<CommunicationPreference__c> toInsert = new List<CommunicationPreference__c>();
        for (Id contactId : contactIds) {
            for (Id configId : configIds) {
                toInsert.add(new CommunicationPreference__c(
                    Contact__c   = contactId,
                    Config__c    = configId,
                    IsEnabled__c = true,
                    Source__c    = 'Import'
                ));
            }
        }

        Database.SaveResult[] results = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) {
                insertedCount++;
            } else {
                skippedCount++;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Btch_PrefillMBrandPreferences finished: inserted=' + insertedCount + ' skipped(existing)=' + skippedCount);
    }
}
