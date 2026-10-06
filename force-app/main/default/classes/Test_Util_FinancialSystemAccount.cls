@IsTest
private class Test_Util_FinancialSystemAccount {

	/** Imitates Exact: answers per entity and records every call as "METHOD entity". */
	public class ExactSim implements HttpCalloutMock {
		public List<String> calls = new List<String>();
		public List<String> bodies = new List<String>();
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
			this.bodies.add(m + ' ' + entity + ' ' + req.getBody());
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

		public String body(String call) {
			for (String b : this.bodies) {
				if (b.startsWith(call + ' ')) {
					return b;
				}
			}
			return null;
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
				Contact_person__c, Reseller_Name__c, BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode,
				InvoiceAddress__Street__s, ShippingStreet, Payment_Method_Contracts__c
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

	/** Account synchronised once (ids + fingerprints stored), plus a second contact on it. */
	private static Contact syncedAccountWithSecondContact() {
		Account acc = account();
		Test.setMock(HttpCalloutMock.class, new ExactSim());
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false);
		Contact second = Test_Data.createContact(acc.Id, 'Second', null, 'second@sync.test', true);
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		return second;
	}

	private static AccountContactRelation relation(Id contactId) {
		return [
			SELECT Id, Sync_To_Financial_System__c, FinancialIdContact__c FROM AccountContactRelation
			WHERE ContactId = :contactId AND Account.Name LIKE 'Sync Account%' WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void contactStep_relationWithExactId_isPutWithoutAccountSync() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Contact(Id = second.Id, LastName = 'Renamed'), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = account().Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.syncFlaggedContacts(new Set<Id>{ acr.Id }, true);
		Test.stopTest();

		System.assertEquals(new List<String>{ 'PUT Contact' }, sim.calls, 'Only the contact is sent');
		System.assert(sim.body('PUT Contact').contains('Renamed'), sim.bodies);
		System.assertEquals(false, relation(second.Id).Sync_To_Financial_System__c, 'Relation flag cleared');
		System.assertEquals(false, account().SyncToFinancialSystem__c, 'No account sync needed');
		System.assert(account().FinancialSyncState__c.contains('contact:' + second.Id), 'Contact fingerprint stored on the account');
	}

	@IsTest
	static void contactStep_unchangedContact_noCall() {
		// the main contact was sent by the account sync: its fingerprint is in the account state
		syncedAccountWithSecondContact();
		Account acc = account();
		AccountContactRelation acr = relation(acc.Contact_person__c);
		System.assertNotEquals(null, acr.FinancialIdContact__c);
		Database.update(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.syncFlaggedContacts(new Set<Id>{ acr.Id }, true);
		Test.stopTest();
		System.assertEquals(new List<String>(), sim.calls, 'Fingerprint unchanged');
		System.assertEquals(false, relation(acc.Contact_person__c).Sync_To_Financial_System__c);
	}

	@IsTest
	static void contactStep_noExactId_withShippingRole_flagsAccount() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, Roles = 'Shipping'), AccessLevel.SYSTEM_MODE);
		Database.update(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = account().Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.syncFlaggedContacts(new Set<Id>{ acr.Id }, true);
		Test.stopTest();
		System.assertEquals(new List<String>(), sim.calls);
		System.assertEquals(true, account().SyncToFinancialSystem__c, 'The account sync creates the contact and links it to the address');
		System.assertEquals(true, relation(second.Id).Sync_To_Financial_System__c, 'Left to the account sync');
	}

	@IsTest
	static void contactStep_noExactId_noRole_isCleared() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, Roles = null, Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = account().Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Util_FinancialSystemAccount.syncFlaggedContacts(new Set<Id>{ acr.Id }, true);
		Test.stopTest();
		System.assertEquals(false, relation(second.Id).Sync_To_Financial_System__c);
		System.assertEquals(false, account().SyncToFinancialSystem__c, 'Not relevant for Exact');
	}

	@IsTest
	static void rbbRelation_roleChangeOfExactContact_setsFlag() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Roles = 'Digital', Sync_To_Financial_System__c = false), AccessLevel.SYSTEM_MODE);
		Database.update(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = false), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Database.update(new AccountContactRelation(Id = acr.Id, Roles = null), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		System.assertEquals(true, relation(second.Id).Sync_To_Financial_System__c, 'rbb_AccountContactRelation flags the role change');
	}

	@IsTest
	static void contactStep_roleRemoved_retiresExactContact() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Roles = null, Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = account().Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.syncFlaggedContacts(new Set<Id>{ acr.Id }, true);
		Test.stopTest();

		String body = sim.body('PUT Contact');
		System.assertNotEquals(null, body, sim.calls);
		System.assert(body.contains(Util_FinancialSystemAccount.DO_NOT_USE.trim()), body);
		System.assert(body.contains('"Email":""'), 'Email cleared: ' + body);
		System.assert(body.contains('"IsMailingExcluded":true'), body);
		System.assert(body.contains('"EndDate":"' + Datetime.now().formatGmt('yyyy-MM-dd')), 'Ended today (inactive): ' + body);
		System.assertEquals(false, relation(second.Id).Sync_To_Financial_System__c);
		System.assert(account().FinancialSyncState__c.contains(Util_FinancialSystemAccount.STATE_RETIRED), 'Retired state stored');
	}

	@IsTest
	static void contactStep_roleBack_restoresExactContact() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Account acc = account();
		Map<String, Object> state = (Map<String, Object>) JSON.deserializeUntyped(acc.FinancialSyncState__c);
		state.put('contact:' + second.Id, Util_FinancialSystemAccount.STATE_RETIRED + 'old');
		Database.update(new Account(Id = acc.Id, FinancialSyncState__c = JSON.serialize(state), SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Roles = 'Digital', Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.syncFlaggedContacts(new Set<Id>{ acr.Id }, true);
		Test.stopTest();

		String body = sim.body('PUT Contact');
		System.assertNotEquals(null, body, sim.calls);
		System.assert(!body.contains(Util_FinancialSystemAccount.DO_NOT_USE.trim()), body);
		System.assert(body.contains('"EndDate":null') && body.contains('"IsMailingExcluded":false'), 'Reactivated: ' + body);
		System.assert(body.contains('second@sync.test'), 'Email back: ' + body);
	}

	@IsTest
	static void contactRequest_alreadyRetired_keepsEndDate() {
		Contact con = new Contact(FirstName = 'A', LastName = 'B', Email = 'a@b.test');
		AccountContactRelation acr = new AccountContactRelation(Roles = null);
		acr.Contact = con;
		Util_FinancialSystemAccount.ContactRequest first = new Util_FinancialSystemAccount.ContactRequest('acc', acr, true, 'plainhash');
		Util_FinancialSystemAccount.ContactRequest again = new Util_FinancialSystemAccount.ContactRequest('acc', acr, true, first.fingerprint);
		System.assert(first.body.contains('EndDate'), first.body);
		System.assert(!again.body.contains('EndDate'), 'A change of a retired contact does not move its end date: ' + again.body);
		System.assertEquals(first.fingerprint, again.fingerprint);
		Util_FinancialSystemAccount.ContactRequest active = new Util_FinancialSystemAccount.ContactRequest('acc', acr, false, null);
		System.assert(!active.body.contains('EndDate') && !active.body.contains('IsMailingExcluded'), 'Active contact body unchanged: ' + active.body);
	}

	@IsTest
	static void contactBatch_runsTheContactStep() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Contact(Id = second.Id, LastName = 'Batch'), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = account().Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		insert new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemContactSync', Subscription25__Unique_Name__c = 'Batch_FinancialSystemContactSync');

		Test.setMock(HttpCalloutMock.class, new ExactSim());
		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemContactSync());
		Test.stopTest();
		System.assertEquals(false, relation(second.Id).Sync_To_Financial_System__c);
	}

	@IsTest
	static void accountSync_alsoSendsFlaggedRelationOutsideTheRoles() {
		Contact second = syncedAccountWithSecondContact();
		AccountContactRelation acr = relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Sync_To_Financial_System__c = true), AccessLevel.SYSTEM_MODE);
		Database.update(new Contact(Id = second.Id, LastName = 'Changed'), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ account().Id }, true);
		Test.stopTest();
		System.assertEquals(1, sim.count('PUT Contact'), sim.calls);
		System.assert(sim.body('PUT Contact').contains('con-guid-second') || sim.body('PUT Contact').contains('Changed'), sim.bodies);
		System.assertEquals(false, relation(second.Id).Sync_To_Financial_System__c);
	}

	@IsTest
	static void invoiceAddress_notSupplied_otherInvoiceContact_usesEstablishmentAddress() {
		Account acc = account();
		Contact billing = Test_Data.createContact(acc.Id, 'Billing', null, 'billing@sync.test', true);
		Database.update(new Account(Id = acc.Id, Contact_Billing__c = billing.Id,
			InvoiceAddress__Street__s = null, InvoiceAddress__PostalCode__s = null, InvoiceAddress__City__s = null), AccessLevel.SYSTEM_MODE);
		acc = account();

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false).get(acc.Id);
		Test.stopTest();

		System.assert(r.success, String.join(r.messages, ' | ') + ' ' + sim.calls);
		String body = sim.body('POST Address');
		System.assertNotEquals(null, body, 'Invoice address created for the other invoice contact: ' + sim.calls);
		System.assert(body.contains('"Type":3') && body.contains('"Main":true'), body);
		if (String.isBlank(acc.InvoiceAddress__Street__s)) {
			System.assert(body.contains(acc.BillingStreet.escapeJava()) || body.contains(acc.BillingStreet), 'Establishment address used: ' + body);
		}
		System.assertNotEquals(null, account().FinancialIdInvoiceAddress__c);
	}

	@IsTest
	static void invoiceAddress_existing_keptUpToDate_whenEqualToEstablishmentAgain() {
		// in Exact with an invoice address created earlier; now address and contact equal the establishment again
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'acc-guid-1', FinancialDebtorNumber__c = '12345', FinancialDebtorCheck__c = true,
			FinancialIdInvoiceAddress__c = 'address-guid-old', Contact_Billing__c = acc.Contact_person__c,
			InvoiceAddress__Street__s = acc.BillingStreet, InvoiceAddress__PostalCode__s = acc.BillingPostalCode,
			InvoiceAddress__City__s = acc.BillingCity, InvoiceAddress__CountryCode__s = acc.BillingCountryCode), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false).get(acc.Id);
		Test.stopTest();
		System.assert(r.success, String.join(r.messages, ' | ') + ' ' + sim.calls);
		System.assertEquals(1, sim.count('PUT Address'), 'Existing invoice address updated, not abandoned: ' + sim.calls);
		System.assertEquals(0, sim.count('POST Address'), sim.calls);
		System.assertEquals('address-guid-old', account().FinancialIdInvoiceAddress__c);
	}

	@IsTest
	static void accountSync_retiresQueuedRemovedContacts() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'acc-guid-1', FinancialDebtorNumber__c = '12345', FinancialDebtorCheck__c = true,
			FinancialContactsToRetire__c = '[{"id":"con-removed","firstName":"Old","lastName":"Person"}]'), AccessLevel.SYSTEM_MODE);

		ExactSim sim = new ExactSim();
		Test.setMock(HttpCalloutMock.class, sim);
		Test.startTest();
		Util_FinancialSystemAccount.Result r = Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ acc.Id }, false).get(acc.Id);
		Test.stopTest();

		System.assert(r.success, String.join(r.messages, ' | ') + ' ' + sim.calls);
		String body;
		for (String b : sim.bodies) {
			if (b.startsWith('PUT Contact') && b.contains('Person (DO NOT USE)')) {
				body = b;
			}
		}
		System.assertNotEquals(null, body, 'Removed contact retired: ' + sim.bodies);
		System.assert(body.contains('"Email":""') && body.contains('"IsMailingExcluded":true') && body.contains('EndDate'), body);
		System.assertEquals(null, [SELECT FinancialContactsToRetire__c FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE].FinancialContactsToRetire__c, 'Queue emptied');
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
