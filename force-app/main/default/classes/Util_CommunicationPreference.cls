public with sharing class Util_CommunicationPreference {

    // =====================================================
    // 🔐 TOKEN SERVICE (nested, isolated)
    // =====================================================
    public class Token {

        private static final String SECRET = 'REPLACE_ME_SECURE';

        public class TokenResult {
            public Id contactId;
            public String brand;

            public TokenResult(Id contactId, String brand) {
                this.contactId = contactId;
                this.brand = brand;
            }
        }

        // -------------------------
        // Generate
        // -------------------------
        public static String generate(Id contactId, String brand, Integer ttlSeconds) {

            Long exp = DateTime.now().getTime() / 1000 + ttlSeconds;
            String nonce = EncodingUtil.convertToHex(
                Crypto.generateDigest('MD5', Blob.valueOf(String.valueOf(Math.random())))
            );

            Map<String, Object> payload = new Map<String, Object>{
                'cid' => contactId,
                'brand' => brand,
                'exp' => exp,
                'nonce' => nonce
            };

            String encoded = EncodingUtil.base64Encode(Blob.valueOf(JSON.serialize(payload)));
            String signature = sign(encoded);

            return encoded + '.' + signature;
        }

        // -------------------------
        // Validate
        // -------------------------
        public static TokenResult validate(String token) {

            if (String.isBlank(token) || !token.contains('.')) {
                throw new AuraHandledException('Invalid token');
            }

            List<String> parts = token.split('\\.');
            String encoded = parts[0];
            String signature = parts[1];

            if (sign(encoded) != signature) {
                throw new AuraHandledException('Invalid signature');
            }

            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(
                    EncodingUtil.base64Decode(encoded).toString()
                );

            Long exp = (Long) payload.get('exp');

            if (DateTime.now().getTime() / 1000 > exp) {
                throw new AuraHandledException('Token expired');
            }

            String nonce = (String) payload.get('nonce');

            if (isNonceUsed(nonce)) {
                throw new AuraHandledException('Token already used');
            }

            markNonceUsed(nonce);

            return new TokenResult(
                (String) payload.get('cid'),
                (String) payload.get('brand')
            );
        }

        // -------------------------
        // Signing
        // -------------------------
        private static String sign(String data) {
            Blob mac = Crypto.generateMac(
                'HmacSHA256',
                Blob.valueOf(data),
                Blob.valueOf(SECRET)
            );
            return EncodingUtil.convertToHex(mac);
        }

        // -------------------------
        // Replay protection
        // -------------------------
        private static Boolean isNonceUsed(String nonce) {
            return [SELECT COUNT() FROM PreferenceTokenNonce__c WHERE Nonce__c = :nonce] > 0;
        }

        private static void markNonceUsed(String nonce) {
            insert new PreferenceTokenNonce__c(Nonce__c = nonce);
        }
    }

    // =====================================================
    // 📥 GET
    // =====================================================
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

    // =====================================================
    // 💾 SAVE
    // =====================================================
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
                SELECT Id, Contact__c, Brand__c, Category__c,
                       CommunicationType__c, Channel__c,
                       Is_Enabled__c, CompositeKey__c
                FROM CommunicationPreference__c
                WHERE Contact__c = :contactId
                  AND Brand__c = :brand
            ]
        );

        List<CommunicationPreference__c> updates = new List<CommunicationPreference__c>();
        List<Log_CommunicationPreference.AuditInput> logs = new List<Log_CommunicationPreference.AuditInput>();

        for (Ctrl_CommunicationPreference.PreferenceInput input : inputs) {

            CommunicationPreference__c pref = existing.get(input.preferenceId);
            if (pref == null) continue;

            Boolean oldVal = pref.Is_Enabled__c;
            Boolean newVal = input.isEnabled;

            if (pref.Category__c == 'SERVICE' && !isRealAdmin) {
                newVal = true;
            }

            if (oldVal == newVal) continue;

            pref.Is_Enabled__c = newVal;
            updates.add(pref);

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
            log.changeSource = isRealAdmin ? 'SUPPORT' : 'PREFERENCE_CENTER';
            log.changeReason = isRealAdmin ? 'ADMIN_OVERRIDE' : 'USER_ACTION';
            log.compositeKey = pref.CompositeKey__c;
            log.requestId = requestId;
            log.sessionId = sessionId;

            logs.add(log);
        }

        if (!updates.isEmpty()) update updates;
        if (!logs.isEmpty()) Log_CommunicationPreference.log(logs);
    }

    private static Boolean hasAdminAccess() {
        return FeatureManagement.checkPermission('Manage_Communication_Preferences');
    }
}