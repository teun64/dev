@IsTest
private class Test_rac_Order {

	// rac_Order dec_02_FinancialSync: a p0 account whose renewal order is I8 is queued for the account sync when its
	// Exact bank account or mandate id is missing (Exact refuses a direct debit invoice without a mandate)
	@TestSetup
	static void setup() {
		Map<String, String> resellerByName = new Map<String, String>{
			'No Ids' => '1', 'Bank Only' => '1', 'Both Ids' => '1', 'UK' => '6', 'On Account' => '1', 'No IBAN' => '1'
		};
		List<Account> accounts = new List<Account>();
		for (String name : resellerByName.keySet()) {
			Account acc = Test_Data.createAccount(name, (String) null, 'B2C', false);
			acc.Reseller_Name__c = resellerByName.get(name);
			accounts.add(acc);
		}
		Database.insert(accounts, AccessLevel.SYSTEM_MODE);
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		for (Account acc : accounts) {
			Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
		}

		// rbb_Account queues new accounts itself: start from an account the sync has done
		List<Account> upd = new List<Account>();
		for (Account acc : accounts) {
			Account u = new Account(Id = acc.Id, SyncToFinancialSystem__c = false, FinancialIdAccount__c = 'guid-account-' + acc.Name);
			if (acc.Name == 'Bank Only' || acc.Name == 'Both Ids') {
				u.FinancialIdBankAccount__c = 'guid-bank-' + acc.Name;
			}
			if (acc.Name == 'Both Ids') {
				u.FinancialIdBankMandate__c = 'guid-mandate-' + acc.Name;
			}
			if (acc.Name == 'No IBAN') {
				u.Bank_Account_Number__c = null;
			}
			upd.add(u);
		}
		Database.update(upd, AccessLevel.SYSTEM_MODE);
		upd.clear();
		for (Account acc : accounts) {
			// the reseller is overwritten on insert / debtor number: set it last
			upd.add(new Account(Id = acc.Id, SyncToFinancialSystem__c = false, Reseller_Name__c = resellerByName.get(acc.Name)));
		}
		Database.update(upd, AccessLevel.SYSTEM_MODE);
	}

	private static Map<String, Account> accounts() {
		Map<String, Account> byName = new Map<String, Account>();
		for (Account a : [SELECT Id, Name, SyncToFinancialSystem__c FROM Account WITH SYSTEM_MODE]) {
			byName.put(a.Name, a);
		}
		return byName;
	}

	@IsTest
	static void queuesP0AccountWithoutExactMandateOnDirectDebitOrder() {
		Map<String, Account> byName = accounts();
		for (Account a : byName.values()) {
			System.assertEquals(false, a.SyncToFinancialSystem__c, 'Setup: not queued yet - ' + a.Name);
		}
		Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c WITH SYSTEM_MODE LIMIT 1];
		List<Order> orders = new List<Order>();
		for (Account a : byName.values()) {
			Order ord = Test_Data.createOrder(a.Id, admin.Id, Date.today(), false);
			ord.Payment_Method__c = a.Name == 'On Account' ? '08' : 'I8';
			orders.add(ord);
		}

		Test.startTest();
		Database.insert(orders, AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		byName = accounts();
		System.assertEquals(true, byName.get('No Ids').SyncToFinancialSystem__c, 'No bank account / mandate in Exact: queued');
		System.assertEquals(true, byName.get('Bank Only').SyncToFinancialSystem__c, 'No mandate in Exact: queued');
		System.assertEquals(false, byName.get('Both Ids').SyncToFinancialSystem__c, 'Bank account and mandate in Exact');
		System.assertEquals(false, byName.get('UK').SyncToFinancialSystem__c, 'UK collects through Bottomline, no Exact mandate');
		System.assertEquals(false, byName.get('On Account').SyncToFinancialSystem__c, 'Not a direct debit order');
		System.assertEquals(false, byName.get('No IBAN').SyncToFinancialSystem__c, 'No bank account to sync');
	}
}
