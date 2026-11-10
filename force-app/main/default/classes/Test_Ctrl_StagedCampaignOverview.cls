/**
 * Tests Ctrl_StagedCampaignOverview (status, release and revenue on the parent of a staged campaign).
 */
@IsTest
private class Test_Ctrl_StagedCampaignOverview {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Overview Account', (String) null, 'B2B', true);
		Campaign parent = new Campaign(Name = 'Overview', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : Ctrl_StagedCampaignOverview.ROLES) {
			children.add(new Campaign(Name = 'Overview - ' + role, ParentId = parent.Id, IsActive = true, CampaignRole__c = role));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		// one Contact per insert: "rab - Contact" faults on a multi-row Contact insert
		List<CampaignMember> members = new List<CampaignMember>();
		for (Integer i = 0; i < 5; i++) {
			Contact con = Test_Data.createContact(acct.Id, i == 0 ? 'Main' : 'Other', null, 'o' + i + '@overview.test', true);
			members.add(new CampaignMember(CampaignId = children[0].Id, ContactId = con.Id, Priority__c = 11 + i));
		}
		members[0].RecontactFrom__c = Date.today().addMonths(4);   // "Not now": parked
		members[0].Response__c = 'Not now';
		members[0].MailBatch__c = 1;
		Database.insert(members, AccessLevel.SYSTEM_MODE);
	}

	static Campaign parent() {
		return [SELECT Id FROM Campaign WHERE Name = 'Overview' WITH SYSTEM_MODE];
	}

	@IsTest
	static void overview_countsSourceAndReactions() {
		Test.startTest();
		Ctrl_StagedCampaignOverview.Overview o = Ctrl_StagedCampaignOverview.getOverview(parent().Id);
		Integer rows = Limits.getQueryRows();
		Test.stopTest();
		System.debug('query rows used: ' + rows);

		Assert.isTrue(o.staged);
		Assert.areEqual(7, o.campaigns.size());
		Assert.areEqual(5, o.campaigns[0].count, 'all members in Source');
		Assert.areEqual(4, o.sourceReady);
		Assert.areEqual(1, o.sourceParked);
		Assert.areEqual(4, o.sourceByPriority.size());
		Assert.areEqual(1, o.released, 'the parked member was released before');
		Assert.areEqual(1, o.reacted);
		Assert.areEqual(1, o.notNow.size());
		Assert.areEqual(1, o.batches.size());
		Assert.areEqual(1, o.batches[0].notNow);
		Assert.areEqual(3, o.revenue.size());
	}

	@IsTest
	static void release_movesBatchAndStartsMail1() {
		Test.startTest();
		Ctrl_StagedCampaignOverview.ReleaseResult r = Ctrl_StagedCampaignOverview.release(parent().Id, 3);
		Ctrl_StagedCampaignOverview.Overview o = Ctrl_StagedCampaignOverview.getOverview(parent().Id);
		Test.stopTest();

		Assert.areEqual(3, r.released);
		Assert.areEqual(2, r.batchNumber, 'batch 1 already used');
		Assert.areEqual(3, o.campaigns[1].count, 'Operational');
		Assert.areEqual(1, o.sourceReady);
		Assert.areEqual(3, o.mails[0].count, 'mail 1 due');
		Assert.areEqual(2, o.batches.size());
		Assert.areEqual(3, o.batches[1].inCycle);
	}

	@IsTest
	static void revenue_groupsOpportunities() {
		Campaign offer = [SELECT Id FROM Campaign WHERE Name = 'Overview - Offer' WITH SYSTEM_MODE];
		Account acct = [SELECT Id FROM Account WHERE Name = 'Overview Account' WITH SYSTEM_MODE];
		Database.insert(new Opportunity(Name = 'Overview Opp', AccountId = acct.Id, CampaignId = offer.Id, StageName = 'Preparation',
			CloseDate = Date.today().addDays(30), Amount = 1000), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Ctrl_StagedCampaignOverview.Overview o = Ctrl_StagedCampaignOverview.getOverview(parent().Id);
		Test.stopTest();

		Assert.areEqual('Open', o.revenue[0].label);
		Assert.areEqual(1, o.revenue[0].count);
	}

	@IsTest
	static void childOrPlainCampaign_notStaged() {
		Campaign source = [SELECT Id FROM Campaign WHERE Name = 'Overview - Source' WITH SYSTEM_MODE];
		Campaign plain = new Campaign(Name = 'Plain', IsActive = true);
		Database.insert(plain, AccessLevel.SYSTEM_MODE);
		Assert.isFalse(Ctrl_StagedCampaignOverview.getOverview(source.Id).staged);
		Assert.isFalse(Ctrl_StagedCampaignOverview.getOverview(plain.Id).staged);
	}

	@IsTest
	static void release_withoutAccess_refused() {
		User u = new User(
			Alias = 'ovw', Email = 'ovw@overview.test', EmailEncodingKey = 'UTF-8', LastName = 'Overview',
			LanguageLocaleKey = 'en_US', LocaleSidKey = 'nl_NL', TimeZoneSidKey = 'Europe/Amsterdam',
			ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1].Id,
			Username = 'ovw' + System.currentTimeMillis() + '@overview.test'
		);
		Id parentId = parent().Id;
		System.runAs(u) {
			try {
				Ctrl_StagedCampaignOverview.release(parentId, 1);
				Assert.fail('expected a refusal');
			} catch (AuraHandledException e) {
				Assert.isNotNull(e);
			}
		}
	}
}
