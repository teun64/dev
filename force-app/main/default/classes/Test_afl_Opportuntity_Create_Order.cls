/**
 * Tests the flow afl_Opportuntity_Create_Order (one order per financial system warehouse) and the order update
 * in rau_Opportunity (all orders of the opportunity not yet in Exact).
 */
@IsTest
private class Test_afl_Opportuntity_Create_Order {

	@TestSetup
	static void setup() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('21%', 21, true, true);
		Account acct = Test_Data.createAccount('Create Order Account', (String) null, 'B2B', false);
		acct.Reseller_Name__c = '1';
		Database.insert(acct, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Sales', null, 'sales@createorder.test', true);
		Subscription25__Debtor_Number__c debNr = Test_Data.createDebtorNumber(admin.Id, acct.Id, false);
		debNr.Exact_ID__c = 'acc-guid-create';
		Database.insert(debNr, AccessLevel.SYSTEM_MODE);
		// the Closed Won check reads the account's own Exact id (the new sync does not fill the debtor number's Exact_ID__c)
		Database.update(new Account(Id = acct.Id, FinancialIdAccount__c = 'acc-guid-create'), AccessLevel.SYSTEM_MODE);

		Product2 prodET = Test_Data.createProduct('ET Tracker', 'CO.ET', '1-hw-11', 'Hardware', true);
		Product2 prodMI = Test_Data.createProduct('MI Tracker', 'CO.MI', '1-hw-12', 'Hardware', true);
		Test_Data.createPricebookEntry(prodET.Id, 100, true);
		Test_Data.createPricebookEntry(prodMI.Id, 50, true);
		Subscription25__Administration_Product__c apET = Test_Data.createAdministrationProduct(admin.Id, prodET.Id, vr.Id, false);
		apET.FinancialSystemIdWarehouse__c = '1_ET';
		Database.insert(apET, AccessLevel.SYSTEM_MODE);
		Test_Data.createAdministrationProduct(admin.Id, prodMI.Id, vr.Id, true);

		Opportunity opp = Test_Data.createOpportunity(acct.Id, con.Id, 'Create Order Opp', true);
		Database.update(new Opportunity(Id = opp.Id, Pricebook2Id = Test.getStandardPricebookId(), Administration__c = admin.Id), AccessLevel.SYSTEM_MODE);
	}

	static Opportunity opp() {
		return [SELECT Id FROM Opportunity WHERE Name = 'Create Order Opp' WITH SYSTEM_MODE LIMIT 1];
	}

	static void addLines(Id oppId, List<String> productCodes) {
		List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
		for (String code : productCodes) {
			Id pbeId = [SELECT Id FROM PricebookEntry WHERE Product2.ProductCode = :code WITH SYSTEM_MODE LIMIT 1].Id;
			olis.add(Test_Data.createOpportunityLineItem(oppId, pbeId, false));
		}
		Database.insert(olis, AccessLevel.SYSTEM_MODE);
	}

	static void setDefaultWarehouse(String warehouse) {
		Id adminId = [SELECT Id FROM Subscription25__Administration__c WITH SYSTEM_MODE LIMIT 1].Id;
		Database.update(new Subscription25__Administration__c(Id = adminId, FinancialSystemIdWarehouse__c = warehouse), AccessLevel.SYSTEM_MODE);
	}

	static void run(Id oppId) {
		Flow.Interview.createInterview('afl_Opportuntity_Create_Order', new Map<String, Object>{ 'recordID' => oppId }).start();
	}

	@IsTest
	static void mixedWarehouses_twoOrders() {
		setDefaultWarehouse('1_MI');
		Opportunity opp = opp();
		addLines(opp.Id, new List<String>{ 'CO.ET', 'CO.MI', 'CO.ET' });

		Test.startTest();
		run(opp.Id);
		Test.stopTest();

		Map<String, Order> byWarehouse = new Map<String, Order>();
		for (Order ord : [SELECT Id, FinancialSystemIdWarehouse__c, (SELECT Id FROM OrderItems) FROM Order WHERE OpportunityId = :opp.Id WITH SYSTEM_MODE]) {
			byWarehouse.put(ord.FinancialSystemIdWarehouse__c, ord);
		}
		Opportunity after = [SELECT Order__c, Order_Creation_Fault_Message__c FROM Opportunity WHERE Id = :opp.Id WITH SYSTEM_MODE];
		System.assertEquals(2, byWarehouse.size(), after.Order_Creation_Fault_Message__c);
		System.assertEquals(2, byWarehouse.get('1_ET').OrderItems.size());
		System.assertEquals(1, byWarehouse.get('1_MI').OrderItems.size());
		System.assertEquals(byWarehouse.get('1_ET').Id, after.Order__c, 'Opportunity.Order__c = order of the first product');
		System.assert(after.Order_Creation_Fault_Message__c.contains('2 orders created'), after.Order_Creation_Fault_Message__c);
	}

	@IsTest
	static void noWarehouses_oneOrderAsBefore() {
		Opportunity opp = opp();
		Database.update(new Subscription25__Administration_Product__c(Id = [SELECT Id FROM Subscription25__Administration_Product__c WHERE FinancialSystemIdWarehouse__c != null WITH SYSTEM_MODE LIMIT 1].Id,
			FinancialSystemIdWarehouse__c = null), AccessLevel.SYSTEM_MODE);
		addLines(opp.Id, new List<String>{ 'CO.ET', 'CO.MI' });

		Test.startTest();
		run(opp.Id);
		Test.stopTest();

		List<Order> orders = [SELECT Id, FinancialSystemIdWarehouse__c, (SELECT Id FROM OrderItems) FROM Order WHERE OpportunityId = :opp.Id WITH SYSTEM_MODE];
		System.assertEquals(1, orders.size());
		System.assertEquals(null, orders[0].FinancialSystemIdWarehouse__c);
		System.assertEquals(2, orders[0].OrderItems.size());
		System.assertEquals(orders[0].Id, [SELECT Order__c FROM Opportunity WHERE Id = :opp.Id WITH SYSTEM_MODE].Order__c);
	}

	@IsTest
	static void paymentMethodChange_updatesAllOpenOrders() {
		setDefaultWarehouse('1_MI');
		Opportunity opp = opp();
		addLines(opp.Id, new List<String>{ 'CO.ET', 'CO.MI' });
		run(opp.Id);
		List<Order> orders = [SELECT Id FROM Order WHERE OpportunityId = :opp.Id WITH SYSTEM_MODE];
		System.assertEquals(2, orders.size());
		// the first order is already in Exact: the other one is still updated
		Database.update(new Order(Id = [SELECT Order__c FROM Opportunity WHERE Id = :opp.Id WITH SYSTEM_MODE].Order__c, Exact_Id__c = 'in-exact'), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Database.update(new Opportunity(Id = opp.Id, Payment_Method__c = 'I0'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		for (Order ord : [SELECT Exact_Id__c, Payment_Method__c FROM Order WHERE OpportunityId = :opp.Id WITH SYSTEM_MODE]) {
			if (ord.Exact_Id__c == null) {
				System.assertEquals('I0', ord.Payment_Method__c, 'Open order updated');
			} else {
				System.assertNotEquals('I0', ord.Payment_Method__c, 'Order in Exact is left alone');
			}
		}
	}
}
