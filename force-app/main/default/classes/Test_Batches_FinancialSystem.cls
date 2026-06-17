@IsTest
public with sharing class Test_Batches_FinancialSystem  {
    
        @TestSetup
        static void testSetup() {
            Test_DataIntegrationDefinition.createFinancialSystemAccountSyncDefinitions();
            Test_DataIntegrationDefinition.createFinancialSystemFinalizeInvoiceDefinitions();
        }
    
        @IsTest
        private static void testBatchFinalizeInvoice_FinalizeInvoice() {
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', true);
            Subscription25__Invoice__c invoice = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
            invoice.Subscription25__Exact_Order_Number__c = '123';
            Database.insert(invoice);
    
            Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
            Test.startTest();
            Batch_FinalizeInvoices batch = new Batch_FinalizeInvoices();
            Database.executeBatch(batch);
            Test.stopTest();
    
            // Validate log for errors
            List<Event_Log__c> logs = [
                SELECT Id, Integration_Status__c, Result_Status__c, Status__c, Message__c
                FROM Event_Log__c
            ];
            for (Event_Log__c log : logs) {
                if (log.Status__c != 'COMPLETED' && log.Status__c != 'PROCESSED') {
                    System.debug(JSON.serialize(log));
                    System.assert(false, log.Message__c);
                }
            }
            // Assert all processes were called
            System.assertEquals(5, logs.size(), 'Expected amount of logs');
    
            invoice = [SELECT Id, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c FROM Subscription25__Invoice__c WHERE Id = :invoice.Id];
            System.assert(invoice.Subscription25__Finalized_In_Exact__c, 'Invoice should be set as printed');
        }
    
        @IsTest
        private static void testBatchFinalizeInvoice_LoadInvoiceNumber_NotPrinted() {
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', true);
            Subscription25__Invoice__c invoice = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
            invoice.Subscription25__Exact_Order_Number__c = '123';
            invoice.Subscription25__Finalized_In_Exact__c = true;
            Database.insert(invoice);
    
            Test_Mocks.ExactMock mock = new Test_Mocks.ExactMock();
            mock.invoicePrinted = false;
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            Batch_FinalizeInvoices batch = new Batch_FinalizeInvoices();
            Database.executeBatch(batch);
            Test.stopTest();
    
            invoice = [SELECT Id, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c FROM Subscription25__Invoice__c WHERE Id = :invoice.Id];
            System.assert(!invoice.Subscription25__Finalized_In_Exact__c, 'Invoice should not be set as printed');
        }
    
        @IsTest
        private static void testBatchFinalizeInvoice_LoadInvoiceNumber_Succes() {
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', true);
            Subscription25__Invoice__c invoice = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
            invoice.Subscription25__Exact_Order_Number__c = '123';
            invoice.Subscription25__Finalized_In_Exact__c = true;
            Database.insert(invoice);
    
            Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
            Test.startTest();
            Batch_FinalizeInvoices batch = new Batch_FinalizeInvoices();
            Database.executeBatch(batch);
            Test.stopTest();
    
            invoice = [SELECT Id, Subscription25__Finalized_In_Exact__c, Subscription25__Invoice_Number__c, FinancialId__c FROM Subscription25__Invoice__c WHERE Id = :invoice.Id];
            System.assert(invoice.Subscription25__Finalized_In_Exact__c, 'Invoice should be set as printed');
            System.assertEquals('TTT123', invoice.Subscription25__Invoice_Number__c, 'Invoice number not set');
            System.assertEquals('invoice_sync', invoice.FinancialId__c, 'Invoice ID not set');
        }
    
        @IsTest
        private static void testBatchFinalizeInvoice_ExactLimitsReached() {
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', true);
            Subscription25__Invoice__c invoice = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
            invoice.Subscription25__Exact_Order_Number__c = '123';
            Database.insert(invoice);
    
            // Log no remaining calls
            Util_FinancialSystem.Limits l = Util_FinancialSystem.getLimits(admin);
            l.minutelyLimit = 0;
            l.minutelyRemaining = 0;
            l.minutelyReset = DateTime.now().addYears(10000).getTime();
            l.dailyLimit = 0;
            l.dailyRemaining = 0;
            l.dailyReset = DateTime.now().addYears(10000).getTime();
            l.consecutiveErrors = 0;
            Cache.Org.put(Util_FinancialSystem.EXACT_LIMIT_CACHE_NAME, l);
    
            Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
            Test.startTest();
            Batch_FinalizeInvoices batch = new Batch_FinalizeInvoices();
            Database.executeBatch(batch);
            Test.stopTest();
    
            invoice = [SELECT Id, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c FROM Subscription25__Invoice__c WHERE Id = :invoice.Id];
            // Assert invoice not processed
            System.assert(!invoice.Subscription25__Finalized_In_Exact__c, 'Invoice should not be processed');
        }
    
        @IsTest
        private static void testActivateDraftContractProducts_SyncAccount() {
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
    
            Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
            Test.startTest();
            Batch_ActivateDraftContractProducts batch = new Batch_ActivateDraftContractProducts();
            Database.executeBatch(batch);
            Test.stopTest();
    
            cp = [SELECT Id, Subscription25__Contract__r.Account.FinancialIdAccount__c FROM Subscription25__Contract_Product__c WHERE Id = :cp.Id];
            // Assert account should be synced
            System.assert(!String.isBlank(cp.Subscription25__Contract__r.Account.FinancialIdAccount__c), 'Account should be synced');
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
    
            Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
            Test.startTest();
            Batch_ActivateDraftContractProducts batch = new Batch_ActivateDraftContractProducts();
            Database.executeBatch(batch);
            Test.stopTest();
    
            cp = [SELECT Id, Subscription25__Status__c FROM Subscription25__Contract_Product__c WHERE Id = :cp.Id];
            // Assert Contract Product should be activated
            System.assertEquals('Activated', cp.Subscription25__Status__c, 'Contract Product should be activated');
        }
    
        @IsTest
        private static void testActivateDraftContractProducts_ExactLimitsReached() {
            // Set u
            Subscription25__Administration__c admin = Test_Data.createAdministration(true);
            Account acc = Test_Data.createAccount('Test Account', '12345', 'B2B', true);
            Contract contr = Test_Data.createContract(acc.Id, admin.Id, true);
    
            Product2 prod = Test_Data.createProduct('Test Product', 'Tst_Prod', '123', 'Package', true);
            PricebookEntry entry = Test_Data.createPricebookEntry(prod.Id, 123, true);
            Subscription25__VATRate__c vatRate = Test_Data.createVATRate('Test', 99.9, true, true);
            Subscription25__Administration_Product__c adminProd = Test_Data.createAdministrationProduct(admin.Id, prod.Id, vatRate.Id, true);
            Subscription25__Contract_Product__c cp = Test_Data.createContractProduct(contr.Id, prod.Id, false);
            cp.Subscription25__Status__c = 'Draft';
            Database.insert(cp);
    
            // Log no remaining calls
            Util_FinancialSystem.Limits l = Util_FinancialSystem.getLimits(admin);
            l.minutelyLimit = 0;
            l.minutelyRemaining = 0;
            l.minutelyReset = DateTime.now().addYears(10000).getTime();
            l.dailyLimit = 0;
            l.dailyRemaining = 0;
            l.dailyReset = DateTime.now().addYears(10000).getTime();
            l.consecutiveErrors = 0;
            Cache.Org.put(Util_FinancialSystem.EXACT_LIMIT_CACHE_NAME, l);
    
            Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
            Test.startTest();
            Batch_ActivateDraftContractProducts batch = new Batch_ActivateDraftContractProducts();
            Database.executeBatch(batch);
            Test.stopTest();
    
            cp = [SELECT Id, Subscription25__Contract__r.Account.FinancialIdAccount__c FROM Subscription25__Contract_Product__c WHERE Id = :cp.Id];
            // Assert account should not be synced
            System.assert(String.isBlank(cp.Subscription25__Contract__r.Account.FinancialIdAccount__c), 'Account should not be synced');
        }
    }