@IsTest
private class Test_Batch_RotatePreferenceTokens {

	@TestSetup
	static void makeData() {
		insert new PreferenceTokenConfig__c(
			SetupOwnerId = UserInfo.getOrganizationId(),
			Secret__c    = 'unit-test-secret',
			Base_Url__c  = 'https://example.my.site.com/customerhub'
		);
		insert new Subscription25__Schedulable_Class__c(Name = 'Batch_RotatePreferenceTokens', Subscription25__Unique_Name__c = 'Batch_RotatePreferenceTokens');
	}

	private static Contact makeContact(String email) {
		Contact c = new Contact(FirstName = 'Rota', LastName = 'Tester' + email.left(4), Email = email);
		insert c;
		return [SELECT Id, Email, Preference_Token_Key__c, Preference_Token_Previous__c, Preference_Token_Date__c, Preference_Center_Url__c FROM Contact WHERE Id = :c.Id];
	}

	@IsTest
	static void testTriggerStampsKeyAndDate() {
		Contact c = makeContact('rotate.new@example.com');
		System.assertNotEquals(null, c.Preference_Token_Key__c);
		System.assertEquals(64, c.Preference_Token_Key__c.length(), 'Stays a 64 character hex key');
		System.assertEquals(Date.today(), c.Preference_Token_Date__c);
		System.assertEquals(null, c.Preference_Token_Previous__c);
	}

	@IsTest
	static void testRotationMovesOldKeyToPrevious() {
		Contact c = makeContact('rotate.old@example.com');
		String oldKey = c.Preference_Token_Key__c;
		// Pretend the token is a legacy one, 100 days old, from a different period.
		update new Contact(
			Id = c.Id,
			Preference_Token_Key__c = Util_CommunicationPreferenceToken.hashEmail(c.Email, '202001'),
			Preference_Token_Date__c = Date.today().addDays(-100)
		);
		String legacyKey = [SELECT Preference_Token_Key__c FROM Contact WHERE Id = :c.Id].Preference_Token_Key__c;

		Test.startTest();
		Database.executeBatch(new Batch_RotatePreferenceTokens(), 100);
		Test.stopTest();

		Contact after = [SELECT Preference_Token_Key__c, Preference_Token_Previous__c, Preference_Token_Date__c, Preference_Center_Url__c FROM Contact WHERE Id = :c.Id];
		System.assertEquals(oldKey, after.Preference_Token_Key__c, 'New key is the key of the current period');
		System.assertEquals(legacyKey, after.Preference_Token_Previous__c, 'Old key moved to previous');
		System.assertEquals(Date.today(), after.Preference_Token_Date__c);
		System.assert(after.Preference_Center_Url__c.contains(oldKey), 'Link carries the new key');
	}

	@IsTest
	static void testFreshTokenIsNotRotated() {
		Contact c = makeContact('rotate.fresh@example.com');
		Test.startTest();
		Database.executeBatch(new Batch_RotatePreferenceTokens(), 100);
		Test.stopTest();
		Contact after = [SELECT Preference_Token_Key__c, Preference_Token_Previous__c FROM Contact WHERE Id = :c.Id];
		System.assertEquals(c.Preference_Token_Key__c, after.Preference_Token_Key__c);
		System.assertEquals(null, after.Preference_Token_Previous__c);
	}

	@IsTest
	static void testGuestAcceptsCurrentAndPreviousButNotOlder() {
		Contact c = makeContact('rotate.guest@example.com');
		String legacyKey = Util_CommunicationPreferenceToken.hashEmail(c.Email, '202001');
		update new Contact(Id = c.Id, Preference_Token_Key__c = legacyKey, Preference_Token_Date__c = Date.today().addDays(-100));
		Database.executeBatch(new Batch_RotatePreferenceTokens(), 100);
		Test.startTest();
		Test.stopTest();
		Contact after = [SELECT Preference_Token_Key__c, Preference_Token_Previous__c FROM Contact WHERE Id = :c.Id];

		Ctrl_PreferenceCenterGuest.Resolved current = Ctrl_PreferenceCenterGuest.resolve(after.Preference_Token_Key__c);
		System.assertEquals(false, current.stale);
		Ctrl_PreferenceCenterGuest.Resolved previous = Ctrl_PreferenceCenterGuest.resolve(legacyKey);
		System.assertEquals(true, previous.stale, 'Previous key works but is flagged');
		System.assertEquals(current.contactId, previous.contactId);

		try {
			Ctrl_PreferenceCenterGuest.resolve(Util_CommunicationPreferenceToken.hashEmail(c.Email, '201901'));
			System.assert(false, 'An older key must be rejected');
		} catch (AuraHandledException e) {
			System.assertEquals(Ctrl_PreferenceCenterGuest.EXPIRED_MESSAGE, e.getMessage());
		}
	}

	@IsTest
	static void testEmailChangeInvalidatesOldLinks() {
		Contact c = makeContact('rotate.mail@example.com');
		String before = c.Preference_Token_Key__c;
		update new Contact(Id = c.Id, Email = 'rotate.mail2@example.com');
		Contact after = [SELECT Preference_Token_Key__c, Preference_Token_Previous__c FROM Contact WHERE Id = :c.Id];
		System.assertNotEquals(before, after.Preference_Token_Key__c);
		System.assertEquals(null, after.Preference_Token_Previous__c, 'Old links must not survive an email change');
	}
}
