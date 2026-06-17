@isTest
private class Test_Invoice {

    @IsTest
    private static void test_Ctrl_Invoice(){
        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
        Account acc = Test_Data.createAccount('CustomerNL', '12345', 'B2B', true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest', '12.MiTest', '1-sv-1', 'Subscription', true);
        Data_Translation__c dt = Test_Data.createProductTranslation(prd.Id, 'nl', 'Test-NL', 'Description-NL', true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vat = Test_Data.createVATRate('TestVAT', 19.5, true, true);
        Subscription25__Administration_Product__c apr = Test_Data.createAdministrationProduct(adm.Id, prd.Id, vat.Id, true);
        system.debug(apr.id);
        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', true);
        system.debug(inv.id);
        Order ord = Test_Data.createOrder(acc.Id, adm.Id, date.today().addDays(-14) , false);
        ord.Subscription25__Invoice__c = inv.Id;
        Database.insert(ord);
        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, true);

        PageReference pageRef = new PageReference('/apex/Invoice?renderType=PDF&amp;id=' + inv.Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('id', inv.Id);
        Ctrl_Invoice contr = new Ctrl_Invoice();

        Test.startTest();
        contr.getTest();
        Test.stopTest();
    }
}