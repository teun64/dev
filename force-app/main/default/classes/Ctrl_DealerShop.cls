public without sharing class Ctrl_DealerShop {

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

    private static Account getDealerAccount() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null) {
            throw new AuraHandledException('No contact linked to current user.');
        }
        Id contactId = users[0].ContactId;

        List<Contact> contacts = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :contactId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (contacts.isEmpty() || contacts[0].AccountId == null) {
            throw new AuraHandledException('No account linked to current user contact.');
        }
        Id accountId = contacts[0].AccountId;

        List<Account> accounts = [
            SELECT Id, BillingCountryCode, Dealer_category__c
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw new AuraHandledException('Dealer account not found.');
        }
        return accounts[0];
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

    // ── ProductDTO builder ────────────────────────────────────────────────────

    private static ProductDTO buildProductDTO(
        Product2 prod,
        PricebookEntry entry,
        Product_Discount__c disc
    ) {
        ProductDTO dto      = new ProductDTO();
        dto.id              = prod.Id;
        dto.name            = prod.Name;
        dto.displayName     = String.isNotBlank(prod.Shop_Display_Name__c)
                                ? prod.Shop_Display_Name__c
                                : prod.Name;
        dto.shortDescription = prod.Shop_Short_Description__c;
        dto.description     = prod.Shop_Description__c;
        dto.category        = prod.Shop_Category__c;
        dto.productCode     = prod.ProductCode;
        dto.family          = prod.Family;
        dto.imageUrl        = prod.Shop_Image_URL__c;

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

        Account acct      = getDealerAccount();
        Id pricebookId    = resolvePricebookId(acct);

        // Total count query
        Integer total;
        if (String.isNotBlank(category)) {
            total = [
                SELECT COUNT()
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                  AND Shop_Category__c = :category
                WITH USER_MODE
            ];
        } else {
            total = [
                SELECT COUNT()
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                WITH USER_MODE
            ];
        }

        // Page query
        List<Product2> products;
        if (String.isNotBlank(category)) {
            products = [
                SELECT Id, Name, ProductCode, Family, Shop_Display_Name__c,
                       Shop_Short_Description__c, Shop_Description__c, Shop_Category__c,
                       Shop_Image_URL__c, webkul_wws__ContentDocumentId__c
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                  AND Shop_Category__c = :category
                WITH USER_MODE
                ORDER BY Shop_Display_Name__c NULLS LAST, Name
                LIMIT :safePageSize
                OFFSET :offsetVal
            ];
        } else {
            products = [
                SELECT Id, Name, ProductCode, Family, Shop_Display_Name__c,
                       Shop_Short_Description__c, Shop_Description__c, Shop_Category__c,
                       Shop_Image_URL__c, webkul_wws__ContentDocumentId__c
                FROM Product2
                WHERE IsActive = true
                  AND Is_Public__c = true
                WITH USER_MODE
                ORDER BY Shop_Display_Name__c NULLS LAST, Name
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
                WITH USER_MODE
            ]) {
                entryByProduct.put(pbe.Product2Id, pbe);
            }
        }

        // Account-level discounts
        Map<Id, Product_Discount__c> discountByProduct = new Map<Id, Product_Discount__c>();
        if (!productIds.isEmpty()) {
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

        List<ProductDTO> dtos = new List<ProductDTO>();
        for (Product2 p : products) {
            dtos.add(buildProductDTO(
                p,
                entryByProduct.get(p.Id),
                discountByProduct.get(p.Id)
            ));
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

        List<Product2> prods = [
            SELECT Id, Name, ProductCode, Family, Shop_Display_Name__c,
                   Shop_Short_Description__c, Shop_Description__c, Shop_Category__c,
                   Shop_Image_URL__c, webkul_wws__ContentDocumentId__c
            FROM Product2
            WHERE Id = :productId
              AND IsActive = true
              AND Is_Public__c = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (prods.isEmpty()) throw new AuraHandledException('Product not found.');
        Product2 prod = prods[0];

        Account acct   = getDealerAccount();
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
                WITH USER_MODE
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

        // Resolve image URL from ContentVersion when no direct URL is set
        if (String.isBlank(dto.imageUrl) && String.isNotBlank(prod.webkul_wws__ContentDocumentId__c)) {
            List<ContentVersion> versions = [
                SELECT Id, VersionDataUrl
                FROM ContentVersion
                WHERE ContentDocumentId = :prod.webkul_wws__ContentDocumentId__c
                  AND IsLatest = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!versions.isEmpty()) {
                dto.imageUrl = '/sfc/servlet.shepherd/version/download/' + versions[0].Id;
            }
        }

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

        Account acct   = getDealerAccount();
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
            WITH USER_MODE
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
        @AuraEnabled public String          description;
        @AuraEnabled public String          category;
        @AuraEnabled public String          productCode;
        @AuraEnabled public String          family;
        @AuraEnabled public String          imageUrl;
        @AuraEnabled public Decimal         unitPrice;
        @AuraEnabled public List<PriceTierDTO> priceTiers;
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
