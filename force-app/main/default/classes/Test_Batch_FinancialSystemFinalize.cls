@IsTest
private class Test_Batch_FinancialSystemFinalize {

	private class ErrorMock implements HttpCalloutMock {
		public HttpResponse respond(HttpRequest req) {
			HttpResponse res = new HttpResponse();
			res.setBody('{"error":{"message":{"value":"boom"}}}');
			res.setStatusCode(200);
			return res;
		}
	}

	@TestSetup
	static void makeData() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Account acc = Test_Data.createAccount('Finalize BV', '9071', 'B2B', true);
		Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
		inv.Subscription25__Exact_Order_Number__c = '123';
		Database.insert(inv, AccessLevel.SYSTEM_MODE);
		// the package sets the state itself on insert: force it afterwards
		Util_FinancialSystem_Invoice.saveInvoices(new List<Subscription25__Invoice__c>{
			new Subscription25__Invoice__c(Id = inv.Id, Subscription25__Sync_State__c = 'COMPLETE')
		});
		Database.insert(new Subscription25__Schedulable_Class__c(
			Name = 'Batch_FinancialSystemFinalizeInvoices', Subscription25__Unique_Name__c = 'Batch_FinancialSystemFinalizeInvoices'
		), AccessLevel.SYSTEM_MODE);
	}

	private static Business_Entities__c entity(String credential) {
		Business_Entities__c e = new Business_Entities__c(Name = 'NL', Reseller__c = '1', FinSys_FI__c = credential);
		Database.insert(e, AccessLevel.SYSTEM_MODE);
		Util_FinancialSystem.entitiesByReseller = null;
		return e;
	}

	private static Subscription25__Administration__c admin() {
		return Batch_FinancialSystemFinalizeAdmin.getAdministration([SELECT Id FROM Subscription25__Administration__c LIMIT 1].Id);
	}

	private static Subscription25__Invoice__c invoice() {
		return [SELECT Id, Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c, FinSysFinalizeAttempts__c, FinSysFinalizeNextAttempt__c FROM Subscription25__Invoice__c WITH SYSTEM_MODE LIMIT 1];
	}

	@IsTest
	static void namedCredential_finalizeHasNoFallback() {
		Subscription25__Administration__c admin = admin();
		System.assertEquals(null, Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE), 'No entity: no finalize credential');
		System.assertEquals('Exact_NL', Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.SYNC), 'Sync keeps the administration credential');
		System.assert(!Util_FinancialSystem.isSyncEnabled(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE));

		entity(' Exact_NL ');
		System.assertEquals('Exact_NL', Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE), 'Trimmed entity credential');
		System.assert(Util_FinancialSystem.isSyncEnabled(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE));
	}

	@IsTest
	static void namedCredential_syncPrefersEntityCredential() {
		Subscription25__Administration__c admin = admin();
		Business_Entities__c e = entity(null);
		System.assertEquals('Exact_NL', Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.SYNC), 'No TM credential: administration');
		System.assert(!Util_FinancialSystem.getLimits(admin, Util_FinancialSystem.CredentialPurpose.SYNC).onEntity, 'Limit state on the administration');

		e.FinSys_TM__c = ' Exact_TM ';
		Database.update(e, AccessLevel.SYSTEM_MODE);
		Util_FinancialSystem.entitiesByReseller = null;
		System.assertEquals('Exact_TM', Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.SYNC), 'Entity credential wins');
		System.assertEquals(null, Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE), 'Finalize is separate');
	}

	@IsTest
	static void syncLimits_ownCredential_storedOnEntityNextToFinalize() {
		Subscription25__Administration__c admin = admin();
		Business_Entities__c e = entity('Exact_NL');
		e.FinSys_TM__c = 'Exact_NL';
		Database.update(e, AccessLevel.SYSTEM_MODE);
		Util_FinancialSystem.entitiesByReseller = null;
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		Util_FinancialSystem.doRequest(admin, 'api/v1/current/Me', null, 'GET', null, null);
		Util_FinancialSystem.doRequest(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE, 'api/v1/current/Me', null, 'GET', null, null);
		Util_FinancialSystem.saveLimits();
		Test.stopTest();

		Business_Entities__c after = [SELECT SyncRateLimitCheckedOn__c, FinalizeRateLimitCheckedOn__c FROM Business_Entities__c WHERE Id = :e.Id WITH SYSTEM_MODE];
		System.assertNotEquals(null, after.SyncRateLimitCheckedOn__c, 'Sync state on the entity');
		System.assertNotEquals(null, after.FinalizeRateLimitCheckedOn__c, 'Finalize state on the same entity');
		System.assertEquals(null, [SELECT FinancialRateLimitCheckedOn__c FROM Subscription25__Administration__c WHERE Id = :admin.Id WITH SYSTEM_MODE].FinancialRateLimitCheckedOn__c, 'Administration untouched');
	}

	@IsTest
	static void doRequest_finalizeWithoutCredential_throws() {
		try {
			Util_FinancialSystem.doRequest(admin(), Util_FinancialSystem.CredentialPurpose.FINALIZE, 'api/v1/current/Me', null, 'GET', null, null);
			System.assert(false, 'Expected an exception');
		} catch (Util_System.FinancialSyncException e) {
			System.assert(e.getMessage().contains('FINALIZE'), e.getMessage());
		}
	}

	@IsTest
	static void pick_onlyAdministrationsWithCredentialAndWork() {
		System.assert(Batch_FinancialSystemFinalizeInvoices.pickAdministrations().isEmpty(), 'No finalize credential: legacy path');

		entity('Exact_NL');
		System.assertEquals(new List<Id>{ admin().Id }, Batch_FinancialSystemFinalizeInvoices.pickAdministrations());

		Subscription25__Invoice__c inv = invoice();
		inv.FinSysFinalizeNextAttempt__c = System.now().addHours(1);
		Database.update(inv, AccessLevel.SYSTEM_MODE);
		System.assert(Batch_FinancialSystemFinalizeInvoices.pickAdministrations().isEmpty(), 'Backing off: nothing to do');
	}

	@IsTest
	static void pick_skipsAdministrationWithoutCapacity() {
		Business_Entities__c e = entity('Exact_NL');
		e.FinalizeDailyLimit__c = 100;
		e.FinalizeRateLimitRemaining__c = 5;
		e.FinalizeRateLimitResetOn__c = System.now().addHours(2);
		Database.update(e, AccessLevel.SYSTEM_MODE);
		Util_FinancialSystem.entitiesByReseller = null;
		System.assert(Batch_FinancialSystemFinalizeInvoices.pickAdministrations().isEmpty(), '95% used, above the 90% share');
	}

	@IsTest
	static void adminBatch_minutDispatcher_isCappedPerRun() {
		entity('Exact_NL');
		invoice();
		Batch_FinancialSystemFinalizeAdmin.minutPerRun = 0;
		Integer minut = 0;
		Database.QueryLocatorIterator itminut = ((Database.QueryLocator) new Batch_FinancialSystemFinalizeAdmin(admin().Id, new List<Id>(), 'Minut', 1).start(null)).iterator();
		while (itminut.hasNext()) {
			itminut.next();
			minut++;
		}
		Integer hour = 0;
		Database.QueryLocatorIterator ithour = ((Database.QueryLocator) new Batch_FinancialSystemFinalizeAdmin(admin().Id, new List<Id>(), 'Hour', 1).start(null)).iterator();
		while (ithour.hasNext()) {
			ithour.next();
			hour++;
		}
		System.assertEquals(0, minut, 'Minut: capped');
		System.assertEquals(1, hour, 'Hour: not capped');
	}

	@IsTest
	static void adminBatch_invoiceWithNumberOnlyGetsTheFlag() {
		entity('Exact_NL');
		Subscription25__Invoice__c inv = invoice();
		Util_FinancialSystem_Invoice.saveInvoices(new List<Subscription25__Invoice__c>{
			new Subscription25__Invoice__c(Id = inv.Id, Subscription25__Invoice_Number__c = 'NL123', Subscription25__Finalized_In_Exact__c = false)
		});
		System.assert(Batch_FinancialSystemFinalizeAdmin.hasWork(admin().Id), 'COMPLETE, flag false, number present: still work');
		// no mock: a callout would fail the test
		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(admin().Id), 1);
		Test.stopTest();

		System.assertEquals(true, invoice().Subscription25__Finalized_In_Exact__c, 'Flag set without an Exact call');
		System.assertEquals('TTTNL123', invoice().Subscription25__Invoice_Number__c, 'Number untouched');
		System.assert(!Batch_FinancialSystemFinalizeAdmin.hasWork(admin().Id), 'Nothing left');
	}

	@IsTest
	static void hasWork_requiresCompleteSyncState() {
		Subscription25__Invoice__c inv = invoice();
		Util_FinancialSystem_Invoice.saveInvoices(new List<Subscription25__Invoice__c>{
			new Subscription25__Invoice__c(Id = inv.Id, Subscription25__Sync_State__c = 'PENDING')
		});
		System.assert(!Batch_FinancialSystemFinalizeAdmin.hasWork(admin().Id), 'Not COMPLETE: no work');
	}

	@IsTest
	static void adminBatch_finalizesInvoiceAndStoresLimitsOnEntity() {
		Business_Entities__c e = entity('Exact_NL');
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(admin().Id), 1);
		Test.stopTest();

		System.assertEquals('TTT123', invoice().Subscription25__Invoice_Number__c, 'Invoice number loaded');
		Business_Entities__c after = [SELECT FinalizeRateLimitCheckedOn__c, FinalizeRateLimitRemaining__c FROM Business_Entities__c WHERE Id = :e.Id WITH SYSTEM_MODE];
		System.assertNotEquals(null, after.FinalizeRateLimitCheckedOn__c, 'Limit state stored on the entity');
	}

	@IsTest
	static void adminBatch_failure_backsOff() {
		entity('Exact_NL');
		Test.setMock(HttpCalloutMock.class, new ErrorMock());

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(admin().Id), 1);
		Test.stopTest();

		Subscription25__Invoice__c inv = invoice();
		System.assertEquals(null, inv.Subscription25__Invoice_Number__c);
		System.assertEquals(1, inv.FinSysFinalizeAttempts__c, 'One failed attempt');
		System.assert(inv.FinSysFinalizeNextAttempt__c > System.now(), 'Back-off set');
	}

	@IsTest
	static void adminBatch_noRoomInDailyShare_doesNothing() {
		Business_Entities__c e = entity('Exact_NL');
		e.FinalizeDailyLimit__c = 100;
		e.FinalizeRateLimitRemaining__c = 5;
		e.FinalizeRateLimitResetOn__c = System.now().addHours(2);
		Database.update(e, AccessLevel.SYSTEM_MODE);
		Util_FinancialSystem.entitiesByReseller = null;
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(admin().Id), 1);
		Test.stopTest();

		System.assertEquals(null, invoice().Subscription25__Invoice_Number__c, 'Daily share used: nothing sent');
	}

	@IsTest
	static void adminBatch_minutelyLimit_stopsAndBlocks() {
		entity('Exact_NL');
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
		Batch_FinancialSystemFinalizeAdmin batch = new Batch_FinancialSystemFinalizeAdmin(admin().Id);
		batch.minutelyRemaining = 3;
		batch.minutelyReset = System.now().addSeconds(30).getTime();

		Test.startTest();
		batch.execute(null, new List<SObject>{ invoice() });
		Test.stopTest();

		System.assert(batch.stopped, 'Stopped');
		System.assert(batch.minutelyBlocked, 'Blocked by the minutely window, not the daily share');
		System.assertEquals(0, batch.processed, 'No call made');
		System.assertEquals(null, invoice().Subscription25__Invoice_Number__c);
	}

	@IsTest
	static void adminBatch_noCredential_stops() {
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
		Batch_FinancialSystemFinalizeAdmin batch = new Batch_FinancialSystemFinalizeAdmin(admin().Id);
		batch.execute(null, new List<SObject>{ invoice() });
		System.assert(batch.stopped);
		System.assertEquals(0, batch.processed);
	}

	@IsTest
	static void continuation_scheduledOnce() {
		Id adminId = admin().Id;
		Test.startTest();
		Batch_FinancialSystemFinalizeAdmin.scheduleContinuation(adminId, 2);
		Batch_FinancialSystemFinalizeAdmin.scheduleContinuation(adminId, 3);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM Event_Log__c], 'No callouts for a continuation without work');
	}

	@IsTest
	static void genericBatch_nothingToDo_runs() {
		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemFinalizeInvoices(), 1);
		Test.stopTest();
		System.assertEquals(0, [SELECT COUNT() FROM Event_Log__c WHERE Context_Id__c = :invoice().Id], 'Nothing sent without a finalize credential');
	}
}
