/**
 * Ctrl_PreferenceCenter
 *
 * Reads and writes CommunicationPreference__c records for a given Contact.
 * Each preference is a row master-detailed to a CommunicationPreferenceConfig__c —
 * Config__c carries the Brand + Category + Channel + CommunicationType identity, so
 * deleting a config row cascade-deletes every preference row that pointed to it.
 *
 * After any save, a CommunicationPreferenceAudit__c record is inserted for every
 * changed row, capturing old/new value, agent, source, and timestamp.
 *
 * Security:
 *   - without sharing → runs in system mode (no record-level restrictions)
 *   - WITH SYSTEM_MODE in all SOQL → bypasses FLS / CRUD
 */
public without sharing class Ctrl_PreferenceCenter {

    // ── Constants ─────────────────────────────────────────────────────────────
    private static final String CHANGE_REASON = 'USER_ACTION';
    private static AccessLevel runningMode = AccessLevel.SYSTEM_MODE;

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC METHODS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Returns the full preference catalog for a Contact or the Contact linked to a Case.
     * contextId accepts a Contact Id or a Case Id — SObjectType is detected automatically.
     *
     * Brand resolution order:
     *   Contact page → newest AccountContactRelation whose Account has PrimaryBrand__c set
     *   Case page    → Case.Account.PrimaryBrand__c first, then Contact's AccountContactRelation
     *   Fallback     → null (component defaults to first catalog tab)
     */
    @AuraEnabled(cacheable=true)
    public static PreferencePageData getPreferences(Id contextId) {
        if (contextId == null) throw new AuraHandledException('A Contact or Case Id is required.');

        Id      contactId;
        String  primaryBrand;
        Boolean showPartnerCategory = false;

        if (contextId.getSObjectType() == Contact.SObjectType) {
            // ── Contact page ──────────────────────────────────────────────────
            contactId = contextId;
            AccountContext ctx = resolveAccountContext(contactId, null);
            primaryBrand        = ctx.primaryBrand;
            showPartnerCategory = ctx.showPartnerCategory;

        } else if (contextId.getSObjectType() == Case.SObjectType) {
            // ── Case page — resolve Contact and brand from Case ────────────────
            Case c = [
                SELECT ContactId, AccountId, Account.PrimaryBrand__c,
                       Account.RecordType.DeveloperName
                FROM   Case
                WHERE  Id = :contextId
                WITH   SYSTEM_MODE
                LIMIT  1
            ];
            contactId = c.ContactId;
            // Try Case's own Account first
            if (c.Account != null && !String.isBlank(c.Account.PrimaryBrand__c)) {
                primaryBrand = c.Account.PrimaryBrand__c;
                // Get the ACR Roles for this specific Contact↔Account relationship
                List<AccountContactRelation> caseRels = [
                    SELECT Roles FROM AccountContactRelation
                    WHERE  ContactId = :contactId AND AccountId = :c.AccountId
                    WITH   SYSTEM_MODE LIMIT 1
                ];
                String caseRoles = caseRels.isEmpty() ? null : caseRels[0].Roles;
                showPartnerCategory = isPartnerCategoryVisible(
                    c.Account.RecordType.DeveloperName, caseRoles
                );
            }
            // Fall back to Contact's newest AccountContactRelation
            if (String.isBlank(primaryBrand) && contactId != null) {
                AccountContext ctx = resolveAccountContext(contactId, null);
                primaryBrand        = ctx.primaryBrand;
                showPartnerCategory = ctx.showPartnerCategory;
            }
        } else if (contextId.getSObjectType() == User.SObjectType) {
            // ── Experience Cloud landing page — resolve from logged-in user ────────
            List<User> users = [
                SELECT ContactId FROM User WHERE Id = :contextId WITH SYSTEM_MODE LIMIT 1
            ];
            if (users.isEmpty() || users[0].ContactId == null) {
                throw new AuraHandledException('No contact is linked to your user account.');
            }
            contactId = users[0].ContactId;
            AccountContext ctx = resolveAccountContext(contactId, null);
            primaryBrand        = ctx.primaryBrand;
            showPartnerCategory = ctx.showPartnerCategory;

        } else {
            throw new AuraHandledException('Unsupported record type — provide a Contact, Case or User Id.');
        }

        validateContactId(contactId);
        Contact con = queryContact(contactId);

        // ── 1. Load the catalog — CommunicationPreferenceConfig__c carries Brand,
        // CommunicationType, Channel and the Category derived from it, so it's both
        // the catalog and the parent every synthesized/existing row links to.
        List<CommunicationPreferenceConfig__c> catalog = [
            SELECT Id, Brand__c, CommunicationType__c, Channel__c, Category__c
            FROM CommunicationPreferenceConfig__c
            WITH SYSTEM_MODE
        ];

        // ── 2. Load existing preference records, keyed by CompositeKey ────────
        Map<String, CommunicationPreference__c> existingByKey = new Map<String, CommunicationPreference__c>();
        for (CommunicationPreference__c pref : [
            SELECT Id, Config__c, Config__r.Brand__c, Config__r.Category__c,
                   Config__r.Channel__c, Config__r.CommunicationType__c,
                   IsEnabled__c, LegalBasis__c, EffectiveDate__c, Source__c,
                   CompositeKey__c, Channel_Detail__c, BusinessLine__c,
                   Google_Ads_Eligible__c
            FROM CommunicationPreference__c
            WHERE Contact__c = :contactId
            WITH SYSTEM_MODE
        ]) {
            existingByKey.put(pref.CompositeKey__c, pref);
        }

        // ── 3. Build catalog-driven preference list ───────────────────────────
        // Key mirrors stampCompositeKeys: person|Config__c|BusinessLine.
        // Catalog-derived records always have BusinessLine = NONE.
        String person = String.valueOf(contactId);
        List<CommunicationPreference__c> prefs = new List<CommunicationPreference__c>();
        for (CommunicationPreferenceConfig__c cfg : catalog) {
            String key = person + '|' + cfg.Id + '|NONE';

            if (existingByKey.containsKey(key)) {
                prefs.add(existingByKey.get(key));
            } else {
                CommunicationPreference__c newRow = new CommunicationPreference__c(
                    Contact__c      = contactId,
                    Config__c       = cfg.Id,
                    IsEnabled__c    = 'SERVICE'.equals(cfg.Category__c),
                    Source__c       = resolveSource(),
                    CompositeKey__c = key
                );
                // Attach the parent in-memory so the client can read Config__r.* on a row
                // that was never queried from the database (it doesn't exist yet).
                newRow.putSObject('Config__r', cfg);
                prefs.add(newRow);
            }
        }

        CommunicationPreferenceAudit__c lastAudit = getLastAudit(contactId);

        PreferencePageData page  = new PreferencePageData();
        page.contactId           = String.valueOf(contactId);
        page.contactName         = con.FirstName + ' ' + con.LastName;
        page.contactEmail        = con.Email;
        page.contactPhone        = String.isNotBlank(con.MobilePhone) ? con.MobilePhone : con.Phone;
        page.preferences         = prefs;
        page.lastAudit           = lastAudit;
        page.primaryBrand        = primaryBrand;
        page.showPartnerCategory = showPartnerCategory;
        page.language            = resolveLanguage(con.Language__c);

        Boolean isExperienceCloud = String.isNotBlank(Site.getBaseUrl());
        Map<String, Map<String, String>> displayLabels = resolveDisplayLabels(isExperienceCloud, page.language);
        page.categoryLabels = displayLabels.get('ComPrev_Catergory');
        page.typeLabels     = displayLabels.get('ComPrev_CommunicationType');
        page.channelLabels  = displayLabels.get('ComPref_Channel');
        return page;
    }

    /**
     * Upserts a list of CommunicationPreference__c records.
     * Detects changed rows (IsEnabled__c toggle) and writes one
     * CommunicationPreferenceAudit__c record per change.
     *
     * @param contactId   Contact the preferences belong to
     * @param incoming    Full list of preference records (existing + new)
     * @param sessionId   Optional: browser session id for audit trail
     * @param requestId   Optional: correlation id for audit trail
     * @return            Number of audit records written
     */
    @AuraEnabled
    public static Integer savePreferences(
        Id contactId,
        List<CommunicationPreference__c> incoming,
        String sessionId,
        String requestId
    ) {
        validateContactId(contactId);
        if (incoming == null || incoming.isEmpty()) {
            throw new AuraHandledException('No preference records provided.');
        }

        // Stamp contact and source
        String src = resolveSource();
        for (CommunicationPreference__c p : incoming) {
            p.Contact__c = contactId;
            p.Source__c  = src;
        }

        // Brand/Category/Channel/CommunicationType live on Config__c now — re-query them
        // server-side (needed for the audit snapshot below) rather than trust anything the
        // client sent for those values.
        Map<Id, CommunicationPreferenceConfig__c> configById = loadConfigMap(incoming);

        // Build composite keys — mirrors rbb_CommunicationPreference Before Save flow:
        // BLANKVALUE(Contact__c, Lead__c) | Config__c | BusinessLine
        stampCompositeKeys(incoming, String.valueOf(contactId));

        // Only persist records for opted-in preferences OR existing records being updated.
        // New records (no Id) with IsEnabled__c = false are skipped — the batch cleanup
        // handles removal of records that have been explicitly opted out after creation.
        // Existing records (Id present) are always updated so the audit trail stays accurate.
        List<CommunicationPreference__c> toUpsert = new List<CommunicationPreference__c>();
        for (CommunicationPreference__c p : incoming) {
            if (p.Id != null || p.IsEnabled__c == true) {
                toUpsert.add(p);
            }
        }

        // Load current state to detect changes (only for records being persisted)
        Map<Id, Boolean> previousValues = getPreviousValues(toUpsert);

        // Upsert on CompositeKey__c external id
        if (!toUpsert.isEmpty()) {
            try {
                database.upsert(toUpsert, CommunicationPreference__c.CompositeKey__c, true, Ctrl_PreferenceCenter.runningMode);
            } catch (DmlException e) {
                throw new AuraHandledException('Save failed: ' + e.getDmlMessage(0));
            }
        }

        // Write audit records for changed rows
        List<CommunicationPreferenceAudit__c> audits =
            buildAuditRecords(contactId, toUpsert, previousValues, sessionId, requestId, configById);

        if (!audits.isEmpty()) {
            try {
                insert audits;
            } catch (DmlException e) {
                // Audit failure must not roll back preferences — log and continue
                System.debug(LoggingLevel.ERROR, 'Audit insert failed: ' + e.getMessage());
            }
        }

        return audits.size();
    }

    /**
     * Category/CommunicationType/Channel labels for an explicit language — used by the
     * Experience Cloud hub header's language switcher (nl/de/fr/en buttons), which changes
     * what the visitor is looking at without reloading the underlying preference catalog.
     * Always overlays the PicklistTranslation__c cache for the requested language (falling back
     * to the English master label via describe for anything not yet synced): unlike
     * getPreferences(), a caller here has explicitly asked for a specific language, so there's
     * no "running user's own language" case to preserve.
     */
    @AuraEnabled(cacheable=true)
    public static DisplayLabels getDisplayLabels(String language) {
        Map<String, Map<String, String>> labels = resolveDisplayLabels(true, language);
        DisplayLabels result = new DisplayLabels();
        result.categoryLabels = labels.get('ComPrev_Catergory');
        result.typeLabels     = labels.get('ComPrev_CommunicationType');
        result.channelLabels  = labels.get('ComPref_Channel');
        return result;
    }

    /**
     * Returns branding configuration for a given brand code (E, M, T).
     * Queries BrandThemeConfig__mdt for colors, logo path, and MC brand ID.
     * Cacheable — does not make callouts.
     */
    @AuraEnabled(cacheable=true)
    public static BrandThemeData getBrandTheme(String brand) {
        BrandThemeData data = new BrandThemeData();
        data.brand = brand;

        for (BrandThemeConfig__mdt cfg : BrandThemeConfig__mdt.getAll().values()) {
            if (cfg.Brand__c == brand) {
                data.brandName      = cfg.BrandName__c;
                data.primaryColor   = cfg.PrimaryColor__c;
                data.accentColor    = cfg.AccentColor__c;
                data.logoStaticPath = cfg.LogoStaticResource__c;
                data.mcBrandId      = cfg.McBrandId__c;
                data.tagLine        = cfg.TagLine__c;
                break;
            }
        }
        return data;
    }

    /**
     * Fetches live brand assets (logo URL, colors) from Marketing Cloud BrandCenter.
     * Requires Named Credential 'MC_Marketing_Cloud' to be configured in Setup.
     * Non-cacheable — makes an HTTP callout.
     */
    @AuraEnabled
    public static BrandThemeData getMCBrandAssets(String mcBrandId) {
        if (String.isBlank(mcBrandId)) return null;
        try {
            return Svc_MCBrandCenter.getBrandAssets(mcBrandId);
        } catch (Exception e) {
            return null; // caller falls back to static metadata
        }
    }

    /**
     * Returns the audit history for a Contact, most-recent first.
     */
    @AuraEnabled(cacheable=true)
    public static List<CommunicationPreferenceAudit__c> getAuditHistory(
        Id contactId, Integer limitRows
    ) {
        validateContactId(contactId);
        Integer maxRows = (limitRows != null && limitRows > 0) ? limitRows : 50;
        return [
            SELECT Id, CommunicationPreference__c, Brand__c, Category__c,
                   CommunicationType__c, Channel__c, Old_Value__c, New_Value__c,
                   Changed_By__c, Changed_By__r.Name, Change_Source__c,
                   Change_Reason__c, IsAdminOverride__c, OverrideReason__c,
                   EventTimestamp__c, Session_Id__c, Request_Id__c
            FROM CommunicationPreferenceAudit__c
            WHERE Contact__c = :contactId
            WITH SYSTEM_MODE
            ORDER BY EventTimestamp__c DESC
            LIMIT :maxRows
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /** Returns 'Self-Service' on Customer Hub (Experience Cloud), 'Support' on internal pages. */
    private static String resolveSource() {
        return String.isNotBlank(Site.getBaseUrl()) ? 'Preference Center' : 'Support';
    }

    /** Returns 'CUSTOMER_PORTAL' on Customer Hub (Experience Cloud), 'SUPPORT_CONSOLE' internally. */
    private static String resolveChangeSource() {
        return String.isNotBlank(Site.getBaseUrl()) ? 'CUSTOMER_PORTAL' : 'SUPPORT_CONSOLE';
    }

    /**
     * Loads the CommunicationPreferenceConfig__c parent for every Config__c Id referenced by
     * incoming — queried fresh rather than trusting anything the client sent, since Brand/
     * Category/Channel/CommunicationType live only on that related record now.
     */
    private static Map<Id, CommunicationPreferenceConfig__c> loadConfigMap(
        List<CommunicationPreference__c> incoming
    ) {
        Set<Id> configIds = new Set<Id>();
        for (CommunicationPreference__c p : incoming) {
            if (p.Config__c != null) configIds.add(p.Config__c);
        }
        return new Map<Id, CommunicationPreferenceConfig__c>([
            SELECT Id, Brand__c, Category__c, Channel__c, CommunicationType__c
            FROM CommunicationPreferenceConfig__c
            WHERE Id IN :configIds
            WITH SYSTEM_MODE
        ]);
    }

    /** Mutates each record's CompositeKey__c to match the Before Save flow formula */
    private static void stampCompositeKeys(List<CommunicationPreference__c> prefs, String ckPerson) {
        for (CommunicationPreference__c pref : prefs) {
            String ckConfig = pref.Config__c        != null ? String.valueOf(pref.Config__c) : 'NONE';
            String ckBLine  = pref.BusinessLine__c   != null ? pref.BusinessLine__c           : 'NONE';
            pref.CompositeKey__c = ckPerson + '|' + ckConfig + '|' + ckBLine;
        }
    }

    private static Contact queryContact(Id contactId) {
        try {
            return [
                SELECT Id, FirstName, LastName, Email, MobilePhone, Phone, Language__c
                FROM Contact
                WHERE Id = :contactId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('Contact not found or access denied.');
        }
    }

    // Contact.Language__c is a country code, not a language code — map to the 4 languages the
    // Preference Center LWC supports (nl/de/fr/en). Unmapped/blank codes fall back to English
    // rather than Dutch, since NL is only the org's default, not a safe guess for e.g. ES/PL/RO.
    private static final Map<String, String> COUNTRY_TO_LANGUAGE = new Map<String, String>{
        'NL' => 'nl', 'BE' => 'nl', 'AN' => 'nl',
        'DE' => 'de', 'AT' => 'de', 'CH' => 'de', 'LU' => 'de',
        'FR' => 'fr',
        'GB' => 'en', 'EN' => 'en'
    };

    /** Contact's language when known; English otherwise — never null, so the client always has a language to render in rather than silently keeping whatever it was already showing. */
    private static String resolveLanguage(String countryCode) {
        if (String.isBlank(countryCode)) return 'en';
        String lang = COUNTRY_TO_LANGUAGE.get(countryCode);
        return lang != null ? lang : 'en';
    }

    private static final Map<String, String> VALUE_SET_TO_FIELD = new Map<String, String>{
        'ComPrev_Catergory'         => 'Category__c',
        'ComPrev_CommunicationType' => 'CommunicationType__c',
        'ComPref_Channel'           => 'Channel__c'
    };

    /**
     * Category/CommunicationType/Channel display labels, keyed by Global Value Set name then
     * API value.
     *
     * Internal Console: native picklist describe already resolves Translation Workbench text
     * in the running (internal) user's own language — verified directly (switching a user's
     * LanguageLocaleKey to nl_NL/fr changes getPicklistValues().getLabel() accordingly), so no
     * extra query is needed there.
     *
     * Experience Cloud (guest or logged-in portal user): the site runs under one fixed-language
     * Guest User (confirmed en_US, single record for the whole site) and a portal user's own
     * language isn't necessarily the Contact's, so describe can't serve the CONTACT's language.
     * Overlay PicklistTranslation__c for that language instead — kept in sync with Translation
     * Workbench by the admin-triggered Svc_PicklistTranslationSync.syncAll().
     */
    private static Map<String, Map<String, String>> resolveDisplayLabels(
        Boolean isExperienceCloud, String contactLanguage
    ) {
        Map<String, Map<String, String>> byValueSet = new Map<String, Map<String, String>>();

        Map<String, Schema.DescribeFieldResult> fieldDescribes = new Map<String, Schema.DescribeFieldResult>{
            'Category__c'          => CommunicationPreferenceConfig__c.Category__c.getDescribe(),
            'CommunicationType__c' => CommunicationPreferenceConfig__c.CommunicationType__c.getDescribe(),
            'Channel__c'           => CommunicationPreferenceConfig__c.Channel__c.getDescribe()
        };
        for (String valueSet : VALUE_SET_TO_FIELD.keySet()) {
            Map<String, String> labels = new Map<String, String>();
            for (Schema.PicklistEntry pe : fieldDescribes.get(VALUE_SET_TO_FIELD.get(valueSet)).getPicklistValues()) {
                labels.put(pe.getValue(), pe.getLabel());
            }
            byValueSet.put(valueSet, labels);
        }

        if (isExperienceCloud && String.isNotBlank(contactLanguage) && !'en'.equals(contactLanguage)) {
            for (PicklistTranslation__c row : [
                SELECT ValueSetName__c, ApiValue__c, Label__c
                FROM PicklistTranslation__c
                WHERE ValueSetName__c IN :VALUE_SET_TO_FIELD.keySet() AND Language__c = :contactLanguage
                WITH SYSTEM_MODE
            ]) {
                Map<String, String> labels = byValueSet.get(row.ValueSetName__c);
                if (labels != null) labels.put(row.ApiValue__c, row.Label__c);
            }
        }
        return byValueSet;
    }

    private static CommunicationPreferenceAudit__c getLastAudit(Id contactId) {
        List<CommunicationPreferenceAudit__c> audits = [
            SELECT Changed_By__r.Name, Change_Source__c, EventTimestamp__c
            FROM CommunicationPreferenceAudit__c
            WHERE Contact__c = :contactId
            WITH SYSTEM_MODE
            ORDER BY EventTimestamp__c DESC
            LIMIT 1
        ];
        return audits.isEmpty() ? null : audits[0];
    }

    /** Returns a map of existing record Id → current IsEnabled__c value */
    private static Map<Id, Boolean> getPreviousValues(
        List<CommunicationPreference__c> incoming
    ) {
        Set<Id> existingIds = new Set<Id>();
        for (CommunicationPreference__c p : incoming) {
            if (p.Id != null) existingIds.add(p.Id);
        }
        Map<Id, Boolean> result = new Map<Id, Boolean>();
        if (existingIds.isEmpty()) return result;

        for (CommunicationPreference__c existing : [
            SELECT Id, IsEnabled__c
            FROM CommunicationPreference__c
            WHERE Id IN :existingIds
            WITH SYSTEM_MODE
        ]) {
            result.put(existing.Id, existing.IsEnabled__c);
        }
        return result;
    }

    /** Builds one audit record per row where IsEnabled__c actually changed */
    private static List<CommunicationPreferenceAudit__c> buildAuditRecords(
        Id contactId,
        List<CommunicationPreference__c> saved,
        Map<Id, Boolean> previousValues,
        String sessionId,
        String requestId,
        Map<Id, CommunicationPreferenceConfig__c> configById
    ) {
        List<CommunicationPreferenceAudit__c> audits = new List<CommunicationPreferenceAudit__c>();
        Datetime now = Datetime.now();
        String changeSource = resolveChangeSource();

        for (CommunicationPreference__c p : saved) {
            Boolean oldVal = previousValues.containsKey(p.Id)
                ? previousValues.get(p.Id)
                : null; // null = newly created row

            // Only audit when the enabled flag changed (or row is brand new)
            Boolean changed = (oldVal == null) || (oldVal != p.IsEnabled__c);
            if (!changed) continue;

            // Audit keeps its own Brand/Category/Channel/CommunicationType snapshot — a
            // permanent historical record independent of any later catalog edit, so it's
            // intentionally NOT a relationship to CommunicationPreferenceConfig__c.
            CommunicationPreferenceConfig__c cfg = configById.get(p.Config__c);
            CommunicationPreferenceAudit__c audit = new CommunicationPreferenceAudit__c(
                Contact__c                 = contactId,
                CommunicationPreference__c = p.Id,
                Brand__c                   = cfg?.Brand__c,
                Category__c                = cfg?.Category__c,
                CommunicationType__c       = cfg?.CommunicationType__c,
                Channel__c                 = cfg?.Channel__c,
                Old_Value__c               = (oldVal == null) ? false : oldVal,
                New_Value__c               = p.IsEnabled__c,
                Google_Ads_Eligible__c     = p.Google_Ads_Eligible__c,
                Changed_By__c              = UserInfo.getUserId(),
                Change_Source__c           = changeSource,
                Change_Reason__c           = CHANGE_REASON,
                IsAdminOverride__c         = false,
                EventTimestamp__c          = now,
                CompositeKey__c            = p.CompositeKey__c,
                Channel_Detail__c          = p.Channel_Detail__c,
                Session_Id__c              = sessionId,
                Request_Id__c              = requestId
            );
            audits.add(audit);
        }
        return audits;
    }

    /**
     * Resolves brand, RecordType and relation role from the newest AccountContactRelation
     * that has PrimaryBrand__c set. accountId may be passed to target a specific account
     * (Case page); when null, the newest ACR is used.
     */
    private static AccountContext resolveAccountContext(Id contactId, Id accountId) {
        List<AccountContactRelation> rels;
        if (accountId != null) {
            rels = [
                SELECT Account.PrimaryBrand__c, Account.RecordType.DeveloperName, Roles
                FROM   AccountContactRelation
                WHERE  ContactId  = :contactId
                AND    AccountId  = :accountId
                WITH   SYSTEM_MODE
                LIMIT  1
            ];
        } else {
            rels = [
                SELECT Account.PrimaryBrand__c, Account.RecordType.DeveloperName, Roles
                FROM   AccountContactRelation
                WHERE  ContactId              = :contactId
                AND    Account.PrimaryBrand__c != null
                WITH   SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT  1
            ];
        }
        if (rels.isEmpty()) return new AccountContext(null, false);
        AccountContactRelation rel = rels[0];
        return new AccountContext(
            rel.Account.PrimaryBrand__c,
            isPartnerCategoryVisible(rel.Account.RecordType.DeveloperName, rel.Roles)
        );
    }

    /**
     * Partner Network category is visible only for B2B contacts whose relation role
     * is explicitly set to something other than "End User".
     * B2C accounts always default to End User and never see Partner Network.
     */
    private static Boolean isPartnerCategoryVisible(String recordTypeDeveloperName, String roles) {
        if ('B2C'.equals(recordTypeDeveloperName)) return false;
        return !String.isBlank(roles) && !'End User'.equals(roles);
    }

    private static void validateContactId(Id contactId) {
        if (contactId == null) {
            throw new AuraHandledException('A Contact Id is required.');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WRAPPER CLASSES
    // ─────────────────────────────────────────────────────────────────────────

    public class BrandThemeData {
        @AuraEnabled public String brand;
        @AuraEnabled public String brandName;
        @AuraEnabled public String primaryColor;
        @AuraEnabled public String accentColor;
        @AuraEnabled public String logoStaticPath;
        @AuraEnabled public String mcBrandId;
        @AuraEnabled public String mcLogoUrl;
        @AuraEnabled public String tagLine;
    }

    public class PreferencePageData {
        @AuraEnabled public String                           contactId;
        @AuraEnabled public String                           contactName;
        @AuraEnabled public String                           contactEmail;
        @AuraEnabled public String                           contactPhone;
        @AuraEnabled public List<CommunicationPreference__c> preferences;
        @AuraEnabled public CommunicationPreferenceAudit__c  lastAudit;
        @AuraEnabled public String                           primaryBrand;
        @AuraEnabled public Boolean                          showPartnerCategory;
        @AuraEnabled public String                           language;
        @AuraEnabled public Map<String, String>              categoryLabels;
        @AuraEnabled public Map<String, String>              typeLabels;
        @AuraEnabled public Map<String, String>              channelLabels;
    }

    public class DisplayLabels {
        @AuraEnabled public Map<String, String> categoryLabels;
        @AuraEnabled public Map<String, String> typeLabels;
        @AuraEnabled public Map<String, String> channelLabels;
    }

    private class AccountContext {
        String  primaryBrand;
        Boolean showPartnerCategory;
        AccountContext(String brand, Boolean showPartner) {
            this.primaryBrand        = brand;
            this.showPartnerCategory = showPartner;
        }
    }
}