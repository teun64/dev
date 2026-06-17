@isTest
public class Test_Inv_syncOrderToFinancialSystem {

    @isTest
    private static void testSyncOrderToFinancialSystem (){
 		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Product2 prod = Test_Data.createProduct('name', 'code.P', '1-in-1', 'SubscriptionP', false);
        //prod.Is_Installation_Product__c = true;
        Database.insert(prod);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 10, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vr.Id, true);
        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        opp.Installation_Notes__c = 'installation notes';
        opp.Sales_Contact__c = cont.Id;

        Database.insert(opp);

		Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
		ord.OpportunityId = opp.Id;
		Database.insert(ord);

		OrderItem oi = Test_Data.createOrderItem(ord.Id, pbe.Id, 100, false);
        oi.Partner_Code__c = '1A2B3C4D5E6F7';
        Database.insert(oi);

        Inv_syncOrderToFinancialSystem.syncOrderToFinancialSystemRequests inp = new Inv_syncOrderToFinancialSystem.syncOrderToFinancialSystemRequests();
        inp.orderId = ord.id;
        list<Inv_syncOrderToFinancialSystem.syncOrderToFinancialSystemRequests> inpList = new list<Inv_syncOrderToFinancialSystem.syncOrderToFinancialSystemRequests>();
        inpList.add(inp);

        Test.startTest();
        //List<Inv_syncOrderToFinancialSystem.syncOrderToFinancialSystemResult> resultMessages = 
        Inv_syncOrderToFinancialSystem.syncOrderToFinancialSystem(inpList);
        Test.stopTest();
    
        Order ort = [SELECT Id FROM Order WHERE Id = :ord.Id];
        System.assertEquals(ord.Id, ort.Id);     
    }
}