@IsTest
private class Test_Svc_AccountContactRelationRoles {

	@TestSetup
	static void setup() {
		Account acc = Test_Data.createAccount('Roles Account', (String) null, 'B2B', true);
		// one at a time: rab_Contact faults on bulk Contact DML with Email
		Test_Data.createContact(acc.Id, 'Chris', null, 'chris@roles.test', true);
		Test_Data.createContact(acc.Id, 'Afdeling', null, 'afdeling@roles.test', true);
		Test_Data.createContact(acc.Id, 'Mart', null, 'mart@roles.test', true);
		Test_Data.createContact(acc.Id, 'Noemail', null, null, true);
	}

	private static Account account() {
		return [SELECT Id, Contact_person__c, Contact_Billing__c, Contact_Shipping__c, Subscription25__Billing_Attendant_To__c,
			Subscription25__UBL_Billing_Attendant_To__c, Subscription25__Reminder_Contact__c FROM Account WHERE Name = 'Roles Account' WITH SYSTEM_MODE];
	}

	private static AccountContactRelation relation(String lastName) {
		return [SELECT Id, ContactId, Roles, RoleRemovalAlert__c FROM AccountContactRelation
			WHERE Account.Name = 'Roles Account' AND Contact.LastName = :lastName WITH SYSTEM_MODE];
	}

	private static Set<String> roles(String lastName) {
		String r = relation(lastName).Roles;
		return String.isBlank(r) ? new Set<String>() : new Set<String>(r.split(';'));
	}

	private static void setRoles(Map<String, String> rolesByName) {
		List<AccountContactRelation> rows = new List<AccountContactRelation>();
		for (String name : rolesByName.keySet()) {
			rows.add(new AccountContactRelation(Id = relation(name).Id, Roles = rolesByName.get(name)));
		}
		Database.update(rows, AccessLevel.SYSTEM_MODE);
	}

	// the acc case of 2026-10-15: two roles move in one save, a third relation held both
	@IsTest
	static void twoRolesMoveInOneSave_thirdRelationLosesBoth() {
		setRoles(new Map<String, String>{ 'Chris' => 'Main;Shipping', 'Afdeling' => 'Invoice;Digital', 'Mart' => 'Payment;Reminder;Sales' });

		Test.startTest();
		setRoles(new Map<String, String>{ 'Chris' => 'Main;Shipping;Payment', 'Afdeling' => 'Invoice;Digital;Reminder' });
		Test.stopTest();

		System.assertEquals(new Set<String>{ 'Sales' }, roles('Mart'), 'Mart loses Payment and Reminder, keeps Sales');
		System.assertEquals(new Set<String>{ 'Main', 'Shipping', 'Payment' }, roles('Chris'));
		System.assertEquals(new Set<String>{ 'Invoice', 'Digital', 'Reminder' }, roles('Afdeling'));
		Account acc = account();
		System.assertEquals(relation('Afdeling').ContactId, acc.Subscription25__Reminder_Contact__c);
	}

	@IsTest
	static void gainedRole_winsAndMovesTheLookups() {
		setRoles(new Map<String, String>{ 'Chris' => 'Main;Invoice;Shipping;Digital' });
		Account before = account();
		System.assertEquals(relation('Chris').ContactId, before.Contact_person__c);
		System.assertEquals(relation('Chris').ContactId, before.Contact_Billing__c);
		System.assertEquals(relation('Chris').ContactId, before.Subscription25__Billing_Attendant_To__c);
		System.assertEquals(relation('Chris').ContactId, before.Subscription25__UBL_Billing_Attendant_To__c);
		System.assertEquals(relation('Chris').ContactId, before.Contact_Shipping__c);

		Test.startTest();
		setRoles(new Map<String, String>{ 'Afdeling' => 'Invoice;Digital;Service' });
		Test.stopTest();

		System.assertEquals(new Set<String>{ 'Main', 'Shipping' }, roles('Chris'));
		System.assertEquals(new Set<String>{ 'Invoice', 'Digital', 'Service' }, roles('Afdeling'));
		Account acc = account();
		System.assertEquals(relation('Chris').ContactId, acc.Contact_person__c);
		System.assertEquals(relation('Afdeling').ContactId, acc.Contact_Billing__c);
		System.assertEquals(relation('Afdeling').ContactId, acc.Subscription25__Billing_Attendant_To__c);
		System.assertEquals(relation('Afdeling').ContactId, acc.Subscription25__UBL_Billing_Attendant_To__c);
	}

	@IsTest
	static void sameRoleGainedTwiceInOneSave_lastOneWins() {
		Test.startTest();
		List<AccountContactRelation> rows = new List<AccountContactRelation>{
			new AccountContactRelation(Id = relation('Chris').Id, Roles = 'Main'),
			new AccountContactRelation(Id = relation('Mart').Id, Roles = 'Main')
		};
		Database.update(rows, AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		System.assertEquals(new Set<String>(), roles('Chris'));
		System.assertEquals(new Set<String>{ 'Main' }, roles('Mart'));
		System.assertEquals(relation('Mart').ContactId, account().Contact_person__c);
	}

	@IsTest
	static void noEmail_rolesRemovedWithAlert_mainAndShippingStay() {
		setRoles(new Map<String, String>{ 'Chris' => 'Main' });

		Test.startTest();
		// Invoice / Digital / Reminder without an email address are refused by a validation rule already
		setRoles(new Map<String, String>{ 'Noemail' => 'Main;Shipping;Payment;Sales' });
		Test.stopTest();

		AccountContactRelation acr = relation('Noemail');
		System.assertEquals(new Set<String>{ 'Main', 'Shipping', 'Sales' }, roles('Noemail'), 'Main needs no email address');
		System.assert(acr.RoleRemovalAlert__c.contains('Payment') && !acr.RoleRemovalAlert__c.contains('Main'), acr.RoleRemovalAlert__c);
		System.assertEquals(new Set<String>(), roles('Chris'), 'Main moved to Noemail');
		Account acc = account();
		System.assertEquals(acr.ContactId, acc.Contact_person__c);
		System.assertEquals(acr.ContactId, acc.Contact_Shipping__c);
	}

	@IsTest
	static void otherRolesAndAccountsUntouched() {
		Account other = Test_Data.createAccount('Other Account', (String) null, 'B2B', true);
		Contact otherContact = Test_Data.createContact(other.Id, 'Elsewhere', null, 'elsewhere@roles.test', true);
		AccountContactRelation otherAcr = [SELECT Id FROM AccountContactRelation WHERE ContactId = :otherContact.Id];
		Database.update(new AccountContactRelation(Id = otherAcr.Id, Roles = 'Main;Payment'), AccessLevel.SYSTEM_MODE);
		setRoles(new Map<String, String>{ 'Mart' => 'Sales;Service;ASR' });

		Test.startTest();
		setRoles(new Map<String, String>{ 'Chris' => 'Main;Payment;Sales' });
		Test.stopTest();

		System.assertEquals(new Set<String>{ 'Sales', 'Service', 'ASR' }, roles('Mart'));
		System.assertEquals('Main;Payment', [SELECT Roles FROM AccountContactRelation WHERE Id = :otherAcr.Id].Roles);
	}

	@IsTest
	static void insertedRelation_takesItsRoles() {
		Account other = Test_Data.createAccount('Other Account', (String) null, 'B2B', true);
		Contact outside = Test_Data.createContact(other.Id, 'Outside', null, 'outside@roles.test', true);
		setRoles(new Map<String, String>{ 'Chris' => 'Main;Shipping' });

		Test.startTest();
		Database.insert(new AccountContactRelation(AccountId = account().Id, ContactId = outside.Id, Roles = 'Shipping'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		System.assertEquals(new Set<String>{ 'Main' }, roles('Chris'));
		System.assertEquals(outside.Id, account().Contact_Shipping__c);
	}
}
