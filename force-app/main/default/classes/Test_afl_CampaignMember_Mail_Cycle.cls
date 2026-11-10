/**
 * Tests the flow afl_CampaignMember_Mail_Cycle (called daily by stf_CampaignMember_Mail_Cycle):
 * release of a batch, next mail after the interval or on the schedule days, completion after the last mail (+ move to the
 * follow-up campaign) and stop on an answer.
 */
@IsTest
private class Test_afl_CampaignMember_Mail_Cycle {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Mail Cycle Account', (String) null, 'B2B', true);
		Campaign camp = new Campaign(Name = 'Mail Cycle Campaign', IsActive = true, MaxMailAttempts__c = 4,
			MailIntervalDays__c = 14, MailCompletedStatus__c = 'Responded');
		Database.insert(camp, AccessLevel.SYSTEM_MODE);
		Contact con = Test_Data.createContact(acct.Id, 'Main', null, 'main@mailcycle.test', true);
		Database.insert(new CampaignMember(CampaignId = camp.Id, ContactId = con.Id, Status = 'Sent', MailStage__c = 'Waiting'),
			AccessLevel.SYSTEM_MODE);
	}

	static CampaignMember member() {
		return [SELECT Id, ContactId, Status, MailStage__c, MailNumber__c, MailDueOn__c FROM CampaignMember
			WHERE Campaign.Name = 'Mail Cycle Campaign' WITH SYSTEM_MODE LIMIT 1];
	}

	static CampaignMember run(CampaignMember cm) {
		Database.update(cm, AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Flow.Interview.createInterview('afl_CampaignMember_Mail_Cycle', new Map<String, Object>{ 'recordId' => cm.Id }).start();
		Test.stopTest();
		return member();
	}

	@IsTest
	static void waiting_notReleased_unchanged() {
		CampaignMember cm = run(new CampaignMember(Id = member().Id, MailBatchReleasedOn__c = Date.today().addDays(1)));
		System.assertEquals('Waiting', cm.MailStage__c);
		System.assertEquals(null, cm.MailNumber__c);
	}

	@IsTest
	static void waiting_released_firstMailDue() {
		CampaignMember cm = run(new CampaignMember(Id = member().Id, MailBatchReleasedOn__c = Date.today()));
		System.assertEquals('Due', cm.MailStage__c);
		System.assertEquals(1, cm.MailNumber__c);
		System.assertEquals(Date.today(), cm.MailDueOn__c);
	}

	@IsTest
	static void due_intervalPassed_nextMail() {
		CampaignMember cm = run(new CampaignMember(Id = member().Id, MailStage__c = 'Due', MailNumber__c = 1,
			MailDueOn__c = Date.today().addDays(-14)));
		System.assertEquals('Due', cm.MailStage__c);
		System.assertEquals(2, cm.MailNumber__c);
		System.assertEquals(Date.today(), cm.MailDueOn__c);
	}

	@IsTest
	static void due_intervalNotPassed_unchanged() {
		CampaignMember cm = run(new CampaignMember(Id = member().Id, MailStage__c = 'Due', MailNumber__c = 1,
			MailDueOn__c = Date.today().addDays(-13)));
		System.assertEquals(1, cm.MailNumber__c);
		System.assertEquals(Date.today().addDays(-13), cm.MailDueOn__c);
	}

	@IsTest
	static void lastMail_intervalPassed_completedWithStatus() {
		CampaignMember cm = run(new CampaignMember(Id = member().Id, MailStage__c = 'Due', MailNumber__c = 4,
			MailDueOn__c = Date.today().addDays(-14)));
		System.assertEquals('Completed', cm.MailStage__c);
		System.assertEquals(4, cm.MailNumber__c);
		System.assertEquals('Responded', cm.Status);
	}

	@IsTest
	static void answered_stopped() {
		CampaignMember cm = run(new CampaignMember(Id = member().Id, MailStage__c = 'Due', MailNumber__c = 2,
			MailDueOn__c = Date.today().addDays(-3), Response__c = 'Call me', ResponseOn__c = Datetime.now()));
		System.assertEquals('Stopped', cm.MailStage__c);
		System.assertEquals(2, cm.MailNumber__c);
	}

	// schedule "5,12,20": mail 2 on day 5, mail 3 on day 12, closed on day 20 (business days after the release; here every
	// day counts, so the dates don't depend on the weekday the test runs; the business-day math: Test_Util_BusinessDays)
	static void useSchedule() {
		Util_BusinessDays.everyDayForTest = true;
		Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Mail Cycle Campaign' WITH SYSTEM_MODE];
		Database.update(new Campaign(Id = camp.Id, MaxMailAttempts__c = 3, MailScheduleDays__c = '5, 12, 20'), AccessLevel.SYSTEM_MODE);
	}

	// the campaign becomes the Operational child of a staged campaign with a Not reacted sister
	static void useStaged() {
		Campaign parent = new Campaign(Name = 'Mail Cycle Parent', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		Database.insert(new Campaign(Name = 'Mail Cycle Not reacted', IsActive = true, ParentId = parent.Id,
			CampaignRole__c = 'Not reacted'), AccessLevel.SYSTEM_MODE);
		Campaign camp = [SELECT Id FROM Campaign WHERE Name = 'Mail Cycle Campaign' WITH SYSTEM_MODE];
		Database.update(new Campaign(Id = camp.Id, ParentId = parent.Id, CampaignRole__c = 'Operational'), AccessLevel.SYSTEM_MODE);
	}

	static CampaignMember onDay(Integer mailNumber, Integer day) {
		Date released = Date.today().addDays(-day);
		return run(new CampaignMember(Id = member().Id, MailStage__c = 'Due', MailNumber__c = mailNumber,
			MailBatchReleasedOn__c = released, MailDueOn__c = released));
	}

	@IsTest
	static void schedule_day5_secondMail() {
		useSchedule();
		System.assertEquals(2, onDay(1, 5).MailNumber__c);
	}

	@IsTest
	static void schedule_day4_unchanged() {
		useSchedule();
		System.assertEquals(1, onDay(1, 4).MailNumber__c);
	}

	@IsTest
	static void schedule_day12_thirdMail() {
		useSchedule();
		System.assertEquals(3, onDay(2, 12).MailNumber__c);
	}

	@IsTest
	static void schedule_day19_lastMailWaits() {
		useSchedule();
		System.assertEquals('Due', onDay(3, 19).MailStage__c);
	}

	@IsTest
	static void schedule_day20_completed() {
		useSchedule();
		CampaignMember cm = onDay(3, 20);
		System.assertEquals('Completed', cm.MailStage__c);
		System.assertEquals('Responded', cm.Status);
	}

	@IsTest
	static void staged_day20_movedToNotReacted() {
		useSchedule();
		useStaged();
		Id contactId = member().ContactId;
		Date released = Date.today().addDays(-20);
		Database.update(new CampaignMember(Id = member().Id, MailStage__c = 'Due', MailNumber__c = 3,
			MailBatchReleasedOn__c = released, MailDueOn__c = released), AccessLevel.SYSTEM_MODE);
		Id cmId = member().Id;
		Test.startTest();
		Flow.Interview.createInterview('afl_CampaignMember_Mail_Cycle', new Map<String, Object>{ 'recordId' => cmId }).start();
		Test.stopTest();
		CampaignMember moved = [SELECT MailStage__c, MailNumber__c FROM CampaignMember
			WHERE Campaign.Name = 'Mail Cycle Not reacted' AND ContactId = :contactId WITH SYSTEM_MODE];
		System.assertEquals('Completed', moved.MailStage__c);
		System.assertEquals(3, moved.MailNumber__c);
		System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE Campaign.Name = 'Mail Cycle Campaign' WITH SYSTEM_MODE]);
	}
}
