/**
 * Tests Svc_CampaignResponse (apply answer in a staged campaign, token stamping, quarters) and the guest page
 * controller Ctrl_CampaignResponseGuest. Setup: parent "Response" with the 5 role campaigns; the member starts in
 * Operational.
 */
@IsTest
private class Test_Svc_CampaignResponse {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Response Account', (String) null, 'B2B', true);
		Campaign parent = new Campaign(Name = 'Response', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : new List<String>{ 'Source', 'Operational', 'Offer', 'Not interested', 'Not reacted', 'Dealer' }) {
			children.add(new Campaign(Name = 'Response - ' + role, ParentId = parent.Id, IsActive = true,
				CampaignRole__c = role, CallbackLabel__c = '2G/4G conversion'));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		Id operationalId = children[1].Id;
		Database.insert(new List<CampaignMemberStatus>{
			new CampaignMemberStatus(CampaignId = operationalId, Label = 'Call requested', SortOrder = 10),
			new CampaignMemberStatus(CampaignId = children[3].Id, Label = 'Declined', SortOrder = 11),
			new CampaignMemberStatus(CampaignId = children[5].Id, Label = 'Via dealer', SortOrder = 12)
		}, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Main', null, 'main@response.test', true);
		Database.insert(new CampaignMember(CampaignId = operationalId, ContactId = con.Id, Status = 'Sent', MailStage__c = 'Due',
			MailNumber__c = 1, Priority__c = 7), AccessLevel.SYSTEM_MODE);
	}

	// the contact's member, wherever it moved to under the parent
	static CampaignMember member() {
		return [
			SELECT Id, CampaignId, Campaign.CampaignRole__c, ContactId, Status, MailStage__c, MailNumber__c, Response__c,
			       ResponseOn__c, RecontactFrom__c, ResponseToken__c, ResponseUrl__c, Priority__c
			FROM CampaignMember WHERE Campaign.Parent.Name = 'Response' WITH SYSTEM_MODE LIMIT 1
		];
	}

	static Svc_CampaignResponse.Request request(String answer) {
		Svc_CampaignResponse.Request r = new Svc_CampaignResponse.Request();
		r.campaignMemberId = member().Id;
		r.answer = answer;
		r.source = 'Campaign mail';
		return r;
	}

	static List<Case> callbacks() {
		return [SELECT Id, Status, Description, CampaignMemberId__c, Campaign__c FROM Case WHERE CallbackSource__c != null WITH SYSTEM_MODE];
	}

	@IsTest
	static void insert_stampsTokenAndUrl() {
		CampaignMember cm = member();
		System.assert(Pattern.matches('[0-9a-f]{64}', cm.ResponseToken__c), 'random 64-hex token');
		String baseUrl = PreferenceTokenConfig__c.getOrgDefaults()?.Base_Url__c;
		if (String.isNotBlank(baseUrl)) System.assert(cm.ResponseUrl__c.endsWith('/response?token=' + cm.ResponseToken__c));
	}

	@IsTest
	static void callMe_staysOperationalAndOpensCallback() {
		Test.startTest();
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME));
		Test.stopTest();
		CampaignMember cm = member();
		System.assertEquals(Svc_CampaignResponse.OUTCOME_APPLIED, res.outcome);
		System.assertEquals('Operational', cm.Campaign.CampaignRole__c);
		System.assertEquals('Call me', cm.Response__c);
		System.assertEquals('Stopped', cm.MailStage__c);
		System.assertEquals('Call requested', cm.Status, 'campaign has this status');
		List<Case> cases = callbacks();
		System.assertEquals(1, cases.size());
		System.assertEquals(res.caseId, cases[0].Id);
		System.assertEquals(String.valueOf(cm.Id), cases[0].CampaignMemberId__c);
	}

	@IsTest
	static void sameAnswerTwice_unchanged() {
		Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME));
		Test.startTest();
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME));
		Test.stopTest();
		System.assertEquals(Svc_CampaignResponse.OUTCOME_UNCHANGED, res.outcome);
		System.assertEquals(1, callbacks().size(), 'no second call-back');
	}

	@IsTest
	static void offer_movesToOfferWithOpportunity() {
		Test.startTest();
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_OFFER));
		Test.stopTest();
		CampaignMember cm = member();
		System.assertEquals('Offer', cm.Response__c);
		System.assertEquals('Offer', cm.Campaign.CampaignRole__c, 'offer made = finished');
		Opportunity opp = [SELECT CampaignId FROM Opportunity WHERE Id = :res.opportunityId WITH SYSTEM_MODE];
		System.assertEquals(cm.CampaignId, opp.CampaignId, 'linked to the Offer campaign');
		System.assertEquals(0, callbacks().size(), 'the Opportunity is the follow-up');
	}

	@IsTest
	static void offer_onCallback_linksAndClosesCase() {
		Svc_CampaignResponse.Result callMe = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME));
		Svc_CampaignResponse.Request r = request(Svc_CampaignResponse.ANSWER_OFFER);
		r.caseId = callMe.caseId;
		r.source = 'Call';
		Test.startTest();
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(r);
		Test.stopTest();
		Case c = [SELECT Status, Opportunity__c, Campaign__c FROM Case WHERE Id = :callMe.caseId WITH SYSTEM_MODE];
		System.assertEquals(res.opportunityId, c.Opportunity__c);
		System.assertEquals(Svc_CampaignResponse.CASE_STATUS_REACHED, c.Status);
		System.assertEquals(member().CampaignId, c.Campaign__c, 'the Case followed the member to Offer');
		System.assertEquals('Telephone', [SELECT LeadSource FROM Opportunity WHERE Id = :res.opportunityId WITH SYSTEM_MODE].LeadSource);
	}

	@IsTest
	static void offer_onPage_closesOpenCallback() {
		Svc_CampaignResponse.Result callMe = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME));
		Test.startTest();
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_OFFER));
		Test.stopTest();
		Case c = [SELECT Status, Opportunity__c, Description FROM Case WHERE Id = :callMe.caseId WITH SYSTEM_MODE];
		System.assertEquals(res.opportunityId, c.Opportunity__c);
		System.assertEquals(Svc_CampaignResponse.CASE_STATUS_REACHED, c.Status, 'the Opportunity is the follow-up');
		System.assert(c.Description.contains('answered on the page, closed'), c.Description);
	}

	@IsTest
	static void offerClosedLost_memberBackToSource() {
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_OFFER));
		String token = member().ResponseToken__c;
		Test.startTest();
		Database.update(new Opportunity(Id = res.opportunityId, StageName = Svc_CampaignOffer.STAGE_LOST), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		CampaignMember cm = member();
		System.assertEquals('Source', cm.Campaign.CampaignRole__c);
		System.assertEquals(null, cm.Response__c, 'answer cleared: the mail links work again');
		System.assertEquals(null, cm.MailStage__c);
		System.assertEquals(token, cm.ResponseToken__c);
	}

	@IsTest
	static void offerClosedUnqualified_memberStaysInOffer() {
		Svc_CampaignResponse.Result res = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_OFFER));
		Test.startTest();
		Database.update(new Opportunity(Id = res.opportunityId, StageName = 'Closed Unqualified'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		System.assertEquals('Offer', member().Campaign.CampaignRole__c);
	}

	@IsTest
	static void notNow_movesToSourceWithQuarterAndTokenKept() {
		String token = member().ResponseToken__c;
		Test.startTest();
		Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_NOT_NOW));
		Test.stopTest();
		CampaignMember cm = member();
		System.assertEquals('Source', cm.Campaign.CampaignRole__c);
		System.assertEquals(Svc_CampaignResponse.quarterStarts(Date.today(), 1)[0], cm.RecontactFrom__c);
		System.assertEquals(null, cm.MailStage__c, 'out of the mail cycle');
		System.assertEquals(null, cm.MailNumber__c);
		System.assertEquals(7, cm.Priority__c, 'fields move along');
		System.assertEquals(token, cm.ResponseToken__c, 'links in sent mails keep working');
		System.assertEquals(0, callbacks().size());
	}

	@IsTest
	static void notInterested_movesAndClosesOpenCallback() {
		Id caseId = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME)).caseId;
		Test.startTest();
		Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_NOT_INTERESTED));
		Test.stopTest();
		CampaignMember cm = member();
		System.assertEquals('Not interested', cm.Campaign.CampaignRole__c);
		System.assertEquals('Declined', cm.Status);
		Case c = [SELECT Description, IsClosed, CampaignMemberId__c, Campaign__c FROM Case WHERE Id = :caseId WITH SYSTEM_MODE];
		System.assert(c.Description.contains('Not interested'), 'the answer is on the Case');
		System.assert(c.IsClosed, 'no call needed any more');
		System.assertEquals(String.valueOf(cm.Id), c.CampaignMemberId__c, 'the call-back follows the member');
		System.assertEquals(cm.CampaignId, c.Campaign__c);
	}

	static Account dealer(String name) {
		Account d = Test_Data.createAccount(name, (String) null, 'B2B', true);
		// separate update: the create flows set their own defaults
		Database.update(new Account(Id = d.Id, Relation_type__c = 'Dealer'), AccessLevel.SYSTEM_MODE);
		return d;
	}

	@IsTest
	static void dealer_onCallback_movesSetsDealerAndPreferred() {
		Id caseId = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME)).caseId;
		Account d = dealer('Response Dealer');
		Svc_CampaignResponse.Request r = request(Svc_CampaignResponse.ANSWER_DEALER);
		r.source = 'Call';
		r.caseId = caseId;
		r.dealerId = d.Id;
		Test.startTest();
		Svc_CampaignResponse.apply(r);
		Test.stopTest();
		CampaignMember cm = [SELECT Id, CampaignId, Campaign.CampaignRole__c, Status, MailStage__c, Dealer__c, Contact.AccountId
			FROM CampaignMember WHERE Id = :member().Id WITH SYSTEM_MODE];
		System.assertEquals('Dealer', cm.Campaign.CampaignRole__c);
		System.assertEquals('Via dealer', cm.Status);
		System.assertEquals('Stopped', cm.MailStage__c, 'no more mails');
		System.assertEquals(d.Id, cm.Dealer__c, 'the dealer moved along');
		System.assertEquals(d.Id, [SELECT Preferred_Installation_Specialist__c FROM Account WHERE Id = :cm.Contact.AccountId WITH SYSTEM_MODE]
			.Preferred_Installation_Specialist__c, 'empty: the account gets the dealer');
		System.assert([SELECT IsClosed FROM Case WHERE Id = :caseId WITH SYSTEM_MODE].IsClosed, 'the call-back is done');
		System.assertEquals(0, [SELECT COUNT() FROM Opportunity WHERE CampaignId = :cm.CampaignId WITH SYSTEM_MODE]);
	}

	@IsTest
	static void dealer_keepsAccountPreferred() {
		Account own = dealer('Own Dealer');
		Account d = dealer('Response Dealer');
		Id accountId = [SELECT Contact.AccountId FROM CampaignMember WHERE Id = :member().Id WITH SYSTEM_MODE].Contact.AccountId;
		Database.update(new Account(Id = accountId, Preferred_Installation_Specialist__c = own.Id), AccessLevel.SYSTEM_MODE);
		Svc_CampaignResponse.Request r = request(Svc_CampaignResponse.ANSWER_DEALER);
		r.dealerId = d.Id;
		Test.startTest();
		Svc_CampaignResponse.apply(r);
		Test.stopTest();
		System.assertEquals(d.Id, [SELECT Dealer__c FROM CampaignMember WHERE Id = :member().Id WITH SYSTEM_MODE].Dealer__c);
		System.assertEquals(own.Id, [SELECT Preferred_Installation_Specialist__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE]
			.Preferred_Installation_Specialist__c, 'the account keeps its own choice');
	}

	@IsTest
	static void callMeAfterNotInterested_backToOperational() {
		Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_NOT_INTERESTED));
		Test.startTest();
		Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME));
		Test.stopTest();
		System.assertEquals('Operational', member().Campaign.CampaignRole__c);
		System.assertEquals(1, callbacks().size());
	}

	@IsTest
	static void reachedOnCallback_notInterested_closesCase() {
		Id caseId = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME)).caseId;
		Svc_CampaignResponse.Request r = request(Svc_CampaignResponse.ANSWER_NOT_INTERESTED);
		r.source = 'Call';
		r.caseId = caseId;
		Test.startTest();
		Svc_CampaignResponse.run(new List<Svc_CampaignResponse.Request>{ r });
		Test.stopTest();
		Case c = [SELECT Status, CallbackLastAgent__c FROM Case WHERE Id = :caseId WITH SYSTEM_MODE];
		System.assertEquals(Svc_CampaignResponse.CASE_STATUS_REACHED, c.Status);
		System.assertEquals(UserInfo.getUserId(), c.CallbackLastAgent__c);
		System.assertEquals('Not interested', member().Campaign.CampaignRole__c);
	}

	@IsTest
	static void callMeCallbackNotReached_memberBackInCycle() {
		Id caseId = Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_CALL_ME)).caseId;
		Svc_SalesCallback.notReached(caseId, null);
		Test.startTest();
		Svc_SalesCallback.notReached(caseId, null);
		Test.stopTest();
		CampaignMember cm = member();
		System.assertEquals(null, cm.Response__c);
		System.assertEquals('Due', cm.MailStage__c);
	}

	@IsTest
	static void invalidAnswer_invalid() {
		System.assertEquals(Svc_CampaignResponse.OUTCOME_INVALID, Svc_CampaignResponse.apply(request('Maybe')).outcome);
		System.assertEquals(Svc_CampaignResponse.OUTCOME_INVALID, Svc_CampaignResponse.apply(null).outcome);
	}

	@IsTest
	static void quarterStarts_afterCurrentQuarter() {
		List<Date> q = Svc_CampaignResponse.quarterStarts(Date.newInstance(2026, 11, 6), 4);
		System.assertEquals(Date.newInstance(2027, 1, 1), q[0]);
		System.assertEquals(Date.newInstance(2027, 10, 1), q[3]);
	}

	@IsTest
	static void targetRole_perAnswer() {
		System.assertEquals(null, Svc_CampaignResponse.targetRole(null, 'Not now'), 'not staged: stays');
		System.assertEquals('Source', Svc_CampaignResponse.targetRole('Operational', 'Not now'));
		System.assertEquals('Operational', Svc_CampaignResponse.targetRole('Not reacted', 'Call me'));
		System.assertEquals('Offer', Svc_CampaignResponse.targetRole('Operational', 'Offer'));
		System.assertEquals('Dealer', Svc_CampaignResponse.targetRole('Not reacted', 'Dealer'));
		System.assertEquals(null, Svc_CampaignResponse.targetRole('Offer', 'Call me'), 'offer made = finished');
	}

	// ── Guest page ────────────────────────────────────────────────────────────
	@IsTest
	static void guest_getResponse_validToken() {
		CampaignMember cm = member();
		Ctrl_CampaignResponseGuest.PageData data = Ctrl_CampaignResponseGuest.getResponse(cm.ResponseToken__c);
		System.assert(data.valid);
		System.assertEquals('2G/4G conversion', data.campaignLabel);
		System.assertEquals('Response', data.campaignName, 'the main (parent) campaign, not the child');
		System.assert(data.translations.isEmpty());
		System.assertEquals(4, data.quarters.size());
		System.assertEquals(null, data.currentAnswer);
	}

	@IsTest
	static void guest_getResponse_mainCampaignDescriptionAndTranslation() {
		CampaignMember cm = member();
		Campaign parent = [SELECT Id FROM Campaign WHERE Name = 'Response' WITH SYSTEM_MODE];
		Database.update(new Campaign(Id = parent.Id, Description = 'Uw 2G-hardware stopt.'), AccessLevel.SYSTEM_MODE);
		Id baseRt = Schema.SObjectType.Data_Translation__c.getRecordTypeInfosByDeveloperName().get('Base').getRecordTypeId();
		Data_Translation__c dt = new Data_Translation__c(RecordTypeId = baseRt, Campaign__c = parent.Id, Language__c = 'en',
			Name__c = '2G switch-off', Description__c = 'Your 2G hardware stops.');
		Database.insert(dt, AccessLevel.SYSTEM_MODE);

		Ctrl_CampaignResponseGuest.PageData data = Ctrl_CampaignResponseGuest.getResponse(cm.ResponseToken__c);
		System.assertEquals('Response', data.campaignName);
		System.assertEquals('Uw 2G-hardware stopt.', data.campaignDescription);
		System.assertEquals(1, data.translations.size());
		System.assertEquals('en', data.translations[0].language);
		System.assertEquals('2G switch-off', data.translations[0].name);
		System.assertEquals('Your 2G hardware stops.', data.translations[0].description);
		Data_Translation__c saved = [SELECT Source_Id__c, Composite_Key__c, Source_Name__c FROM Data_Translation__c WHERE Id = :dt.Id WITH SYSTEM_MODE];
		System.assertEquals(String.valueOf(parent.Id), saved.Source_Id__c, 'rbb_Data_Translation: the campaign is the source');
		System.assertEquals(String.valueOf(parent.Id) + 'en', saved.Composite_Key__c);
		System.assertEquals('Response', saved.Source_Name__c);
	}

	@IsTest
	static void guest_getResponse_badTokenInvalid() {
		System.assert(!Ctrl_CampaignResponseGuest.getResponse('abc').valid);
		System.assert(!Ctrl_CampaignResponseGuest.getResponse(null).valid);
		System.assert(!Ctrl_CampaignResponseGuest.getResponse('0'.repeat(64)).valid);
	}

	@IsTest
	static void guest_submit_notNowChosenQuarter_linkStillWorks() {
		CampaignMember cm = member();
		Date q2 = Svc_CampaignResponse.quarterStarts(Date.today(), 4)[1];
		Test.startTest();
		String outcome = Ctrl_CampaignResponseGuest.submit(cm.ResponseToken__c, 'notnow', String.valueOf(q2));
		Test.stopTest();
		System.assertEquals(Svc_CampaignResponse.OUTCOME_APPLIED, outcome);
		System.assertEquals(q2, member().RecontactFrom__c);
		System.assertEquals('notnow', Ctrl_CampaignResponseGuest.getResponse(cm.ResponseToken__c).currentAnswer,
			'the same link finds the moved member');
	}

	@IsTest
	static void guest_submit_rejectsOtherDateAndCode() {
		String token = member().ResponseToken__c;
		System.assertEquals(Svc_CampaignResponse.OUTCOME_INVALID, Ctrl_CampaignResponseGuest.submit(token, 'notnow', '2040-01-01'));
		System.assertEquals(Svc_CampaignResponse.OUTCOME_INVALID, Ctrl_CampaignResponseGuest.submit(token, 'notnow', 'garbage'));
		System.assertEquals(Svc_CampaignResponse.OUTCOME_INVALID, Ctrl_CampaignResponseGuest.submit(token, 'buy', null));
		System.assertEquals(null, member().Response__c);
	}

	@IsTest
	static void guest_submit_inactiveCampaignInvalid() {
		CampaignMember cm = member();
		Database.update(new Campaign(Id = cm.CampaignId, IsActive = false), AccessLevel.SYSTEM_MODE);
		System.assertEquals(Svc_CampaignResponse.OUTCOME_INVALID, Ctrl_CampaignResponseGuest.submit(cm.ResponseToken__c, 'callme', null));
	}
}
