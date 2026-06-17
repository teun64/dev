public with sharing class Util_CommunicationPreferenceToken {

    // ⚠️ Replace with secure storage in production
    private static final String SECRET = 'REPLACE_ME_SECURE';

    // =========================
    // DTO
    // =========================
    public class TokenResult {
        public Id contactId;
        public String brand;

        public TokenResult(Id contactId, String brand) {
            this.contactId = contactId;
            this.brand = brand;
        }
    }

    // =========================
    // Generate
    // =========================
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

        String encoded = EncodingUtil.base64Encode(
            Blob.valueOf(JSON.serialize(payload))
        );

        String signature = sign(encoded);

        return encoded + '.' + signature;
    }

    // =========================
    // Validate
    // =========================
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

    // =========================
    // Signing
    // =========================
    private static String sign(String data) {
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(data),
            Blob.valueOf(SECRET)
        );
        return EncodingUtil.convertToHex(mac);
    }

    // =========================
    // Replay protection
    // =========================
    private static Boolean isNonceUsed(String nonce) {
        return [
            SELECT COUNT()
            FROM PreferenceTokenNonce__c
            WHERE Nonce__c = :nonce
        ] > 0;
    }

    private static void markNonceUsed(String nonce) {
        insert new PreferenceTokenNonce__c(Nonce__c = nonce);
    }
}