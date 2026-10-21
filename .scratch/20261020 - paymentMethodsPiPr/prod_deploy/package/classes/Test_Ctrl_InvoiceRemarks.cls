@isTest
private class Test_Ctrl_InvoiceRemarks {

    @IsTest
    private static void test_remarkGetters(){
        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
        Account acc = Test_Data.createAccount('CustomerNL', '12345', 'B2B', true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest', '12.MiTest', '1-sv-1', 'Subscription', true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vat = Test_Data.createVATRate('TestVAT', 19.5, true, true);
        Test_Data.createAdministrationProduct(adm.Id, prd.Id, vat.Id, true);
        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', true);
        Order ord = Test_Data.createOrder(acc.Id, adm.Id, Date.today().addDays(-14), false);
        ord.Subscription25__Invoice__c = inv.Id;
        Database.insert(ord, AccessLevel.SYSTEM_MODE);
        Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, true);

        Test.setCurrentPage(new PageReference('/apex/Invoice'));
        ApexPages.currentPage().getParameters().put('id', inv.Id);

        Test.startTest();
        Ctrl_Invoice contr = new Ctrl_Invoice();
        System.assertNotEquals(null, contr.getAdmin());
        System.assertEquals('pdf', contr.getIsPdf());
        ApexPages.currentPage().getParameters().put('h', '1');
        System.assertEquals('html', contr.getIsPdf());

        // remark texts are empty whenever their flag is off
        System.assertEquals(contr.getShowRemarkGeneral(), String.isNotBlank(contr.getRemarkGeneral()));
        System.assertEquals(contr.getShowRemarkEU(), String.isNotBlank(contr.getRemarkEU()));
        System.assertEquals(contr.getShowRemarkNonEU(), String.isNotBlank(contr.getRemarkNonEU()));
        contr.getPaymentRemark();
        Test.stopTest();
    }
}
