@isTest
private class Test_Inv_syncPlatformAccount {

    @isTest
    private static void testSyncPlatformAccount(){
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.PlatformMock());

        Subscription25__Administration__c adm = Test_Data.createAdministration(true);

        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
        Database.insert(ers);

        Account acct = Test_Data.createAccount('Test', '78729', 'B2B', true);
        Subscription25__Debtor_Number__c debNr1 = new Subscription25__Debtor_Number__c(Subscription25__Debtor_Number__c = 'TEST_11', Subscription25__Account__c = acct.Id, Subscription25__Administration__c = adm.id);

        Database.insert(debNr1);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        acct.Contact_person__c = cont.Id;
        acct.MI_Administrator__c = cont.Id;
        acct.Contact_Shipping__c = cont.Id;
        acct.Contact_Billing__c = cont.Id;

        acct.FinancialDebtorNumber__c = 'TEST_11';

        Database.update(acct);

        Inv_syncPlatformAccount.syncPlatformAccountRequests accRequest = new Inv_syncPlatformAccount.syncPlatformAccountRequests();
       
        accRequest.accountId = acct.Id;
        accRequest.platformId = '1';       
    

        Test.startTest();
        Inv_syncPlatformAccount.syncPlatformAccount(new List<Inv_syncPlatformAccount.syncPlatformAccountRequests> {accRequest});
        Test.stopTest();
        
        account accResult = [Select id, extId_1__c from Account where id = :acct.id];

        System.assertEquals('78729', accResult.extId_1__c);   
    }

}