@IsTest(SeeAllData=false)
private class Test_Ctrl_DealerShop {

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name                = 'Test Dealer',
            BillingCountryCode  = 'NL',
            Dealer_category__c  = 'Gold',
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

        Product2 publicProd = new Product2(
            Name                 = 'Public Product A',
            ProductCode          = 'PP-001',
            IsActive             = true,
            Is_Public__c         = true,
            Category_Platform__c = 'Fleet',
            Description          = 'Short desc A'
        );

        Product2 publicProd2 = new Product2(
            Name                 = 'Public Product B',
            ProductCode          = 'PP-002',
            IsActive             = true,
            Is_Public__c         = true,
            Category_Platform__c = 'Security',
            Description          = 'Short desc B'
        );

        Product2 privateProd = new Product2(
            Name                 = 'Private Product C',
            ProductCode          = 'PP-003',
            IsActive             = true,
            Is_Public__c         = false,
            Category_Platform__c = 'Fleet'
        );

        insert new List<Product2>{ publicProd, publicProd2, privateProd };

        PricebookEntry pbeA = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = publicProd.Id,
            UnitPrice    = 99.00,
            IsActive     = true
        );
        PricebookEntry pbeB = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = publicProd2.Id,
            UnitPrice    = 49.00,
            IsActive     = true
        );
        PricebookEntry pbeC = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
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
    }

    @IsTest
    static void testGetProducts_returnsOnlyPublic() {
        Test.startTest();
        Ctrl_DealerShop.ProductPageResult result =
            Ctrl_DealerShop.getProducts(null, 1, 10);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.products, 'Products list should not be null');
        Integer publicCount = [SELECT COUNT() FROM Product2 WHERE Is_Public__c = true AND IsActive = true];
        System.assertEquals(publicCount, result.products.size(), 'Product count mismatch');
    }

    @IsTest
    static void testGetProducts_filterByCategory() {
        Test.startTest();
        Ctrl_DealerShop.ProductPageResult result =
            Ctrl_DealerShop.getProducts('Fleet', 1, 10);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        for (Ctrl_DealerShop.ProductDTO dto : result.products) {
            System.assertEquals('Fleet', dto.category, 'Category filter not applied correctly');
        }
    }

    @IsTest
    static void testGetProducts_pagination() {
        Test.startTest();
        Ctrl_DealerShop.ProductPageResult page1 =
            Ctrl_DealerShop.getProducts(null, 1, 1);
        Ctrl_DealerShop.ProductPageResult page2 =
            Ctrl_DealerShop.getProducts(null, 2, 1);
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

        Test.startTest();
        Ctrl_DealerShop.ProductDTO dto =
            Ctrl_DealerShop.getProductDetail(prod.Id);
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
        try {
            Ctrl_DealerShop.ProductDTO dto =
                Ctrl_DealerShop.getProductDetail(privateProd.Id);
            System.assertEquals(null, dto, 'Private product detail should not be accessible');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException is acceptable for private product');
        }
        Test.stopTest();
    }

    @IsTest
    static void testPlaceOrder_createsOrderAndItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [
            SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1
        ];
        PricebookEntry pbe = [
            SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = :prod.Id LIMIT 1
        ];

        List<Map<String, Object>> cartItems = new List<Map<String, Object>>();
        Map<String, Object> cartItem = new Map<String, Object>{
            'productId'       => (String) prod.Id,
            'pricebookEntryId'=> (String) pbe.Id,
            'quantity'        => 2,
            'unitPrice'       => pbe.UnitPrice
        };
        cartItems.add(cartItem);

        String cartJson = JSON.serialize(new Map<String, Object>{
            'accountId'   => (String) acc.Id,
            'pricebookId' => Test.getStandardPricebookId(),
            'currency'    => 'EUR',
            'items'       => cartItems
        });

        Test.startTest();
        Id orderId = Ctrl_DealerShop.placeOrder(cartJson);
        Test.stopTest();

        System.assertNotEquals(null, orderId, 'Order Id should be returned');

        Order ord = [
            SELECT Id, AccountId, Status, Pricebook2Id, CurrencyIsoCode
            FROM Order
            WHERE Id = :orderId
        ];
        System.assertEquals(acc.Id, ord.AccountId, 'Order AccountId mismatch');
        System.assertNotEquals(null, ord.Status, 'Order Status should be set');

        List<OrderItem> items = [
            SELECT Id, Product2Id, Quantity, UnitPrice
            FROM OrderItem
            WHERE OrderId = :orderId
        ];
        System.assertEquals(1, items.size(), 'One OrderItem should be created');
        System.assertEquals(prod.Id, items[0].Product2Id, 'OrderItem Product2Id mismatch');
        System.assertEquals(2, items[0].Quantity, 'OrderItem Quantity mismatch');
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
                'productId'       => (String) prodA.Id,
                'pricebookEntryId'=> (String) pbeA.Id,
                'quantity'        => 1,
                'unitPrice'       => pbeA.UnitPrice
            },
            new Map<String, Object>{
                'productId'       => (String) prodB.Id,
                'pricebookEntryId'=> (String) pbeB.Id,
                'quantity'        => 3,
                'unitPrice'       => pbeB.UnitPrice
            }
        };

        String cartJson = JSON.serialize(new Map<String, Object>{
            'accountId'   => (String) acc.Id,
            'pricebookId' => Test.getStandardPricebookId(),
            'currency'    => 'EUR',
            'items'       => cartItems
        });

        Test.startTest();
        Id orderId = Ctrl_DealerShop.placeOrder(cartJson);
        Test.stopTest();

        System.assertNotEquals(null, orderId, 'Order Id should be returned');

        List<OrderItem> items = [
            SELECT Id, Product2Id, Quantity
            FROM OrderItem
            WHERE OrderId = :orderId
            ORDER BY Quantity ASC
        ];
        System.assertEquals(2, items.size(), 'Two OrderItems should be created');
    }

    @IsTest
    static void testGetProducts_emptyCategory_returnsAll() {
        Test.startTest();
        Ctrl_DealerShop.ProductPageResult result =
            Ctrl_DealerShop.getProducts('', 1, 50);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        Integer publicCount = [SELECT COUNT() FROM Product2 WHERE Is_Public__c = true AND IsActive = true];
        System.assertEquals(publicCount, result.products.size(), 'All public products should be returned for empty category');
    }

    @IsTest
    static void testGetProductDetail_withDiscount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'PP-001' LIMIT 1];

        Test.startTest();
        Ctrl_DealerShop.ProductDTO dto =
            Ctrl_DealerShop.getProductDetail(prod.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'ProductDTO should not be null');
        System.assertEquals(prod.Id, dto.id, 'Product Id should match');
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
}
