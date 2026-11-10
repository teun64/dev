/**
 * Tests Ctrl_CampaignMemberCall (member page + call list) and the large-account rules: phone only, so Not now and
 * Closed Lost lead back to the Large account campaign and the release never mails them.
 */
@IsTest
private class Test_Ctrl_CampaignMemberCall {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Call Account', (String) null, 'B2B', true);
		Campaign parent = new Campaign(Name = 'Call', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : Ctrl_StagedCampaignOverview.ROLES) {
			children.add(new Campaign(Name = 'Call - ' + role, ParentId = parent.Id, IsActive = true, CampaignRole__c = role));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Main', null, 'main@call.test', true);
		Database.insert(new CampaignMember(CampaignId = campaignId(children, Svc_CampaignMove.ROLE_LARGE_ACCOUNT), ContactId = con.Id,
			Account__c = acct.Id, LargeAccount__c = true, Priority__c = 11, UnitCount__c = 12), AccessLevel.SYSTEM_MODE);
	}

	static Id campaignId(List<Campaign> children, String role) {
		for (Campaign c : children) if (c.CampaignRole__c == role) return c.Id;
		return null;
	}

	static CampaignMember member() {
		return [
			SELECT Id, CampaignId, Campaign.CampaignRole__c, Response__c, RecontactFrom__c, LargeAccount__c, MailStage__c
			FROM CampaignMember WHERE Campaign.Parent.Name = 'Call' WITH SYSTEM_MODE LIMIT 1
		];
	}

	static Id roleId(String role) {
		return [SELECT Id FROM Campaign WHERE Name = :('Call - ' + role) WITH SYSTEM_MODE].Id;
	}

	@IsTest
	static void getMember_showsAccountContactAndQuarters() {
		Ctrl_CampaignMemberCall.Member m = Ctrl_CampaignMemberCall.getMember(member().Id);
		Assert.areEqual('Call Account', m.accountName);
		Assert.isNotNull(m.contactId);
		Assert.areEqual('main@call.test', m.contactEmail);
		Assert.areEqual('Large account', m.campaignRole);
		Assert.isTrue(m.largeAccount);
		Assert.isTrue(m.canAnswer);
		Assert.areEqual(4, m.quarters.size());
		Assert.isNull(Ctrl_CampaignMemberCall.getMember(Id.valueOf('00v000000000000AAA')), 'moved or deleted');
	}

	@IsTest
	static void notNow_largeAccountWaitsInLargeAccount() {
		Date q = Svc_CampaignResponse.quarterStarts(Date.today(), 2)[1];
		Test.startTest();
		Ctrl_CampaignMemberCall.AnswerResult r = Ctrl_CampaignMemberCall.answer(member().Id, 'Not now', String.valueOf(q));
		Test.stopTest();
		CampaignMember cm = member();
		Assert.areEqual(Svc_CampaignResponse.OUTCOME_APPLIED, r.outcome);
		Assert.areEqual('Large account', cm.Campaign.CampaignRole__c, 'never into Source');
		Assert.areEqual(q, cm.RecontactFrom__c);
		Ctrl_CampaignMemberCall.CallList cl = Ctrl_CampaignMemberCall.getCallList(roleId('Large account'));
		Assert.areEqual(1, cl.waiting);
		Assert.areEqual(0, cl.toCall);
	}

	@IsTest
	static void notInterested_movesWithNewIdAndFlag() {
		Id oldId = member().Id;
		Test.startTest();
		Ctrl_CampaignMemberCall.AnswerResult r = Ctrl_CampaignMemberCall.answer(oldId, 'Not interested', null);
		Test.stopTest();
		CampaignMember cm = member();
		Assert.areEqual(cm.Id, r.campaignMemberId, 'the page opens the moved member');
		Assert.areNotEqual(oldId, cm.Id);
		Assert.areEqual('Not interested', cm.Campaign.CampaignRole__c);
		Assert.isTrue(cm.LargeAccount__c, 'the flag moves along');
	}

	@IsTest
	static void offerClosedLost_backToLargeAccount() {
		Ctrl_CampaignMemberCall.AnswerResult r = Ctrl_CampaignMemberCall.answer(member().Id, 'Offer', null);
		Assert.isNotNull(r.opportunityId);
		Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Opportunity WHERE Id = :r.opportunityId WITH SYSTEM_MODE].OwnerId,
			'a call: the person who clicks owns the Opportunity');
		Test.startTest();
		Database.update(new Opportunity(Id = r.opportunityId, StageName = Svc_CampaignOffer.STAGE_LOST), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		CampaignMember cm = member();
		Assert.areEqual('Large account', cm.Campaign.CampaignRole__c, 'not Source: no mails');
		Assert.isNull(cm.Response__c);
	}

	@IsTest
	static void release_skipsLargeAccountInSource() {
		Svc_CampaignMove.move(new Set<Id>{ member().Id }, Svc_CampaignMove.ROLE_SOURCE, null);
		Test.startTest();
		Svc_CampaignRelease.Result r = Svc_CampaignRelease.release(roleId('Source'), 10);
		Test.stopTest();
		Assert.areEqual(0, r.released == null ? 0 : r.released, 'a large account is never mailed');
		Assert.areEqual('Source', member().Campaign.CampaignRole__c);
	}

	@IsTest
	static void callList_toCallByPriority() {
		Ctrl_CampaignMemberCall.CallList cl = Ctrl_CampaignMemberCall.getCallList(roleId('Large account'));
		Assert.areEqual(1, cl.toCall);
		Assert.areEqual(1, cl.rows.size());
		Assert.areEqual('Call Account', cl.rows[0].accountName);
	}

	@IsTest
	static void unknownAnswer_refused() {
		try {
			Ctrl_CampaignMemberCall.answer(member().Id, 'Dealer', null);
			Assert.fail('expected a refusal');
		} catch (AuraHandledException e) {
			Assert.isNotNull(e);
		}
	}
}
