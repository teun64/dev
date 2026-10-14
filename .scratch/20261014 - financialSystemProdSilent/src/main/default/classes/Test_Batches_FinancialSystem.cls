@IsTest
public with sharing class Test_Batches_FinancialSystem  {
    
        // invoice finalisation tests: Test_Util_FinancialSystem_Invoice
    
        @IsTest
        private static void testActivateDraftContractProducts_NoDebtorNumber_SkipsWithoutLog() {
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', true);
            Contact con = Test_Data.createContact(acc.Id, 'Test', null, 'ran@gen25.com', true);
            Contract contr = Test_Data.createContract(acc.Id, admin.Id, true);

            Product2 prod = Test_Data.createProduct('Test Product', 'Tst_Prod', '123', 'Package', true);
            PricebookEntry entry = Test_Data.createPricebookEntry(prod.Id, 123, true);
            Subscription25__VATRate__c vatRate = Test_Data.createVATRate('Test', 99.9, true, true);
            Subscription25__Administration_Product__c adminProd = Test_Data.createAdministrationProduct(admin.Id, prod.Id, vatRate.Id, true);
            Subscription25__Contract_Product__c cp = Test_Data.createContractProduct(contr.Id, prod.Id, false);
            cp.Subscription25__Status__c = 'Draft';
            Database.insert(cp);

            insert new Subscription25__Schedulable_Class__c(Name = 'Batch_ActivateDraftContractProducts');

            Test.startTest();
            Batch_ActivateDraftContractProducts batch = new Batch_ActivateDraftContractProducts();
            Database.executeBatch(batch);
            Test.stopTest();

            cp = [SELECT Id, Subscription25__Status__c FROM Subscription25__Contract_Product__c WHERE Id = :cp.Id];
            // Assert Contract Product is left untouched, not activated
            System.assertEquals('Draft', cp.Subscription25__Status__c, 'Contract Product should not be activated without a debtor number');

            // deliberately not logged: it recurs every run until the account gets a debtor number (Event_Log__c flood, 3c8fdc9)
            System.assertEquals(0, [SELECT COUNT() FROM Event_Log__c WHERE Context_Id__c = :acc.Id], 'A skipped account is not logged');
        }
    
        @IsTest
        private static void testActivateDraftContractProducts_ActivatedContractProduct() {
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', false);
            acc.FinancialDebtorNumber__c = 'FDN';
            Database.insert(acc);
            Contract contr = Test_Data.createContract(acc.Id, admin.Id, true);
    
            Product2 prod = Test_Data.createProduct('Test Product', 'Tst_Prod', '123', 'Package', true);
            PricebookEntry entry = Test_Data.createPricebookEntry(prod.Id, 123, true);
            Subscription25__VATRate__c vatRate = Test_Data.createVATRate('Test', 99.9, true, true);
            Subscription25__Administration_Product__c adminProd = Test_Data.createAdministrationProduct(admin.Id, prod.Id, vatRate.Id, true);
            Subscription25__Contract_Product__c cp = Test_Data.createContractProduct(contr.Id, prod.Id, false);
            cp.Subscription25__Status__c = 'Draft';
            Database.insert(cp);
    
            insert new Subscription25__Schedulable_Class__c(Name = 'Batch_ActivateDraftContractProducts');

            Test.startTest();
            Batch_ActivateDraftContractProducts batch = new Batch_ActivateDraftContractProducts();
            Database.executeBatch(batch);
            Test.stopTest();

            cp = [SELECT Id, Subscription25__Status__c FROM Subscription25__Contract_Product__c WHERE Id = :cp.Id];
            // Assert Contract Product should be activated
            System.assertEquals('Activated', cp.Subscription25__Status__c, 'Contract Product should be activated');
        }
    }