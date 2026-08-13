public without sharing class Ctrl_DealerShop {

    // ── Data_Translation__c (base record type) ────────────────────────────────

    private static Id baseTranslationRtId {
        get {
            if (baseTranslationRtId == null) {
                List<RecordType> rts = [
                    SELECT Id FROM RecordType
                    WHERE SObjectType = 'Data_Translation__c'
                      AND DeveloperName = 'base'
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                baseTranslationRtId = rts.isEmpty() ? null : rts[0].Id;
            }
            return baseTranslationRtId;
        }
        set;
    }

    // ── Pricebook resolution ──────────────────────────────────────────────────

    private static Id resolvePricebookId(Account acct) {
        String countryCode = acct.BillingCountryCode;
        if ('GB'.equals(countryCode)) countryCode = 'UK';

        String market = 'All';
        String dealerCat = acct.Dealer_category__c;
        if (String.isNotBlank(dealerCat)) {
            if (dealerCat.contains('Fleet'))    market = 'Fleet';
            else if (dealerCat.contains('Security')) market = 'Security';
        }

        List<Pricebook2> books = [
            SELECT Id, Name
            FROM Pricebook2
            WHERE Name LIKE '%Dealer%'
              AND Name LIKE :('%' + countryCode + '%')
              AND Name LIKE :('%' + market + '%')
            WITH SYSTEM_MODE
            ORDER BY Name DESC
            LIMIT 1
        ];
        if (!books.isEmpty()) return books[0].Id;

        List<Pricebook2> fallback = [
            SELECT Id
            FROM Pricebook2
            WHERE Name LIKE '%Dealer%'
            WITH SYSTEM_MODE
            ORDER BY Name DESC
            LIMIT 1
        ];
        return fallback.isEmpty() ? null : fallback[0].Id;
    }

    // ── Language resolution ───────────────────────────────────────────────────

    private static final Set<String> SUPPORTED_LANGUAGES = new Set<String>{
        'en', 'nl', 'de', 'fr', 'es'
    };

    // Maps Contact.Language__c country codes (uppercase) to ISO 639-1 language codes.
    // Returns null when no mapping exists so callers can fall through to the next source.
    private static String resolveLanguage(String countryCode) {
        if (String.isBlank(countryCode)) return null;
        Map<String, String> mapping = new Map<String, String>{
            'EN' => 'en', 'GB' => 'en',
            'NL' => 'nl', 'AN' => 'nl', 'BE' => 'nl',
            'DE' => 'de', 'AT' => 'de', 'CH' => 'de',
            'FR' => 'fr', 'LU' => 'fr', 'MC' => 'fr',
            'ES' => 'es', 'AD' => 'es'
        };
        return mapping.get(countryCode.toUpperCase());
    }

    // Validates a lowercase ISO 639-1 code against SUPPORTED_LANGUAGES.
    // Returns the code (lowercased) or null when unsupported.
    private static String normalizeLang(String isoCode) {
        if (String.isBlank(isoCode)) return null;
        String lower = isoCode.toLowerCase();
        return SUPPORTED_LANGUAGES.contains(lower) ? lower : null;
    }

    private static DealerContext getDealerContext() {
        List<User> users = [
            SELECT ContactId, DefaultLanguage__c, Email
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) return fallbackContext(null);
        User usr = users[0];

        // Primary: external/community user with ContactId
        if (usr.ContactId != null) {
            List<Contact> contacts = [
                SELECT AccountId, Language__c
                FROM Contact WHERE Id = :usr.ContactId WITH SYSTEM_MODE LIMIT 1
            ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                return buildContextFromContact(contacts[0], usr.DefaultLanguage__c);
            }
        }

        // Secondary: Identity/internal user — resolve Account via Contact email match
        if (String.isNotBlank(usr.Email)) {
            List<Contact> emailCons = [
                SELECT AccountId, Language__c
                FROM Contact WHERE Email = :usr.Email AND AccountId != null
                WITH SYSTEM_MODE LIMIT 1
            ];
            if (!emailCons.isEmpty()) {
                return buildContextFromContact(emailCons[0], usr.DefaultLanguage__c);
            }
        }

        return fallbackContext(normalizeLang(usr.DefaultLanguage__c));
    }

    private static DealerContext buildContextFromContact(Contact con, String defaultLang) {
        List<Account> accounts = [
            SELECT Id, Name, BillingCountryCode, Dealer_category__c, Sales_Language__c, Reseller_Name__c
            FROM Account WHERE Id = :con.AccountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (accounts.isEmpty()) return fallbackContext(normalizeLang(defaultLang));

        DealerContext ctx = new DealerContext();
        ctx.account   = accounts[0];
        ctx.contactId = con.Id;
        String lang = resolveLanguage(con.Language__c);
        if (lang == null) lang = normalizeLang(accounts[0].Sales_Language__c);
        if (lang == null) lang = normalizeLang(defaultLang);
        ctx.language = lang != null ? lang : 'en';
        return ctx;
    }

    // Returns a context with a stub Account (no Id) — used for preview/admin and unlinked users.
    // Pricebook resolution falls back to any Dealer pricebook; no discounts applied.
    private static DealerContext fallbackContext(String language) {
        DealerContext ctx = new DealerContext();
        ctx.language = language != null ? language : 'en';
        Account stub = new Account();
        stub.BillingCountryCode = 'NL';
        ctx.account = stub;
        return ctx;
    }

    // ── Price tier helpers ────────────────────────────────────────────────────

    private static List<PriceTierDTO> buildPriceTiersFromEntry(PricebookEntry entry) {
        List<PriceTierDTO> tiers = new List<PriceTierDTO>();
        tiers.add(makeTier(entry.From_Quantity_1__c, entry.From_Price_1__c, null));
        tiers.add(makeTier(entry.From_Quantity_2__c, entry.From_Price_2__c, null));
        tiers.add(makeTier(entry.From_Quantity_3__c, entry.From_Price_3__c, null));
        tiers.add(makeTier(entry.From_Quantity_4__c, entry.From_Price_4__c, null));
        List<PriceTierDTO> result = new List<PriceTierDTO>();
        for (PriceTierDTO t : tiers) {
            if (t != null) result.add(t);
        }
        return result;
    }

    private static List<PriceTierDTO> applyDiscountToTiers(
        PricebookEntry entry,
        Product_Discount__c disc
    ) {
        List<PriceTierDTO> tiers = new List<PriceTierDTO>();
        if (disc.isFixedPrice__c == true) {
            tiers.add(makeTier(disc.From_Quantity_1__c, disc.FixedPrice_1__c, null));
            tiers.add(makeTier(disc.From_Quantity_2__c, disc.FixedPrice_2__c, null));
            tiers.add(makeTier(disc.From_Quantity_3__c, disc.FixedPrice_3__c, null));
            tiers.add(makeTier(disc.From_Quantity_4__c, disc.FixedPrice_4__c, null));
        } else {
            // Tier-level discounts override entry tiers when From_Discount fields are populated
            Boolean hasTierDiscount = disc.From_Discount_1__c != null
                || disc.From_Discount_2__c != null
                || disc.From_Discount_3__c != null
                || disc.From_Discount_4__c != null;

            if (hasTierDiscount) {
                // A tiered price agreement takes over from the pricebook entry's own tier structure
                // entirely, discounting off the entry's single UnitPrice - not entry.From_Price_X,
                // which this org never actually populates. Only pass a price when this specific tier
                // slot is actually defined (From_Discount_X set) - makeTier() skips a tier when both
                // quantity and price come back null, so an undefined slot must not get a non-null
                // price just because entry.UnitPrice itself is always non-null.
                tiers.add(makeTier(
                    disc.From_Quantity_1__c != null ? disc.From_Quantity_1__c : entry.From_Quantity_1__c,
                    disc.From_Discount_1__c != null ? entry.UnitPrice : null, disc.From_Discount_1__c
                ));
                tiers.add(makeTier(
                    disc.From_Quantity_2__c != null ? disc.From_Quantity_2__c : entry.From_Quantity_2__c,
                    disc.From_Discount_2__c != null ? entry.UnitPrice : null, disc.From_Discount_2__c
                ));
                tiers.add(makeTier(
                    disc.From_Quantity_3__c != null ? disc.From_Quantity_3__c : entry.From_Quantity_3__c,
                    disc.From_Discount_3__c != null ? entry.UnitPrice : null, disc.From_Discount_3__c
                ));
                tiers.add(makeTier(
                    disc.From_Quantity_4__c != null ? disc.From_Quantity_4__c : entry.From_Quantity_4__c,
                    disc.From_Discount_4__c != null ? entry.UnitPrice : null, disc.From_Discount_4__c
                ));
            } else {
                // Flat discount_percentage__c applied off the entry's UnitPrice, but only at
                // quantity breakpoints the entry itself actually defines - this discount has no
                // tier structure of its own to fall back on.
                tiers.add(makeTier(entry.From_Quantity_1__c, entry.From_Quantity_1__c != null ? entry.UnitPrice : null, disc.Discount_percentage__c));
                tiers.add(makeTier(entry.From_Quantity_2__c, entry.From_Quantity_2__c != null ? entry.UnitPrice : null, disc.Discount_percentage__c));
                tiers.add(makeTier(entry.From_Quantity_3__c, entry.From_Quantity_3__c != null ? entry.UnitPrice : null, disc.Discount_percentage__c));
                tiers.add(makeTier(entry.From_Quantity_4__c, entry.From_Quantity_4__c != null ? entry.UnitPrice : null, disc.Discount_percentage__c));
            }
        }
        List<PriceTierDTO> result = new List<PriceTierDTO>();
        for (PriceTierDTO t : tiers) {
            if (t != null) result.add(t);
        }
        return result;
    }

    private static PriceTierDTO makeTier(Decimal fromQty, Decimal price, Decimal discountPct) {
        if (fromQty == null && price == null) return null;
        PriceTierDTO t  = new PriceTierDTO();
        t.fromQty       = fromQty != null ? fromQty.intValue() : null;
        if (discountPct != null && price != null) {
            t.price = price * (1 - discountPct / 100);
        } else {
            t.price = price;
        }
        return t;
    }

    // ── Image URL from ContentDocumentLink ───────────────────────────────────

    public static Map<Id, String> getProductImageUrls(Set<Id> productIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (productIds.isEmpty()) return result;

        // A product can end up with more than one linked file (e.g. an old image kept alongside a
        // newly uploaded one) - without an explicit order, "first row returned" is whatever the
        // query planner picks, which is not reliably the newest. Ordering by CreatedDate DESC and
        // keeping only the first-seen link per product guarantees the most recent upload wins.
        Map<Id, Id> cdocByProduct = new Map<Id, Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productIds
            WITH SYSTEM_MODE
            ORDER BY ContentDocument.CreatedDate DESC, Id DESC
        ]) {
            if (!cdocByProduct.containsKey(cdl.LinkedEntityId)) {
                cdocByProduct.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
            }
        }
        if (cdocByProduct.isEmpty()) return result;

        Map<Id, Id> cvByDoc = new Map<Id, Id>();
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :cdocByProduct.values()
              AND IsLatest = true
            WITH SYSTEM_MODE
        ]) {
            cvByDoc.put(cv.ContentDocumentId, cv.Id);
        }

        // A raw "/sfc/servlet.shepherd/version/download/{id}" path (with or without a site prefix)
        // does not reliably serve the file to portal/guest users on a My Domain/LWR site - it returns
        // errorduringprocessing.jsp instead, even with the correct site prefix and even for otherwise-
        // visible files. ContentDistribution.ContentDownloadUrl is the platform-supported way to expose
        // a file for external/community viewing; distributions must already exist (created ahead of
        // time, e.g. when the file is linked to the product) since this method must stay read-only to
        // remain @AuraEnabled(cacheable=true)-compatible for callers that use @wire.
        Map<Id, String> urlByContentVersion = new Map<Id, String>();
        for (ContentDistribution cd : [
            SELECT ContentVersionId, ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId IN :cvByDoc.values()
            WITH SYSTEM_MODE
        ]) {
            urlByContentVersion.put(cd.ContentVersionId, cd.ContentDownloadUrl);
        }

        for (Id productId : cdocByProduct.keySet()) {
            Id cvId = cvByDoc.get(cdocByProduct.get(productId));
            String url = cvId != null ? urlByContentVersion.get(cvId) : null;
            if (url != null) {
                result.put(productId, url);
            }
        }
        return result;
    }

    // ── ProductDTO builder ────────────────────────────────────────────────────

    private static ProductDTO buildProductDTO(
        Product2 prod,
        PricebookEntry entry,
        Product_Discount__c disc
    ) {
        Data_Translation__c trans = (prod.Data_Translations__r != null && !prod.Data_Translations__r.isEmpty())
            ? prod.Data_Translations__r[0]
            : null;

        ProductDTO dto           = new ProductDTO();
        dto.id                   = prod.Id;
        dto.name                 = prod.Name;
        dto.displayName      = trans != null && String.isNotBlank(trans.Name__c)
                                 ? trans.Name__c
                                 : prod.Name;
        dto.shortDescription = trans != null && String.isNotBlank(trans.shortDescription__c)
                                 ? trans.shortDescription__c
                                 : prod.shortDescription__c;
        dto.longDescription  = trans != null && String.isNotBlank(trans.longDescription__c)
                                 ? trans.longDescription__c
                                 : prod.longDescription__c;
        dto.category             = prod.Category_Platform__c;
        dto.productCode          = (disc != null && disc.IsActive__c == true && String.isNotBlank(disc.Product_Code_Customer__c))
                                     ? disc.Product_Code_Customer__c
                                     : prod.ProductCode;

        if (entry != null) {
            dto.unitPrice = entry.UnitPrice;

            if (disc != null && disc.IsActive__c == true) {
                if (disc.isFixedPrice__c == true && disc.FixedPrice_1__c != null) {
                    dto.unitPrice = disc.FixedPrice_1__c;
                } else if (disc.Discount_percentage__c != null) {
                    dto.unitPrice = entry.UnitPrice * (1 - disc.Discount_percentage__c / 100);
                }
                dto.priceTiers = applyDiscountToTiers(entry, disc);

                // A tier starting at quantity 1 already applies to a single unit, so it IS the
                // unit price - show it there instead of as a redundant first "volume" row above
                // the remaining, genuinely higher-quantity tiers.
                if (!dto.priceTiers.isEmpty() && dto.priceTiers[0].fromQty == 1) {
                    dto.unitPrice = dto.priceTiers[0].price;
                    dto.priceTiers.remove(0);
                }
            } else {
                dto.priceTiers = buildPriceTiersFromEntry(entry);
            }
        }
        if (dto.priceTiers == null) dto.priceTiers = new List<PriceTierDTO>();
        return dto;
    }

    // ── Favorites ─────────────────────────────────────────────────────────────

    private static Set<Id> getFavoriteProductIds(Id contactId, Set<Id> productIds) {
        Set<Id> favoriteIds = new Set<Id>();
        if (contactId == null || productIds.isEmpty()) return favoriteIds;
        for (Dealer_Product_Favorite__c f : [
            SELECT Product__c
            FROM Dealer_Product_Favorite__c
            WHERE Contact__c = :contactId AND Product__c IN :productIds
            WITH SYSTEM_MODE
        ]) {
            favoriteIds.add(f.Product__c);
        }
        return favoriteIds;
    }

    // Toggles the current dealer contact's favorite flag for a product and returns the new state.
    @AuraEnabled
    public static Boolean toggleFavorite(Id productId) {
        if (productId == null) throw new AuraHandledException('productId is required.');

        Id contactId = getDealerContext().contactId;
        if (contactId == null) {
            throw new AuraHandledException('You must be logged in as a dealer contact to save favorites.');
        }

        List<Dealer_Product_Favorite__c> existing = [
            SELECT Id
            FROM Dealer_Product_Favorite__c
            WHERE Contact__c = :contactId AND Product__c = :productId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Database.delete(existing[0], AccessLevel.SYSTEM_MODE);
            return false;
        }

        Database.insert(
            new Dealer_Product_Favorite__c(Contact__c = contactId, Product__c = productId),
            AccessLevel.SYSTEM_MODE
        );
        return true;
    }

    // Tabs for the current dealer's reseller: one per platform value in the Administration's
    // Available_System_Platforms__c, labeled from the shared "System" global value set - in that
    // value set's defined order, not the reseller field's (unordered Set) iteration order.
    @AuraEnabled(cacheable=true)
    public static List<PlatformTabDTO> getPlatformTabs() {
        Set<String> platforms = getAvailablePlatforms(getDealerContext().account);
        List<PlatformTabDTO> tabs = new List<PlatformTabDTO>();
        if (platforms.isEmpty()) return tabs;

        for (Schema.PicklistEntry entry : Schema.SObjectType.Product2.fields.System_Platform__c.getPicklistValues()) {
            if (platforms.contains(entry.getValue())) {
                PlatformTabDTO dto = new PlatformTabDTO();
                dto.value = entry.getValue();
                dto.label = entry.getLabel();
                tabs.add(dto);
            }
        }
        return tabs;
    }

    // ── Public methods ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static ProductPageResult getProducts(String category, Integer pageNum, Integer pageSize, String searchTerm) {
        Integer safePageNum  = (pageNum  != null && pageNum  > 0) ? pageNum  : 1;
        Integer safePageSize = (pageSize != null && pageSize > 0) ? pageSize : 20;
        Integer offsetVal    = (safePageNum - 1) * safePageSize;

        DealerContext ctx  = getDealerContext();
        Account acct      = ctx.account;
        String lang       = ctx.language;
        Id contactId      = ctx.contactId;
        Id pricebookId    = resolvePricebookId(acct);

        Boolean isFavoritesTab = 'favorites'.equals(category);
        if (isFavoritesTab && contactId == null) {
            ProductPageResult empty = new ProductPageResult();
            empty.products    = new List<ProductDTO>();
            empty.total       = 0;
            empty.pricebookId = pricebookId;
            return empty;
        }

        // Pricebook entries drive visibility: only products with an active pricebook entry appear.
        Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
        Boolean filterByEntry = pricebookId != null;
        if (filterByEntry) {
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, UnitPrice, From_Quantity_1__c, From_Price_1__c,
                       From_Quantity_2__c, From_Price_2__c, From_Quantity_3__c, From_Price_3__c,
                       From_Quantity_4__c, From_Price_4__c
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebookId
                  AND IsActive = true
                  AND IsActive_r__c = true
                WITH SYSTEM_MODE
            ]) {
                entryByProduct.put(pbe.Product2Id, pbe);
            }
        }
        Set<Id> pricedIds = entryByProduct.keySet();

        if (filterByEntry && pricedIds.isEmpty()) {
            ProductPageResult empty = new ProductPageResult();
            empty.products    = new List<ProductDTO>();
            empty.total       = 0;
            empty.pricebookId = pricebookId;
            return empty;
        }

        Id baseRtId = baseTranslationRtId;

        List<String> conditions = new List<String>{ 'IsActive = true', 'Show_In_Dealer_Shop__c = true' };
        if (isFavoritesTab) {
            conditions.add('Id IN (SELECT Product__c FROM Dealer_Product_Favorite__c WHERE Contact__c = :contactId)');
        } else if (String.isNotBlank(category)) {
            // A specific platform tab - direct match only, no fail-open: unlike the "All Products"
            // tab, selecting platform X is an explicit request for products confirmed to be on X.
            conditions.add('System_Platform__c INCLUDES (:category)');
        } else {
            // "All Products" tab only - a product/reseller with no platform data set never gets
            // excluded (fail-open), since most Product2 records don't have System_Platform__c
            // populated yet; only an actual mismatch between two populated values excludes it.
            Set<String> availablePlatforms = getAvailablePlatforms(acct);
            if (!availablePlatforms.isEmpty()) {
                // INCLUDES('a;b') means "has BOTH a AND b", not "has either" - a single product
                // only ever carries one platform value, so that would always match zero rows.
                // "Any of" requires one INCLUDES() per value, OR'd together.
                List<String> platformClauses = new List<String>();
                for (String p : availablePlatforms) {
                    platformClauses.add('System_Platform__c INCLUDES (\'' + String.escapeSingleQuotes(p) + '\')');
                }
                conditions.add('(System_Platform__c = null OR ' + String.join(platformClauses, ' OR ') + ')');
            }
        }
        if (filterByEntry)                conditions.add('Id IN :pricedIds');

        String searchLike = String.isNotBlank(searchTerm)
            ? ('%' + String.escapeSingleQuotes(searchTerm.trim()) + '%')
            : null;
        if (searchLike != null) {
            List<String> searchClauses = new List<String>{
                'Name LIKE :searchLike',
                'ProductCode LIKE :searchLike',
                'Id IN (SELECT Product__c FROM Data_Translation__c WHERE Name__c LIKE :searchLike AND RecordTypeId = :baseRtId AND Language__c = :lang)'
            };
            if (acct.Id != null) {
                searchClauses.add('Id IN (SELECT Product__c FROM Product_Discount__c WHERE Product_Code_Customer__c LIKE :searchLike AND Account__c = :acct.Id AND IsActive__c = true)');
            }
            conditions.add('(' + String.join(searchClauses, ' OR ') + ')');
        }

        String whereClause = String.join(conditions, ' AND ');

        Integer total = Database.countQuery('SELECT COUNT() FROM Product2 WHERE ' + whereClause + ' WITH SYSTEM_MODE');

        String soql =
            'SELECT Id, Name, ProductCode, shortDescription__c, longDescription__c, Category_Platform__c, ' +
            '(SELECT Id, Name__c, shortDescription__c, longDescription__c FROM Data_Translations__r ' +
            ' WHERE RecordTypeId = :baseRtId AND Language__c = :lang LIMIT 1) ' +
            'FROM Product2 WHERE ' + whereClause + ' ' +
            'WITH SYSTEM_MODE ORDER BY Name LIMIT :safePageSize OFFSET :offsetVal';
        List<Product2> products = Database.query(soql);

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) productIds.add(p.Id);

        // Account-level discounts
        Map<Id, Product_Discount__c> discountByProduct = new Map<Id, Product_Discount__c>();
        if (acct.Id != null && !productIds.isEmpty()) {
            for (Product_Discount__c disc : [
                SELECT Product__c, IsActive__c, Discount_percentage__c, Product_Code_Customer__c,
                       isFixedPrice__c, FixedPrice_1__c, FixedPrice_2__c, FixedPrice_3__c, FixedPrice_4__c,
                       From_Quantity_1__c, From_Quantity_2__c, From_Quantity_3__c, From_Quantity_4__c,
                       From_Discount_1__c, From_Discount_2__c, From_Discount_3__c, From_Discount_4__c
                FROM Product_Discount__c
                WHERE Account__c = :acct.Id
                  AND Product__c IN :productIds
                  AND IsActive__c = true
                WITH SYSTEM_MODE
            ]) {
                discountByProduct.put(disc.Product__c, disc);
            }
        }

        Map<Id, String> imageUrls = getProductImageUrls(productIds);
        Set<Id> favoriteIds = getFavoriteProductIds(contactId, productIds);

        List<ProductDTO> dtos = new List<ProductDTO>();
        for (Product2 p : products) {
            ProductDTO dto = buildProductDTO(p, entryByProduct.get(p.Id), discountByProduct.get(p.Id));
            dto.imageUrl   = imageUrls.get(p.Id);
            dto.isFavorite = favoriteIds.contains(p.Id);
            dtos.add(dto);
        }

        ProductPageResult result = new ProductPageResult();
        result.products    = dtos;
        result.total       = total;
        result.pricebookId = pricebookId;
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static ProductDTO getProductDetail(Id productId) {
        if (productId == null) throw new AuraHandledException('productId is required.');

        DealerContext ctx = getDealerContext();
        String lang    = ctx.language;
        Id baseRtId    = baseTranslationRtId;
        List<Product2> prods = [
            SELECT Id, Name, ProductCode, shortDescription__c, longDescription__c, Category_Platform__c,
                   (SELECT Id, Name__c, shortDescription__c, longDescription__c FROM Data_Translations__r
                    WHERE RecordTypeId = :baseRtId AND Language__c = :lang LIMIT 1)
            FROM Product2
            WHERE Id = :productId
              AND IsActive = true
              AND Show_In_Dealer_Shop__c = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (prods.isEmpty()) throw new AuraHandledException('Product not found.');
        Product2 prod = prods[0];

        Account acct   = ctx.account;
        Id pricebookId = resolvePricebookId(acct);

        PricebookEntry entry = null;
        if (pricebookId != null) {
            List<PricebookEntry> entries = [
                SELECT Id, Product2Id, UnitPrice, From_Quantity_1__c, From_Price_1__c,
                       From_Quantity_2__c, From_Price_2__c, From_Quantity_3__c, From_Price_3__c,
                       From_Quantity_4__c, From_Price_4__c
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebookId
                  AND Product2Id = :productId
                  AND IsActive = true
                  AND IsActive_r__c = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!entries.isEmpty()) entry = entries[0];
        }

        List<Product_Discount__c> discs = [
            SELECT Product__c, IsActive__c, Discount_percentage__c, Product_Code_Customer__c,
                   isFixedPrice__c, FixedPrice_1__c, FixedPrice_2__c, FixedPrice_3__c, FixedPrice_4__c,
                   From_Quantity_1__c, From_Quantity_2__c, From_Quantity_3__c, From_Quantity_4__c,
                   From_Discount_1__c, From_Discount_2__c, From_Discount_3__c, From_Discount_4__c
            FROM Product_Discount__c
            WHERE Account__c = :acct.Id
              AND Product__c = :productId
              AND IsActive__c = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Product_Discount__c disc = discs.isEmpty() ? null : discs[0];

        ProductDTO dto = buildProductDTO(prod, entry, disc);
        Map<Id, String> imageUrls = getProductImageUrls(new Set<Id>{ productId });
        dto.imageUrl   = imageUrls.get(productId);
        dto.isFavorite = getFavoriteProductIds(ctx.contactId, new Set<Id>{ productId }).contains(productId);
        return dto;
    }

    @AuraEnabled
    public static String placeOrder(String cartJson) {
        if (String.isBlank(cartJson)) throw new AuraHandledException('cartJson is required.');

        List<CartItemInput> items;
        try {
            items = (List<CartItemInput>) JSON.deserialize(cartJson, List<CartItemInput>.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid cart data: ' + e.getMessage());
        }
        if (items == null || items.isEmpty()) throw new AuraHandledException('Cart is empty.');

        Account acct   = getDealerContext().account;
        Id pricebookId = resolvePricebookId(acct);
        if (pricebookId == null) throw new AuraHandledException('No dealer pricebook found for your account.');

        // Collect product ids for pricebook entry lookup
        Set<Id> productIds = new Set<Id>();
        for (CartItemInput item : items) {
            if (item.productId != null) productIds.add(item.productId);
        }

        Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
              AND Product2Id IN :productIds
              AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            entryByProduct.put(pbe.Product2Id, pbe);
        }

        List<RecordType> webshopRts = [
            SELECT Id, Name
            FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Webshop'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        RecordType webshopRt = webshopRts.isEmpty() ? null : webshopRts[0];

        // Opportunity/OpportunityLineItem access can't be granted to the Customer Community Plus
        // license at all (not a permission-set gap - the license itself doesn't allow it), so
        // these run as system - same pattern as the Order/OrderItem approach this replaces.
        //
        // Name can't be set to its final "<RecordType>#<Opportunity Number>" form yet - Auto_Number__c
        // is only populated by Salesforce after the insert completes, not on the in-memory record -
        // so insert with a placeholder and fix it up below.
        Opportunity opp = new Opportunity(
            AccountId    = acct.Id,
            Name         = 'Dealer shop order',
            Type         = 'Webshop',
            LeadSource   = 'Webshop',
            StageName    = 'Webshop',
            CloseDate    = Date.today().addDays(30),
            RecordTypeId = webshopRt?.Id
        );
        Database.insert(opp, AccessLevel.SYSTEM_MODE);

        opp = [
            SELECT Id, Auto_Number__c
            FROM Opportunity
            WHERE Id = :opp.Id
            WITH SYSTEM_MODE
        ];

        // The org-wide "rbc - Opportunity" before-save flow re-resolves Pricebook2Id for every
        // new Opportunity from the account's sales relation type, overriding whatever we set on
        // insert. Dealer-shop pricing must use the dealer pricebook resolved above, so force it
        // back with a follow-up update (that flow only fires on Create, so this update sticks).
        opp.Name         = (webshopRt != null ? webshopRt.Name : 'Webshop') + ' #' + opp.Auto_Number__c;
        opp.Pricebook2Id = pricebookId;
        Database.update(opp, AccessLevel.SYSTEM_MODE);

        List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
        for (CartItemInput item : items) {
            if (item.productId == null || item.quantity == null || item.quantity <= 0) continue;
            PricebookEntry pbe = entryByProduct.get(item.productId);
            if (pbe == null) continue;

            Decimal unitPrice = item.unitPrice != null ? item.unitPrice : pbe.UnitPrice;
            lineItems.add(new OpportunityLineItem(
                OpportunityId    = opp.Id,
                Product2Id       = item.productId,
                PricebookEntryId = pbe.Id,
                Quantity         = item.quantity,
                UnitPrice        = unitPrice
            ));
        }

        if (lineItems.isEmpty()) {
            Database.delete(opp, AccessLevel.SYSTEM_MODE);
            throw new AuraHandledException('No valid order items could be created from cart.');
        }

        Database.insert(lineItems, AccessLevel.SYSTEM_MODE);
        return opp.Name;
    }

    // ── Order history ─────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<OrderHistoryDTO> getOrderHistory(Boolean onlyMine) {
        Account acct = getDealerContext().account;
        if (acct.Id == null) return new List<OrderHistoryDTO>();

        List<Opportunity> opps = onlyMine
            ? [
                SELECT Id, Name, CreatedDate, StageName, Amount, CreatedBy.Name
                FROM Opportunity
                WHERE AccountId = :acct.Id
                  AND RecordType.DeveloperName = 'Webshop'
                  AND CreatedById = :UserInfo.getUserId()
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ]
            : [
                SELECT Id, Name, CreatedDate, StageName, Amount, CreatedBy.Name
                FROM Opportunity
                WHERE AccountId = :acct.Id
                  AND RecordType.DeveloperName = 'Webshop'
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ];

        List<OrderHistoryDTO> results = new List<OrderHistoryDTO>();
        for (Opportunity o : opps) {
            OrderHistoryDTO dto = new OrderHistoryDTO();
            dto.id           = o.Id;
            dto.orderNumber  = o.Name;
            dto.placedDate   = o.CreatedDate;
            dto.stageName    = o.StageName;
            dto.amount       = o.Amount;
            dto.placedByName = o.CreatedBy != null ? o.CreatedBy.Name : null;
            results.add(dto);
        }
        return results;
    }

    // ── Order detail ──────────────────────────────────────────────────────────

    // Returns an order's line items priced at TODAY's live pricing/discounts (not the historical
    // price paid at the time), so "reorder"/"add to cart" always uses current prices.
    @AuraEnabled(cacheable=true)
    public static OrderDetailDTO getOrderDetail(Id opportunityId) {
        if (opportunityId == null) throw new AuraHandledException('opportunityId is required.');

        DealerContext ctx = getDealerContext();
        Account acct = ctx.account;
        if (acct.Id == null) throw new AuraHandledException('No dealer account context.');

        List<Opportunity> opps = [
            SELECT Id, Name, CreatedDate, StageName
            FROM Opportunity
            WHERE Id = :opportunityId
              AND AccountId = :acct.Id
              AND RecordType.DeveloperName = 'Webshop'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (opps.isEmpty()) throw new AuraHandledException('Order not found.');
        Opportunity opp = opps[0];

        List<OpportunityLineItem> lineItems = [
            SELECT Product2Id, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            WITH SYSTEM_MODE
        ];

        Set<Id> productIds = new Set<Id>();
        for (OpportunityLineItem li : lineItems) productIds.add(li.Product2Id);

        String lang = ctx.language;
        Id baseRtId = baseTranslationRtId;
        Map<Id, Product2> prodById = productIds.isEmpty()
            ? new Map<Id, Product2>()
            : new Map<Id, Product2>([
                SELECT Id, Name, ProductCode, shortDescription__c, longDescription__c, Category_Platform__c,
                       (SELECT Id, Name__c, shortDescription__c, longDescription__c FROM Data_Translations__r
                        WHERE RecordTypeId = :baseRtId AND Language__c = :lang LIMIT 1)
                FROM Product2
                WHERE Id IN :productIds
                WITH SYSTEM_MODE
            ]);

        Id pricebookId = resolvePricebookId(acct);
        Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
        if (pricebookId != null && !productIds.isEmpty()) {
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, UnitPrice, From_Quantity_1__c, From_Price_1__c,
                       From_Quantity_2__c, From_Price_2__c, From_Quantity_3__c, From_Price_3__c,
                       From_Quantity_4__c, From_Price_4__c
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebookId
                  AND Product2Id IN :productIds
                  AND IsActive = true
                  AND IsActive_r__c = true
                WITH SYSTEM_MODE
            ]) {
                entryByProduct.put(pbe.Product2Id, pbe);
            }
        }

        Map<Id, Product_Discount__c> discByProduct = new Map<Id, Product_Discount__c>();
        if (!productIds.isEmpty()) {
            for (Product_Discount__c d : [
                SELECT Product__c, IsActive__c, Discount_percentage__c, Product_Code_Customer__c,
                       isFixedPrice__c, FixedPrice_1__c, FixedPrice_2__c, FixedPrice_3__c, FixedPrice_4__c,
                       From_Quantity_1__c, From_Quantity_2__c, From_Quantity_3__c, From_Quantity_4__c,
                       From_Discount_1__c, From_Discount_2__c, From_Discount_3__c, From_Discount_4__c
                FROM Product_Discount__c
                WHERE Account__c = :acct.Id
                  AND Product__c IN :productIds
                  AND IsActive__c = true
                WITH SYSTEM_MODE
            ]) {
                discByProduct.put(d.Product__c, d);
            }
        }

        Map<Id, String> imageUrls = getProductImageUrls(productIds);

        OrderDetailDTO result = new OrderDetailDTO();
        result.orderId     = opp.Id;
        result.orderNumber = opp.Name;
        result.placedDate  = opp.CreatedDate;
        result.stageName   = opp.StageName;
        result.lines       = new List<OrderLineDTO>();

        for (OpportunityLineItem li : lineItems) {
            Product2 prod = prodById.get(li.Product2Id);
            if (prod == null) continue;

            ProductDTO current = buildProductDTO(prod, entryByProduct.get(li.Product2Id), discByProduct.get(li.Product2Id));
            current.imageUrl = imageUrls.get(li.Product2Id);

            OrderLineDTO line = new OrderLineDTO();
            line.productId         = li.Product2Id;
            line.quantity          = Integer.valueOf(li.Quantity);
            line.originalUnitPrice = li.UnitPrice;
            line.product           = current;
            result.lines.add(line);
        }
        return result;
    }

    // ── Inner classes ─────────────────────────────────────────────────────────

    public class ProductPageResult {
        @AuraEnabled public List<ProductDTO> products;
        @AuraEnabled public Integer          total;
        @AuraEnabled public Id               pricebookId;
    }

    public class ProductDTO {
        @AuraEnabled public Id              id;
        @AuraEnabled public String          name;
        @AuraEnabled public String          displayName;
        @AuraEnabled public String          shortDescription;
        @AuraEnabled public String          longDescription;
        @AuraEnabled public String          category;
        @AuraEnabled public String          productCode;
        @AuraEnabled public String          imageUrl;
        @AuraEnabled public Decimal         unitPrice;
        @AuraEnabled public List<PriceTierDTO> priceTiers;
        @AuraEnabled public Boolean         isFavorite;
    }

    public class PlatformTabDTO {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class DealerContext {
        public Account account;
        public String  language;
        public Id      contactId;
    }

    // ── Reseller/platform resolution ──────────────────────────────────────────

    // Account.Reseller_Name__c and Administration.Reseller__c are both plain picklist codes
    // ("1".."6") that happen to overlap digit-wise with the unrelated System__c global value
    // set - they are NOT platform codes themselves, just the join key to find the Administration
    // record that actually carries the platform requirement.
    private static Set<String> getAvailablePlatforms(Account acct) {
        Set<String> platforms = new Set<String>();
        if (acct == null || String.isBlank(acct.Reseller_Name__c)) return platforms;
        for (Subscription25__Administration__c admin : [
            SELECT Available_System_Platforms__c
            FROM Subscription25__Administration__c
            WHERE Reseller__c = :acct.Reseller_Name__c
              AND Available_System_Platforms__c != null
            WITH SYSTEM_MODE
        ]) {
            platforms.addAll(admin.Available_System_Platforms__c.split(';'));
        }
        return platforms;
    }

    public class OrderHistoryDTO {
        @AuraEnabled public Id       id;
        @AuraEnabled public String   orderNumber;
        @AuraEnabled public Datetime placedDate;
        @AuraEnabled public String   stageName;
        @AuraEnabled public Decimal  amount;
        @AuraEnabled public String   placedByName;
    }

    public class OrderDetailDTO {
        @AuraEnabled public Id                orderId;
        @AuraEnabled public String            orderNumber;
        @AuraEnabled public Datetime          placedDate;
        @AuraEnabled public String            stageName;
        @AuraEnabled public List<OrderLineDTO> lines;
    }

    public class OrderLineDTO {
        @AuraEnabled public Id         productId;
        @AuraEnabled public Integer    quantity;
        @AuraEnabled public Decimal    originalUnitPrice;
        @AuraEnabled public ProductDTO product;
    }

    public class PriceTierDTO {
        @AuraEnabled public Integer fromQty;
        @AuraEnabled public Decimal price;
    }

    public class CartItemInput {
        @AuraEnabled public Id      productId;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal unitPrice;
    }
}
