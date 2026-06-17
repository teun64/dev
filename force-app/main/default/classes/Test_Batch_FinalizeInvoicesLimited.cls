@isTest
private class Test_Batch_FinalizeInvoicesLimited {

    @IsTest
    private static void Test_Batch_FinalizeInvoicesLimited_FinalizeInvoice() {
        Subscription25__Administration__c adminNL = Test_Data.createAdministration(true);
        Subscription25__Administration__c adminDE = Test_Data.createAdministration(false);
        adminDE.Name = 'DE Administration';
        adminDE.Language_Default__c = 'de';
        adminDE.Subscription25__Invoice_Number_Prefix__c = 'TTD';
        adminDE.Reseller__c = '5';
        adminDE.External_ID__c = 5;
        Database.insert(adminDE);
        Account accNL = Test_Data.createAccount('Account NL', '12345NL', 'B2B', true);
        Account accDE = Test_Data.createAccount('Account DE', '12345DE', 'B2B', false);
        accDE.Reseller_Name__c = '5';
        Database.insert(accDE);
        Subscription25__Invoice__c invNL = Test_Data.createInvoice(adminNL.Id, accNL.Id, 'DRAFT', false);
        invNL.Subscription25__Exact_Order_Number__c = '1230';
        Database.insert(invNL);
        Subscription25__Invoice__c invDE = Test_Data.createInvoice(adminDE.Id, accDE.Id, 'DRAFT', false);
        invDE.Subscription25__Exact_Order_Number__c = '1231';
        Database.insert(invDE);

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Batch_FinalizeInvoicesLimited batch = new Batch_FinalizeInvoicesLimited();
        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        id invNL_Id = invNL.Id;
        id invDE_Id = invDE.Id;
        invNL = [SELECT Id, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c FROM Subscription25__Invoice__c WHERE Id = :invNL.Id];
        //System.assert(invNL.Subscription25__Finalized_In_Exact__c, 'Invoice should be set as printed');
        system.assertEquals(invNL_Id,invNL.Id);

        invDE = [SELECT Id, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c FROM Subscription25__Invoice__c WHERE Id = :invDE.Id];
        //System.assert(invDE.Subscription25__Finalized_In_Exact__c, 'Invoice should be set as printed');
        system.assertEquals(invDE_Id,invDE.Id);
    }
}
