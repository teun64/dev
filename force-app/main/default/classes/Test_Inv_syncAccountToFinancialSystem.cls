@isTest
private class Test_Inv_syncAccountToFinancialSystem {

    @isTest
    private static void testSyncAccountToFinancialSystem (){
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);

        
        Inv_syncAccountToFinancialSystem.syncAccountToFinancialSystemRequests inp = new Inv_syncAccountToFinancialSystem.syncAccountToFinancialSystemRequests();
        inp.accountId = acct.id;
        list<Inv_syncAccountToFinancialSystem.syncAccountToFinancialSystemRequests> inpList = new list<Inv_syncAccountToFinancialSystem.syncAccountToFinancialSystemRequests>();
        inpList.add(inp);

        Test.startTest();
        //List<Inv_syncAccountToFinancialSystem.syncAccountToFinancialSystemResult> resultMessages = 
        Inv_syncAccountToFinancialSystem.syncAccountToFinancialSystem(inpList);
        Test.stopTest();
    
        Account actt = [SELECT Id, Reseller_Name__c FROM Account WHERE Id = :acct.Id];
        System.assertEquals(acct.Id, actt.Id);       
    }

}