@IsTest
private class Test_Svc_FinancialSystemSyncAlert {

	private static List<Svc_FinancialSystemSyncAlert.Issue> issues(Svc_FinancialSystemSyncAlert.Category c, String message) {
		return new List<Svc_FinancialSystemSyncAlert.Issue>{ new Svc_FinancialSystemSyncAlert.Issue(c, message) };
	}

	private static Account account() {
		Account acct = Test_Data.createAccount('Alert Account', (String) null, 'B2B', false);
		Database.insert(acct, AccessLevel.SYSTEM_MODE);
		return acct;
	}

	@IsTest
	static void categorize_byExceptionType() {
		System.assertEquals(Svc_FinancialSystemSyncAlert.Category.DATA,
			Svc_FinancialSystemSyncAlert.categorize(new Svc_FinancialSystemSyncAlert.DataException('x')));
		System.assertEquals(Svc_FinancialSystemSyncAlert.Category.SILENT,
			Svc_FinancialSystemSyncAlert.categorize(new Util_System.CustomException('x')));
		System.assertEquals(Svc_FinancialSystemSyncAlert.Category.TECHNICAL,
			Svc_FinancialSystemSyncAlert.categorize(new DmlException('x')));

		Util_FinancialSystem.lastErrorStatus = 400;
		System.assertEquals(Svc_FinancialSystemSyncAlert.Category.DATA,
			Svc_FinancialSystemSyncAlert.categorize(new Util_System.FinancialSyncException('Postcode invalid')), 'Exact validation message');
		Util_FinancialSystem.lastErrorStatus = 403;
		System.assertEquals(Svc_FinancialSystemSyncAlert.Category.TECHNICAL,
			Svc_FinancialSystemSyncAlert.categorize(new Util_System.FinancialSyncException('Forbidden')));
		Util_FinancialSystem.lastErrorStatus = null;
		System.assertEquals(Svc_FinancialSystemSyncAlert.Category.TECHNICAL,
			Svc_FinancialSystemSyncAlert.categorize(new Util_System.FinancialSyncException('Callout failed')));
	}

	@IsTest
	static void hardFailure_onlyData() {
		System.assertEquals('A', Svc_FinancialSystemSyncAlert.hardFailure(issues(Svc_FinancialSystemSyncAlert.Category.DATA, 'A')));
		System.assertEquals(null, Svc_FinancialSystemSyncAlert.hardFailure(issues(Svc_FinancialSystemSyncAlert.Category.TECHNICAL, 'B')));
		System.assertEquals(null, Svc_FinancialSystemSyncAlert.hardFailure(issues(Svc_FinancialSystemSyncAlert.Category.SILENT, 'C')));
	}

	@IsTest
	static void queueName_greeceAndBelgiumToNetherlands() {
		System.assertEquals('gqCaseAdministration1', Svc_FinancialSystemSyncAlert.queueName('1'));
		System.assertEquals('gqCaseAdministration1', Svc_FinancialSystemSyncAlert.queueName('2'));
		System.assertEquals('gqCaseAdministration1', Svc_FinancialSystemSyncAlert.queueName('3'));
		System.assertEquals('gqCaseAdministration1', Svc_FinancialSystemSyncAlert.queueName(null));
		System.assertEquals('gqCaseAdministration5', Svc_FinancialSystemSyncAlert.queueName('5'));
		System.assertEquals('gqCaseAdministration6', Svc_FinancialSystemSyncAlert.queueName('6'));
	}

	@IsTest
	static void isIntegrationProfile_peopleIncludingAdminsAreNot() {
		System.assert(Svc_FinancialSystemSyncAlert.isIntegrationProfile('miAPIIntegration'));
		System.assert(Svc_FinancialSystemSyncAlert.isIntegrationProfile('miSync'));
		System.assert(!Svc_FinancialSystemSyncAlert.isIntegrationProfile('System Administrator'));
		System.assert(!Svc_FinancialSystemSyncAlert.isIntegrationProfile('miSales'));
		System.assert(!Svc_FinancialSystemSyncAlert.isIntegrationProfile(null));
	}

	@IsTest
	static void send_activePersonNotified() {
		Account acct = account();
		Svc_FinancialSystemSyncAlert.Alert a = Svc_FinancialSystemSyncAlert.blocked(acct.Id, acct.Id, UserInfo.getUserId(), '1', 'Alert Account', 'Address missing', 'Fix it.');

		Map<Id, String> outcome = Svc_FinancialSystemSyncAlert.send(new List<Svc_FinancialSystemSyncAlert.Alert>{ a });

		System.assertEquals('Sync stopped; owner notified.', outcome.get(acct.Id));
		System.assertEquals(1, Svc_FinancialSystemSyncAlert.notified.size());
		System.assert(a.body.contains('Address missing') && a.body.contains('Fix it.'), a.body);
	}

	@IsTest
	static void send_inactiveOwner_caseForTheAdministrationQueue_once() {
		List<User> inactive = [SELECT Id FROM User WHERE IsActive = false AND UserType = 'Standard' LIMIT 1];
		List<Group> queue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'gqCaseAdministration1' LIMIT 1];
		if (inactive.isEmpty() || queue.isEmpty()) {
			return; // org without inactive users / queue not deployed yet
		}
		Account acct = account();
		// reseller 3 (BE) goes to the NL queue
		Svc_FinancialSystemSyncAlert.Alert a = Svc_FinancialSystemSyncAlert.blocked(acct.Id, acct.Id, inactive[0].Id, '3', 'Alert Account', 'Address missing', 'Fix it.');

		Map<Id, String> outcome = Svc_FinancialSystemSyncAlert.send(new List<Svc_FinancialSystemSyncAlert.Alert>{ a });

		System.assert(outcome.get(acct.Id).startsWith('Sync stopped; case created'), outcome.get(acct.Id));
		Case c = [SELECT OwnerId, AccountId, Origin, Subject FROM Case WHERE AccountId = :acct.Id WITH SYSTEM_MODE];
		System.assertEquals(queue[0].Id, c.OwnerId, 'Case flows keep the administration queue as owner');
		System.assertEquals('Automated', c.Origin);

		outcome = Svc_FinancialSystemSyncAlert.send(new List<Svc_FinancialSystemSyncAlert.Alert>{ a });
		System.assertEquals('Sync stopped; an open case already exists.', outcome.get(acct.Id));
	}

	@IsTest
	static void send_queueMissing_reportedNotThrown() {
		Account acct = account();
		List<User> inactive = [SELECT Id FROM User WHERE IsActive = false LIMIT 1];
		Id owner = inactive.isEmpty() ? acct.Id : inactive[0].Id; // a non-user owner id is routed to a case as well
		Svc_FinancialSystemSyncAlert.Alert a = Svc_FinancialSystemSyncAlert.blocked(acct.Id, acct.Id, owner, '4', 'Alert Account', 'X', 'Y');

		Map<Id, String> outcome = Svc_FinancialSystemSyncAlert.send(new List<Svc_FinancialSystemSyncAlert.Alert>{ a });

		System.assert(outcome.get(acct.Id).contains('gqCaseAdministration4 missing'), outcome.get(acct.Id));
	}
}
