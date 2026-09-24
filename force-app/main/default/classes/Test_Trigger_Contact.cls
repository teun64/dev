@IsTest
private class Test_Trigger_Contact {

	@TestSetup
	static void makeData() {
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
}
