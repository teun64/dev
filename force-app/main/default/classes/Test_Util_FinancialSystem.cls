@IsTest
private class Test_Util_FinancialSystem {

    @TestSetup
    static void testSetup() {
        Test_DataIntegrationDefinition.createFinancialSystemContactSyncDefinitions();
        Test_DataIntegrationDefinition.createFinancialSystemAccountSyncDefinitions();
        Test_DataIntegrationDefinition.createFinancialSystemOrderSyncDefinitions();
    }

    @IsTest
    private static void testContactSync() {
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test_Data.createOAuthToken(true);
        Test_Data.createExactSettings('123', true);

        Subscription25__Administration__c adm = Test_Data.createAdministration(true);

        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
        Database.insert(ers);

        Account acct1 = Test_Data.createAccount('Test', '11', 'B2B', true);

        // Create a contact linked to the Account, and relink it to that same account using more lookups.
        Contact cont = Test_Data.createContact(acct1.Id, 'Test', '1234567890', 'ran@gen25.com', true);
        acct1.Contact_person__c = cont.Id;
        acct1.MI_Administrator__c = cont.Id;
        acct1.Contact_Billing__c = cont.Id;
        acct1.Contact_Shipping__c = cont.Id;
        acct1.FinancialDebtorNumber__c = 'TEST_11';
        Database.update(acct1);

        AccountContactRelation rel = [
            SELECT Id
            FROM AccountContactRelation
            WHERE AccountId = :acct1.Id
                AND ContactId = :cont.Id
        ];

        Test.startTest();
        Inv_Integration.Request request = new Inv_Integration.Request();
        request.integrationDefinitionName = 'Financial System - Contact Sync';
        request.relatedRecordId = rel.Id;
        List<Inv_Integration.Result> results = Inv_Integration.execute(new List<Inv_Integration.Request>{request});
        Test.stopTest();

        System.debug([SELECT Id, Status__c FROM Event_Log__c]);
        System.debug([SELECT Id, Status__c FROM OAuth_Log__c]);

        // Validate produced data
        AccountContactRelation assertRel = [SELECT Id, FinancialIdContact__c FROM AccountContactRelation WHERE Id = :rel.Id];
        System.assertEquals('contact_sync', assertRel.FinancialIdContact__c);
    }

    @IsTest
    private static void testAccountSyncCreate(){
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test_Data.createOAuthToken(true);
        Test_Data.createExactSettings('123', true);

        Subscription25__Administration__c adm = Test_Data.createAdministration(true);

        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
        Database.insert(ers);

        Account acct1 = Test_Data.createAccount('Test', '11', 'B2B', true);
        acct1.VisitingAddress__Street__s = 'Naarderstraat 82';
        acct1.VisitingAddress__PostalCode__s = '1251 BH';
        acct1.VisitingAddress__City__s = 'Laren';
        acct1.VisitingAddress__CountryCode__s = 'NL';

        // Create a contact linked to the Account, and relink it to that same account using more lookups.
        Contact cont = Test_Data.createContact(acct1.Id, 'Test', '1234567890', 'ran@gen25.com', true);
        acct1.Contact_person__c = cont.Id;
        acct1.MI_Administrator__c = cont.Id;
        acct1.Contact_Billing__c = cont.Id;
        acct1.Contact_Shipping__c = cont.Id;
        acct1.FinancialDebtorNumber__c = 'TEST_11';
        Database.update(acct1);

        AccountContactRelation rel = [
            SELECT Id
            FROM AccountContactRelation
            WHERE AccountId = :acct1.Id
                AND ContactId = :cont.Id
        ];
        rel.Roles = 'Billing';
        Database.update(rel);

        Test.startTest();
        Util_FinancialSystem.syncAccountAsync(acct1.Id);
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
        // Assert all 11 processes were called
        System.assertEquals(11, logs.size(), 'Expected 11 logs');

        // Validate produced data
        Account assertAcct = [SELECT Id, FinancialIdAccount__c, FinancialIdShippingAddress__c, FinancialIdBankMandate__c FROM Account WHERE Id = :acct1.Id];
        System.assertEquals('account_sync', assertAcct.FinancialIdAccount__c);
        System.assertEquals('address_sync', assertAcct.FinancialIdShippingAddress__c);
        System.assertEquals('mandate_sync', assertAcct.FinancialIdBankMandate__c);
        // Validate produced data
        AccountContactRelation assertRel = [SELECT Id, FinancialIdContact__c FROM AccountContactRelation WHERE ContactId = :cont.Id];
        System.assertEquals('contact_sync', assertRel.FinancialIdContact__c);
    }

    @IsTest
    private static void testAccountSyncUpdate(){
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test_Data.createOAuthToken(true);
        Test_Data.createExactSettings('123', true);

        Subscription25__Administration__c adm = Test_Data.createAdministration(true);

        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
        Database.insert(ers);

        Account acct1 = Test_Data.createAccount('Test', '11', 'B2B', true);
        acct1.VisitingAddress__Street__s = 'Naarderstraat 82';
        acct1.VisitingAddress__PostalCode__s = '1251 BH';
        acct1.VisitingAddress__City__s = 'Laren';
        acct1.VisitingAddress__CountryCode__s = 'NL';
        acct1.FinancialIdAccount__c = '123';
        acct1.FinancialIdBankAccount__c = '123';
        acct1.FinancialIdBankMandate__c = '123';

        // Create a contact linked to the Account, and relink it to that same account using more lookups.
        Contact cont = Test_Data.createContact(acct1.Id, 'Test', '1234567890', 'ran@gen25.com', true);
        acct1.Contact_person__c = cont.Id;
        acct1.MI_Administrator__c = cont.Id;
        acct1.Contact_Billing__c = cont.Id;
        acct1.Contact_Shipping__c = cont.Id;
        acct1.FinancialDebtorNumber__c = 'TEST_11';
        Database.update(acct1);

        Test.startTest();
        Util_FinancialSystem.syncAccountAsync(acct1.Id);
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
        // Assert all 11 processes were called
        System.assertEquals(11, logs.size(), 'Expected 11 logs');

        // Validate produced datas
        Account assertAcct = [SELECT Id, FinancialIdAccount__c, FinancialIdBillingAddress__c FROM Account WHERE Id = :acct1.Id];
        System.assertEquals('123', assertAcct.FinancialIdAccount__c);
    }

    @isTest
    private static void testOrderSync(){
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
        Test_Data.createOAuthToken(true);
        Test_Data.createExactSettings('123', true);

		Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = admin.Id, Classification__c = 'SC', Sales_Channel__c = 'Moving Intelligence', Exact_ID__c = 'Sales_Channel');
        Database.insert(ers);

        ers = new Exact_Relation_Setting__c(Administration__c = admin.Id, Classification__c = 'WH', Sales_Channel__c = 'Moving Intelligence', Exact_ID__c = 'Warehouse');
        Database.insert(ers);

		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'AccountContact', '1234567890', 'ran@123.com', true);
        AccountContactRelation rel = [SELECT Id, Roles FROM AccountContactRelation WHERE AccountId = :acct.Id AND ContactId = :cont.Id];
        rel.Roles = 'Billing';
        Database.update(rel);
        acct.Contact_person__c = cont.Id;
        acct.MI_Administrator__c = cont.Id;
        acct.Contact_Shipping__c = cont.Id;
        acct.Contact_Billing__c = cont.Id;
        Database.update(acct);

        // Update Account Contact Relation
        AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acct.Id AND ContactId = :cont.Id];
        acr.Roles = 'Main;Billing;Shipping;Administrator;Service';
        Database.update(acr);

        // Create products
        Product2 hwProd = Test_Data.createProduct('HardwareProduct', 'code', '1-hw-1', 'Hardware', true);
        PricebookEntry hwPBE = Test_Data.createPricebookEntry(hwProd.Id, 200, true);

        Product2 sProd = Test_Data.createProduct('SubscriptionPrepaid', 'code.P', '1-in-1', 'SubscriptionP', true);
        PricebookEntry sPBE = Test_Data.createPricebookEntry(sProd.Id, 10, true);
        Subscription25__Administration_Product__c hwAdminProd = Test_Data.createAdministrationProduct(admin.Id, hwProd.Id, vr.Id, true);
        Subscription25__Administration_Product__c sAdminProd = Test_Data.createAdministrationProduct(admin.Id, sProd.Id, vr.Id, false);
        sAdminProd.Exact_Id__c = 'item_sync';
        Database.insert(sAdminProd);

        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);
        Contact salesCont = Test_Data.createContact(acct.Id, 'SalesContact', '0987654321', 'xel@321.com', true);

        // Create opportunity
        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        opp.Installation_Notes__c = 'installation notes';
        opp.Sales_Contact__c = salesCont.Id;
        opp.Payment_Method__c = 'I8';
        opp.Sales_Channel__c = 'Moving Intelligence';
        Database.insert(opp);

        // Create contract (with subscription items)
        Contract contr = Test_Data.createContract(acct.Id, admin.Id, true);
        Subscription25__Contract_Product__c hwContrProd = Test_Data.createContractProduct(contr.Id, hwProd.Id, false);
        Subscription25__Contract_Product__c sContrProd = Test_Data.createContractProduct(contr.Id, sProd.Id, false);
        Database.insert(new List<Subscription25__Contract_Product__c> { hwContrProd, sContrProd });

        // Create order
		Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
		ord.OpportunityId = opp.Id;
        ord.Contract__c = contr.Id;
        ord.Payment_Method__c = 'I8';
        ord.Sales_Channel__c = 'Moving Intelligence';
		Database.insert(ord);

        Test_Data.createOrderItem(ord.Id, hwPBE.Id, 1, true);
		OrderItem oi = Test_Data.createOrderItem(ord.Id, sPBE.Id, 1, false);
        oi.Partner_Code__c = '1A2B3C4D5E6F7';
        Database.insert(oi);
		OrderItem oi2 = Test_Data.createOrderItem(ord.Id, hwPBE.Id, 1, false);
        oi2.Partner_Code__c = '1A2B3C4D5E6F8';
        Database.insert(oi2);

        Test.startTest();
        Util_FinancialSystem.syncOrderAsync(ord.Id);
        Test.stopTest();


        // Validate log for errors
        List<Event_Log__c> logs = [
            SELECT Id, Action__c, Status__c, Message__c, Stack_Trace__c
            FROM Event_Log__c
        ];
        System.debug(JSON.serialize(logs));
        for (Event_Log__c log : logs) {
            if (log.Status__c != 'COMPLETED' && log.Status__c != 'PROCESSED') {
                System.debug(JSON.serialize(log));
                System.assert(false, log.Message__c);
            }
        }
        // Assert all 11 processes were called
        System.assertEquals(7, logs.size(), 'Expected 7 logs');

        // Validate data results
        Subscription25__Administration_Product__c hwAdminProdResult = [Select Exact_Id__c from Subscription25__Administration_Product__c where Id = :hwAdminProd.Id];
        Order orderResult =  [Select Exact_Id__c, Exact_Order_Number__c from Order where Id = :ord.Id];
        System.assertEquals('70c625f4-b8c9-4aa8-9272-06ac96d6a901', hwAdminProdResult.Exact_Id__c);
        System.assertEquals('item_sync', sAdminProd.Exact_Id__c);
        System.assertEquals('12345', orderResult.Exact_Order_Number__c);
        System.assertEquals('order_sync', orderResult.Exact_Id__c);

        System.assertEquals('70c625f4-b8c9-4aa8-9272-06ac96d6a901', [SELECT FinancialIdProduct__c FROM Subscription25__Contract_Product__c WHERE Id = :hwContrProd.Id].FinancialIdProduct__c);
        System.assertEquals('item_sync', [SELECT FinancialIdProduct__c FROM Subscription25__Contract_Product__c WHERE Id = :sContrProd.Id].FinancialIdProduct__c);
    }

    @isTest
    private static void testLetterCodeConversion(){
        Account acct = Test_Data.createAccount('Test', '13', 'B2B', false);
        acct.WSONE_DATA_Billing_Country__c = 'NLD';
        acct.WSONE_DATA_Shipping_Country__c = 'NLD';

        Database.insert(acct);

        System.assertEquals('NL', [SELECT BillingCountryCode FROM Account WHERE Id = :acct.Id].BillingCountryCode);
    }

    @isTest
    private static void testInvoice() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'ran@gen25.com', true);
        Product2 prod = Test_Data.createProduct('name', 'code.P', '1-in-1', 'SubscriptionP', true);
        //prod.Is_Installation_Product__c = true;
        //Database.insert(prod);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 10, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vr.Id, true);
        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        opp.Installation_Notes__c = 'installation notes';
        opp.Sales_Contact__c = cont.Id;

        Database.insert(opp);

		Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
		ord.OpportunityId = opp.Id;
        ord.Payment_Method__c = 'I8';
		Database.insert(ord);

		OrderItem oi = Test_Data.createOrderItem(ord.Id, pbe.Id, 100, false);
        oi.Partner_Code__c = '1A2B3C4D5E6F7';
        Database.insert(oi);

        Subscription25__Invoice__c inv = Test_data.createInvoice(admin.Id, acct.Id, 'Draft', true);

        ord.subscription25__invoice__c = inv.id;
        Database.update(ord);

        inv.Subscription25__Status__c = 'Finalized';
        inv.Subscription25__Exact_Order_Number__c = '55';
        Database.update(inv);

        Test.starttest();
        Util_FinancialSystem.finalizeInvoice(inv.Id);
        Util_FinancialSystem.loadInvoiceNumber(inv.Id);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Subscription25__Invoice__c WHERE Id = :inv.Id]);
    }

    // @IsTest
    // private static void testAccountSyncCreate(){
    //     Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
    //     Test_Data.createOAuthToken(true);
    //     Test_Data.createExactSettings('123', true);

    //     Subscription25__Administration__c adm = Test_Data.createAdministration(true);

    //     Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
    //     Database.insert(ers);

    //     Account acct1 = Test_Data.createAccount('Test', '11', 'B2B', true);
    //     acct1.VisitingAddress__Street__s = 'Naarderstraat 82';
    //     acct1.VisitingAddress__PostalCode__s = '1251 BH';
    //     acct1.VisitingAddress__City__s = 'Laren';
    //     acct1.VisitingAddress__CountryCode__s = 'NL';

    //     // Create a contact linked to the Account, and relink it to that same account using more lookups.
    //     Contact cont = Test_Data.createContact(acct1.Id, 'Test', '1234567890', 'lex@gen25.com', true);
    //     acct1.Contact_person__c = cont.Id;
    //     acct1.MI_Administrator__c = cont.Id;
    //     acct1.Contact_Billing__c = cont.Id;
    //     acct1.Contact_Shipping__c = cont.Id;
    //     acct1.FinancialDebtorNumber__c = 'TEST_11';
    //     Database.update(acct1);

    //     Test.startTest();
    //     Util_FinancialSystem.syncAccountAsync(acct1.Id);
    //     Test.stopTest();

    //     // Validate log for errors
    //     List<Event_Log__c> logs = [
    //         SELECT Id, Integration_Status__c, Result_Status__c, Message__c
    //         FROM Event_Log__c
    //     ];
    //     System.assertEquals(1, logs.size(), 'Expected single log');
    //     System.assertEquals('PROCESSED', logs.get(0).Integration_Status__c, logs.get(0).Message__c ?? 'No message');
    //     System.assertEquals('COMPLETED', logs.get(0).Result_Status__c, logs.get(0).Message__c ?? 'No message');

    //     // Validate produced data
    //     Account assertAcct = [SELECT Id, FinancialIdAccount__c, FinancialIdBillingAddress__c FROM Account WHERE Id = :acct1.Id];
    //     System.assertEquals('account_sync', assertAcct.FinancialIdAccount__c);
    //     System.assertEquals('address_sync', assertAcct.FinancialIdBillingAddress__c);
    // }

    // @IsTest
    // private static void testAccountSyncUpdate(){
    //     Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
    //     Test_Data.createOAuthToken(true);
    //     Test_Data.createExactSettings('123', true);

    //     Subscription25__Administration__c adm = Test_Data.createAdministration(true);

    //     Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
    //     Database.insert(ers);

    //     Account acct1 = Test_Data.createAccount('Test', '11', 'B2B', true);
    //     acct1.VisitingAddress__Street__s = 'Naarderstraat 82';
    //     acct1.VisitingAddress__PostalCode__s = '1251 BH';
    //     acct1.VisitingAddress__City__s = 'Laren';
    //     acct1.VisitingAddress__CountryCode__s = 'NL';
    //     acct1.FinancialIdAccount__c = '123';
    //     acct1.FinancialIdBankAccount__c = '123';
    //     acct1.FinancialIdBankMandate__c = '123';

    //     // Create a contact linked to the Account, and relink it to that same account using more lookups.
    //     Contact cont = Test_Data.createContact(acct1.Id, 'Test', '1234567890', 'lex@gen25.com', true);
    //     acct1.Contact_person__c = cont.Id;
    //     acct1.MI_Administrator__c = cont.Id;
    //     acct1.Contact_Billing__c = cont.Id;
    //     acct1.Contact_Shipping__c = cont.Id;
    //     acct1.FinancialDebtorNumber__c = 'TEST_11';
    //     Database.update(acct1);

    //     Test.startTest();
    //     Util_FinancialSystem.syncAccountAsync(acct1.Id);
    //     Test.stopTest();

    //     // Validate log for errors
    //     List<Event_Log__c> logs = [
    //         SELECT Id, Integration_Status__c, Result_Status__c, Message__c
    //         FROM Event_Log__c
    //     ];
    //     System.assertEquals(1, logs.size(), 'Expected single log');
    //     System.assertEquals('PROCESSED', logs.get(0).Integration_Status__c, logs.get(0).Message__c ?? 'No message');
    //     System.assertEquals('COMPLETED', logs.get(0).Result_Status__c, logs.get(0).Message__c ?? 'No message');

    //     // Validate produced datas
    //     Account assertAcct = [SELECT Id, FinancialIdAccount__c, FinancialIdBillingAddress__c FROM Account WHERE Id = :acct1.Id];
    //     System.assertEquals('123', assertAcct.FinancialIdAccount__c);
    // }

    // @isTest
    // private static void testAutomaticAccountSync(){
	//     //create an account and an opportunity, set the opportunity to closed won, and assert that the account was synced
	//     Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
    //     Test_Data.createOAuthToken(true);
    //     Test_Data.createExactSettings('123', true);

    //     Test_Data.createAdministration(true);

    //     Account acct = Test_Data.createAccount('Test', '11', 'B2B', false);
    //     acct.Reseller_Name__c = '1';
    //     Database.insert(acct);
    //     Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
    //     Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', true);

    //     Test.startTest();
    //     opp.StageName = 'Closed Won';
    //     Database.update(opp);
    //     Test.stopTest();

    //     /*Subscription25__Debtor_Number__c debNr = [SELECT Id, FinancialIdAccount__c, Exact_Billing_Address_ID__c FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :acct.Id];
    //     System.assertEquals('account_sync', debNr.FinancialIdAccount__c);
    //     System.assertEquals('address_sync', debNr.Exact_Billing_Address_ID__c);*/
    // }

    // @isTest
    // private static void testOrderSync(){
    //     Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
    //     Test_Data.createOAuthToken(true);
    //     Test_Data.createExactSettings('123', true);

	// 	Subscription25__Administration__c admin = Test_Data.createAdministration(true);

    //     Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = admin.Id, Classification__c = 'SC', Sales_Channel__c = 'Moving Intelligence', Exact_ID__c = 'Sales_Channel');
    //     Database.insert(ers);

    //     ers = new Exact_Relation_Setting__c(Administration__c = admin.Id, Classification__c = 'WH', Sales_Channel__c = 'Moving Intelligence', Exact_ID__c = 'Warehouse');
    //     Database.insert(ers);

	// 	Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
    //     Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
    //     Contact cont = Test_Data.createContact(acct.Id, 'AccountContact', '1234567890', 'lex@123.com', true);
    //     acct.Contact_person__c = cont.Id;
    //     acct.MI_Administrator__c = cont.Id;
    //     acct.Contact_Shipping__c = cont.Id;
    //     acct.Contact_Billing__c = cont.Id;
    //     Database.update(acct);

    //     // Update Account Contact Relation
    //     AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acct.Id AND ContactId = :cont.Id];
    //     acr.Roles = 'Main;Billing;Shipping;Administrator;Service';
    //     Database.update(acr);

    //     // Create products
    //     Product2 hwProd = Test_Data.createProduct('HardwareProduct', 'code', '1-hw-1', 'Hardware', true);
    //     PricebookEntry hwPBE = Test_Data.createPricebookEntry(hwProd.Id, 200, true);

    //     Product2 sProd = Test_Data.createProduct('SubscriptionPrepaid', 'code.P', '1-in-1', 'SubscriptionP', true);
    //     PricebookEntry sPBE = Test_Data.createPricebookEntry(sProd.Id, 10, true);
    //     Subscription25__Administration_Product__c hwAdminProd = Test_Data.createAdministrationProduct(admin.Id, hwProd.Id, vr.Id, true);
    //     Subscription25__Administration_Product__c sAdminProd = Test_Data.createAdministrationProduct(admin.Id, sProd.Id, vr.Id, false);
    //     sAdminProd.Exact_Id__c = 'item_sync';
    //     Database.insert(sAdminProd);

    //     Test_Data.createDebtorNumber(admin.Id, acct.Id, true);
    //     Contact salesCont = Test_Data.createContact(acct.Id, 'SalesContact', '0987654321', 'xel@321.com', true);

    //     // Create opportunity
    //     Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
    //     opp.Installation_Notes__c = 'installation notes';
    //     opp.Sales_Contact__c = salesCont.Id;
    //     opp.Payment_Method__c = 'I8';
    //     opp.Sales_Channel__c = 'Moving Intelligence';
    //     Database.insert(opp);

    //     // Create contract (with subscription items)
    //     Contract contr = Test_Data.createContract(acct.Id, admin.Id, true);
    //     Subscription25__Contract_Product__c hwContrProd = Test_Data.createContractProduct(contr.Id, hwProd.Id, false);
    //     Subscription25__Contract_Product__c sContrProd = Test_Data.createContractProduct(contr.Id, sProd.Id, false);
    //     Database.insert(new List<Subscription25__Contract_Product__c> { hwContrProd, sContrProd });

    //     // Create order
	// 	Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
	// 	ord.OpportunityId = opp.Id;
    //     ord.Contract__c = contr.Id;
    //     ord.Payment_Method__c = 'I8';
    //     ord.Sales_Channel__c = 'Moving Intelligence';
	// 	Database.insert(ord);

    //     Test_Data.createOrderItem(ord.Id, hwPBE.Id, 1, true);
	// 	OrderItem oi = Test_Data.createOrderItem(ord.Id, sPBE.Id, 1, false);
    //     oi.Partner_Code__c = '1A2B3C4D5E6F7';
    //     Database.insert(oi);
	// 	OrderItem oi2 = Test_Data.createOrderItem(ord.Id, hwPBE.Id, 1, false);
    //     oi2.Partner_Code__c = '1A2B3C4D5E6F8';
    //     Database.insert(oi2);

    //     Test.startTest();
    //     Util_FinancialSystem.syncOrderAsync(ord.Id);
    //     Test.stopTest();

    //     // Validate log for errors
    //     List<Event_Log__c> logs = [
    //         SELECT Id, Integration_Status__c, Result_Status__c, Message__c
    //         FROM Event_Log__c
    //     ];
    //     System.assertEquals(1, logs.size(), 'Expected single log');
    //     System.assertEquals('PROCESSED', logs.get(0).Integration_Status__c, logs.get(0).Message__c ?? 'No message');
    //     System.assertEquals('COMPLETED', logs.get(0).Result_Status__c, logs.get(0).Message__c ?? 'No message');

    //     Subscription25__Administration_Product__c hwAdminProdResult = [Select Exact_Id__c from Subscription25__Administration_Product__c where Id = :hwAdminProd.Id];
    //     Order orderResult =  [Select Exact_Id__c, Exact_Order_Number__c from Order where Id = :ord.Id];
    //     System.assertEquals('70c625f4-b8c9-4aa8-9272-06ac96d6a901', hwAdminProdResult.Exact_Id__c);
    //     System.assertEquals('item_sync', sAdminProd.Exact_Id__c);
    //     System.assertEquals('12345', orderResult.Exact_Order_Number__c);
    //     System.assertEquals('order_sync', orderResult.Exact_Id__c);

    //     System.assertEquals('70c625f4-b8c9-4aa8-9272-06ac96d6a901', [SELECT FinancialIdProduct__c FROM Subscription25__Contract_Product__c WHERE Id = :hwContrProd.Id].FinancialIdProduct__c);
    //     System.assertEquals('item_sync', [SELECT FinancialIdProduct__c FROM Subscription25__Contract_Product__c WHERE Id = :sContrProd.Id].FinancialIdProduct__c);
    // }

    // @isTest
    // private static void testLetterCodeConversion(){
    //     Account acct = Test_Data.createAccount('Test', '13', 'B2B', false);
    //     acct.WSONE_DATA_Billing_Country__c = 'NLD';
    //     acct.WSONE_DATA_Shipping_Country__c = 'NLD';

    //     Database.insert(acct);

    //     System.assertEquals('NL', [SELECT BillingCountryCode FROM Account WHERE Id = :acct.Id].BillingCountryCode);
    // }

    // @isTest
    // private static void testInvoice() {
    //     Subscription25__Administration__c admin = Test_Data.createAdministration(true);
	// 	Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
    //     Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
    //     Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
    //     Product2 prod = Test_Data.createProduct('name', 'code.P', '1-in-1', 'SubscriptionP', true);
    //     //prod.Is_Installation_Product__c = true;
    //     //Database.insert(prod);
    //     PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 10, true);
    //     Test_Data.createAdministrationProduct(admin.Id, prod.Id, vr.Id, true);
    //     Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

    //     Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
    //     opp.Installation_Notes__c = 'installation notes';
    //     opp.Sales_Contact__c = cont.Id;

    //     Database.insert(opp);

	// 	Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
	// 	ord.OpportunityId = opp.Id;
    //     ord.Payment_Method__c = 'I8';
	// 	Database.insert(ord);

	// 	OrderItem oi = Test_Data.createOrderItem(ord.Id, pbe.Id, 100, false);
    //     oi.Partner_Code__c = '1A2B3C4D5E6F7';
    //     Database.insert(oi);

    //     Subscription25__Invoice__c inv = Test_data.createInvoice(admin.Id, acct.Id, 'Draft', true);

    //     ord.subscription25__invoice__c = inv.id;
    //     Database.update(ord);

    //     inv.Subscription25__Status__c = 'Finalized';
    //     inv.Subscription25__Exact_Order_Number__c = '55';
    //     Database.update(inv);

    //     Test.starttest();
    //     Util_FinancialSystem.finalizeInvoice(inv.Id);
    //     Util_FinancialSystem.loadInvoiceNumber(inv.Id);
    //     Test.stopTest();

    //     System.assertEquals(1, [SELECT COUNT() FROM Subscription25__Invoice__c WHERE Id = :inv.Id]);
    // }
}