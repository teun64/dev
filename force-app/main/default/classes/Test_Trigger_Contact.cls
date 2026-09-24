@IsTest
private class Test_Trigger_Contact {

	@TestSetup
	static void makeData() {
		insert new Subscription25__Schedulable_Class__c(
			Name = 'Batch_DedupeCommunicationPreferences', Subscription25__Unique_Name__c = 'Batch_DedupeCommunicationPreferences');
		insert new List<CommunicationPreferenceConfig__c>{
			new CommunicationPreferenceConfig__c(Brand__c = 'M', CommunicationType__c = 'NEWSLETTER', Channel__c = 'EMAIL', Category__c = 'MARKETING'),
			new CommunicationPreferenceConfig__c(Brand__c = 'M', CommunicationType__c = 'PROMOTIONS', Channel__c = 'EMAIL', Category__c = 'MARKETING')
		};
	}

	// Distinct, non-realistic names and allowSave: prod's Contact Duplicate Rules otherwise
	// block test inserts that sandboxes accept.
	private static List<Contact> createContacts(String lastNamePrefix, Integer count) {
		List<Contact> contacts = new List<Contact>();
		for (Integer i = 0; i < count; i++) {
			contacts.add(new Contact(FirstName = 'Rbd', LastName = lastNamePrefix + i));
		}
		Database.DMLOptions dml = new Database.DMLOptions();
		dml.DuplicateRuleHeader.allowSave = true;
		Database.insert(contacts, dml);
		return contacts;
	}

	private static List<CommunicationPreference__c> createPreferences(List<Contact> contacts, Id configId) {
		List<CommunicationPreference__c> prefs = new List<CommunicationPreference__c>();
		for (Contact c : contacts) {
			prefs.add(new CommunicationPreference__c(Contact__c = c.Id, Config__c = configId));
		}
		insert prefs;
		return prefs;
	}

	@IsTest
	static void testDelete_removesPreferences() {
		Id configId = [SELECT Id FROM CommunicationPreferenceConfig__c LIMIT 1].Id;
		List<Contact> contacts = createContacts('RbdDeleteTest', 1);
		List<CommunicationPreference__c> prefs = createPreferences(contacts, configId);

		Test.startTest();
		delete contacts;
		Test.stopTest();

		System.assertEquals(0, [SELECT COUNT() FROM CommunicationPreference__c WHERE Id IN :prefs],
			'Preferences of a deleted Contact should be deleted');
	}

	@IsTest
	static void testDelete_bulk() {
		Id configId = [SELECT Id FROM CommunicationPreferenceConfig__c LIMIT 1].Id;
		List<Contact> contacts = createContacts('RbdBulkTest', 200);
		List<CommunicationPreference__c> prefs = createPreferences(contacts, configId);

		Test.startTest();
		delete contacts;
		Test.stopTest();

		System.assertEquals(0, [SELECT COUNT() FROM CommunicationPreference__c WHERE Id IN :prefs],
			'Preferences of all deleted Contacts should be deleted');
	}

	@IsTest
	static void testMerge_keepsLoserPreferencesOnMaster() {
		List<CommunicationPreferenceConfig__c> configs = [SELECT Id FROM CommunicationPreferenceConfig__c ORDER BY CommunicationType__c];
		List<Contact> contacts = createContacts('RbdMergeTest', 2);
		Contact master = contacts[0];
		Contact loser = contacts[1];
		CommunicationPreference__c masterPref = createPreferences(new List<Contact>{ master }, configs[0].Id)[0];
		CommunicationPreference__c loserPref = createPreferences(new List<Contact>{ loser }, configs[1].Id)[0];

		Test.startTest();
		merge master loser;
		Test.stopTest();

		Map<Id, CommunicationPreference__c> prefs = new Map<Id, CommunicationPreference__c>(
			[SELECT Id, Contact__c FROM CommunicationPreference__c WHERE Id IN (:masterPref.Id, :loserPref.Id)]);
		System.assertEquals(2, prefs.size(), 'Merge should not delete any preferences');
		System.assertEquals(master.Id, prefs.get(loserPref.Id).Contact__c, 'Loser preference should move to the master');
		System.assertEquals(master.Id, prefs.get(masterPref.Id).Contact__c, 'Master preference should stay on the master');
	}

	// Master and loser with a preference for the same config, differing in date and opt-in.
	private static List<CommunicationPreference__c> createConflictingPair(Contact master, Contact loser,
			Datetime masterDate, Boolean masterEnabled, Datetime loserDate, Boolean loserEnabled) {
		Id configId = [SELECT Id FROM CommunicationPreferenceConfig__c LIMIT 1].Id;
		List<CommunicationPreference__c> prefs = new List<CommunicationPreference__c>{
			new CommunicationPreference__c(Contact__c = master.Id, Config__c = configId, EffectiveDate__c = masterDate, IsEnabled__c = masterEnabled),
			new CommunicationPreference__c(Contact__c = loser.Id, Config__c = configId, EffectiveDate__c = loserDate, IsEnabled__c = loserEnabled)
		};
		insert prefs;
		return prefs;
	}

	private static List<CommunicationPreference__c> prefsOf(Id contactId) {
		return [SELECT Id, IsEnabled__c, CompositeKey__c FROM CommunicationPreference__c WHERE Contact__c = :contactId];
	}

	@IsTest
	static void testMerge_sameConfig_latestEffectiveDateWins() {
		List<Contact> contacts = createContacts('RbdMergeDupTest', 2);
		Contact master = contacts[0];
		Contact loser = contacts[1];
		List<CommunicationPreference__c> prefs = createConflictingPair(master, loser,
			Datetime.now().addDays(-10), true, Datetime.now().addDays(-1), false);

		Test.startTest();
		merge master loser;
		Test.stopTest();

		List<CommunicationPreference__c> remaining = prefsOf(master.Id);
		System.assertEquals(1, remaining.size(), 'Duplicate preference should be collapsed to one');
		System.assertEquals(prefs[1].Id, remaining[0].Id, 'The more recent (loser) preference should survive');
		System.assertEquals(false, remaining[0].IsEnabled__c);
		System.assert(remaining[0].CompositeKey__c.startsWith(String.valueOf(master.Id)), 'Composite key should point at the master');
	}

	@IsTest
	static void testMerge_sameConfig_tieOptOutWins() {
		List<Contact> contacts = createContacts('RbdMergeTieTest', 2);
		Contact master = contacts[0];
		Contact loser = contacts[1];
		Datetime sameDate = Datetime.now().addDays(-5);
		List<CommunicationPreference__c> prefs = createConflictingPair(master, loser, sameDate, false, sameDate, true);

		Test.startTest();
		merge master loser;
		Test.stopTest();

		List<CommunicationPreference__c> remaining = prefsOf(master.Id);
		System.assertEquals(1, remaining.size());
		System.assertEquals(prefs[0].Id, remaining[0].Id, 'On a tie the opt-out should survive');
	}

	// Reproduces the pre-fix merge result: a duplicate on the master with a stale composite key.
	private static Contact createMergedDuplicate(String lastNamePrefix) {
		List<Contact> contacts = createContacts(lastNamePrefix, 2);
		Contact master = contacts[0];
		createConflictingPair(master, contacts[1], Datetime.now().addDays(-10), true, Datetime.now().addDays(-1), false);
		Trigger_Contact.skipMergeDedupe = true;
		merge master contacts[1];
		Trigger_Contact.skipMergeDedupe = false;
		System.assertEquals(2, prefsOf(master.Id).size(), 'Setup: merge without dedupe leaves a duplicate');
		return master;
	}

	@IsTest
	static void testBatch_dryRunChangesNothing() {
		Contact master = createMergedDuplicate('RbdBatchDryTest');

		Svc_CommunicationPreferenceDedupe.Result dry = Svc_CommunicationPreferenceDedupe.dedupe(new Set<Id>{ master.Id }, true);
		System.assertEquals(1, dry.deleted);
		System.assertEquals(1, dry.keysRepaired);
		System.assertEquals(1, dry.enabledConflicts);

		Test.startTest();
		Database.executeBatch(new Batch_DedupeCommunicationPreferences(true), 200);
		Test.stopTest();

		System.assertEquals(2, prefsOf(master.Id).size(), 'Dry run must not change data');
	}

	@IsTest
	static void testBatch_realRunCleansUp() {
		Contact master = createMergedDuplicate('RbdBatchRealTest');

		Test.startTest();
		Database.executeBatch(new Batch_DedupeCommunicationPreferences(), 200);
		Test.stopTest();

		List<CommunicationPreference__c> remaining = prefsOf(master.Id);
		System.assertEquals(1, remaining.size(), 'Real run should collapse the duplicate');
		System.assertEquals(false, remaining[0].IsEnabled__c, 'The more recent opt-out should survive');
		System.assert(remaining[0].CompositeKey__c.startsWith(String.valueOf(master.Id)), 'Composite key should be repaired');
	}
}
