@IsTest
private class Test_Util_JobDispatcher {
	private static final String DISPATCHER = 'TestDispatcher';
	private static final String ACCOUNT_SYNC = 'Batch_FinancialSystemAccountSync';

	private static JobDispatcherStep__mdt step(String dispatcher, String apexClass, Integer order, Boolean active) {
		return new JobDispatcherStep__mdt(Dispatcher__c = dispatcher, ApexClass__c = apexClass, Order__c = order, IsActive__c = active);
	}

	private static void registerJobs() {
		Database.insert(new List<Subscription25__Schedulable_Class__c>{
			new Subscription25__Schedulable_Class__c(Name = 'Batch_JobDispatcher', Subscription25__Unique_Name__c = 'Batch_JobDispatcher'),
			new Subscription25__Schedulable_Class__c(Name = ACCOUNT_SYNC, Subscription25__Unique_Name__c = ACCOUNT_SYNC)
		}, AccessLevel.SYSTEM_MODE);
	}

	private static Integer openJobs(String apexClass) {
		return [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = :apexClass];
	}

	@IsTest
	static void getSteps_onlyActiveOfDispatcherInOrder() {
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{
			step(DISPATCHER, 'Third', 30, true),
			step(DISPATCHER, 'First', 10, true),
			step(DISPATCHER, 'Inactive', 15, false),
			step('Other', 'OtherDispatcher', 5, true),
			step(DISPATCHER, 'Second', 20, true)
		};

		List<JobDispatcherStep__mdt> steps = Util_JobDispatcher.getSteps(DISPATCHER);

		System.assertEquals(3, steps.size());
		System.assertEquals('First', steps[0].ApexClass__c);
		System.assertEquals('Second', steps[1].ApexClass__c);
		System.assertEquals('Third', steps[2].ApexClass__c);
	}

	@IsTest
	static void getSteps_repeatedClassOnlyAtFirstPosition() {
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{
			step(DISPATCHER, 'First', 10, true),
			step(DISPATCHER, 'Second', 20, true),
			step(DISPATCHER, 'First', 30, true)
		};

		List<JobDispatcherStep__mdt> steps = Util_JobDispatcher.getSteps(DISPATCHER);

		System.assertEquals(2, steps.size());
		System.assertEquals(null, Util_JobDispatcher.startNext(DISPATCHER, 'Second'), 'Second is the last step: no restart of First');
	}

	@IsTest
	static void dispatcherRun_startsFirstStep() {
		registerJobs();
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{ step(DISPATCHER, ACCOUNT_SYNC, 10, true) };

		Test.startTest();
		Database.executeBatch(new Batch_JobDispatcher(DISPATCHER));
		Test.stopTest();

		System.assertEquals(1, openJobs(ACCOUNT_SYNC), 'The dispatcher finish starts the first step');
	}

	@IsTest
	static void startRound_skipsWhileAStepIsRunning() {
		registerJobs();
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{ step(DISPATCHER, ACCOUNT_SYNC, 10, true) };

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemAccountSync(), 5);
		Id started = Util_JobDispatcher.startRound(DISPATCHER);
		Test.stopTest();

		System.assertEquals(null, started, 'No new round while the previous one runs');
		System.assertEquals(1, openJobs(ACCOUNT_SYNC));
	}

	@IsTest
	static void startRound_noActiveSteps_doesNothing() {
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{ step(DISPATCHER, ACCOUNT_SYNC, 10, false) };

		System.assertEquals(null, Util_JobDispatcher.startRound(DISPATCHER));
	}

	@IsTest
	static void startNext_startsFollowingStepWithItsBatchSize() {
		registerJobs();
		JobDispatcherStep__mdt second = step(DISPATCHER, ACCOUNT_SYNC, 20, true);
		second.BatchSize__c = 3;
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{ step(DISPATCHER, 'Batch_Previous', 10, true), second };

		Test.startTest();
		Id started = Util_JobDispatcher.startNext(DISPATCHER, 'Batch_Previous');
		Test.stopTest();

		System.assertNotEquals(null, started);
		System.assertEquals(1, openJobs(ACCOUNT_SYNC));
	}

	@IsTest
	static void startNext_lastStepOrNoDispatcher_doesNothing() {
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{ step(DISPATCHER, ACCOUNT_SYNC, 10, true) };

		System.assertEquals(null, Util_JobDispatcher.startNext(DISPATCHER, ACCOUNT_SYNC), 'Last step ends the round');
		System.assertEquals(null, Util_JobDispatcher.startNext(null, ACCOUNT_SYNC), 'Not started by a dispatcher');
	}

	@IsTest
	static void startRound_invalidStepClass_throws() {
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{ step(DISPATCHER, 'Batch_DoesNotExist', 10, true) };

		try {
			Util_JobDispatcher.startRound(DISPATCHER);
			System.assert(false, 'Expected a DispatcherException');
		} catch (Util_JobDispatcher.DispatcherException e) {
			System.assert(e.getMessage().contains('Batch_DoesNotExist'), e.getMessage());
		}
	}

	@IsTest
	static void scheduleEvery5Minutes_creates12Schedules() {
		registerJobs();
		// independent of the org's real steps: those also run when the schedule fires at stopTest
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>();

		Test.startTest();
		Batch_JobDispatcher.scheduleEvery5Minutes();
		Test.stopTest();

		System.assertEquals(12, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'GoMeddo Subscription - Batch_JobDispatcher - %']);
	}

	@IsTest
	static void scheduleDaily_createsOneScheduleAt0013() {
		registerJobs();
		// independent of the org's real steps: those also run when the schedule fires at stopTest
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>();

		Test.startTest();
		Batch_JobDispatcher.scheduleDaily();
		Test.stopTest();

		List<CronTrigger> schedules = [
			SELECT CronExpression FROM CronTrigger WHERE CronJobDetail.Name LIKE 'GoMeddo Subscription - Batch_JobDispatcher - Day - %'
		];
		System.assertEquals(1, schedules.size());
		System.assertEquals('0 13 0 * * ?', schedules[0].CronExpression, 'Fires once a day at 00:13');
	}

	@IsTest
	static void scheduleHourly_createsOneScheduleAtMinute23() {
		registerJobs();
		// independent of the org's real steps: those also run when the schedule fires at stopTest
		Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>();

		Test.startTest();
		Batch_JobDispatcher.scheduleHourly();
		Test.stopTest();

		List<CronTrigger> schedules = [
			SELECT CronExpression FROM CronTrigger WHERE CronJobDetail.Name LIKE 'GoMeddo Subscription - Batch_JobDispatcher - Hour - %'
		];
		System.assertEquals(1, schedules.size());
		System.assertEquals('0 23 * * * ?', schedules[0].CronExpression, 'Fires once an hour at minute 23');
	}
}
