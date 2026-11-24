/**
 * Guest-only entry points for the Communication Preference Center.
 *
 * Deliberately a separate class from Ctrl_PreferenceCenter: Salesforce grants Apex class
 * access per class, not per method, so any @AuraEnabled method on a class the Guest profile
 * can call is invokable directly (bypassing the LWC) with an arbitrary parameter. Keeping the
 * key-hash-only surface here — and granting only this class to ps_miCustomerHub — means a
 * guest request can never supply a raw Contact Id; it must present the Contact's
 * Preference_Token_Key__c value (an HMAC of their email, unforgeable without the org secret),
 * which is resolved to a Contact server-side.
 */
public without sharing class Ctrl_PreferenceCenterGuest {

    @AuraEnabled(cacheable=true)
    public static Ctrl_PreferenceCenter.PreferencePageData getPreferences(String token) {
        Resolved r = resolve(token);
        Ctrl_PreferenceCenter.PreferencePageData data = Ctrl_PreferenceCenter.getPreferences(r.contactId);
        data.staleToken = r.stale;
        // Data minimisation: a link in an email is not a login. Show first + middle name, a masked last name and a masked address only.
        List<Contact> names = [SELECT FirstName, MiddleName, LastName FROM Contact WHERE Id = :r.contactId WITH SYSTEM_MODE LIMIT 1];
        data.contactName  = names.isEmpty() ? '' : maskName(names[0]);
        data.contactEmail = maskEmail(data.contactEmail);
        data.contactPhone = null;
        return data;
    }

    /** Jane Marie Doe -> Jane Marie D*** */
    @TestVisible
    private static String maskName(Contact c) {
        List<String> parts = new List<String>();
        if (!String.isBlank(c.FirstName))  parts.add(c.FirstName);
        if (!String.isBlank(c.MiddleName)) parts.add(c.MiddleName);
        if (!String.isBlank(c.LastName))   parts.add(c.LastName.left(1) + '***');
        return String.join(parts, ' ');
    }

    /** jane.doe@example.com -> j***@example.com */
    @TestVisible
    private static String maskEmail(String email) {
        if (String.isBlank(email) || !email.contains('@')) return email == null ? null : '***';
        String local = email.substringBefore('@');
        return local.left(1) + '***@' + email.substringAfter('@');
    }

    @AuraEnabled
    public static Integer savePreferences(
        String token,
        List<CommunicationPreference__c> incoming,
        String sessionId,
        String requestId
    ) {
        return Ctrl_PreferenceCenter.savePreferences(
            resolve(token).contactId, incoming, sessionId, requestId
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

    public class Resolved {
        public Id contactId;
        public Boolean stale;
    }

    /**
     * Resolves the key hash to a Contact - never trusts a client-supplied Id. The current key is tried
     * first; the previous key (before the last rotation) still works but is flagged stale so the page
     * can tell the visitor to use their newest link. Anything else is expired or invalid.
     */
    @TestVisible
    private static Resolved resolve(String keyHash) {
        if (String.isBlank(keyHash)) {
            throw aura(EXPIRED_MESSAGE);
        }

        // Not enforced unique in the schema - Contacts can legitimately share an Email
        // (shared inbox, duplicates). Order deterministically so a given link always
        // resolves to the same Contact rather than an arbitrary one of several matches.
        List<Contact> current = [
            SELECT Id FROM Contact
            WHERE  Preference_Token_Key__c = :keyHash
            WITH   SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT  1
        ];
        Resolved r = new Resolved();
        if (!current.isEmpty()) {
            r.contactId = current[0].Id;
            r.stale = false;
            return r;
        }

        List<Contact> previous = [
            SELECT Id FROM Contact
            WHERE  Preference_Token_Previous__c = :keyHash
            WITH   SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT  1
        ];
        if (!previous.isEmpty()) {
            r.contactId = previous[0].Id;
            r.stale = true;
            return r;
        }
        throw aura(EXPIRED_MESSAGE);
    }

    @TestVisible
    private static final String EXPIRED_MESSAGE =
        '[LINK_EXPIRED] This link has expired or is no longer valid. To protect your data and your privacy, links are only valid for a limited time. '
        + 'Please use the link in a more recent email from us. We value your security.';

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
