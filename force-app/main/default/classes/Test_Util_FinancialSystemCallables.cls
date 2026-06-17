@isTest
public with sharing class Test_Util_FinancialSystemCallables {

    @TestSetup
    private static void testSetup() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
    }

    @isTest
    private static void testAccountSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'AccountSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'syncAccount' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.AccountSync callable = new Util_FinancialSystemCallables.AccountSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
    }

    @isTest
    private static void testContactPersonSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact con = Test_Data.createContact(acc.Id, 'Test', '1234567890', 'ran@gen25.com', true);
        AccountContactRelation rel = [
            SELECT Id, FinancialIdContact__c, Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone
            FROM AccountContactRelation
            WHERE AccountId = :acc.Id
                AND ContactId = :con.Id
        ];

        String action = 'ContactPersonSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'contactPerson' => rel,
            'syncContact' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.ContactPersonSync callable = new Util_FinancialSystemCallables.ContactPersonSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveContactPerson'));
    }

    @isTest
    private static void testShippingAddressSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'ShippingAddressSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'syncShippingAddress' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.ShippingAddressSync callable = new Util_FinancialSystemCallables.ShippingAddressSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
    }

    @isTest
    private static void testBillingAddressSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'BillingAddressSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'syncBillingAddress' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.BillingAddressSync callable = new Util_FinancialSystemCallables.BillingAddressSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
    }

    @isTest
    private static void testVisitingAddressSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'VisitingAddressSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'syncVisitingAddress' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.VisitingAddressSync callable = new Util_FinancialSystemCallables.VisitingAddressSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
    }

    @isTest
    private static void testBankAccountSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'BankAccountSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'syncBankAccount' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.BankAccountSync callable = new Util_FinancialSystemCallables.BankAccountSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
    }

    @isTest
    private static void testMandateSync() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'MandateSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc,
            'syncMandate' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.MandateSync callable = new Util_FinancialSystemCallables.MandateSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
    }

    @isTest
    private static void testGetDebtorNumber() {

        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);

        String action = 'GetDebtorNumber';
        Map<String, Object> inputs = new Map<String, Object> {
            'accountRecord' => acc
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.GetDebtorNumber callable = new Util_FinancialSystemCallables.GetDebtorNumber();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAccount'));
        Assert.isNotNull(acc.FinancialDebtorNumber__c);
    }

    @isTest
    private static void testGetProductIdsFinancialSystem() {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__VATRate__c testVatRate = Test_Data.createVATRate('Test VAT', 21, true, true);
        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);
        Subscription25__Debtor_Number__c deb = Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
        Order ord = Test_Data.createOrder(acc.Id, admin.Id, Date.today().addDays(-14), true);

        Product2 prd = Test_Data.createProduct('MiTest', 'code', '1-sv-1', 'Subscription', true);
        Subscription25__Administration_Product__c adminProduct = Test_Data.createAdministrationProduct(admin.Id, prd.Id, testVatRate.Id, true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, true);

        String action = 'GetProductIdsFinancialSystem';
        Map<String, Object> inputs = new Map<String, Object> {
            'orderRecord' => ord
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.GetProductIdsFinancialSystem callable = new Util_FinancialSystemCallables.GetProductIdsFinancialSystem();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveAdminProducts'));
    }

    @isTest
    private static void testOrderSync() {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__VATRate__c testVatRate = Test_Data.createVATRate('Test VAT', 21, true, true);
        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);
        Subscription25__Debtor_Number__c deb = Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
        Opportunity opp = Test_Data.createOpportunity(acc.Id, null, 'Test Opp', true);
        Order ord = Test_Data.createOrder(acc.Id, admin.Id, Date.today().addDays(-14), false);
        ord.OpportunityId = opp.Id;
        Database.insert(ord);

        // Create billing contact
        Contact con = Test_Data.createContact(acc.Id, 'Test', '1234567890', 'ran@gen25.com', true);
        AccountContactRelation rel = [
            SELECT Id, FinancialIdContact__c, Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone
            FROM AccountContactRelation
            WHERE AccountId = :acc.Id
                AND ContactId = :con.Id
        ];
        rel.FinancialIdContact__c = '123';
        Database.update(rel);

        Product2 prd = Test_Data.createProduct('MiTest', 'code', '1-sv-1', 'Subscription', true);
        Subscription25__Administration_Product__c adminProduct = Test_Data.createAdministrationProduct(admin.Id, prd.Id, testVatRate.Id, true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, true);

        String action = 'OrderSync';
        Map<String, Object> inputs = new Map<String, Object> {
            'orderRecord' => ord,
            'accountRecord' => acc,
            'contactPerson' => rel,
            'syncOrder' => true
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.OrderSync callable = new Util_FinancialSystemCallables.OrderSync();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isTrue((Boolean) inputs.get('saveOrder'));
    }

    @isTest
    private static void testGetSalesOrderLines() {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__VATRate__c testVatRate = Test_Data.createVATRate('Test VAT', 21, true, true);
        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);
        Subscription25__Debtor_Number__c deb = Test_Data.createDebtorNumber(admin.Id, acc.Id, true);

        Product2 prd = Test_Data.createProduct('MiTest', 'code', '1-sv-1', 'Subscription', true);
        Subscription25__Administration_Product__c adminProduct = Test_Data.createAdministrationProduct(admin.Id, prd.Id, testVatRate.Id, false);
        adminProduct.Exact_Id__c = '70c625f4-b8c9-4aa8-9272-06ac96d6a902';
        Database.insert(adminProduct);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);

        Contract contr = Test_Data.createContract(acc.Id, admin.Id, true);
        Test_Data.createContractProduct(contr.Id, prd.Id, true);
        Order ord = Test_Data.createOrder(acc.Id, admin.Id, Date.today().addDays(-14), false);
        ord.Contract__c = contr.Id;
        Database.insert(ord);
        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, true);

        String action = 'GetSalesOrderLines';
        Map<String, Object> inputs = new Map<String, Object> {
            'orderRecord' => ord
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.GetSalesOrderLines callable = new Util_FinancialSystemCallables.GetSalesOrderLines();
        callable.call(action, inputs);
        Test.stopTest();

        Assert.isNotNull(inputs.get('contractProducts'));
        Assert.isTrue((Boolean) inputs.get('saveContractProducts'));
    }

    @isTest
    private static void testGetInvoiceDetails() {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__VATRate__c testVatRate = Test_Data.createVATRate('Test VAT', 21, true, true);
        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);
        Subscription25__Debtor_Number__c deb = Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
        Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', true);

        String action = 'GetInvoiceDetails';
        Map<String, Object> inputs = new Map<String, Object> {
            'getInvoiceDetails' => true,
            'invoice' => inv
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.GetInvoiceDetails callable = new Util_FinancialSystemCallables.GetInvoiceDetails();
        callable.call(action, inputs);
        Test.stopTest();

        System.debug(inputs);
        System.debug(inputs.get('saveInvoice'));
        Assert.isTrue(inputs.containsKey('saveInvoice'));
        Assert.isTrue((Boolean) inputs.get('saveInvoice'));
    }

    @isTest
    private static void testFinalizeInvoice() {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__VATRate__c testVatRate = Test_Data.createVATRate('Test VAT', 21, true, true);
        Account acc = Test_Data.createAccount('Test', '12', 'B2B', true);
        Subscription25__Debtor_Number__c deb = Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
        Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', true);

        String action = 'FinalizeInvoice';
        Map<String, Object> inputs = new Map<String, Object> {
            'finalizeInvoice' => true,
            'invoice' => inv
        };

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test.startTest();
        Util_FinancialSystemCallables.FinalizeInvoice callable = new Util_FinancialSystemCallables.FinalizeInvoice();
        callable.call(action, inputs);
        Test.stopTest();

        System.debug(inputs);
        System.debug(inputs.get('saveInvoice'));
        Assert.isTrue(inputs.containsKey('saveInvoice'));
        Assert.isTrue((Boolean) inputs.get('saveInvoice'));
    }
}