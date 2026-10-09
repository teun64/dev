@IsTest
private class Test_Batch_BackfillPreferenceCenterUrl {

	@TestSetup
	static void makeData() {
		insert new PreferenceTokenConfig__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Secret__c    = 'unit-test-secret',
			Base_Url__c  = 'https://example.my.site.com/customerhub'
		);

		Account acc = Test_Data.createAccount('ACME PreferenceBackfill BV', '9024', 'B2B', false);
		insert acc;

		// Inserted one at a time - the "rab - Contact" flow faults on a bulk multi-row
		// Contact insert/update in this org (unhandled fault, CANNOT_EXECUTE_FLOW_TRIGGER).
		Contact missing  = new Contact(FirstName = 'Missing', LastName = 'BackfillTester', Email = 'missing@example.com');
		Contact noEmail  = new Contact(FirstName = 'NoEmail', LastName = 'BackfillTester');
		Contact excluded = new Contact(AccountId = acc.Id, FirstName = 'Excluded', LastName = 'BackfillTester', Email = 'excluded@example.com');
		insert missing;
		insert noEmail;
		insert excluded;

		AccountContactRelation acr = [
			SELECT Id, Roles FROM AccountContactRelation
			WHERE AccountId = :acc.Id AND ContactId = :excluded.Id LIMIT 1
		];
		acr.Roles = 'Invoice'; // invoice-only -> Marketing__c = false -> excluded from marketing
		update acr;

		// Simulate Contacts created before the Preference Center went live: Trigger_Contact stamped them on insert,
		// clearing the fields without an Email change does not re-stamp.
		update new Contact(Id = missing.Id, Preference_Token_Key__c = null, Preference_Center_Url__c = null);
		update new Contact(Id = excluded.Id, Preference_Token_Key__c = null, Preference_Center_Url__c = null);
	}

	private static Contact getContact(String firstName) {
		return [
			SELECT Id, Email, Preference_Token_Key__c, Preference_Center_Url__c
			FROM Contact WHERE FirstName = :firstName AND LastName = 'BackfillTester' LIMIT 1
		];
	}

	@IsTest
	static void testBackfill_stampsMissingLink() {
		Test.startTest();
		Database.executeBatch(new Batch_BackfillPreferenceCenterUrl(), 100);
		Test.stopTest();

		Contact missing = getContact('Missing');
		String expectedKey = Util_CommunicationPreferenceToken.hashEmail('missing@example.com');
		System.assertEquals(expectedKey, missing.Preference_Token_Key__c, 'Key hash is stamped');
		System.assertEquals(
			Util_CommunicationPreferenceToken.buildPreferenceCenterUrl(expectedKey),
			missing.Preference_Center_Url__c,
			'Url is built from the stamped key hash'
		);
	}

	@IsTest
	static void testBackfill_skipsExcludedAndNoEmail() {
		Test.startTest();
		Database.executeBatch(new Batch_BackfillPreferenceCenterUrl(), 100);
		Test.stopTest();

		System.assertEquals(null, getContact('Excluded').Preference_Center_Url__c, 'Invoice-only Contact gets no link');
		System.assertEquals(null, getContact('NoEmail').Preference_Center_Url__c, 'Contact without Email gets no link');
	}

	@IsTest
	static void testBackfill_dryRunChangesNothing() {
		Test.startTest();
		Database.executeBatch(new Batch_BackfillPreferenceCenterUrl(true), 100);
		Test.stopTest();

		System.assertEquals(null, getContact('Missing').Preference_Center_Url__c, 'Dry run does no DML');
	}
}
