/**
 * Guest-only entry points for the Communication Preference Center.
 *
 * Deliberately a separate class from Ctrl_PreferenceCenter: Salesforce grants Apex class
 * access per class, not per method, so any @AuraEnabled method on a class the Guest profile
 * can call is invokable directly (bypassing the LWC) with an arbitrary parameter. Keeping the
 * key-hash-only surface here — and granting only this class to Guest_CustomerHub — means a
 * guest request can never supply a raw Contact Id; it must present the Contact's
 * Preference_Token_Key__c value (an HMAC of their email, unforgeable without the org secret),
 * which is resolved to a Contact server-side.
 */
public without sharing class Ctrl_PreferenceCenterGuest {

    @AuraEnabled(cacheable=true)
    public static Ctrl_PreferenceCenter.PreferencePageData getPreferences(String token) {
        return Ctrl_PreferenceCenter.getPreferences(resolveContactId(token));
    }

    @AuraEnabled
    public static Integer savePreferences(
        String token,
        List<CommunicationPreference__c> incoming,
        String sessionId,
        String requestId
    ) {
        return Ctrl_PreferenceCenter.savePreferences(
            resolveContactId(token), incoming, sessionId, requestId
        );
    }

    /**
     * Passthroughs for the brand-theming calls the Preference Center LWC makes for every
     * visitor, guest or authenticated. Brand code / MC brand id carry no contact data, so
     * these are safe to expose directly — unlike getPreferences/savePreferences above, they
     * never need a token-to-Contact resolution.
     */
    @AuraEnabled(cacheable=true)
    public static Ctrl_PreferenceCenter.BrandThemeData getBrandTheme(String brand) {
        return Ctrl_PreferenceCenter.getBrandTheme(brand);
    }

    @AuraEnabled(cacheable=true)
    public static Ctrl_PreferenceCenter.DisplayLabels getDisplayLabels(String language) {
        return Ctrl_PreferenceCenter.getDisplayLabels(language);
    }

    @AuraEnabled
    public static Ctrl_PreferenceCenter.BrandThemeData getMCBrandAssets(String mcBrandId) {
        return Ctrl_PreferenceCenter.getMCBrandAssets(mcBrandId);
    }

    /** Resolves the key hash to a Contact — never trusts a client-supplied Id. */
    private static Id resolveContactId(String keyHash) {
        if (String.isBlank(keyHash)) {
            throw aura('Invalid token');
        }

        // Not enforced unique in the schema — Contacts can legitimately share an Email
        // (shared inbox, duplicates). Order deterministically so a given link always
        // resolves to the same Contact rather than an arbitrary one of several matches.
        List<Contact> matches = [
            SELECT Id
            FROM   Contact
            WHERE  Preference_Token_Key__c = :keyHash
            WITH   SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT  1
        ];
        if (matches.isEmpty()) {
            throw aura('No contact found for this link.');
        }
        return matches[0].Id;
    }

    /**
     * AuraHandledException.getMessage() returns a generic placeholder unless setMessage() is
     * also called — the constructor's message only reaches the client (error.body.message).
     * Routing every throw through here keeps server-side catches (tests, callers) able to
     * inspect the real message too.
     */
    private static AuraHandledException aura(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
