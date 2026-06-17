/**
 * Created by Gerbrand Spaans (Gen25) on 14/12/2023.
 */
@IsTest
private with sharing class Test_Ctrl_GetContractProducts {
    private static final String CONTRACT_PRODUCT_FIELDS = 'Id,Name,Subscription25__Contract__c,Subscription25__Contract__r.Account.Name,Subscription25__Product__r.Name,Subscription25__Price__c,Subscription25__Status__c,Subscription25__Start_Date__c';

    @TestSetup
    private static void testSetup() {
        // Create the Account and the Contact. The Account wil have a Contract and the products.
        Account testAccount = Test_Data.createAccount('Test', '123', 'B2B', true);
        Test_Data.createContact(testAccount.Id, 'Test', '0612345678', 'dont@mail.me', true);

        // Create the VAT Rate, the Administration and the Contract. These will hold the products.
        // The VAT Rate and  Administration are needed for Subs25
        Subscription25__Administration__c testAdministration = Test_Data.createAdministration(true);
        Contract testContract = Test_Data.createContract(testAccount.Id, testAdministration.Id, true);
        Subscription25__VATRate__c testVatRate = Test_Data.createVATRate('Test VAT', 21, true, true);

        // Create 3 products, Test0, Test1 and Test2
        Integer i = 0; // increments with every prepared product
        List<Product2> testProducts = new List<Product2>{
                Test_Data.createProduct('Test' + i, 'ABC'+i, '123'+i++, 'Hardware', false),
                Test_Data.createProduct('Test' + i, 'ABC'+i, '123'+i++, 'Hardware', false),
                Test_Data.createProduct('Test' + i, 'ABC'+i, '123'+i++, 'Hardware', false)
        };
        insert testProducts;
        // Create a PriceBook Entry for each product
        insert new List<PricebookEntry>{
                Test_Data.createPricebookEntry(testProducts[0].Id, 10, false),
                Test_Data.createPricebookEntry(testProducts[1].Id, 10, false),
                Test_Data.createPricebookEntry(testProducts[2].Id, 10, false)
        };
        // Link the Products to the Administration
        insert new List<Subscription25__Administration_Product__c>{
                Test_Data.createAdministrationProduct(testAdministration.Id, testProducts[0].Id, testVatRate.Id, false),
                Test_Data.createAdministrationProduct(testAdministration.Id, testProducts[1].Id, testVatRate.Id, false),
                Test_Data.createAdministrationProduct(testAdministration.Id, testProducts[2].Id, testVatRate.Id, false)
        };
        // Create the actual Contract Products
        insert new List<Subscription25__Contract_Product__c>{
                Test_Data.createContractProduct(testContract.Id, testProducts[0].Id, false),
                Test_Data.createContractProduct(testContract.Id, testProducts[1].Id, false),
                Test_Data.createContractProduct(testContract.Id, testProducts[2].Id, false)
        };
    }

    @IsTest
    private static void testControllerFromAccount() {
        // provide the account id and get 3 contract products
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        List<Object> contractProducts = Ctrl_GetContractProducts.getContractProducts(testAccount.Id, Test_Ctrl_GetContractProducts.CONTRACT_PRODUCT_FIELDS);
        Test.stopTest();
        Assert.areEqual(3, contractProducts.size(), 'Expected all three contract products to be returned');
    }
    @IsTest
    private static void testControllerFromContract() {
        // provide the contract id and get 3 contract products
        Contract testContract = [SELECT Id FROM Contract LIMIT 1];

        Test.startTest();
        List<Object> contractProducts = Ctrl_GetContractProducts.getContractProducts(testContract.Id, Test_Ctrl_GetContractProducts.CONTRACT_PRODUCT_FIELDS);
        Test.stopTest();
        Assert.areEqual(3, contractProducts.size(), 'Expected all three contract products to be returned');
    }
    @IsTest
    private static void testControllerFromContact() {
        // provide the contact id and get 3 contract products
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        List<Object> contractProducts = Ctrl_GetContractProducts.getContractProducts(testContact.Id, Test_Ctrl_GetContractProducts.CONTRACT_PRODUCT_FIELDS);
        Test.stopTest();
        Assert.areEqual(3, contractProducts.size(), 'Expected all three contract products to be returned');
    }
    @IsTest
    private static void testExceptions() {
        // Trigger each exception once to get coverage and assert the exception logic.

        // null id error
        try {
            Ctrl_GetContractProducts.getContractProducts(null, CONTRACT_PRODUCT_FIELDS);
            Assert.fail('Method should fail with a null id');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        // invalid id error
        try {
            Ctrl_GetContractProducts.getContractProducts('NotAnId', CONTRACT_PRODUCT_FIELDS);
            Assert.fail('Method should fail with an invalid id');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        // unsupported sobject id error
        try {
            Ctrl_GetContractProducts.getContractProducts(UserInfo.getUserId(), CONTRACT_PRODUCT_FIELDS);
            Assert.fail('Method should fail with an unsupported id');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        // NULL Field list error
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        try {
            Ctrl_GetContractProducts.getContractProducts(testAccount.Id, '');
            Assert.fail('Method should fail with an invalid field list');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }
}