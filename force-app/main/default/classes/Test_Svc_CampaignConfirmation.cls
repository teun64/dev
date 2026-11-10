/**
 * Tests Svc_CampaignConfirmation: the confirmation mail per answer (via CampaignConfirmation__e) and the quarter label.
 */
@IsTest
private class Test_Svc_CampaignConfirmation {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Confirm Account', (String) null, 'B2B', true);
		Campaign parent = new Campaign(Name = 'Confirm', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : new List<String>{ 'Source', 'Operational', 'Offer', 'Not interested', 'Not reacted', 'Dealer' }) {
			children.add(new Campaign(Name = 'Confirm - ' + role, ParentId = parent.Id, IsActive = true,
				CampaignRole__c = role, CallbackLabel__c = '2G/4G conversion'));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Main', null, 'main@confirm.test', true);
		Database.insert(new CampaignMember(CampaignId = children[1].Id, ContactId = con.Id, Status = 'Sent', MailStage__c = 'Due',
			MailNumber__c = 1, Priority__c = 7), AccessLevel.SYSTEM_MODE);
	}

	static Svc_CampaignResponse.Request request(String answer) {
		Svc_CampaignResponse.Request r = new Svc_CampaignResponse.Request();
		r.campaignMemberId = [SELECT Id FROM CampaignMember WHERE Campaign.Parent.Name = 'Confirm' WITH SYSTEM_MODE LIMIT 1].Id;
		r.answer = answer;
		r.source = 'Campaign mail';
		return r;
	}

	static Integer sentFor(Svc_CampaignResponse.Request r) {
		Test.startTest();
		Svc_CampaignResponse.apply(r);
		Test.getEventBus().deliver();
		Test.stopTest();
		return Svc_CampaignConfirmation.sentCount;
	}

	@IsTest
	static void notNow_sendsOneMail() {
		Svc_CampaignResponse.Request r = request(Svc_CampaignResponse.ANSWER_NOT_NOW);
		r.recontactFrom = Date.newInstance(2027, 4, 1);
		Assert.areEqual(1, sentFor(r));
	}

	@IsTest
	static void callMeFromPage_sendsOneMail() {
		Assert.areEqual(1, sentFor(request(Svc_CampaignResponse.ANSWER_CALL_ME)));
	}

	@IsTest
	static void notInterested_sendsNothing() {
		Assert.areEqual(0, sentFor(request(Svc_CampaignResponse.ANSWER_NOT_INTERESTED)));
	}

	@IsTest
	static void sameAnswerTwice_sendsOnce() {
		Svc_CampaignResponse.apply(request(Svc_CampaignResponse.ANSWER_NOT_NOW));
		Test.getEventBus().deliver();
		Svc_CampaignConfirmation.sentCount = 0;
		Assert.areEqual(0, sentFor(request(Svc_CampaignResponse.ANSWER_NOT_NOW)), 'unchanged: no second mail');
	}

	@IsTest
	static void confirms_rules() {
		Assert.isTrue(Svc_CampaignConfirmation.confirms('Offer', 'Operational', null));
		Assert.isTrue(Svc_CampaignConfirmation.confirms('Offer', 'Operational', '500000000000001AAA'), 'Offer on a call: confirmed');
		Assert.isFalse(Svc_CampaignConfirmation.confirms('Call me', 'Operational', '500000000000001AAA'), 'rep is on the call');
		Assert.isFalse(Svc_CampaignConfirmation.confirms('Offer', null, null), 'not a staged campaign');
		Assert.isFalse(Svc_CampaignConfirmation.confirms('Dealer', 'Operational', null));
	}

	@IsTest
	static void periodLabel_dutchQuarter() {
		Assert.areEqual('het tweede kwartaal van 2027 (april tot en met juni)', Svc_CampaignConfirmation.periodLabel(Date.newInstance(2027, 4, 1)));
		Assert.areEqual('het vierde kwartaal van 2027 (oktober tot en met december)', Svc_CampaignConfirmation.periodLabel(Date.newInstance(2027, 10, 1)));
		Assert.areEqual('', Svc_CampaignConfirmation.periodLabel(null));
	}
}
