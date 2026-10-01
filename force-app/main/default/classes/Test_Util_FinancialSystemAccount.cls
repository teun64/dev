@IsTest
private class Test_Util_FinancialSystemAccount {

	/** Imitates Exact: answers per entity and records every call as "METHOD entity". */
	public class ExactSim implements HttpCalloutMock {
		public List<String> calls = new List<String>();
		public String matchResult = '{"d":{"results":[]}}';
		public String bankLookup = '{"d":{"results":[]}}';
		private Integer seq = 0;

		public HttpResponse respond(HttpRequest req) {
			String ep = req.getEndpoint();
			String m = req.getMethod();
			String entity = ep.contains('DirectDebitMandates') ? 'Mandate'
				: ep.contains('BankAccounts') ? 'Bank'
				: ep.contains('Addresses') ? 'Address'
				: ep.contains('Contacts') ? 'Contact'
				: ep.contains('Accounts') ? 'Account' : 'Other';
			this.calls.add(m + ' ' + entity);
			HttpResponse res = new HttpResponse();
			res.setHeader('X-RateLimit-Limit', '5000');
			res.setHeader('X-RateLimit-Remaining', '4000');
			res.setHeader('X-RateLimit-Minutely-Remaining', '50');
			if (m == 'PUT') {
				res.setStatusCode(204);
				return res;
			}
			res.setStatusCode(m == 'POST' ? 201 : 200);
			this.seq++;
			if (m == 'GET') {
				res.setBody(entity == 'Bank' ? this.bankLookup : this.matchResult);
			} else if (entity == 'Account') {
				res.setBody('{"d":{"ID":"acc-guid-1","Code":"             12345","MainContact":null}}');
			} else {
				res.setBody('{"d":{"ID":"' + entity.toLowerCase() + '-guid-' + this.seq + '"}}');
			}
			return res;
		}

		public Integer count(String call) {
			Integer n = 0;
			for (String c : this.calls) {
				if (c == call) {
					n++;
				}
			}
			return n;
		}
	}

	@TestSetup
	static void setup() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(false);
		admin.Subscription25__Synchronisation__c = 'Exact';
		admin.Acceptance_Environment_Available__c = true;
		Database.insert(admin, AccessLevel.SYSTEM_MODE);

		Account acc = Test_Data.createAccount('Sync Account', (String) null, 'B2B', false);
		acc.Reseller_Name__c = '1';
		Database.insert(acc, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acc.Id, 'Main', null, 'main@sync.test', true);
		Database.update(new Account(Id = acc.Id, Contact_person__c = con.Id), AccessLevel.SYSTEM_MODE);
	}

	private static Account account() {
		return [
			SELECT Id, Name, FinancialIdAccount__c, FinancialDebtorNumber__c, FinancialIdInvoiceAddress__c, FinancialIdShippingAddress__c,
				FinancialIdBankAccount__c, FinancialIdBankMandate__c, SyncToFinancialSystem__c, FinancialSyncState__c,
				FinancialSyncAttempts__c, FinancialSyncNextAttempt__c, FinancialSyncLastError__c, FinancialDebtorCheck__c,
				Contact_person__c, Reseller_Name__c, BillingStreet, InvoiceAddress__Street__s, ShippingStreet, Payment_Method_Contracts__c
			FROM Account WHERE Name LIKE 'Sync Account%' WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void newAccount_fullSync_storesIdsOnAccountAndRelation() {
		Account acc = account();
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false).get(acc.Id);
		Test.stopTest();

		System.assert(r.success, String.join(r.messages, ' | ') + ' calls: ' + sim.calls);
		Account after = account();
		System.assertEquals('acc-guid-1', after.FinancialIdAccount__c);
		System.assertEquals('12345', after.FinancialDebtorNumber__c, 'Debtor number from the POST response (trimmed)');
		System.assertEquals(false, after.SyncToFinancialSystem__c, 'Flag cleared after success');
		System.assertNotEquals(null, after.FinancialSyncState__c, 'Fingerprints stored');
		System.assertEquals(1, sim.count('GET Account'), 'Duplicate check for a new account: ' + sim.calls);
		System.assertEquals(1, sim.count('POST Account'), sim.calls);
		System.assertEquals(1, sim.count('POST Contact'), sim.calls);
		AccountContactRelation acr = [SELECT FinancialIdContact__c FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :acc.Contact_person__c WITH SYSTEM_MODE];
		System.assert(acr.FinancialIdContact__c.startsWith('contact-guid-'), 'Exact contact id on the relation');
		System.assertEquals(1, sim.count('PUT Account'), 'Main contact set on the new Exact account: ' + sim.calls);
		if (after.InvoiceAddress__Street__s != after.BillingStreet) {
			System.assertNotEquals(null, after.FinancialIdInvoiceAddress__c, 'Invoice address created');
		}
		List<Subscription25__Debtor_Number__c> debNrs = [SELECT Subscription25__Debtor_Number__c FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :acc.Id WITH SYSTEM_MODE];
		System.assertEquals(1, debNrs.size(), 'Debtor number record upserted from the account');
		System.assertEquals('12345', debNrs[0].Subscription25__Debtor_Number__c);
		System.assertEquals(1, [SELECT COUNT() FROM Event_Log__c WHERE Context_Id__c = :acc.Id AND Action__c = 'sync2Exact'], 'One log per account');
	}

	@IsTest
	static void secondRun_withoutChanges_makesNoCalls() {
		Account acc = account();
		ExactSim first = new ExactSim();
		Test.setMock(HttpCalloutMock.class, first);
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false);

		ExactSim second = new ExactSim();
		Test.setMock(HttpCalloutMock.class, second);
		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false).get(acc.Id);
		Test.stopTest();

		System.assert(r.success, String.join(r.messages, ' | '));
		System.assertEquals(new List<String>(), second.calls, 'Nothing changed, nothing sent');
	}

	@IsTest
	static void changedAccountName_onlyAccountIsSentAgain() {
		Account acc = account();
		Test.setMock(HttpCalloutMock.class, new ExactSim());
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false);
		Database.update(new Account(Id = acc.Id, Name = 'Sync Account B.V.'), AccessLevel.SYSTEM_MODE);

		ExactSim second = new ExactSim();
		Test.setMock(HttpCalloutMock.class, second);
		Test.startTest();
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false);
		Test.stopTest();

		System.assertEquals(new List<String>{ 'PUT Account' }, second.calls, 'Only the changed part');
	}

	@IsTest
	static void match_exactAccountLinkedToOtherAccount_isRefused() {
		Account other = Test_Data.createAccount('Other Account', (String) null, 'B2B', false);
		other.FinancialIdAccount__c = 'acc-guid-dup';
		Database.insert(other, AccessLevel.SYSTEM_MODE);
		Account acc = account();
		ExactSim sim = new ExactSim();
		sim.matchResult = '{"d":{"results":[{"ID":"acc-guid-dup","Code":"   999","Name":"Sync Account","MainContact":null}]}}';
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, true).get(acc.Id);
		Test.stopTest();

		System.assert(!r.success);
		System.assert(r.messages[0].contains('already linked'), r.messages[0]);
		Account after = account();
		System.assertEquals(null, after.FinancialIdAccount__c, 'Not linked');
		System.assertEquals(true, after.SyncToFinancialSystem__c, 'Stays flagged');
		System.assertEquals(1, after.FinancialSyncAttempts__c);
		System.assert(after.FinancialSyncNextAttempt__c > System.now(), 'Back-off');
		System.assertEquals(0, sim.count('POST Account'), 'No duplicate created');
	}

	@IsTest
	static void match_existingExactAccount_isLinkedAndUpdated() {
		Account acc = account();
		ExactSim sim = new ExactSim();
		sim.matchResult = '{"d":{"results":[{"ID":"acc-guid-found","Code":"   777","Name":"Sync Account","MainContact":null}]}}';
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, true);
		Test.stopTest();

		Account after = account();
		System.assertEquals('acc-guid-found', after.FinancialIdAccount__c);
		System.assertEquals('777', after.FinancialDebtorNumber__c.trim());
		System.assertEquals(0, sim.count('POST Account'), 'Existing Exact account reused: ' + sim.calls);
		System.assert(sim.count('PUT Account') >= 1, sim.calls);
	}

	@IsTest
	static void noCapacity_postponesWithoutAttempt() {
		Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c WITH SYSTEM_MODE LIMIT 1];
		Database.update(new Subscription25__Administration__c(Id = admin.Id, Daily_Limit__c = 1000, FinancialRateLimitRemaining__c = 100,
			FinancialRateLimitResetOn__c = System.now().addHours(1), FinancialRateLimitMaxPercentage__c = 90), AccessLevel.SYSTEM_MODE);
		Account acc = account();
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = true), AccessLevel.SYSTEM_MODE);
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, true).get(acc.Id);
		Test.stopTest();

		System.assert(r.postponed, r.messages + '');
		System.assertEquals(new List<String>(), sim.calls, '900 of 1000 used: batch budget exhausted');
		Account after = account();
		System.assertEquals(true, after.SyncToFinancialSystem__c);
		System.assert(after.FinancialSyncAttempts__c == null || after.FinancialSyncAttempts__c == 0, 'Postponing is not a failed attempt');
	}

	@IsTest
	static void validationError_countsAttempt() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, InvoiceAddress__Street__s = null, InvoiceAddress__City__s = null), AccessLevel.SYSTEM_MODE);
		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);

		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, true).get(acc.Id);

		Account after = account();
		if (!FeatureManagement.checkPermission('cp_miIntegrationSkipDataCheck') && after.InvoiceAddress__Street__s == null) {
			System.assert(!r.success);
			System.assertEquals(1, after.FinancialSyncAttempts__c);
			System.assertEquals(0, sim.calls.size(), 'No callouts for an invalid account');
		}
	}

	@IsTest
	static void batch_syncsFlaggedAccounts() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = true), AccessLevel.SYSTEM_MODE);
		Database.insert(new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemAccountSync', Subscription25__Unique_Name__c = 'Batch_FinancialSystemAccountSync'), AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new ExactSim());

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemAccountSync());
		Test.stopTest();

		Account after = account();
		List<Event_Log__c> logs = [SELECT Result_Status__c, Message__c FROM Event_Log__c WHERE Context_Id__c = :acc.Id];
		List<Subscription25__Cron_Log__c> cron = [SELECT Subscription25__Status__c, Subscription25__Log__c, Subscription25__Total_Record_Count__c, Subscription25__Total_Error_Count__c FROM Subscription25__Cron_Log__c];
		System.assertEquals('acc-guid-1', after.FinancialIdAccount__c, 'flag=' + after.SyncToFinancialSystem__c + ' err=' + after.FinancialSyncLastError__c + ' logs=' + logs + ' cronlogs=' + cron);
		System.assertEquals(false, after.SyncToFinancialSystem__c);
	}

	@IsTest
	static void invocable_flagsOrSyncsNow() {
		Account acc = account();
		Inv_FinancialSystemAccount.Request flagReq = new Inv_FinancialSystemAccount.Request();
		flagReq.accountId = acc.Id;
		List<Inv_FinancialSystemAccount.Response> flagged = Inv_FinancialSystemAccount.syncAccounts(new List<Inv_FinancialSystemAccount.Request>{ flagReq });
		System.assert(flagged[0].success);
		System.assertEquals(true, account().SyncToFinancialSystem__c, 'Flagged for the batch');

		Test.setMock(HttpCalloutMock.class, new ExactSim());
		Inv_FinancialSystemAccount.Request nowReq = new Inv_FinancialSystemAccount.Request();
		nowReq.accountId = acc.Id;
		nowReq.syncNow = true;
		Test.startTest();
		List<Inv_FinancialSystemAccount.Response> synced = Inv_FinancialSystemAccount.syncAccounts(new List<Inv_FinancialSystemAccount.Request>{ nowReq });
		Test.stopTest();
		System.assert(synced[0].success, synced[0].message);
		System.assertEquals(false, account().SyncToFinancialSystem__c);
	}

	@IsTest
	static void debtorNumber_changeOnAccount_upsertsRecord() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555'), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55556'), AccessLevel.SYSTEM_MODE);
		List<Subscription25__Debtor_Number__c> debNrs = [SELECT Subscription25__Debtor_Number__c FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :acc.Id WITH SYSTEM_MODE];
		System.assertEquals(1, debNrs.size(), 'One record per account + administration');
		System.assertEquals('55556', debNrs[0].Subscription25__Debtor_Number__c);
	}

	@IsTest
	static void backoff_growsAndParks() {
		Datetime now = System.now();
		System.assert(Util_FinancialSystem.nextAttempt(1) <= now.addMinutes(16));
		System.assert(Util_FinancialSystem.nextAttempt(3) >= now.addMinutes(59));
		System.assert(Util_FinancialSystem.nextAttempt(7) <= now.addHours(25));
		System.assert(Util_FinancialSystem.nextAttempt(Util_FinancialSystemAccount.MAX_ATTEMPTS) >= now.addDays(6), 'Parked');
	}

	@IsTest
	static void state_unreadable_meansFullResync() {
		System.assertEquals(new Map<String, String>(), Util_FinancialSystemAccount.readState('not json'));
		System.assertEquals(new Map<String, String>(), Util_FinancialSystemAccount.readState(null));
	}

	@IsTest
	static void rbbAccount_nameChangeOnSyncedAccount_setsFlag() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'acc-guid-flow', SyncToFinancialSystem__c = false, FinancialSyncAttempts__c = 3), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Database.update(new Account(Id = acc.Id, Name = 'Sync Account Renamed'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		Account after = account();
		System.assertEquals(true, after.SyncToFinancialSystem__c, 'rbb_Account flags the name change');
		System.assertEquals(0, after.FinancialSyncAttempts__c, 'Back-off reset by a new change');
	}

	@IsTest
	static void changedContact_flagsItsAccount_andSuccessClearsTheRelation() {
		Account acc = account();
		AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :acc.Contact_person__c WITH SYSTEM_MODE];
		Database.update(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);

		Util_FinancialSystemAccount.flagAccountsOfChangedContacts();
		System.assertEquals(true, account().SyncToFinancialSystem__c, 'Account of the changed contact is flagged');

		Test.setMock(HttpCalloutMock.class, new ExactSim());
		Test.startTest();
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, true);
		Test.stopTest();
		System.assertEquals(false, [SELECT Sync_To_Financial_System__c FROM AccountContactRelation WHERE Id = :acr.Id WITH SYSTEM_MODE].Sync_To_Financial_System__c);
	}

	@IsTest
	static void draftHardwareOrder_withoutDebtorNumber_flagsAccount() {
		Account acc = account();
		Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c WITH SYSTEM_MODE LIMIT 1];
		Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = null, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		Order ord = Test_Data.createOrder(acc.Id, admin.Id, Date.today(), false);
		ord.Type = 'Hardware';
		ord.Status = 'Draft';
		Test.startTest();
		Database.insert(ord);
		Test.stopTest();
		System.assertEquals(true, account().SyncToFinancialSystem__c, 'Account queued for the financial system');
	}
}
