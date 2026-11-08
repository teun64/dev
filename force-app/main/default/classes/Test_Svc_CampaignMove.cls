/**
 * Tests Svc_CampaignMove (move between the role campaigns of a staged campaign) and Svc_CampaignRelease (batch from
 * Source to Operational by priority).
 */
@IsTest
private class Test_Svc_CampaignMove {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Move Account', (String) null, 'B2B', true);
		Campaign parent = new Campaign(Name = 'Move', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : new List<String>{ 'Source', 'Operational', 'Offer', 'Not interested', 'Not reacted' }) {
			children.add(new Campaign(Name = 'Move - ' + role, ParentId = parent.Id, IsActive = true, CampaignRole__c = role));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		// one Contact per insert: "rab - Contact" faults on a multi-row Contact insert
		List<CampaignMember> members = new List<CampaignMember>();
		for (Integer i = 0; i < 4; i++) {
			Contact con = Test_Data.createContact(acct.Id, i == 0 ? 'Main' : 'Other', null, 'c' + i + '@move.test', true);
			members.add(new CampaignMember(CampaignId = children[0].Id, ContactId = con.Id, Priority__c = 4 - i));
		}
		members[0].RecontactFrom__c = Date.today().addMonths(2);   // "Not now": waits
		Database.insert(members, AccessLevel.SYSTEM_MODE);
	}

	static Id campaignId(String role) {
		return [SELECT Id FROM Campaign WHERE Name = :('Move - ' + role) WITH SYSTEM_MODE].Id;
	}

	static List<CampaignMember> membersIn(String role) {
		return [
			SELECT Id, ContactId, Priority__c, MailStage__c, MailNumber__c, MailBatch__c, MailBatchReleasedOn__c, ResponseToken__c
			FROM CampaignMember WHERE CampaignId = :campaignId(role) WITH SYSTEM_MODE ORDER BY Priority__c
		];
	}

	@IsTest
	static void release_byPriority_skipsNotNow_startsCycle() {
		Test.startTest();
		Svc_CampaignRelease.Result res = Svc_CampaignRelease.run(new List<Svc_CampaignRelease.Request>{ request(campaignId('Source'), 2) })[0];
		Test.stopTest();
		System.assertEquals(2, res.released);
		System.assertEquals(1, res.batchNumber);
		List<CampaignMember> operational = membersIn('Operational');
		System.assertEquals(2, operational.size());
		System.assertEquals(1, operational[0].Priority__c, 'highest priority (lowest number) first');
		System.assertEquals(2, operational[1].Priority__c);
		System.assertEquals('Due', operational[0].MailStage__c);
		System.assertEquals(1, operational[0].MailNumber__c);
		System.assertEquals(Date.today(), operational[0].MailBatchReleasedOn__c);
		System.assertEquals(2, membersIn('Source').size(), 'priority 3 and the Not now member stay');
	}

	@IsTest
	static void release_secondBatch_nextNumber() {
		Svc_CampaignRelease.release(campaignId('Source'), 1);
		Test.startTest();
		Svc_CampaignRelease.Result res = Svc_CampaignRelease.release([SELECT Id FROM Campaign WHERE Name = 'Move' WITH SYSTEM_MODE].Id, 5);
		Test.stopTest();
		System.assertEquals(2, res.batchNumber);
		System.assertEquals(2, res.released, 'the Not now member is skipped');
	}

	@IsTest
	static void release_withoutStagedCampaign_message() {
		Campaign lone = new Campaign(Name = 'Lone', IsActive = true);
		Database.insert(lone, AccessLevel.SYSTEM_MODE);
		Svc_CampaignRelease.Result res = Svc_CampaignRelease.release(lone.Id, 10);
		System.assertEquals(0, res.released);
		System.assertNotEquals(null, res.message);
	}

	@IsTest
	static void move_keepsTokenAndFields() {
		CampaignMember cm = membersIn('Source')[0];
		Test.startTest();
		Svc_CampaignMove.Request r = new Svc_CampaignMove.Request();
		r.campaignMemberId = cm.Id;
		r.role = 'Not reacted';
		Svc_CampaignMove.Result res = Svc_CampaignMove.run(new List<Svc_CampaignMove.Request>{ r })[0];
		Test.stopTest();
		CampaignMember moved = [SELECT Id, CampaignId, ResponseToken__c, Priority__c, MailStage__c FROM CampaignMember WHERE Id = :res.campaignMemberId WITH SYSTEM_MODE];
		System.assertEquals(campaignId('Not reacted'), moved.CampaignId);
		System.assertEquals(cm.ResponseToken__c, moved.ResponseToken__c);
		System.assertEquals(cm.Priority__c, moved.Priority__c);
		System.assertEquals('Completed', moved.MailStage__c);
		System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE Id = :cm.Id WITH SYSTEM_MODE], 'old member removed');
	}

	@IsTest
	static void move_contactAlreadyInTarget_updatesThatMember() {
		CampaignMember cm = membersIn('Source')[0];
		CampaignMember there = new CampaignMember(CampaignId = campaignId('Offer'), ContactId = cm.ContactId);
		Database.insert(there, AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Map<Id, CampaignMember> moved = Svc_CampaignMove.move(new Set<Id>{ cm.Id }, 'Offer', null);
		Test.stopTest();
		System.assertEquals(there.Id, moved.get(cm.Id).Id);
		System.assertEquals(1, membersIn('Offer').size());
		System.assertEquals(cm.ResponseToken__c, membersIn('Offer')[0].ResponseToken__c);
	}

	@IsTest
	static void move_sameRole_onlyValues() {
		CampaignMember cm = membersIn('Source')[0];
		Map<Id, CampaignMember> moved = Svc_CampaignMove.move(new Set<Id>{ cm.Id }, 'Source', new Map<String, Object>{ 'MailStage__c' => 'Stopped' });
		System.assertEquals(cm.Id, moved.get(cm.Id).Id);
		System.assertEquals('Stopped', [SELECT MailStage__c FROM CampaignMember WHERE Id = :cm.Id WITH SYSTEM_MODE].MailStage__c);
	}

	@IsTest
	static void siblingId_findsRole() {
		System.assertEquals(campaignId('Offer'), Svc_CampaignMove.siblingId(campaignId('Source'), 'Offer'));
	}

	static Svc_CampaignRelease.Request request(Id campaignId, Integer size) {
		Svc_CampaignRelease.Request r = new Svc_CampaignRelease.Request();
		r.campaignId = campaignId;
		r.size = size;
		return r;
	}
}
