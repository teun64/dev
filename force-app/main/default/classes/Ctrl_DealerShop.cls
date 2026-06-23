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
            ORDER BY Name DESC
            LIMIT 1
        ];
        if (!books.isEmpty()) return books[0].Id;

        List<Pricebook2> fallback = [
            SELECT Id
            FROM Pricebook2
            WHERE Name LIKE '%Dealer%'
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
            SELECT ContactId, DefaultLanguage__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null) {
            return fallbackContext(normalizeLang(users.isEmpty() ? null : users[0].DefaultLanguage__c));
        }

        List<Contact> contacts = [
            SELECT AccountId, Language__c
            FROM Contact
            WHERE Id = :users[0].ContactId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            String lang = normalizeLang(users[0].DefaultLanguage__c);
            if (lang == null && !contacts.isEmpty()) lang = resolveLanguage(contacts[0].Language__c);
            return fallbackContext(lang);
        }

        List<Account> accounts = [
            SELECT Id, BillingCountryCode, Dealer_category__c, Sales_Language__c
            FROM Account
            WHERE Id = :contacts[0].AccountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            String lang = normalizeLang(users[0].DefaultLanguage__c);
            if (lang == null) lang = resolveLanguage(contacts[0].Language__c);
            return fallbackContext(lang);
        }

        DealerContext ctx = new DealerContext();
        ctx.account = accounts[0];

        // Priority: User.DefaultLanguage__c → Contact.Language__c → Account.Sales_Language__c → 'en'
        String lang = normalizeLang(users[0].DefaultLanguage__c);
        if (lang == null) lang = resolveLanguage(contacts[0].Language__c);
        if (lang == null) lang = normalizeLang(accounts[0].Sales_Language__c);
        ctx.language = lang != null ? lang : 'en';
        return ctx;
    }

    // Returns a context with a stub Account (no Id) — used for preview/admin and unlinked users.
    // Pricebook resolution will fall back to any Dealer pricebook; no discounts are applied.
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
                tiers.add(makeTier(
                    disc.From_Quantity_1__c != null ? disc.From_Quantity_1__c : entry.From_Quantity_1__c,
                    entry.From_Price_1__c, disc.From_Discount_1__c
                ));
                tiers.add(makeTier(
                    disc.From_Quantity_2__c != null ? disc.From_Quantity_2__c : entry.From_Quantity_2__c,
                    entry.From_Price_2__c, disc.From_Discount_2__c
                ));
                tiers.add(makeTier(
                    disc.From_Quantity_3__c != null ? disc.From_Quantity_3__c : entry.From_Quantity_3__c,
                    entry.From_Price_3__c, disc.From_Discount_3__c
                ));
                tiers.add(makeTier(
                    disc.From_Quantity_4__c != null ? disc.From_Quantity_4__c : entry.From_Quantity_4__c,
                    entry.From_Price_4__c, disc.From_Discount_4__c
                ));
            } else {
                // Flat discount_percentage__c applied to each entry tier price
                tiers.add(makeTier(entry.From_Quantity_1__c, entry.From_Price_1__c, disc.Discount_percentage__c));
                tiers.add(makeTier(entry.From_Quantity_2__c, entry.From_Price_2__c, disc.Discount_percentage__c));
                tiers.add(makeTier(entry.From_Quantity_3__c, entry.From_Price_3__c, disc.Discount_percentage__c));
                tiers.add(makeTier(entry.From_Quantity_4__c, entry.From_Price_4__c, disc.Discount_percentage__c));
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
        t.discountPct   = discountPct;
        if (discountPct != null && price != null) {
            t.price = price * (1 - discountPct / 100);
        } else {
            t.price = price;
        }
        return t;
    }

    // ── Image URL from ContentDocumentLink ───────────────────────────────────

    private static Map<Id, String> getProductImageUrls(Set<Id> productIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (productIds.isEmpty()) return result;

        Map<Id, Id> cdocByProduct = new Map<Id, Id>();
        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productIds
            WITH SYSTEM_MODE
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

        for (Id productId : cdocByProduct.keySet()) {
            Id cvId = cvByDoc.get(cdocByProduct.get(productId));
            if (cvId != null) {
                result.put(productId, '/sfc/servlet.shepherd/version/download/' + cvId);
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
        dto.shortDescription = trans != null && String.isNotBlank(trans.Short_Description__c)
                                 ? trans.Short_Description__c
                                 : prod.Description;
        dto.longDescription  = trans != null && String.isNotBlank(trans.Description__c)
                                 ? trans.Description__c
                                 : prod.longDescription__c;
        dto.category             = prod.Category_Platform__c;
        dto.productCode          = prod.ProductCode;
        dto.family               = prod.Family;

        if (entry != null) {
            dto.unitPrice = entry.UnitPrice;

            if (disc != null && disc.IsActive__c == true) {
                if (disc.isFixedPrice__c == true && disc.FixedPrice_1__c != null) {
                    dto.unitPrice = disc.FixedPrice_1__c;
                } else if (disc.Discount_percentage__c != null) {
                    dto.unitPrice = entry.UnitPrice * (1 - disc.Discount_percentage__c / 100);
                }
                dto.priceTiers = applyDiscountToTiers(entry, disc);
            } else {
                dto.priceTiers = buildPriceTiersFromEntry(entry);
            }
        }
        if (dto.priceTiers == null) dto.priceTiers = new List<PriceTierDTO>();
        return dto;
    }

    // ── Public methods ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static ProductPageResult getProducts(String category, Integer pageNum, Integer pageSize) {
        Integer safePageNum  = (pageNum  != null && pageNum  > 0) ? pageNum  : 1;
        Integer safePageSize = (pageSize != null && pageSize > 0) ? pageSize : 20;
        Integer offsetVal    = (safePageNum - 1) * safePageSize;

        DealerContext ctx  = getDealerContext();
        Account acct      = ctx.account;
        String lang       = ctx.language;
        Id pricebookId    = resolvePricebookId(acct);

        // Total count query
        Integer total;
        if (String.isNotBlank(category)) {
            total = [
                SELECT COUNT()
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                  AND Category_Platform__c = :category
                WITH SYSTEM_MODE
            ];
        } else {
            total = [
                SELECT COUNT()
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                WITH SYSTEM_MODE
            ];
        }

        // Page query
        Id baseRtId = baseTranslationRtId;
        List<Product2> products;
        if (String.isNotBlank(category)) {
            products = [
                SELECT Id, Name, ProductCode, Family, Description, longDescription__c, Category_Platform__c,
                       (SELECT Id, Name__c, Short_Description__c, Description__c FROM Data_Translations__r
                        WHERE RecordTypeId = :baseRtId AND Language__c = :lang LIMIT 1)
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                  AND Category_Platform__c = :category
                WITH SYSTEM_MODE
                ORDER BY Name
                LIMIT :safePageSize
                OFFSET :offsetVal
            ];
        } else {
            products = [
                SELECT Id, Name, ProductCode, Family, Description, longDescription__c, Category_Platform__c,
                       (SELECT Id, Name__c, Short_Description__c, Description__c FROM Data_Translations__r
                        WHERE RecordTypeId = :baseRtId AND Language__c = :lang LIMIT 1)
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                WITH SYSTEM_MODE
                ORDER BY Name
                LIMIT :safePageSize
                OFFSET :offsetVal
            ];
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) productIds.add(p.Id);

        // Pricebook entries
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
                WITH SYSTEM_MODE
            ]) {
                entryByProduct.put(pbe.Product2Id, pbe);
            }
        }

        // Account-level discounts
        Map<Id, Product_Discount__c> discountByProduct = new Map<Id, Product_Discount__c>();
        if (acct.Id != null && !productIds.isEmpty()) {
            for (Product_Discount__c disc : [
                SELECT Id, Product__c, IsActive__c, Discount_percentage__c,
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

        List<ProductDTO> dtos = new List<ProductDTO>();
        for (Product2 p : products) {
            ProductDTO dto = buildProductDTO(p, entryByProduct.get(p.Id), discountByProduct.get(p.Id));
            dto.imageUrl = imageUrls.get(p.Id);
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
            SELECT Id, Name, ProductCode, Family, Description, Category_Platform__c,
                   (SELECT Id, Name__c, Short_Description__c, Description__c FROM Data_Translations__r
                    WHERE RecordTypeId = :baseRtId AND Language__c = :lang LIMIT 1)
            FROM Product2
            WHERE Id = :productId
              AND IsActive = true
              AND Is_Public__c = true
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
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!entries.isEmpty()) entry = entries[0];
        }

        List<Product_Discount__c> discs = [
            SELECT Id, Product__c, IsActive__c, Discount_percentage__c,
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
        dto.imageUrl = imageUrls.get(productId);
        return dto;
    }

    @AuraEnabled
    public static Id placeOrder(String cartJson) {
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

        Order ord = new Order(
            AccountId      = acct.Id,
            EffectiveDate  = Date.today(),
            Status         = 'Draft',
            Pricebook2Id   = pricebookId
        );
        insert ord;

        List<OrderItem> orderItems = new List<OrderItem>();
        for (CartItemInput item : items) {
            if (item.productId == null || item.quantity == null || item.quantity <= 0) continue;
            PricebookEntry pbe = entryByProduct.get(item.productId);
            if (pbe == null) continue;

            Decimal unitPrice = item.unitPrice != null ? item.unitPrice : pbe.UnitPrice;
            orderItems.add(new OrderItem(
                OrderId          = ord.Id,
                Product2Id       = item.productId,
                PricebookEntryId = pbe.Id,
                Quantity         = item.quantity,
                UnitPrice        = unitPrice,
                ListPrice        = pbe.UnitPrice
            ));
        }

        if (orderItems.isEmpty()) {
            delete ord;
            throw new AuraHandledException('No valid order items could be created from cart.');
        }

        insert orderItems;
        return ord.Id;
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
        @AuraEnabled public String          family;
        @AuraEnabled public String          imageUrl;
        @AuraEnabled public Decimal         unitPrice;
        @AuraEnabled public List<PriceTierDTO> priceTiers;
    }

    public class DealerContext {
        public Account account;
        public String  language;
    }

    public class PriceTierDTO {
        @AuraEnabled public Integer fromQty;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Decimal discountPct;
    }

    public class CartItemInput {
        @AuraEnabled public Id      productId;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Decimal unitPrice;
    }
}
