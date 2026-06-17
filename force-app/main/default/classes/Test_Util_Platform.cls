@isTest
private class Test_Util_Platform {
    @isTest
    private static void testSyncAccount(){    
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.PlatformMock());

        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
    
        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
        Database.insert(ers);
    
        Account acct1 = Test_Data.createAccount('Test_11', '78729', 'B2B', true);
        Subscription25__Debtor_Number__c debNr1 = new Subscription25__Debtor_Number__c(Subscription25__Debtor_Number__c = 'TEST_11', Subscription25__Account__c = acct1.Id, Subscription25__Administration__c = adm.id);
    
        Database.insert(debNr1);
        Contact cont1 = Test_Data.createContact(acct1.Id, 'Test_11', '1234567890', 'lex_11@gen25.com', true);
        acct1.Contact_person__c = cont1.Id;
        acct1.MI_Administrator__c = cont1.Id;
        acct1.Contact_Shipping__c = cont1.Id;
        acct1.Contact_Billing__c = cont1.Id;
    
        acct1.FinancialDebtorNumber__c = 'TEST_11';
    
        Database.update(acct1);

        Contact cont2 = Test_Data.createContact(acct1.Id, 'Test_12', '0987654323', 'lex_12@gen25.com', true);
    

        AccountContactRelation acr2 = new AccountContactRelation(AccountId = acct1.Id, ContactId = cont2.Id, Roles = 'Main;Invoice', CompositeKey__c = String.valueOf(acct1.Id) + String.valueOf(cont2.Id));
        Database.upsert(acr2, AccountContactRelation.Fields.CompositeKey__c, false);

        Test.startTest();
        Util_Platform.syncAccountAsync(acct1.Id, '1');
        Test.stopTest();
        
        Account accResult1 = [Select id, extId_1__c from Account where id = :acct1.id];
    
        System.assertEquals('78729', accResult1.extId_1__c); 
   }
}