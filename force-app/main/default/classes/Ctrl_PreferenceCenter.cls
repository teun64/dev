/**
 * Ctrl_PreferenceCenter
 *
 * Reads and writes CommunicationPreference__c records for a given Contact.
 * Each preference is a row keyed by Brand + Category + Channel + CommunicationType.
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

    // Lazy-loaded cache — queried once per transaction from CommunicationTypeCategory__mdt.
    private static Map<String, String> typeToCategory;

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

        // ── 1. Load the CMT catalog ───────────────────────────────────────────
        List<BrandCommunicationConfig__mdt> catalog = new List<BrandCommunicationConfig__mdt>(
            BrandCommunicationConfig__mdt.getAll().values()
        );

        // ── 2. Load existing preference records, keyed by CompositeKey ────────
        Map<String, CommunicationPreference__c> existingByKey = new Map<String, CommunicationPreference__c>();
        for (CommunicationPreference__c pref : [
            SELECT Id, Brand__c, Category__c, Channel__c, CommunicationType__c,
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
        // Key mirrors stampCompositeKeys: person|Brand|Category|Type|Channel|BusinessLine
        // Category is derived from CommunicationType via CommunicationTypeCategory__mdt.
        // Catalog-derived records always have BusinessLine = NONE.
        Map<String, String> typeToCat = getTypeToCategory();
        String person = String.valueOf(contactId);
        List<CommunicationPreference__c> prefs = new List<CommunicationPreference__c>();
        for (BrandCommunicationConfig__mdt cfg : catalog) {
            String category = typeToCat.containsKey(cfg.CommunicationType__c)
                ? typeToCat.get(cfg.CommunicationType__c)
                : 'NONE';
            String ckBrand = cfg.Brand__c             != null ? cfg.Brand__c             : 'NONE';
            String ckCat   = category;
            String ckType  = cfg.CommunicationType__c != null ? cfg.CommunicationType__c : 'NONE';
            String ckChan  = cfg.Channel__c           != null ? cfg.Channel__c           : 'NONE';
            String key     = person + '|' + ckBrand + '|' + ckCat + '|' + ckType + '|' + ckChan + '|NONE';

            if (existingByKey.containsKey(key)) {
                prefs.add(existingByKey.get(key));
            } else {
                prefs.add(new CommunicationPreference__c(
                    Contact__c           = contactId,
                    Brand__c             = cfg.Brand__c,
                    Category__c          = category,
                    CommunicationType__c = cfg.CommunicationType__c,
                    Channel__c           = cfg.Channel__c,
                    IsEnabled__c         = 'SERVICE'.equals(category),
                    Source__c            = resolveSource(),
                    CompositeKey__c      = key
                ));
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

        // Build composite keys — mirrors rbb_CommunicationPreference Before Save flow:
        // BLANKVALUE(Contact__c, Lead__c) | Brand | Category | CommunicationType | Channel | BusinessLine
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
            buildAuditRecords(contactId, toUpsert, previousValues, sessionId, requestId);

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

    /** Queries CommunicationTypeCategory__mdt once per transaction and caches the result. */
    private static Map<String, String> getTypeToCategory() {
        if (typeToCategory == null) {
            typeToCategory = new Map<String, String>();
            for (CommunicationTypeCategory__mdt m : CommunicationTypeCategory__mdt.getAll().values()) {
                typeToCategory.put(m.CommunicationType__c, m.Category__c);
            }
        }
        return typeToCategory;
    }

    /** Returns 'Self-Service' on Customer Hub (Experience Cloud), 'Support' on internal pages. */
    private static String resolveSource() {
        return String.isNotBlank(Site.getBaseUrl()) ? 'Preference Center' : 'Support';
    }

    /** Returns 'CUSTOMER_PORTAL' on Customer Hub (Experience Cloud), 'SUPPORT_CONSOLE' internally. */
    private static String resolveChangeSource() {
        return String.isNotBlank(Site.getBaseUrl()) ? 'CUSTOMER_PORTAL' : 'SUPPORT_CONSOLE';
    }

    /** Mutates each record's CompositeKey__c to match the Before Save flow formula */
    private static void stampCompositeKeys(List<CommunicationPreference__c> prefs, String ckPerson) {
        for (CommunicationPreference__c pref : prefs) {
            String ckBrand   = pref.Brand__c             != null ? pref.Brand__c             : 'NONE';
            String ckCat     = pref.Category__c          != null ? pref.Category__c          : 'NONE';
            String ckType    = pref.CommunicationType__c != null ? pref.CommunicationType__c : 'NONE';
            String ckChannel = pref.Channel__c           != null ? pref.Channel__c           : 'NONE';
            String ckBLine   = pref.BusinessLine__c      != null ? pref.BusinessLine__c      : 'NONE';
            pref.CompositeKey__c = ckPerson + '|' + ckBrand + '|' + ckCat + '|' + ckType + '|' + ckChannel + '|' + ckBLine;
        }
    }

    private static Contact queryContact(Id contactId) {
        try {
            return [
                SELECT Id, FirstName, LastName, Email, MobilePhone, Phone
                FROM Contact
                WHERE Id = :contactId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new AuraHandledException('Contact not found or access denied.');
        }
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
        String requestId
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

            CommunicationPreferenceAudit__c audit = new CommunicationPreferenceAudit__c(
                Contact__c                 = contactId,
                CommunicationPreference__c = p.Id,
                Brand__c                   = p.Brand__c,
                Category__c                = p.Category__c,
                CommunicationType__c       = p.CommunicationType__c,
                Channel__c                 = p.Channel__c,
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