/**
 * Tests Svc_CampaignCallMe: a member put straight into an Operational campaign with Response "Call me" gets a call-back Case
 * (bulk, no duplicates), and the response page answer still makes exactly one.
 */
@IsTest
private class Test_Svc_CampaignCallMe {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('CallMe Account', (String) null, 'B2B', true);
		Campaign parent = new Campaign(Name = 'CallMe', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : new List<String>{ 'Source', 'Operational', 'Offer', 'Not interested', 'Not reacted' }) {
			children.add(new Campaign(Name = 'CallMe - ' + role, ParentId = parent.Id, IsActive = true, CampaignRole__c = role, CallbackLabel__c = '2G/4G conversion'));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		// one by one: rab - Contact fails on more than one Contact.Email in a single DML
		for (Integer i = 0; i < 25; i++) Test_Data.createContact(acct.Id, 'Main' + i, null, 'main' + i + '@callme.test', true);
	}

	static Id campaignId(String role) {
		return [SELECT Id FROM Campaign WHERE Name = :('CallMe - ' + role) WITH SYSTEM_MODE].Id;
	}

	static List<Contact> contacts() {
		return [SELECT Id FROM Contact WHERE Email LIKE '%@callme.test' WITH SYSTEM_MODE ORDER BY Email];
	}

	static List<Case> callbacks() {
		return [SELECT Id, OwnerId, Origin, Priority, CallbackSource__c, CallbackDueOn__c, CampaignMemberId__c, Campaign__c, ContactId
		        FROM Case WHERE CallbackSource__c != null WITH SYSTEM_MODE];
	}

	@IsTest
	static void insertOperational_callMe_opensCallbackPerMember_bulk() {
		Id operationalId = campaignId('Operational');
		List<CampaignMember> members = new List<CampaignMember>();
		for (Contact c : contacts()) members.add(new CampaignMember(CampaignId = operationalId, ContactId = c.Id, Response__c = 'Call me', Status = 'Sent'));
		Test.startTest();
		Database.insert(members, AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		List<Case> cases = callbacks();
		System.assertEquals(25, cases.size());
		Id queue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :Svc_SalesCallback.QUEUE WITH SYSTEM_MODE].Id;
		Set<String> memberIds = new Set<String>();
		for (CampaignMember cm : [SELECT Id FROM CampaignMember WHERE CampaignId = :operationalId WITH SYSTEM_MODE]) memberIds.add(String.valueOf(cm.Id));
		for (Case c : cases) {
			System.assertEquals(queue, c.OwnerId);
			System.assertEquals('Callback', c.Origin);
			System.assertEquals(Svc_CampaignCallMe.SOURCE, c.CallbackSource__c);
			System.assertEquals(operationalId, c.Campaign__c);
			System.assertNotEquals(null, c.CallbackDueOn__c);
			System.assert(memberIds.contains(c.CampaignMemberId__c));
		}
		CampaignMember one = [SELECT MailStage__c, ResponseOn__c, ResponseToken__c FROM CampaignMember WHERE CampaignId = :operationalId WITH SYSTEM_MODE LIMIT 1];
		System.assertEquals('Stopped', one.MailStage__c, 'no mail for someone who is phoned');
		System.assertNotEquals(null, one.ResponseOn__c);
		System.assertNotEquals(null, one.ResponseToken__c);
	}

	@IsTest
	static void insertOperational_mailStageKept_whenGiven() {
		Database.insert(new CampaignMember(CampaignId = campaignId('Operational'), ContactId = contacts()[0].Id, Response__c = 'Call me', MailStage__c = 'Waiting'), AccessLevel.SYSTEM_MODE);
		System.assertEquals('Waiting', [SELECT MailStage__c FROM CampaignMember WHERE CampaignId = :campaignId('Operational') WITH SYSTEM_MODE].MailStage__c);
	}

	@IsTest
	static void otherRoleOrOtherAnswer_noCallback() {
		List<Contact> cons = contacts();
		Database.insert(new List<CampaignMember>{
			new CampaignMember(CampaignId = campaignId('Source'), ContactId = cons[0].Id, Response__c = 'Call me'),
			new CampaignMember(CampaignId = campaignId('Operational'), ContactId = cons[1].Id, Response__c = 'Not now'),
			new CampaignMember(CampaignId = campaignId('Operational'), ContactId = cons[2].Id)
		}, AccessLevel.SYSTEM_MODE);
		System.assert(callbacks().isEmpty());
	}

	@IsTest
	static void updateToCallMe_opensOne_noSecondOnReEdit() {
		CampaignMember cm = new CampaignMember(CampaignId = campaignId('Operational'), ContactId = contacts()[0].Id, MailStage__c = 'Due', MailNumber__c = 1);
		Database.insert(cm, AccessLevel.SYSTEM_MODE);
		System.assert(callbacks().isEmpty());
		cm.Response__c = 'Call me';
		Database.update(cm, AccessLevel.SYSTEM_MODE);
		System.assertEquals(1, callbacks().size());
		cm.Priority__c = 3;   // Response unchanged
		Database.update(cm, AccessLevel.SYSTEM_MODE);
		cm.Response__c = null;
		Database.update(cm, AccessLevel.SYSTEM_MODE);
		cm.Response__c = 'Call me';   // set again while the call-back is still open: no second Case
		Database.update(cm, AccessLevel.SYSTEM_MODE);
		System.assertEquals(1, callbacks().size());
	}

	@IsTest
	static void pageAnswer_stillExactlyOneCallback_withItsOwnSource() {
		CampaignMember cm = new CampaignMember(CampaignId = campaignId('Operational'), ContactId = contacts()[0].Id, MailStage__c = 'Due', MailNumber__c = 1);
		Database.insert(cm, AccessLevel.SYSTEM_MODE);
		Svc_CampaignResponse.Request r = new Svc_CampaignResponse.Request();
		r.campaignMemberId = cm.Id;
		r.answer = 'Call me';
		r.source = 'Campaign mail';
		Svc_CampaignResponse.apply(r);
		List<Case> cases = callbacks();
		System.assertEquals(1, cases.size());
		System.assertEquals('Campaign mail', cases[0].CallbackSource__c, 'made by the answer code, not by the member trigger');
		System.assertEquals(false, Svc_CampaignCallMe.suppress, 'guard released');
	}
}
