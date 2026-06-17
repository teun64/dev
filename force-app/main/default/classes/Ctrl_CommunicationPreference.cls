public with sharing class Util_CommunicationPreference {

    // =========================
    // GET
    // =========================
    public static List<CommunicationPreference__c> get(
        Id contactId,
        String brand,
        Boolean isAdminMode
    ) {
        if (contactId == null || String.isBlank(brand)) {
            return new List<CommunicationPreference__c>();
        }

        return [
            SELECT Id,
                   Contact__c,
                   Brand__c,
                   Category__c,
                   CommunicationType__c,
                   Channel__c,
                   Channel_Detail__c,
                   Is_Enabled__c,
                   CompositeKey__c,
                   Google_Ads_Eligible__c
            FROM CommunicationPreference__c
            WHERE Contact__c = :contactId
              AND Brand__c = :brand
        ];
    }

    // =========================
    // SAVE
    // =========================
    public static void save(
        Id contactId,
        String brand,
        List<Ctrl_CommunicationPreference.PreferenceInput> inputs,
        Boolean isAdminMode,
        String overrideReason,
        String requestId,
        String sessionId
    ) {

        Boolean isRealAdmin = isAdminMode && hasAdminAccess();

        Map<Id, CommunicationPreference__c> existing = new Map<Id, CommunicationPreference__c>(
            [
                SELECT Id,
                       Contact__c,
                       Brand__c,
                       Category__c,
                       CommunicationType__c,
                       Channel__c,
                       Is_Enabled__c,
                       CompositeKey__c
                FROM CommunicationPreference__c
                WHERE Contact__c = :contactId
                  AND Brand__c = :brand
            ]
        );

        List<CommunicationPreference__c> updates = new List<CommunicationPreference__c>();
        List<Log_CommunicationPreference.AuditInput> logs = new List<Log_CommunicationPreference.AuditInput>();

        for (Ctrl_CommunicationPreference.PreferenceInput input : inputs) {

            if (input.preferenceId == null) continue;

            CommunicationPreference__c pref = existing.get(input.preferenceId);
            if (pref == null) continue;

            Boolean oldVal = pref.Is_Enabled__c;
            Boolean newVal = input.isEnabled;

            // SERVICE enforcement
            if (pref.Category__c == 'SERVICE' && !isRealAdmin) {
                newVal = true;
            }

            if (oldVal == newVal) continue;

            pref.Is_Enabled__c = newVal;
            updates.add(pref);

            // Audit log
            Log_CommunicationPreference.AuditInput log = new Log_CommunicationPreference.AuditInput();

            log.contactId = pref.Contact__c;
            log.preferenceId = pref.Id;

            log.brand = pref.Brand__c;
            log.category = pref.Category__c;
            log.communicationType = pref.CommunicationType__c;
            log.channel = pref.Channel__c;

            log.oldValue = oldVal;
            log.newValue = newVal;

            log.isAdminOverride = isRealAdmin;
            log.overrideReason = overrideReason;

            log.changeSource = isRealAdmin ? 'SUPPORT_CONSOLE' : 'PREFERENCE_CENTER';
            log.changeReason = isRealAdmin ? 'ADMIN_OVERRIDE' : 'USER_ACTION';

            log.compositeKey = pref.CompositeKey__c;

            log.requestId = requestId;
            log.sessionId = sessionId;

            logs.add(log);
        }

        if (!updates.isEmpty()) {
            update updates;
        }

        if (!logs.isEmpty()) {
            Log_CommunicationPreference.log(logs);
        }
    }

    // =========================
    // Security
    // =========================
    private static Boolean hasAdminAccess() {
        return FeatureManagement.checkPermission('Manage_Communication_Preferences');
    }
}