@IsTest
private class Test_Batch_FinancialSystemForceSync {

	@TestSetup
	static void setup() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		List<Account> accounts = new List<Account>();
		for (String name : new List<String>{ 'Due Soon', 'Due Later', 'Not Forced' }) {
			Account acc = Test_Data.createAccount(name, (String) null, 'B2B', false);
			acc.Reseller_Name__c = '1';
			accounts.add(acc);
		}
		Database.insert(accounts, AccessLevel.SYSTEM_MODE);
		List<Account> upd = new List<Account>();
		for (Account acc : accounts) {
			upd.add(new Account(Id = acc.Id, FinancialIdAccount__c = 'guid-' + acc.Name, SyncToFinancialSystem__c = false,
				FinancialSyncForce__c = acc.Name != 'Not Forced'));
		}
		Database.update(upd, AccessLevel.SYSTEM_MODE);
		List<Contract> contracts = new List<Contract>();
		for (Account acc : accounts) {
			Contract c = Test_Data.createContract(acc.Id, admin.Id, false);
			// Subscription25 derives Next_Date__c (next invoice date) from the start date and overrides a set value
			c.StartDate = acc.Name == 'Due Later' ? Date.today().addDays(30) : Date.today().addDays(3);
			contracts.add(c);
		}
		Database.insert(contracts, AccessLevel.SYSTEM_MODE);
		for (Contract c : contracts) {
			c.Status = 'Activated';
		}
		Database.update(contracts, AccessLevel.SYSTEM_MODE);
	}

	private static Map<String, Account> accounts() {
		Map<String, Account> byName = new Map<String, Account>();
		for (Account a : [SELECT Id, Name, SyncToFinancialSystem__c, FinancialSyncForce__c FROM Account WITH SYSTEM_MODE]) {
			byName.put(a.Name, a);
		}
		return byName;
	}

	@IsTest
	static void queuesForcedAccountsWithInvoiceDueSoon() {
		// Subscription25 v2.66 (acc/prod) needs the job configuration record
		Database.insert(new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemForceSync', Subscription25__Unique_Name__c = 'Batch_FinancialSystemForceSync'), AccessLevel.SYSTEM_MODE);
		Batch_FinancialSystemForceSync job = new Batch_FinancialSystemForceSync();
		List<SObject> scope = new List<SObject>();
		Database.QueryLocatorIterator it = job.startBatch(null).iterator();
		while (it.hasNext()) {
			scope.add(it.next());
		}

		Test.startTest();
		job.executeBatch(null, scope);
		Test.stopTest();

		Map<String, Account> byName = accounts();
		System.assertEquals(1, scope.size(), 'Only the forced account invoiced within ' + Batch_FinancialSystemForceSync.DAYS_AHEAD + ' days: ' + scope);
		System.assertEquals(true, byName.get('Due Soon').SyncToFinancialSystem__c, 'Queued for the account sync');
		System.assertEquals(true, byName.get('Due Soon').FinancialSyncForce__c, 'Marker stays until the account sync succeeds');
		System.assertEquals(false, byName.get('Due Later').SyncToFinancialSystem__c, 'Invoice not due yet');
		System.assertEquals(false, byName.get('Not Forced').SyncToFinancialSystem__c, 'No marker');
		System.assertEquals(200, job.getBatchSize());
	}
}
