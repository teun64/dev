@isTest
private class Test_Util_PriceCalculation {
    @isTest
    private static void testGetPricebookEntry(){
		Account acct = Test_Data.createAccount('test', '11', 'B2B', true);
		//Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Product2 prod = Test_Data.createProduct('MiBlack', 'Black.12', '1-sv-1', 'Subscription', true);
		PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 20.00, true);
        Product_Discount__c prodDis = Test_Data.createProductDiscount(prod.Id, acct.Id, true);
        prodDis.Status__c = 'Activated';
        prodDis.IsActive__c = true;
        Database.update(prodDis);

        // Test with productID, priceBookId and CurrencyCode
        Util_PriceCalculation.getPricebookEntryInput pbeIn1 = new Util_PriceCalculation.getPricebookEntryInput();      
        pbeIn1.productId = prod.Id;
        pbeIn1.pricebookId = pbe.Pricebook2Id;
        pbeIn1.accountId = acct.Id;
        pbeIn1.currencyIsoCode = 'EUR';
        pbeIn1.quantity = 1;
        pbeIn1.discount = 0.0;

        // Test with PriceBookEntry
        Util_PriceCalculation.getPricebookEntryInput pbeIn2 = new Util_PriceCalculation.getPricebookEntryInput();  
        pbeIn2.pricebookEntry = pbe;
        pbeIn2.accountId = acct.Id;
        pbeIn2.quantity = 1;
        pbeIn2.discount = 0.0;
        
        Test.startTest();
        List<Util_PriceCalculation.getPricebookEntryPriceOutput> pbeOut1 = Util_PriceCalculation.getPricebookEntry(new List<Util_PriceCalculation.getPricebookEntryInput> {pbeIn1});
        List<Util_PriceCalculation.getPricebookEntryPriceOutput> pbeOut2 = Util_PriceCalculation.getPricebookEntry(new List<Util_PriceCalculation.getPricebookEntryInput> {pbeIn2});
        Test.stopTest();


        System.assertEquals(pbeOut1.size(), 1 );
        System.assertEquals(pbeOut1[0].pricebookEntry.SalesPrice__c, 10.0 );
        System.assertEquals(pbeOut2.size(), 1 );
        System.assertEquals(pbeOut2[0].pricebookEntry.SalesPrice__c, 10.0 );
    }
}