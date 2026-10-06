@IsTest
private class Test_Svc_FinancialSystemContactRemoval {

	@TestSetup
	static void setup() {
		Account x = Test_Data.createAccount('Removal X', (String) null, 'B2B', false);
		x.Reseller_Name__c = '1';
		Account y = Test_Data.createAccount('Removal Y', (String) null, 'B2B', false);
		y.Reseller_Name__c = '1';
		Database.insert(new List<Account>{ x, y }, AccessLevel.SYSTEM_MODE);
		Database.update(new List<Account>{
			new Account(Id = x.Id, FinancialIdAccount__c = 'acc-x', SyncToFinancialSystem__c = false),
			new Account(Id = y.Id, FinancialIdAccount__c = 'acc-y', SyncToFinancialSystem__c = false)
		}, AccessLevel.SYSTEM_MODE);
	}

	private static Account acct(String name) {
		return [SELECT Id, FinancialContactsToRetire__c, SyncToFinancialSystem__c FROM Account WHERE Name = :name WITH SYSTEM_MODE];
	}

	private static Contact contact(Id accountId, String lastName) {
		// one at a time: rab_Contact faults on bulk Contact DML with Email
		return Test_Data.createContact(accountId, lastName, null, lastName.toLowerCase() + '@removal.test', true);
	}

	private static AccountContactRelation relation(Id accountId, Id contactId) {
		List<AccountContactRelation> acrs = [
			SELECT Id, Roles, FinancialIdContact__c, Sync_To_Financial_System__c, extId_1__c, extId_2__c
			FROM AccountContactRelation WHERE AccountId = :accountId AND ContactId = :contactId WITH SYSTEM_MODE
		];
		return acrs.isEmpty() ? null : acrs[0];
	}

	private static void setRelation(Id accountId, Id contactId, Map<String, Object> values) {
		AccountContactRelation acr = new AccountContactRelation(Id = relation(accountId, contactId).Id);
		for (String f : values.keySet()) {
			acr.put(f, values.get(f));
		}
		acr.Sync_To_Financial_System__c = false;
		Database.update(acr, AccessLevel.SYSTEM_MODE);
	}

	private static List<Svc_FinancialSystemContactRemoval.RetireEntry> queued(String accountName) {
		return Svc_FinancialSystemContactRemoval.readEntries(acct(accountName).FinancialContactsToRetire__c);
	}

	@IsTest
	static void deletedContact_queuesItsExactContact() {
		Account x = acct('Removal X');
		Contact keep = contact(x.Id, 'Keep');
		Contact gone = contact(x.Id, 'Gone');
		setRelation(x.Id, gone.Id, new Map<String, Object>{ 'FinancialIdContact__c' => 'g-gone' });

		Test.startTest();
		Database.delete(gone, AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		List<Svc_FinancialSystemContactRemoval.RetireEntry> entries = queued('Removal X');
		System.assertEquals(1, entries.size(), entries);
		System.assertEquals('g-gone', entries[0].id);
		System.assertEquals('Gone', entries[0].lastName);
		System.assertEquals(true, acct('Removal X').SyncToFinancialSystem__c, 'Account flagged for the account sync');
	}

	@IsTest
	static void removedRelation_queuesItsExactContact() {
		Account x = acct('Removal X');
		Account y = acct('Removal Y');
		Contact c = contact(y.Id, 'Indirect');
		AccountContactRelation indirect = new AccountContactRelation(AccountId = x.Id, ContactId = c.Id, Roles = 'Digital');
		Database.insert(indirect, AccessLevel.SYSTEM_MODE);
		setRelation(x.Id, c.Id, new Map<String, Object>{ 'FinancialIdContact__c' => 'g-indirect' });

		Test.startTest();
		Database.delete(new AccountContactRelation(Id = indirect.Id), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		List<Svc_FinancialSystemContactRemoval.RetireEntry> entries = queued('Removal X');
		System.assertEquals(1, entries.size(), entries);
		System.assertEquals('g-indirect', entries[0].id);
		System.assertEquals('Indirect', entries[0].lastName);
		System.assertEquals(0, queued('Removal Y').size(), 'The contact itself stays');
	}

	@IsTest
	static void merge_sameAccount_masterWithoutExactId_takesOver() {
		Account x = acct('Removal X');
		Contact master = contact(x.Id, 'Master');
		Contact loser = contact(x.Id, 'Loser');
		setRelation(x.Id, master.Id, new Map<String, Object>{ 'Roles' => null });
		setRelation(x.Id, loser.Id, new Map<String, Object>{ 'FinancialIdContact__c' => 'g-loser', 'Roles' => 'Digital', 'extId_1__c' => 'p-loser' });

		Test.startTest();
		Database.merge(master, loser.Id);
		Test.stopTest();

		AccountContactRelation acr = relation(x.Id, master.Id);
		System.assertEquals('g-loser', acr.FinancialIdContact__c, 'Master takes over the Exact contact');
		System.assertEquals(true, acr.Sync_To_Financial_System__c, 'Contact update sends the master name / email');
		System.assertEquals('Digital', acr.Roles, 'Master had no roles: takes the loser roles');
		System.assertEquals('p-loser', acr.extId_1__c, 'Empty platform id taken over');
		System.assertEquals(0, queued('Removal X').size(), 'Nothing to retire');
	}

	@IsTest
	static void merge_sameAccount_masterWithOwnIds_keepsThem_retiresLoser() {
		Account x = acct('Removal X');
		Contact master = contact(x.Id, 'Master');
		Contact loser = contact(x.Id, 'Loser');
		setRelation(x.Id, master.Id, new Map<String, Object>{ 'FinancialIdContact__c' => 'g-master', 'Roles' => 'Main', 'extId_1__c' => 'p-master' });
		setRelation(x.Id, loser.Id, new Map<String, Object>{ 'FinancialIdContact__c' => 'g-loser', 'Roles' => 'Digital', 'extId_1__c' => 'p-loser', 'extId_2__c' => 'p2-loser' });

		Test.startTest();
		Database.merge(master, loser.Id);
		Test.stopTest();

		AccountContactRelation acr = relation(x.Id, master.Id);
		System.assertEquals('g-master', acr.FinancialIdContact__c);
		System.assertEquals('p-master', acr.extId_1__c, 'Own platform id kept');
		System.assertEquals('p2-loser', acr.extId_2__c, 'Empty platform id taken over');
		System.assert(!acr.Roles.contains('Digital'), 'Master has roles: left as is (' + acr.Roles + ')');
		List<Svc_FinancialSystemContactRemoval.RetireEntry> entries = queued('Removal X');
		System.assertEquals(1, entries.size(), entries);
		System.assertEquals('g-loser', entries[0].id);
	}

	@IsTest
	static void merge_otherAccount_createsRelationForMaster() {
		Account x = acct('Removal X');
		Account y = acct('Removal Y');
		Contact master = contact(x.Id, 'Master');
		Contact loser = contact(y.Id, 'Loser');
		setRelation(y.Id, loser.Id, new Map<String, Object>{ 'FinancialIdContact__c' => 'g-y', 'Roles' => 'Digital', 'extId_2__c' => 'p-y' });

		Test.startTest();
		Database.merge(master, loser.Id);
		Test.stopTest();

		AccountContactRelation acr = relation(y.Id, master.Id);
		System.assertNotEquals(null, acr, 'Master gets a relation with the loser account');
		System.assertEquals('g-y', acr.FinancialIdContact__c);
		System.assertEquals('Digital', acr.Roles);
		System.assertEquals('p-y', acr.extId_2__c);
		System.assertEquals(true, acr.Sync_To_Financial_System__c);
		System.assertEquals(0, queued('Removal Y').size());
	}
}
