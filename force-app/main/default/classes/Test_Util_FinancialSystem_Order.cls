@IsTest
private class Test_Util_FinancialSystem_Order {

	/** Imitates Exact Items + SalesOrders + SalesOrderLines and records every call. */
	public class ExactSim implements HttpCalloutMock {
		public List<String> calls = new List<String>();
		public String items = '{"d":{"results":[{"ID":"item-guid-1","Code":"ORD.ITEM"}]}}';
		public String lines = '{"d":{"results":[{"ID":"line-guid-1","LineNumber":1,"Item":"item-guid-1"}]}}';
		public Integer linesStatus = 200;
		public HttpResponse respond(HttpRequest req) {
			String ep = req.getEndpoint();
			String entity = ep.contains('Items') ? 'Items' : ep.contains('SalesOrderLines') ? 'SalesOrderLines' : ep.contains('SalesOrders') ? 'SalesOrders' : 'Other';
			this.calls.add(req.getMethod() + ' ' + entity);
			HttpResponse res = new HttpResponse();
			res.setHeader('X-RateLimit-Limit', '5000');
			res.setHeader('X-RateLimit-Remaining', '4000');
			res.setStatusCode(req.getMethod() == 'POST' ? 201 : 200);
			if (entity == 'Items') {
				res.setBody(this.items);
			} else if (entity == 'SalesOrderLines') {
				res.setStatusCode(this.linesStatus);
				res.setBody(this.linesStatus == 200 ? this.lines : '{"error":{"message":{"value":"boom"}}}');
			} else {
				// Exact returns the created lines as deferred
				res.setBody('{"d":{"OrderID":"order-guid-1","OrderNumber":54321,"SalesOrderLines":{"__deferred":{"uri":"x"}}}}');
			}
			return res;
		}
	}

	private static String lineId() {
		return [SELECT FinancialId__c FROM OrderItem WITH SYSTEM_MODE LIMIT 1].FinancialId__c;
	}

	@TestSetup
	static void setup() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(false);
		admin.Subscription25__Synchronisation__c = 'Exact';
		admin.Acceptance_Environment_Available__c = true;
		Database.insert(admin, AccessLevel.SYSTEM_MODE);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);

		Account acct = Test_Data.createAccount('Order Account', (String) null, 'B2B', false);
		acct.Reseller_Name__c = '1';
		Database.insert(acct, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Main', null, 'main@order.test', true);
		Test_Data.createDebtorNumber(admin.Id, acct.Id, true);
		Database.update(new Account(Id = acct.Id, Contact_person__c = con.Id, FinancialIdAccount__c = 'acc-guid-ord', FinancialDebtorNumber__c = 'ORD-1'), AccessLevel.SYSTEM_MODE);
		AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acct.Id AND ContactId = :con.Id];
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-ord'), AccessLevel.SYSTEM_MODE);

		Product2 prod = Test_Data.createProduct('Order Item', 'ORD.ITEM', '1-hw-9', 'Hardware', true);
		PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 100, true);
		Test_Data.createAdministrationProduct(admin.Id, prod.Id, vr.Id, true);

		Opportunity opp = Test_Data.createOpportunity(acct.Id, con.Id, 'Order Opp', true);
		Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
		ord.OpportunityId = opp.Id;
		ord.Payment_Method__c = '08';
		Database.insert(ord);
		Test_Data.createOrderItem(ord.Id, pbe.Id, 1, true);
	}

	private static Order order() {
		return [
			SELECT Id, Status, Exact_Id__c, Exact_Order_Number__c, SyncToFinancialSystem__c, FinancialSyncAttempts__c,
				FinancialSyncNextAttempt__c, FinancialSyncLastError__c, AccountId
			FROM Order WITH SYSTEM_MODE LIMIT 1
		];
	}

	@IsTest
	static void readyAccount_orderCreatedAndActivated_itemGuidCached() {
		Order ord = order();
		Util_FinancialSystem_Order.flagOrders(new Set<Id>{ ord.Id });
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystem_Order.Result r = Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, true).get(ord.Id);
		Test.stopTest();

		System.assert(r.success, r.messages + ' ' + sim.calls);
		Order after = order();
		System.assertEquals('order-guid-1', after.Exact_Id__c);
		System.assertEquals('54321', after.Exact_Order_Number__c);
		System.assertEquals(false, after.SyncToFinancialSystem__c);
		System.assertEquals(new List<String>{ 'GET Items', 'POST SalesOrders', 'GET SalesOrderLines' }, sim.calls);
		System.assertEquals('line-guid-1', lineId(), 'Exact line id stored on the order item');
		System.assertEquals('item-guid-1', [SELECT Exact_Id__c FROM Subscription25__Administration_Product__c WITH SYSTEM_MODE LIMIT 1].Exact_Id__c, 'Item GUID cached');
		// activation may be refused by org validation in a test context; then the Exact id is still stored
		System.assertEquals(Util_FinancialSystem_Order.STATUS_ACTIVATED, after.Status, 'err=' + after.FinancialSyncLastError__c);
	}

	@IsTest
	static void cachedItem_onlyOnePost() {
		Order ord = order();
		Database.update(new Subscription25__Administration_Product__c(Id = [SELECT Id FROM Subscription25__Administration_Product__c WITH SYSTEM_MODE LIMIT 1].Id, Exact_Id__c = 'item-guid-cached'), AccessLevel.SYSTEM_MODE);
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, true);
		Test.stopTest();

		System.assertEquals(new List<String>{ 'POST SalesOrders', 'GET SalesOrderLines' }, sim.calls);
	}

	@IsTest
	static void accountNotInExact_orderWaits_accountQueued() {
		Order ord = order();
		Database.update(new Account(Id = ord.AccountId, FinancialIdAccount__c = null, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		Util_FinancialSystem_Order.flagOrders(new Set<Id>{ ord.Id });
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Util_FinancialSystem_Order.Result r = Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, true).get(ord.Id);

		System.assert(r.postponed);
		System.assertEquals(0, sim.calls.size());
		Order after = order();
		System.assertEquals(true, after.SyncToFinancialSystem__c, 'Order keeps waiting');
		System.assert(after.FinancialSyncNextAttempt__c > System.now());
		System.assert(after.FinancialSyncAttempts__c == null || after.FinancialSyncAttempts__c == 0, 'Waiting is no failed attempt');
		System.assertEquals(true, [SELECT SyncToFinancialSystem__c FROM Account WHERE Id = :ord.AccountId WITH SYSTEM_MODE].SyncToFinancialSystem__c, 'Account queued');
	}

	@IsTest
	static void alreadySynced_flagClearedWithoutCalls() {
		Order ord = order();
		Database.update(new Order(Id = ord.Id, Exact_Id__c = 'existing', SyncToFinancialSystem__c = true), AccessLevel.SYSTEM_MODE);
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, true);

		System.assertEquals(0, sim.calls.size());
		System.assertEquals(false, order().SyncToFinancialSystem__c);
	}

	@IsTest
	static void itemUnknownInExact_failsWithBackoff() {
		Order ord = order();
		Util_FinancialSystem_Order.flagOrders(new Set<Id>{ ord.Id });
		ExactSim sim = new ExactSim();
		sim.items = '{"d":{"results":[]}}';
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystem_Order.Result r = Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, true).get(ord.Id);
		Test.stopTest();

		System.assert(!r.success);
		System.assert(r.messages[0].contains('not available in exact'), r.messages[0]);
		Order after = order();
		System.assertEquals(1, after.FinancialSyncAttempts__c);
		System.assertEquals(true, after.SyncToFinancialSystem__c);
		System.assertEquals(new List<String>{ 'GET Items' }, sim.calls, 'No order POST');
	}

	@IsTest
	static void batch_syncsFlaggedOrders() {
		Order ord = order();
		Util_FinancialSystem_Order.flagOrders(new Set<Id>{ ord.Id });
		Database.insert(new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemOrderSync', Subscription25__Unique_Name__c = 'Batch_FinancialSystemOrderSync'), AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new ExactSim());

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemOrderSync());
		Test.stopTest();

		System.assertEquals('order-guid-1', order().Exact_Id__c);
	}

	@IsTest
	static void invocable_flagsOrSyncsNow() {
		Order ord = order();
		Inv_FinancialSystemOrder.Request flagReq = new Inv_FinancialSystemOrder.Request();
		flagReq.orderId = ord.Id;
		System.assert(Inv_FinancialSystemOrder.syncOrders(new List<Inv_FinancialSystemOrder.Request>{ flagReq })[0].success);
		System.assertEquals(true, order().SyncToFinancialSystem__c);

		Test.setMock(HttpCalloutMock.class, new ExactSim());
		Inv_FinancialSystemOrder.Request nowReq = new Inv_FinancialSystemOrder.Request();
		nowReq.orderId = ord.Id;
		nowReq.syncNow = true;
		Test.startTest();
		Inv_FinancialSystemOrder.Response res = Inv_FinancialSystemOrder.syncOrders(new List<Inv_FinancialSystemOrder.Request>{ nowReq })[0];
		Test.stopTest();
		System.assertEquals('order-guid-1', order().Exact_Id__c, res.message);
	}

	@IsTest
	static void lineIdsUnreadable_orderStillSucceeds() {
		Order ord = order();
		ExactSim sim = new ExactSim();
		sim.linesStatus = 500;
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystem_Order.Result r = Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, false).get(ord.Id);
		Test.stopTest();
		System.assert(r.success, r.messages + ' ' + sim.calls);
		System.assertEquals('order-guid-1', order().Exact_Id__c, 'The order is in Exact and must not be created twice');
		System.assertEquals(false, order().SyncToFinancialSystem__c);
		System.assertEquals(null, lineId());
		System.assert(String.join(r.messages, ' ').contains('line ids could not be read'), r.messages);
	}

	@IsTest
	static void lineOfOtherItem_isNotStored() {
		Order ord = order();
		ExactSim sim = new ExactSim();
		sim.lines = '{"d":{"results":[{"ID":"line-guid-x","LineNumber":1,"Item":"other-item"}]}}';
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystem_Order.Result r = Util_FinancialSystem_Order.syncOrders(new Set<Id>{ ord.Id }, false).get(ord.Id);
		Test.stopTest();
		System.assert(r.success, r.messages + ' ' + sim.calls);
		System.assertEquals(null, lineId(), 'A line for another item is not linked');
		System.assert(String.join(r.messages, ' ').contains('could not be matched'), r.messages);
	}
}
