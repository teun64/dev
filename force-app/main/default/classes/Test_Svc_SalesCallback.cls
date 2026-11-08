/**
 * Tests Svc_SalesCallback: request (queue, subject, due, no duplicates), not reached (retry, close after the last try,
 * member back into the mail cycle), expire and the manager lookup.
 */
@IsTest
private class Test_Svc_SalesCallback {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Callback Account', (String) null, 'B2B', true);
		Campaign camp = new Campaign(Name = 'Callback Campaign', IsActive = true, CallbackLabel__c = '2G/4G conversion');
		Database.insert(camp, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Main', null, 'main@callback.test', true);
		Database.insert(new CampaignMember(CampaignId = camp.Id, ContactId = con.Id, Status = 'Sent', MailStage__c = 'Stopped',
			MailNumber__c = 2, Response__c = 'Call me', ResponseOn__c = Datetime.now()), AccessLevel.SYSTEM_MODE);
	}

	static Contact contact() { return [SELECT Id FROM Contact WITH SYSTEM_MODE LIMIT 1]; }
	static Campaign campaign() { return [SELECT Id FROM Campaign WITH SYSTEM_MODE LIMIT 1]; }
	static CampaignMember member() {
		return [SELECT Id, MailStage__c, Response__c, ResponseOn__c FROM CampaignMember WITH SYSTEM_MODE LIMIT 1];
	}
	static Id queueId() {
		return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :Svc_SalesCallback.QUEUE WITH SYSTEM_MODE].Id;
	}
	static Case read(Id caseId) {
		return [SELECT Id, OwnerId, Origin, Status, Reason, Subject, Description, Campaign__c, CallbackSource__c,
			CallbackAttempts__c, CallbackDueOn__c, CallbackLastAgent__c FROM Case WHERE Id = :caseId WITH SYSTEM_MODE];
	}

	static Svc_SalesCallback.Request request(Id campaignId, String note) {
		Svc_SalesCallback.Request r = new Svc_SalesCallback.Request();
		r.step = Svc_SalesCallback.STEP_REQUEST;
		r.contactId = contact().Id;
		r.campaignId = campaignId;
		r.campaignMemberId = campaignId == null ? null : member().Id;
		r.source = 'Campaign mail';
		r.note = note;
		return r;
	}

	static Id createCallback() {
		return Svc_SalesCallback.run(new List<Svc_SalesCallback.Request>{ request(campaign().Id, null) })[0].caseId;
	}

	@IsTest
	static void request_createsCaseInSalesCallbackQueue() {
		Test.startTest();
		Id caseId = createCallback();
		Test.stopTest();
		Case c = read(caseId);
		System.assertEquals(queueId(), c.OwnerId, 'owned by the sales call-back queue');
		System.assertEquals('Callback', c.Origin);
		System.assertEquals('Callback - 2G/4G conversion - Callback Account', c.Subject);
		System.assertEquals(campaign().Id, c.Campaign__c);
		System.assertEquals('Campaign mail', c.CallbackSource__c);
		System.assertEquals(0, c.CallbackAttempts__c);
		System.assert(c.CallbackDueOn__c > Datetime.now(), 'due in the future');
	}

	@IsTest
	static void request_twice_sameCaseWithNote() {
		Id first = createCallback();
		Test.startTest();
		Id second = Svc_SalesCallback.run(new List<Svc_SalesCallback.Request>{ request(campaign().Id, 'Please after 14:00') })[0].caseId;
		Test.stopTest();
		System.assertEquals(first, second, 'no second open call-back for the same contact and campaign');
		System.assertEquals(1, [SELECT COUNT() FROM Case WHERE CallbackSource__c != null WITH SYSTEM_MODE]);
		System.assert(read(first).Description.contains('Please after 14:00'));
	}

	@IsTest
	static void request_withoutCampaign_salesSubject() {
		Test.startTest();
		Id caseId = Svc_SalesCallback.run(new List<Svc_SalesCallback.Request>{ request(null, null) })[0].caseId;
		Id again = Svc_SalesCallback.run(new List<Svc_SalesCallback.Request>{ request(null, null) })[0].caseId;
		Test.stopTest();
		System.assertEquals('Callback - Sales - Callback Account', read(caseId).Subject);
		System.assertEquals(caseId, again);
	}

	@IsTest
	static void notReached_firstTry_backToQueue() {
		Id caseId = createCallback();
		Database.update(new Case(Id = caseId, OwnerId = UserInfo.getUserId()), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Svc_SalesCallback.notReached(caseId, 'voicemail');
		Test.stopTest();
		Case c = read(caseId);
		System.assertEquals(1, c.CallbackAttempts__c);
		System.assertEquals(Svc_SalesCallback.STATUS_RETRY, c.Status);
		System.assertEquals(queueId(), c.OwnerId, 'back to the queue for the 2nd try');
		System.assertEquals(UserInfo.getUserId(), c.CallbackLastAgent__c);
		System.assertEquals('Stopped', member().MailStage__c, 'member waits while the call-back is open');
	}

	@IsTest
	static void notReached_lastTry_closesAndMemberBackInCycle() {
		Id caseId = createCallback();
		Svc_SalesCallback.notReached(caseId, null);
		Test.startTest();
		Svc_SalesCallback.notReached(caseId, null);
		Test.stopTest();
		Case c = read(caseId);
		System.assertEquals(2, c.CallbackAttempts__c);
		System.assertEquals(Svc_SalesCallback.STATUS_CLOSED, c.Status);
		System.assertEquals(Svc_SalesCallback.REASON_CLOSED, c.Reason);
		CampaignMember cm = member();
		System.assertEquals('Due', cm.MailStage__c);
		System.assertEquals(null, cm.Response__c);
		System.assertEquals(null, cm.ResponseOn__c);
	}

	@IsTest
	static void expire_closesOpenCallback() {
		Id caseId = createCallback();
		Test.startTest();
		Svc_SalesCallback.Request r = new Svc_SalesCallback.Request();
		r.step = Svc_SalesCallback.STEP_EXPIRE;
		r.caseId = caseId;
		Svc_SalesCallback.run(new List<Svc_SalesCallback.Request>{ r });
		Test.stopTest();
		Case c = read(caseId);
		System.assertEquals(Svc_SalesCallback.STATUS_CLOSED, c.Status);
		System.assert(c.Description.contains('working days'));
		System.assertEquals('Due', member().MailStage__c);
	}

	@IsTest
	static void expire_closedCase_unchanged() {
		Id caseId = createCallback();
		Svc_SalesCallback.notReached(caseId, null);
		Svc_SalesCallback.notReached(caseId, null);
		Test.startTest();
		Svc_SalesCallback.expire(new Set<Id>{ caseId });
		Test.stopTest();
		System.assertEquals(2, read(caseId).CallbackAttempts__c);
	}

	@IsTest
	static void expire_manyAtOnce_allClosed() {
		// every call-back requested on one day has the same due moment, so the scheduled path expires them together
		// one Contact for all: "rab - Contact" faults on a multi-row Contact insert, and expire doesn't need different ones
		Account acct = [SELECT Id FROM Account WITH SYSTEM_MODE LIMIT 1];
		Id contactId = contact().Id;
		Id queue = queueId();
		List<Case> cases = new List<Case>();
		for (Integer i = 0; i < 30; i++) {
			cases.add(new Case(OwnerId = queue, Origin = 'Callback', Status = 'New', ContactId = contactId, AccountId = acct.Id,
				Subject = 'Callback - bulk', CallbackSource__c = 'Call', CallbackAttempts__c = 0,
				CallbackDueOn__c = Datetime.now().addDays(3), CallbackLastAgent__c = UserInfo.getUserId()));
		}
		Database.insert(cases, AccessLevel.SYSTEM_MODE);
		List<Svc_SalesCallback.Request> requests = new List<Svc_SalesCallback.Request>();
		for (Case c : cases) {
			Svc_SalesCallback.Request r = new Svc_SalesCallback.Request();
			r.step = Svc_SalesCallback.STEP_EXPIRE;
			r.caseId = c.Id;
			requests.add(r);
		}
		Test.startTest();
		Svc_SalesCallback.run(requests);
		Test.stopTest();
		System.assertEquals(30, [SELECT COUNT() FROM Case WHERE Status = :Svc_SalesCallback.STATUS_CLOSED AND Subject = 'Callback - bulk' WITH SYSTEM_MODE]);
	}

	@IsTest
	static void managerOf_agentWithActiveManager() {
		User agent = [SELECT Id, ManagerId FROM User WHERE IsActive = true AND ManagerId != null AND Manager.IsActive = true WITH SYSTEM_MODE LIMIT 1];
		System.assertEquals(agent.ManagerId, Svc_SalesCallback.managerOf(agent.Id));
	}

	@IsTest
	static void dueOn_fridayRequest_dueWednesdayOpening() {
		Datetime friday = Datetime.newInstance(2026, 11, 6, 14, 55, 0);
		Datetime due = Svc_SalesCallback.dueOn(friday);
		System.assertEquals(Date.newInstance(2026, 11, 11), due.date(), 'Monday + Tuesday are the 2 working days');
		System.assert(due.hour() < 12, 'at opening time');
	}
}
