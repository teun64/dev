public with sharing class Log_CommunicationPreference {

    // 🧾 DTO for clean logging input
    public class AuditInput {
        public Id contactId;
        public Id preferenceId;

        public String brand;
        public String category;
        public String communicationType;
        public String channel;
        public String channelDetail;

        public Boolean oldValue;
        public Boolean newValue;

        public Boolean isAdminOverride;
        public String overrideReason;

        public String changeSource;     // EXPERIENCE_CLOUD, SUPPORT_CONSOLE, API, SYSTEM
        public String changeReason;     // USER_ACTION, ADMIN_OVERRIDE, SYSTEM_ENFORCEMENT

        public String compositeKey;

        public Boolean googleAdsEligible;

        public String requestId;
        public String sessionId;
        public String eventId;

        public String ownerId; // optional override
    }

    // 🚀 Public entry (bulk)
    public static void log(List<AuditInput> inputs) {

        if (inputs == null || inputs.isEmpty()) return;

        List<CommunicationPreferenceAudit__c> records = new List<CommunicationPreferenceAudit__c>();

        for (AuditInput input : inputs) {

            // skip invalid
            if (input.contactId == null || input.preferenceId == null) continue;

            CommunicationPreferenceAudit__c rec = new CommunicationPreferenceAudit__c();

            // 🔹 Required
            rec.Contact__c = input.contactId;
            rec.CommunicationPreference__c = input.preferenceId;
            rec.Changed_By__c = UserInfo.getUserId();

            // 🔹 Context
            rec.Brand__c = input.brand;
            rec.Category__c = input.category;
            rec.CommunicationType__c = input.communicationType;
            rec.Channel__c = input.channel;
            rec.Channel_Detail__c = input.channelDetail;

            // 🔹 Change
            rec.Old_Value__c = input.oldValue;
            rec.New_Value__c = input.newValue;

            // 🔹 Admin
            rec.IsAdminOverride__c = input.isAdminOverride;
            rec.OverrideReason__c = input.overrideReason;

            // 🔹 Meta
            rec.Change_Source__c = input.changeSource;
            rec.Change_Reason__c = input.changeReason;

            // 🔹 Technical
            rec.CompositeKey__c = input.compositeKey;
            rec.EventTimestamp__c = System.now();

            // 🔹 Integration
            rec.Google_Ads_Eligible__c = input.googleAdsEligible;
            rec.Event_Id__c = input.eventId;
            rec.Request_Id__c = input.requestId;
            rec.Session_Id__c = input.sessionId;

            // 🔹 Owner (optional override)
            if (String.isNotBlank(input.ownerId)) {
                rec.OwnerId = input.ownerId;
            }

            records.add(rec);
        }

        if (!records.isEmpty()) {
            insert records;
        }
    }
}