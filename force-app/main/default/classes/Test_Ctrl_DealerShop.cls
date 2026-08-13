@IsTest(SeeAllData=false)
private class Test_Ctrl_DealerShop {

    // getDealerContext() only checks User.ContactId != null to resolve the dealer Account - any
    // portal-type license works. The org's single Customer Community Plus seat is already used by
    // the real dealer portal user, so this uses the (unused) Partner Community license instead -
    // a plain internal profile can't carry ContactId at all ("only portal users can be associated
    // to a contact").
    private static final String PORTAL_USER_USERNAME = 'apex.test.dealershop@mvsc.invalid.test';

    private static User portalUser() {
        return [SELECT Id FROM User WHERE Username = :PORTAL_USER_USERNAME LIMIT 1];
    }

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name                = 'Test Dealer',
            BillingCountryCode  = 'NL',
            Dealer_category__c  = 'D - 0 tot 12',
            RecordTypeId        = Schema.SObjectType.Account
                                    .getRecordTypeInfosByDeveloperName()
                                    .get('B2B')
                                    .getRecordTypeId()
        );
        acc.BillingStreet     = 'Teststraat 1';
        acc.BillingPostalCode = '1234AB';
        acc.BillingCity       = 'Amsterdam';
        acc.Reseller_Name__c  = '1';
        acc.Sales_Language__c = 'NL';
        insert acc;

        Contact con = new Contact(
            AccountId = acc.Id,
            FirstName = 'Apex',
            LastName  = 'Test Dealer User',
            Email     = 'apex.test.dealershop@mvsc.invalid.test'
        );
        insert con;

        Id portalProfileId = [SELECT Id FROM Profile WHERE Name = 'Partner Community User' LIMIT 1].Id;
        insert new User(
            ProfileId         = portalProfileId,
            ContactId         = con.Id,
            Username          = PORTAL_USER_USERNAME,
            Email             = 'apex.test.dealershop@mvsc.invalid.test',
            FirstName         = 'Apex',
            LastName          = 'Test Dealer User',
            Alias             = 'atduser',
            LocaleSidKey      = 'nl_NL',
            LanguageLocaleKey = 'nl_NL',
            TimeZoneSidKey    = 'Europe/Amsterdam',
            EmailEncodingKey  = 'UTF-8',
            IsActive          = true
        );

        Product2 publicProd = new Product2(
            Name                    = 'Public Product A',
            ProductCode             = 'PP-001',
            IsActive                = true,
            Show_In_Dealer_Shop__c  = true,
            Category_Platform__c    = 'Fleet',
            Description             = 'Short desc A'
        );

        Product2 publicProd2 = new Product2(
            Name                    = 'Public Product B',
            ProductCode             = 'PP-002',
            IsActive                = true,
            Show_In_Dealer_Shop__c  = true,
            Category_Platform__c    = 'Security',
            Description             = 'Short desc B'
        );

        Product2 privateProd = new Product2(
            Name                    = 'Private Product C',
            ProductCode             = 'PP-003',
            IsActive                = true,
            Show_In_Dealer_Shop__c  = false,
            Category_Platform__c    = 'Fleet'
        );

        insert new List<Product2>{ publicProd, publicProd2, privateProd };

        // A custom Pricebook2 entry can't exist without a Standard Price Book entry for the same
        // product first (STANDARD_PRICE_NOT_DEFINED).
        insert new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = publicProd.Id,  UnitPrice = 99.00, IsActive = true),
            new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = publicProd2.Id, UnitPrice = 49.00, IsActive = true),
            new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = privateProd.Id, UnitPrice = 29.00, IsActive = true)
        };

        // Matches Ctrl_DealerShop.resolvePricebookId()'s '%Dealer%'/'%NL%'/'%All%' Name lookup for
        // this account (BillingCountryCode NL, Dealer_category__c not Fleet/Security -> market 'All').
        Pricebook2 dealerPricebook = new Pricebook2(Name = 'Dealer NL All Pricebook', IsActive = false);
        insert dealerPricebook;
        dealerPricebook.IsActive = true;
        update dealerPricebook;

        PricebookEntry pbeA = new PricebookEntry(
            Pricebook2Id = dealerPricebook.Id,
            Product2Id   = publicProd.Id,
            UnitPrice    = 99.00,
            IsActive     = true
        );
        PricebookEntry pbeB = new PricebookEntry(
            Pricebook2Id = dealerPricebook.Id,
            Product2Id   = publicProd2.Id,
            UnitPrice    = 49.00,
            IsActive     = true
        );
        PricebookEntry pbeC = new PricebookEntry(
            Pricebook2Id = dealerPricebook.Id,
            Product2Id   = privateProd.Id,
            UnitPrice    = 29.00,
            IsActive     = true
        );
        insert new List<PricebookEntry>{ pbeA, pbeB, pbeC };

        Product_Discount__c discount = new Product_Discount__c(
            Account__c            = acc.Id,
            Product__c            = publicProd.Id,
            IsActive__c           = true,
            Discount_percentage__c = 10,
            isFixedPrice__c       = false,
            From_Quantity_1__c    = 1,
            From_Discount_1__c    = 10
        );
        insert discount;

        // rbb_Product_Discount (before-save, create-only) unconditionally forces IsActive__c=false
        // and Status__c='Preparation' on every new record - same "insert then separate update"
        // workaround as rbb_Account (see feedback_apex_test_fixture_gotchas memory). The update
        // doesn't re-trigger that create-only branch, so this sticks.
        discount.IsActive__c = true;
        update discount;
    }

    @IsTest
    static void testGetProducts_returnsOnlyPublic() {
        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts(null, 1, 10, null);
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.products, 'Products list should not be null');
        Integer publicCount = [SELECT COUNT() FROM Product2 WHERE Show_In_Dealer_Shop__c = true AND IsActive = true];
        System.assertEquals(publicCount, result.products.size(), 'Product count mismatch');
    }

    @IsTest
    static void testGetProducts_filterBySystemPlatform() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];
        prod.System_Platform__c = '2';
        update prod;

        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts('2', 1, 10, null);
        }
        Test.stopTest();

        System.assertEquals(1, result.products.size(), 'Only the product on platform 2 should be returned');
        System.assertEquals(prod.Id, result.products[0].id, 'Wrong product returned for platform tab');
    }

    @IsTest
    static void testGetProducts_platformTab_noFailOpen() {
        // Unlike the "All Products" tab, a specific platform tab is an explicit request for that
        // platform - a product with no System_Platform__c set must NOT show up here.
        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts('2', 1, 10, null);
        }
        Test.stopTest();

        System.assertEquals(0, result.products.size(), 'Products with no platform set must not appear on a specific platform tab');
    }

    @IsTest
    static void testGetProducts_pagination() {
        Ctrl_DealerShop.ProductPageResult page1;
        Ctrl_DealerShop.ProductPageResult page2;
        Test.startTest();
        System.runAs(portalUser()) {
            page1 = Ctrl_DealerShop.getProducts(null, 1, 1, null);
            page2 = Ctrl_DealerShop.getProducts(null, 2, 1, null);
        }
        Test.stopTest();

        System.assertEquals(1, page1.products.size(), 'Page 1 should have 1 product');
        System.assertEquals(1, page2.products.size(), 'Page 2 should have 1 product');
        System.assertNotEquals(
            page1.products[0].id,
            page2.products[0].id,
            'Pages should return different products'
        );
    }

    @IsTest
    static void testGetProductDetail_returnsCorrectProduct() {
        Product2 prod = [
            SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1
        ];

        Ctrl_DealerShop.ProductDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerShop.getProductDetail(prod.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, dto, 'ProductDTO should not be null');
        System.assertEquals(prod.Id, dto.id, 'Product Id mismatch');
        System.assertEquals('Public Product A', dto.name, 'Product name mismatch');
        System.assertEquals('PP-001', dto.productCode, 'Product code mismatch');
        System.assertEquals('Fleet', dto.category, 'Category mismatch');
        System.assertEquals('Public Product A', dto.displayName, 'Display name mismatch');
    }

    @IsTest
    static void testGetProductDetail_privateProductNotVisible() {
        Product2 privateProd = [
            SELECT Id FROM Product2 WHERE ProductCode = 'PP-003' LIMIT 1
        ];

        Test.startTest();
        System.runAs(portalUser()) {
            try {
                Ctrl_DealerShop.ProductDTO dto =
                    Ctrl_DealerShop.getProductDetail(privateProd.Id);
                System.assertEquals(null, dto, 'Private product detail should not be accessible');
            } catch (AuraHandledException e) {
                System.assert(true, 'AuraHandledException is acceptable for private product');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testPlaceOrder_createsOpportunityAndItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [
            SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1
        ];
        PricebookEntry pbe = [
            SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1
        ];

        List<Map<String, Object>> cartItems = new List<Map<String, Object>>();
        Map<String, Object> cartItem = new Map<String, Object>{
            'productId' => (String) prod.Id,
            'quantity'  => 2,
            'unitPrice' => pbe.UnitPrice
        };
        cartItems.add(cartItem);

        String cartJson = JSON.serialize(cartItems);

        String orderNumber;
        Test.startTest();
        System.runAs(portalUser()) {
            orderNumber = Ctrl_DealerShop.placeOrder(cartJson);
        }
        Test.stopTest();

        System.assertNotEquals(null, orderNumber, 'Order number should be returned');

        Opportunity opp = [
            SELECT Id, Name, AccountId, StageName, Type, LeadSource, Pricebook2Id, Auto_Number__c, RecordType.Name
            FROM Opportunity
            WHERE Name = :orderNumber
        ];
        System.assertEquals(acc.Id, opp.AccountId, 'Opportunity AccountId mismatch');
        System.assertEquals('Webshop', opp.StageName, 'Opportunity StageName should be Webshop');
        System.assertEquals(
            opp.RecordType.Name + ' #' + opp.Auto_Number__c, opp.Name,
            'Opportunity Name should be "<RecordType Name>#<Opportunity Number>"'
        );

        List<OpportunityLineItem> items = [
            SELECT Id, Product2Id, Quantity, UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
        ];
        System.assertEquals(1, items.size(), 'One OpportunityLineItem should be created');
        System.assertEquals(prod.Id, items[0].Product2Id, 'OpportunityLineItem Product2Id mismatch');
        System.assertEquals(2, items[0].Quantity, 'OpportunityLineItem Quantity mismatch');
    }

    @IsTest
    static void testPlaceOrder_multipleItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prodA = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];
        Product2 prodB = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-002' LIMIT 1];
        PricebookEntry pbeA = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :prodA.Id LIMIT 1];
        PricebookEntry pbeB = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :prodB.Id LIMIT 1];

        List<Map<String, Object>> cartItems = new List<Map<String, Object>>{
            new Map<String, Object>{
                'productId' => (String) prodA.Id,
                'quantity'  => 1,
                'unitPrice' => pbeA.UnitPrice
            },
            new Map<String, Object>{
                'productId' => (String) prodB.Id,
                'quantity'  => 3,
                'unitPrice' => pbeB.UnitPrice
            }
        };

        String cartJson = JSON.serialize(cartItems);

        String orderNumber;
        Test.startTest();
        System.runAs(portalUser()) {
            orderNumber = Ctrl_DealerShop.placeOrder(cartJson);
        }
        Test.stopTest();

        System.assertNotEquals(null, orderNumber, 'Order number should be returned');

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = :orderNumber];
        List<OpportunityLineItem> items = [
            SELECT Id, Product2Id, Quantity
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            ORDER BY Quantity ASC
        ];
        System.assertEquals(2, items.size(), 'Two OpportunityLineItems should be created');
    }

    @IsTest
    static void testGetProducts_emptyCategory_returnsAll() {
        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts('', 1, 50, null);
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        Integer publicCount = [SELECT COUNT() FROM Product2 WHERE Show_In_Dealer_Shop__c = true AND IsActive = true];
        System.assertEquals(publicCount, result.products.size(), 'All public products should be returned for empty category');
    }

    @IsTest
    static void testGetProductDetail_withDiscount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];

        Ctrl_DealerShop.ProductDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerShop.getProductDetail(prod.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, dto, 'ProductDTO should not be null');
        System.assertEquals(prod.Id, dto.id, 'Product Id should match');

        // The fixture discount's tier 1 starts at quantity 1 (From_Quantity_1__c = 1), so it
        // applies to a single unit already - it IS the unit price, priced off the pricebook
        // entry's UnitPrice (99.00), not entry.From_Price_X (which this org never populates and
        // would silently produce a null price) - and it should not also appear as a redundant
        // separate tier row.
        System.assertEquals(89.10, dto.unitPrice, 'unitPrice should be entry.UnitPrice (99.00) discounted by the qty-1 tier (10%)');
        System.assertEquals(0, dto.priceTiers.size(), 'The qty-1 tier is promoted into unitPrice, not listed separately');
    }

    @IsTest
    static void testGetProductDetail_withDiscount_tierAboveQty1_staysListed() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-002' LIMIT 1];

        insert new Product_Discount__c(
            Account__c            = [SELECT Id FROM Account LIMIT 1].Id,
            Product__c            = prod.Id,
            IsActive__c           = true,
            isFixedPrice__c       = false,
            From_Quantity_1__c    = 5,
            From_Discount_1__c    = 15
        );
        // Activate separately - rbb_Product_Discount forces IsActive__c=false on every new record.
        Product_Discount__c disc = [SELECT Id FROM Product_Discount__c WHERE Product__c = :prod.Id];
        disc.IsActive__c = true;
        update disc;

        Ctrl_DealerShop.ProductDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerShop.getProductDetail(prod.Id);
        }
        Test.stopTest();

        // Tier starts at quantity 5, not 1 - it must stay listed as a volume tier rather than
        // being promoted into unitPrice, and unitPrice should remain the undiscounted base (49.00).
        System.assertEquals(49.00, dto.unitPrice, 'unitPrice should stay at entry.UnitPrice - the tier does not apply at quantity 1');
        System.assertEquals(1, dto.priceTiers.size(), 'The qty-5 tier should be listed');
        System.assertEquals(5, dto.priceTiers[0].fromQty, 'Tier from-quantity should be 5');
        System.assertEquals(41.65, dto.priceTiers[0].price, 'Tier price should be entry.UnitPrice (49.00) discounted by 15%');
    }

    @IsTest
    static void testGetProductDetail_customerProductCode_overridesWhenSet() {
        Product2 prod = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PP-002' LIMIT 1];

        insert new Product_Discount__c(
            Account__c              = [SELECT Id FROM Account LIMIT 1].Id,
            Product__c               = prod.Id,
            IsActive__c              = true,
            isFixedPrice__c          = false,
            Discount_percentage__c   = 5,
            From_Quantity_1__c       = 1,
            From_Discount_1__c       = 5,
            Product_Code_Customer__c = 'CUST-CODE-42'
        );
        // Activate separately - rbb_Product_Discount forces IsActive__c=false on every new record.
        Product_Discount__c disc = [SELECT Id FROM Product_Discount__c WHERE Product__c = :prod.Id];
        disc.IsActive__c = true;
        update disc;

        Ctrl_DealerShop.ProductDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerShop.getProductDetail(prod.Id);
        }
        Test.stopTest();

        System.assertEquals('CUST-CODE-42', dto.productCode, 'productCode should be overridden by the active discount\'s Product_Code_Customer__c');
        System.assertNotEquals(prod.ProductCode, dto.productCode, 'productCode should not be the standard Product2.ProductCode once overridden');
    }

    @IsTest
    static void testGetProducts_customerProductCode_blankFallsBackToStandardCode() {
        Product2 prod = [SELECT Id, ProductCode FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];

        // The @TestSetup discount for PP-001 has no Product_Code_Customer__c set - productCode
        // must fall back to the standard Product2.ProductCode rather than showing blank.
        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts(null, 1, 10, null);
        }
        Test.stopTest();

        Ctrl_DealerShop.ProductDTO dto = null;
        for (Ctrl_DealerShop.ProductDTO d : result.products) {
            if (d.id == prod.Id) dto = d;
        }
        System.assertNotEquals(null, dto, 'PP-001 should be in the results');
        System.assertEquals(prod.ProductCode, dto.productCode, 'productCode should fall back to Product2.ProductCode when Product_Code_Customer__c is blank');
    }

    @IsTest
    static void testPlaceOrder_invalidJson_throwsException() {
        Test.startTest();
        try {
            Ctrl_DealerShop.placeOrder('not-valid-json{{{');
            System.assert(false, 'Expected an exception for invalid JSON');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException expected for invalid cart JSON');
        } catch (Exception e) {
            System.assert(true, 'Any exception is acceptable for malformed input');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrderHistory_returnsPlacedOrder() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        String cartJson = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'productId' => (String) prod.Id,
                'quantity'  => 1,
                'unitPrice' => pbe.UnitPrice
            }
        });

        String orderNumber;
        List<Ctrl_DealerShop.OrderHistoryDTO> mine;
        List<Ctrl_DealerShop.OrderHistoryDTO> all;
        Test.startTest();
        System.runAs(portalUser()) {
            orderNumber = Ctrl_DealerShop.placeOrder(cartJson);
            mine = Ctrl_DealerShop.getOrderHistory(true);
            all  = Ctrl_DealerShop.getOrderHistory(false);
        }
        Test.stopTest();

        System.assertEquals(1, mine.size(), 'The running user placed exactly one order');
        System.assertEquals(orderNumber, mine[0].orderNumber, 'Order number should match the one placeOrder returned');
        System.assertEquals(1, all.size(), 'All-orders view should include the same single order for this account');
    }

    @IsTest
    static void testGetOrderDetail_returnsCurrentPricing() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];
        PricebookEntry pbe = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1];

        String cartJson = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'productId' => (String) prod.Id,
                'quantity'  => 2,
                'unitPrice' => pbe.UnitPrice
            }
        });

        String orderNumber;
        Test.startTest();
        System.runAs(portalUser()) {
            orderNumber = Ctrl_DealerShop.placeOrder(cartJson);
        }
        Test.stopTest();

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = :orderNumber];
        OpportunityLineItem placedLine = [SELECT UnitPrice FROM OpportunityLineItem WHERE OpportunityId = :opp.Id LIMIT 1];

        // Simulate the account's price agreement changing AFTER the order was placed (e.g. the
        // discount was renegotiated) - the org's own rbb_Opportunity_Product flow already applies
        // whatever discount is active at insert time, so the only way to make historical and
        // current genuinely diverge is to change the discount afterwards.
        Product_Discount__c disc = [SELECT Id FROM Product_Discount__c WHERE Product__c = :prod.Id LIMIT 1];
        disc.Discount_percentage__c = 20;
        disc.From_Discount_1__c = 20;
        update disc;

        Ctrl_DealerShop.OrderDetailDTO detail;
        System.runAs(portalUser()) {
            detail = Ctrl_DealerShop.getOrderDetail(opp.Id);
        }

        System.assertEquals(orderNumber, detail.orderNumber, 'Order number should match');
        System.assertEquals(1, detail.lines.size(), 'One line item should be returned');

        Ctrl_DealerShop.OrderLineDTO line = detail.lines[0];
        System.assertEquals(prod.Id, line.productId, 'Line productId mismatch');
        System.assertEquals(2, line.quantity, 'Line quantity should match the original order');
        System.assertEquals(placedLine.UnitPrice, line.originalUnitPrice, 'originalUnitPrice should stay at the historical price actually stored on the line item');

        // The discount is now 20%, not the 10% in effect when the order was placed - current
        // pricing must reflect that change, not repeat the frozen historical price.
        System.assertNotEquals(null, line.product, 'product DTO should be populated with current pricing');
        System.assertEquals(79.20, line.product.unitPrice, 'current unitPrice should reflect the now-20% discount (99.00 * 0.8), not the historical price');
        System.assertNotEquals(line.originalUnitPrice, line.product.unitPrice, 'current price must differ from the historical price once the discount changed');
    }

    @IsTest
    static void testGetOrderDetail_invalidId_throws() {
        Test.startTest();
        System.runAs(portalUser()) {
            try {
                Ctrl_DealerShop.getOrderDetail(null);
                System.assert(false, 'Expected an exception for a null opportunityId');
            } catch (AuraHandledException e) {
                System.assert(true, 'AuraHandledException expected for a null opportunityId');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetProductDetail_imageUrl_resolvesViaContentDistribution() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title        = 'PP-001 image',
            PathOnClient = 'pp-001.png',
            VersionData  = Blob.valueOf('fake image bytes')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            LinkedEntityId = prod.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        ContentDistribution cd = new ContentDistribution(
            Name = 'PP-001 distribution',
            ContentVersionId = cv.Id,
            PreferencesAllowViewInBrowser = true
        );
        insert cd;
        cd = [SELECT Id, ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id];

        Ctrl_DealerShop.ProductDTO dto;
        Test.startTest();
        System.runAs(portalUser()) {
            dto = Ctrl_DealerShop.getProductDetail(prod.Id);
        }
        Test.stopTest();

        System.assertEquals(cd.ContentDownloadUrl, dto.imageUrl, 'imageUrl should come from ContentDistribution.ContentDownloadUrl');
    }

    // ── Favorites ─────────────────────────────────────────────────────────────

    @IsTest
    static void testToggleFavorite_addsThenRemoves() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];

        Boolean afterFirstToggle;
        Boolean afterSecondToggle;
        Test.startTest();
        System.runAs(portalUser()) {
            afterFirstToggle  = Ctrl_DealerShop.toggleFavorite(prod.Id);
            afterSecondToggle = Ctrl_DealerShop.toggleFavorite(prod.Id);
        }
        Test.stopTest();

        System.assertEquals(true, afterFirstToggle, 'First toggle should mark the product as a favorite');
        System.assertEquals(false, afterSecondToggle, 'Second toggle should remove the favorite');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Dealer_Product_Favorite__c WHERE Product__c = :prod.Id],
            'No favorite row should remain after toggling twice'
        );
    }

    @IsTest
    static void testGetProducts_favoritesTab_returnsOnlyFavorited() {
        Product2 favProd = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];

        Test.startTest();
        System.runAs(portalUser()) {
            Ctrl_DealerShop.toggleFavorite(favProd.Id);
        }

        Ctrl_DealerShop.ProductPageResult favorites;
        System.runAs(portalUser()) {
            favorites = Ctrl_DealerShop.getProducts('favorites', 1, 10, null);
        }
        Test.stopTest();

        System.assertEquals(1, favorites.products.size(), 'Only the favorited product should be returned');
        System.assertEquals(favProd.Id, favorites.products[0].id, 'Favorited product Id mismatch');
        System.assertEquals(true, favorites.products[0].isFavorite, 'isFavorite should be true for a favorited product');
    }

    @IsTest
    static void testGetProducts_isFavorite_falseWhenNotFavorited() {
        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts(null, 1, 10, null);
        }
        Test.stopTest();

        for (Ctrl_DealerShop.ProductDTO dto : result.products) {
            System.assertEquals(false, dto.isFavorite, 'isFavorite should default to false when nothing was favorited');
        }
    }

    // ── System_Platform__c / Administration platform filter (All Products tab) ─

    @IsTest
    static void testGetProducts_allTab_platformFilter_failOpen() {
        // Reseller__c '1' matches the @TestSetup Account's Reseller_Name__c '1'. Required platform
        // '2' - PP-001 (no System_Platform__c) and PP-002 (matches '2') must both stay visible
        // (fail-open for the null one); a third product on a non-matching platform must be excluded.
        insert new Subscription25__Administration__c(
            Name                                       = 'Test Administration',
            Reseller__c                                = '1',
            Available_System_Platforms__c              = '2',
            Subscription25__Invoice_Number_Prefix__c   = 'TST',
            Subscription25__Billing_Country__c        = 'NL'
        );

        Product2 matching = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-002' LIMIT 1];
        matching.System_Platform__c = '2';
        update matching;

        Product2 mismatched = new Product2(
            Name                   = 'Mismatched Platform Product',
            ProductCode            = 'PP-004',
            IsActive                = true,
            Show_In_Dealer_Shop__c  = true,
            Category_Platform__c    = 'Fleet',
            System_Platform__c      = '5'
        );
        insert mismatched;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = mismatched.Id, UnitPrice = 10.00, IsActive = true);
        Pricebook2 dealerPricebook = [SELECT Id FROM Pricebook2 WHERE Name = 'Dealer NL All Pricebook' LIMIT 1];
        insert new PricebookEntry(Pricebook2Id = dealerPricebook.Id, Product2Id = mismatched.Id, UnitPrice = 10.00, IsActive = true);

        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts(null, 1, 50, null);
        }
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (Ctrl_DealerShop.ProductDTO dto : result.products) returnedIds.add(dto.id);

        System.assert(returnedIds.contains(matching.Id), 'Product on the required platform should be visible');
        System.assert(!returnedIds.contains(mismatched.Id), 'Product on a non-required platform should be excluded from All Products');

        Product2 noPlatformProd = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];
        System.assert(returnedIds.contains(noPlatformProd.Id), 'Product with no System_Platform__c set should stay visible (fail-open)');
    }

    @IsTest
    static void testGetProducts_allTab_multiplePlatforms_matchesEither() {
        // A reseller with MULTIPLE available platforms ('1;5') - each product only ever carries
        // ONE platform value, so this must match products on platform 1 OR platform 5, not require
        // both on the same product (INCLUDES('1;5') would wrongly demand both at once).
        insert new Subscription25__Administration__c(
            Name                                       = 'Test Administration',
            Reseller__c                                = '1',
            Available_System_Platforms__c              = '1;5',
            Subscription25__Invoice_Number_Prefix__c   = 'TST',
            Subscription25__Billing_Country__c        = 'NL'
        );

        Product2 onPlatform1 = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];
        onPlatform1.System_Platform__c = '1';
        update onPlatform1;

        Product2 onPlatform5 = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-002' LIMIT 1];
        onPlatform5.System_Platform__c = '5';
        update onPlatform5;

        Ctrl_DealerShop.ProductPageResult result;
        Test.startTest();
        System.runAs(portalUser()) {
            result = Ctrl_DealerShop.getProducts(null, 1, 50, null);
        }
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (Ctrl_DealerShop.ProductDTO dto : result.products) returnedIds.add(dto.id);

        System.assert(returnedIds.contains(onPlatform1.Id), 'Product on platform 1 should be visible under All Products');
        System.assert(returnedIds.contains(onPlatform5.Id), 'Product on platform 5 should be visible under All Products');
    }

    @IsTest
    static void testGetPlatformTabs_returnsResellerPlatformsWithLabelsInValueSetOrder() {
        insert new Subscription25__Administration__c(
            Name                                       = 'Test Administration',
            Reseller__c                                = '1',
            Available_System_Platforms__c              = '6;2',
            Subscription25__Invoice_Number_Prefix__c   = 'TST',
            Subscription25__Billing_Country__c        = 'NL'
        );

        List<Ctrl_DealerShop.PlatformTabDTO> tabs;
        Test.startTest();
        System.runAs(portalUser()) {
            tabs = Ctrl_DealerShop.getPlatformTabs();
        }
        Test.stopTest();

        // '6' and '2' were assigned in reverse order - tabs must follow the global value set's
        // own defined order ('2' before '6'), not the reseller field's Set iteration order.
        System.assertEquals(2, tabs.size(), 'Should return one tab per reseller platform');
        System.assertEquals('2', tabs[0].value, 'First tab should be platform 2 (value set order)');
        System.assertEquals('TrackPilot (DE)', tabs[0].label, 'Label should come from the System global value set');
        System.assertEquals('6', tabs[1].value, 'Second tab should be platform 6 (value set order)');
        System.assertEquals('Echoes (FR)', tabs[1].label, 'Label should come from the System global value set');
    }

    @IsTest
    static void testGetPlatformTabs_noAdministration_returnsEmpty() {
        List<Ctrl_DealerShop.PlatformTabDTO> tabs;
        Test.startTest();
        System.runAs(portalUser()) {
            tabs = Ctrl_DealerShop.getPlatformTabs();
        }
        Test.stopTest();

        System.assertEquals(0, tabs.size(), 'No Administration record for this reseller - no platform tabs');
    }
}
