/**
 * Tests the financial system warehouses: one order per warehouse (Inv_FinancialSystemCreateOrders), the Exact GUID mapping and vr_FinancialSystemIdWarehouse.
 */
@IsTest
private class Test_Util_FinancialSystemWarehouse {

	@TestSetup
	static void setup() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Database.update(new Subscription25__Administration__c(Id = admin.Id, FinancialSystemIdWarehouse__c = '1_MI'), AccessLevel.SYSTEM_MODE);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('21%', 21, true, true);
		Account acct = Test_Data.createAccount('Warehouse Account', (String) null, 'B2B', false);
		acct.Reseller_Name__c = '1';
		Database.insert(acct, AccessLevel.SYSTEM_MODE);
		Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

		Product2 prodET = Test_Data.createProduct('Europetrack Tracker', 'WH.ET', '1-hw-1', 'Hardware', true);
		Product2 prodMI = Test_Data.createProduct('MI Tracker', 'WH.MI', '1-hw-2', 'Hardware', true);
		Test_Data.createPricebookEntry(prodET.Id, 100, true);
		Test_Data.createPricebookEntry(prodMI.Id, 50, true);
		Subscription25__Administration_Product__c apET = Test_Data.createAdministrationProduct(admin.Id, prodET.Id, vr.Id, false);
		apET.FinancialSystemIdWarehouse__c = '1_ET';
		Database.insert(apET, AccessLevel.SYSTEM_MODE);
		Test_Data.createAdministrationProduct(admin.Id, prodMI.Id, vr.Id, true);
	}

	static Account account() {
		return [SELECT Id FROM Account WHERE Name = 'Warehouse Account' WITH SYSTEM_MODE LIMIT 1];
	}

	static PricebookEntry pbe(String productCode) {
		return [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = :productCode WITH SYSTEM_MODE LIMIT 1];
	}

	static Order template() {
		Order ord = new Order(AccountId = account().Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = Test.getStandardPricebookId(),
			Sales_Channel__c = 'Moving Intelligence', Subscription25__Administration__c = [SELECT Id FROM Subscription25__Administration__c WITH SYSTEM_MODE LIMIT 1].Id);
		return ord;
	}

	static OrderItem line(String productCode) {
		PricebookEntry entry = pbe(productCode);
		return new OrderItem(PricebookEntryId = entry.Id, Product2Id = entry.Product2Id, Quantity = 1, UnitPrice = 10);
	}

	static Inv_FinancialSystemCreateOrders.Response create(List<OrderItem> lines) {
		Inv_FinancialSystemCreateOrders.Request req = new Inv_FinancialSystemCreateOrders.Request();
		req.order = template();
		req.orderItems = lines;
		return Inv_FinancialSystemCreateOrders.createOrders(new List<Inv_FinancialSystemCreateOrders.Request>{ req })[0];
	}

	@IsTest
	static void createOrders_onePerWarehouse() {
		Test.startTest();
		Inv_FinancialSystemCreateOrders.Response res = create(new List<OrderItem>{ line('WH.ET'), line('WH.MI'), line('WH.ET') });
		Test.stopTest();

		System.assertEquals(2, res.orderIds.size(), res.message);
		Order main = [SELECT Id, FinancialSystemIdWarehouse__c, AccountId, (SELECT Product2.ProductCode FROM OrderItems) FROM Order WHERE Id = :res.orderId WITH SYSTEM_MODE];
		System.assertEquals('1_ET', main.FinancialSystemIdWarehouse__c, 'Main order = warehouse of the first product');
		System.assertEquals(2, main.OrderItems.size());
		for (OrderItem oi : main.OrderItems) {
			System.assertEquals('WH.ET', oi.Product2.ProductCode);
		}
		Order other = [SELECT FinancialSystemIdWarehouse__c, AccountId, (SELECT Product2.ProductCode FROM OrderItems) FROM Order WHERE Id = :res.orderIds[1] WITH SYSTEM_MODE];
		System.assertEquals('1_MI', other.FinancialSystemIdWarehouse__c, 'Administration default');
		System.assertEquals(1, other.OrderItems.size());
		System.assertEquals('WH.MI', other.OrderItems[0].Product2.ProductCode);
		System.assertEquals(main.AccountId, other.AccountId, 'Every order is a copy of the template');
	}

	@IsTest
	static void createOrders_oneWarehouse_oneOrder() {
		Inv_FinancialSystemCreateOrders.Response res = create(new List<OrderItem>{ line('WH.MI'), line('WH.MI') });
		System.assertEquals(1, res.orderIds.size());
		System.assertEquals(2, [SELECT COUNT() FROM OrderItem WHERE OrderId = :res.orderId WITH SYSTEM_MODE]);
	}

	@IsTest
	static void createOrders_failure_rolledBack() {
		OrderItem broken = line('WH.MI');
		broken.PricebookEntryId = null;
		Boolean failed = false;
		try {
			create(new List<OrderItem>{ line('WH.ET'), broken });
		} catch (Util_System.CustomException e) {
			failed = true;
		}
		System.assert(failed, 'The error goes to the flow fault path');
		System.assertEquals(0, [SELECT COUNT() FROM Order WITH SYSTEM_MODE], 'All or nothing');
	}

	@IsTest
	static void exactId_perAdministrationAndWarehouse() {
		Id adminId = [SELECT Id FROM Subscription25__Administration__c WITH SYSTEM_MODE LIMIT 1].Id;
		Database.insert(new Exact_Relation_Setting__c(Administration__c = adminId, Classification__c = 'WH', Sales_Channel__c = 'Europetrack',
			FinancialSystemIdWarehouse__c = '1_ET', Exact_ID__c = 'wh-et-guid'), AccessLevel.SYSTEM_MODE);

		System.assertEquals('wh-et-guid', Util_FinancialSystemWarehouse.getExactId(adminId, '1_ET'));
		System.assertEquals(null, Util_FinancialSystemWarehouse.getExactId(adminId, '1_MI'));
		System.assertEquals(null, Util_FinancialSystemWarehouse.getExactId(adminId, null));
	}

	@IsTest
	static void administrationProduct_warehouseOfOtherAdministration_blocked() {
		Subscription25__Administration_Product__c ap = [SELECT Id FROM Subscription25__Administration_Product__c WHERE Subscription25__Product__r.ProductCode = 'WH.MI' WITH SYSTEM_MODE];
		Database.SaveResult blocked = Database.update(new Subscription25__Administration_Product__c(Id = ap.Id, FinancialSystemIdWarehouse__c = '6_MI'), false, AccessLevel.SYSTEM_MODE);
		System.assert(!blocked.isSuccess(), 'A UK warehouse on an NL administration product');
		Database.SaveResult allowed = Database.update(new Subscription25__Administration_Product__c(Id = ap.Id, FinancialSystemIdWarehouse__c = '1_ET'), false, AccessLevel.SYSTEM_MODE);
		System.assert(allowed.isSuccess(), String.valueOf(allowed.getErrors()));
	}

	// ---------------------------------------------------------------- split (repair)

	static Order draftOrder(List<String> productCodes) {
		Order ord = template();
		ord.Type = 'Hardware';
		Database.insert(ord, AccessLevel.SYSTEM_MODE);
		List<OrderItem> lines = new List<OrderItem>();
		for (String code : productCodes) {
			OrderItem oi = line(code);
			oi.OrderId = ord.Id;
			lines.add(oi);
		}
		Database.insert(lines, AccessLevel.SYSTEM_MODE);
		return ord;
	}

	@IsTest
	static void split_mixedOrder_otherWarehouseMoved() {
		Order ord = draftOrder(new List<String>{ 'WH.MI', 'WH.ET', 'WH.MI' });
		OrderItem et = [SELECT Id, Quantity, UnitPrice FROM OrderItem WHERE OrderId = :ord.Id AND Product2.ProductCode = 'WH.ET' WITH SYSTEM_MODE];

		Test.startTest();
		Map<Id, String> res = Util_FinancialSystemWarehouse.splitOrders(new Set<Id>{ ord.Id });
		Test.stopTest();

		System.assert(res.get(ord.Id).startsWith('Repaired'), res.get(ord.Id));
		Order original = [SELECT FinancialSystemIdWarehouse__c, (SELECT Product2.ProductCode FROM OrderItems) FROM Order WHERE Id = :ord.Id WITH SYSTEM_MODE];
		System.assertEquals('1_MI', original.FinancialSystemIdWarehouse__c, 'Keeps the warehouse of its first product');
		System.assertEquals(2, original.OrderItems.size());
		Order moved = [SELECT FinancialSystemIdWarehouse__c, Type, Status, AccountId, Sales_Channel__c, (SELECT Product2.ProductCode, Quantity, UnitPrice FROM OrderItems)
			FROM Order WHERE Id != :ord.Id WITH SYSTEM_MODE];
		System.assertEquals('1_ET', moved.FinancialSystemIdWarehouse__c);
		System.assertEquals('Hardware', moved.Type);
		System.assertEquals('Draft', moved.Status);
		System.assertEquals('Moving Intelligence', moved.Sales_Channel__c, 'Copy of the order');
		System.assertEquals(1, moved.OrderItems.size());
		System.assertEquals('WH.ET', moved.OrderItems[0].Product2.ProductCode);
		System.assertEquals(et.UnitPrice, moved.OrderItems[0].UnitPrice);
		System.assertEquals(0, [SELECT COUNT() FROM OrderItem WHERE Id = :et.Id WITH SYSTEM_MODE], 'Moved = copied + deleted');
	}

	@IsTest
	static void split_oneWarehouse_onlyWarehouseSet() {
		Order ord = draftOrder(new List<String>{ 'WH.ET' });
		Map<Id, String> res = Util_FinancialSystemWarehouse.splitOrders(new Set<Id>{ ord.Id });
		System.assert(res.get(ord.Id).startsWith('Repaired'), res.get(ord.Id));
		System.assertEquals('1_ET', [SELECT FinancialSystemIdWarehouse__c FROM Order WHERE Id = :ord.Id WITH SYSTEM_MODE].FinancialSystemIdWarehouse__c);
		System.assertEquals(1, [SELECT COUNT() FROM Order WITH SYSTEM_MODE]);
		// second run: nothing to do
		System.assert(Util_FinancialSystemWarehouse.splitOrders(new Set<Id>{ ord.Id }).get(ord.Id).startsWith('OK'));
	}

	@IsTest
	static void split_batch_skipsOrdersInExact() {
		Order open = draftOrder(new List<String>{ 'WH.MI', 'WH.ET' });
		Order inExact = draftOrder(new List<String>{ 'WH.MI', 'WH.ET' });
		Database.insert(new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemOrderWarehouse',
			Subscription25__Unique_Name__c = 'Batch_FinancialSystemOrderWarehouse'), AccessLevel.SYSTEM_MODE);
		Database.update(new Order(Id = inExact.Id, Exact_Id__c = 'in-exact'), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemOrderWarehouse(true));
		Test.stopTest();

		System.assertEquals(3, [SELECT COUNT() FROM Order WITH SYSTEM_MODE], 'Only the open order is split');
		System.assertEquals(2, [SELECT COUNT() FROM OrderItem WHERE OrderId = :inExact.Id WITH SYSTEM_MODE]);
	}

	@IsTest
	static void split_dispatcherStep_onlyFlaggedOrders() {
		Order flagged = draftOrder(new List<String>{ 'WH.MI', 'WH.ET' });
		draftOrder(new List<String>{ 'WH.MI', 'WH.ET' });
		Database.update(new Order(Id = flagged.Id, SyncToFinancialSystem__c = true), AccessLevel.SYSTEM_MODE);
		Database.insert(new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemOrderWarehouse',
			Subscription25__Unique_Name__c = 'Batch_FinancialSystemOrderWarehouse'), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemOrderWarehouse());
		Test.stopTest();

		System.assertEquals(3, [SELECT COUNT() FROM Order WITH SYSTEM_MODE], 'Only the flagged order is split');
		System.assertEquals(true, [SELECT SyncToFinancialSystem__c FROM Order WHERE FinancialSystemIdWarehouse__c = '1_ET' WITH SYSTEM_MODE].SyncToFinancialSystem__c,
			'The new order is flagged too');
	}
}
