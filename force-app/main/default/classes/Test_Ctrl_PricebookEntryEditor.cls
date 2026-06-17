@IsTest
public class Test_Ctrl_PricebookEntryEditor {
   
    @isTest
    static void testUpdateListPrice() {
        // Setup: Create a Product and a PricebookEntry
        Product2 prd = test_data.createProduct('ProductName01', 'P.Code.01', 'Code01-sv-1', 'Subscription', true);
        PricebookEntry pbe = test_data.createPricebookEntry(prd.Id, 100, true);

        // Test case: Update the price with a new valid price
        Test.startTest();
        Decimal newPrice = 120;
        Ctrl_PricebookEntryEditor.updateListPrice(pbe.Id, newPrice);
        boolean eventPublished = Ctrl_PricebookEntryEditor.eventPublished;
        Test.stopTest();

        // Verify that the price has been updated
        pbe = [SELECT UnitPrice FROM PricebookEntry WHERE Id = :pbe.Id];
        System.assertEquals(newPrice, pbe.UnitPrice, 'The price should be updated to the new price');

        // Verify that the platform event was published
        System.assertEquals(true, eventPublished, 'The platform event should have been published successfully');
    }

    @isTest
    static void testUpdateListPriceNoOp() {
        // Setup: Create a Product and a PricebookEntry
        Product2 prd = test_data.createProduct('ProductName02', 'P.Code.02', 'Code02-sv-1', 'Subscription', true);
        PricebookEntry pbe = test_data.createPricebookEntry(prd.Id, 100, true);

        // Test case: Update the price with the same price (no-op)
        Test.startTest();
        Ctrl_PricebookEntryEditor.updateListPrice(pbe.Id, 100);
        Test.stopTest();

        // Verify that the price has not been updated
        pbe = [SELECT UnitPrice FROM PricebookEntry WHERE Id = :pbe.Id];
        System.assertEquals(100, pbe.UnitPrice, 'The price should remain unchanged');
    }

    @isTest
    static void testUpdateListPriceInvalidPrice() {
        // Setup: Create a Product and a PricebookEntry
        Product2 prd = test_data.createProduct('ProductName03', 'P.Code.03', 'Code03-sv-1', 'Subscription', true);
        PricebookEntry pbe = test_data.createPricebookEntry(prd.Id, 100, true);

        // Test case: Update the price with an invalid negative price
        Test.startTest();
        try {
            Ctrl_PricebookEntryEditor.updateListPrice(pbe.Id, -50);
            System.assert(false, 'An exception should have been thrown for negative price');
        } catch (AuraHandledException e) {
            System.assertEquals('Script-thrown exception', e.getMessage(), 'The exception message should match, expected Price must be 0 or higher');
        }
        Test.stopTest();
    }
}
