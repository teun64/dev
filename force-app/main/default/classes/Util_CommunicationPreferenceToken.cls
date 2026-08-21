/**
 * Builds the Contact.Preference_Token_Key__c (an HMAC of the contact's email) used to resolve
 * guest (unauthenticated) Preference Center links to a Contact without ever carrying its record
 * Id, and the ready-to-use URL built around it.
 *
 * The key hash itself is the credential — HMAC-SHA256(email, secret) can't be forged without
 * the secret, and it's not derived from (or reversible to) the Contact Id, so a leaked or
 * guessed link exposes nothing but a hashed email. There's no separate signed/expiring token
 * wrapper on top: one was tried, but it only added length (blocking sync into Data Cloud /
 * Marketing Cloud, which cap or exclude oversized text fields) without adding real protection,
 * since the hash is already an unforgeable MAC. Revoke a single contact's link by changing
 * their Email (new hash), or all links org-wide by rotating PreferenceTokenConfig__c.Secret__c.
 */
public with sharing class Util_CommunicationPreferenceToken {

    public class TokenConfigException extends Exception {}

    /**
     * Builds a ready-to-use Preference Center URL for a Contact's key hash. Used by
     * Trigger_Contact to stamp Contact.Preference_Center_Url__c so email templates can merge
     * it in directly (e.g. {!Contact.Preference_Center_Url__c}) without any Apex at send time.
     */
    public static String buildPreferenceCenterUrl(String keyHash) {
        if (String.isBlank(keyHash)) return null;

        String baseUrl = PreferenceTokenConfig__c.getOrgDefaults()?.Base_Url__c;
        if (String.isBlank(baseUrl)) {
            throw new TokenConfigException(
                'PreferenceTokenConfig__c.Base_Url__c is not configured for this org.'
            );
        }

        return baseUrl.removeEnd('/') + '/preferences?token=' + EncodingUtil.urlEncode(keyHash, 'UTF-8') + '&brand=M';
    }

    // =========================
    // Email -> key hash (used by Trigger_Contact to stamp Contact.Preference_Token_Key__c)
    // =========================
    public static String hashEmail(String email) {
        if (String.isBlank(email)) return null;
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(email.trim().toLowerCase()),
            Blob.valueOf(getSecret())
        );
        return EncodingUtil.convertToHex(mac);
    }

    /**
     * Reads the signing secret from the protected PreferenceTokenConfig__c hierarchy custom
     * setting. Fails closed — an unconfigured secret blocks all key-hash generation rather than
     * falling back to a default value.
     */
    private static String getSecret() {
        String secret = PreferenceTokenConfig__c.getOrgDefaults()?.Secret__c;
        if (String.isBlank(secret)) {
            throw new TokenConfigException(
                'PreferenceTokenConfig__c.Secret__c is not configured for this org.'
            );
        }
        return secret;
    }
}
