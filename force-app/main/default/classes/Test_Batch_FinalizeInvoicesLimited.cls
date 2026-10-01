@isTest
private class Test_Batch_FinalizeInvoicesLimited {

    @TestSetup
    private static void makeData() {
        Subscription25__Administration__c adminNL = Test_Data.createAdministration(true);
        Subscription25__Administration__c adminDE = Test_Data.createAdministration(false);
        adminDE.Name = 'DE Administration';
        adminDE.Language_Default__c = 'de';
        adminDE.Subscription25__Invoice_Number_Prefix__c = 'TTD';
        adminDE.Reseller__c = '5';
        adminDE.External_ID__c = 5;
        adminDE.Subscription25__Twinfield_Company_Code__c = '1234509875'; // unique in Subscription25 >= v2.67
        adminDE.Acceptance_Environment_Available__c = true; // sandbox: financial system calls allowed
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
    }

    private static String invoiceNumber(String exactOrderNumber) {
        return [SELECT Subscription25__Invoice_Number__c FROM Subscription25__Invoice__c
                WHERE Subscription25__Exact_Order_Number__c = :exactOrderNumber].Subscription25__Invoice_Number__c;
    }

    @IsTest
    private static void Test_Batch_FinalizeInvoicesLimited_FinalizeInvoice() {
        // ExactMock reports the invoice as already printed with InvoiceNumber 123: the batch stores prefix + number
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Database.executeBatch(new Batch_FinalizeInvoicesLimited());
        Test.stopTest();

        System.assertEquals('TTT123', invoiceNumber('1230'), 'Default run (reseller 1) loads the NL invoice number');
        // finish() chains a run for the next reseller with open invoices (5), which completes within stopTest()
        System.assertEquals('TTD123', invoiceNumber('1231'), 'Chained reseller 5 run loads the DE invoice number');
    }

    @IsTest
    private static void Test_Batch_FinalizeInvoicesLimited_Reseller5() {
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Database.executeBatch(new Batch_FinalizeInvoicesLimited('5'));
        Test.stopTest();

        System.assertEquals('TTD123', invoiceNumber('1231'), 'Reseller 5 run loads the DE invoice number');
        System.assertEquals(null, invoiceNumber('1230'), 'NL invoice is not part of the reseller 5 run');
    }
}
