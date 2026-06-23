/**
 * Batch_CleanCommunicationPreferences
 *
 * Deletes CommunicationPreference__c records that are opted-out (IsEnabled__c = false)
 * and have not been updated within the retention window defined per brand in
 * BrandCommunicationConfig__mdt.RetentionMonths__c.
 *
 * Only brands present in BrandCommunicationConfig__mdt are processed.
 * CMT records without RetentionMonths__c set are excluded from cleanup.
 *
 * Per brand the most conservative (longest) retention across all its CMT rows is used,
 * so a brand with mixed values keeps records for the longest configured period.
 *
 * Schedule via:
 *   Batch_CleanCommunicationPreferences.setSchedule();          // daily at 02:00
 *   Batch_CleanCommunicationPreferences.setSchedule('0 0 3 * * ? *'); // custom cron
 */
public class Batch_CleanCommunicationPreferences
        implements Database.Batchable<SObject>, Schedulable {

    // Per-brand cutoff datetime, built in start() and serialized into each execute() chunk.
    // brand API value → datetime before which false records are eligible for deletion.
    private Map<String, Datetime> brandCutoff = new Map<String, Datetime>();

    // ── Schedulable ───────────────────────────────────────────────────────────

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new Batch_CleanCommunicationPreferences(), 2000);
    }

    // ── Batchable ─────────────────────────────────────────────────────────────

    public Iterable<SObject> start(Database.BatchableContext bc) {
        // Build per-brand cutoff from CMT.
        // Multiple CMT rows per brand → use the maximum retention (earliest cutoff = keep longer).
        Datetime broadestCutoff = null; // most recent cutoff across all brands → broadest SOQL net

        for (BrandCommunicationConfig__mdt cfg : [
            SELECT Brand__c, RetentionMonths__c
            FROM   BrandCommunicationConfig__mdt
            WHERE  RetentionMonths__c != null
            AND    RetentionMonths__c > 0
        ]) {
            String   brand   = cfg.Brand__c;
            Datetime cutoff  = Datetime.now().addMonths(-Integer.valueOf(cfg.RetentionMonths__c));

            // Per-brand: longest retention = earliest cutoff date → keep records longer
            if (!brandCutoff.containsKey(brand) || brandCutoff.get(brand) > cutoff) {
                brandCutoff.put(brand, cutoff);
            }
            // Broadest SOQL net: most recent cutoff = shortest retention across brands
            if (broadestCutoff == null || cutoff > broadestCutoff) {
                broadestCutoff = cutoff;
            }
        }

        if (brandCutoff.isEmpty()) {
            // Nothing configured — return empty result set
            return (Iterable<SObject>) Database.getQueryLocator(
                [SELECT Id FROM CommunicationPreference__c WHERE Id = null]
            );
        }

        Set<String> activeBrands = brandCutoff.keySet();
        return (Iterable<SObject>) Database.getQueryLocator([
            SELECT Id, Brand__c, LastModifiedDate
            FROM   CommunicationPreference__c
            WHERE  IsEnabled__c  = false
            AND    Brand__c      IN :activeBrands
            AND    LastModifiedDate < :broadestCutoff
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<CommunicationPreference__c> toDelete = new List<CommunicationPreference__c>();
        for (SObject s : scope) {
            CommunicationPreference__c pref = (CommunicationPreference__c) s;
            Datetime cutoff = brandCutoff.get(pref.Brand__c);
            // Apply the brand-specific cutoff (may differ from the broadest SOQL cutoff)
            if (cutoff != null && pref.LastModifiedDate < cutoff) {
                toDelete.add(pref);
            }
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    public void finish(Database.BatchableContext bc) {}

    // ── Schedule helpers ──────────────────────────────────────────────────────

    public static void setSchedule() {
        setSchedule('0 0 2 * * ? *'); // daily at 02:00
    }

    public static void setSchedule(String cronString) {
        System.schedule(
            'Batch_CleanCommunicationPreferences - ' + cronString,
            cronString,
            new Batch_CleanCommunicationPreferences()
        );
    }
}
