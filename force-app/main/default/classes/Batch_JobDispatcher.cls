/**
 * Starts a round of the job dispatcher's steps (JobDispatcherStep__mdt, see Util_JobDispatcher).
 * One schedule for all steps saves Scheduled Apex slots (max 100 per org).
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name),
 * with scheduleEvery5Minutes(); the batch itself does no work, the round starts from finishBatch.
 */
global class Batch_JobDispatcher extends Subscription25.Job_AbstractBatch2 {
	public static final String DEFAULT_DISPATCHER = 'Every5Min';
	// same hours as the other 5-minute Subscription25 jobs
	private static final String HOURS = '1-3,5-23';

	private String dispatcher;

	global Batch_JobDispatcher() {
		this(DEFAULT_DISPATCHER);
	}

	global Batch_JobDispatcher(String dispatcher) {
		super('Batch_JobDispatcher');
		this.dispatcher = dispatcher;
	}

	public override Integer getBatchSize() {
		return 1;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// one row so the framework runs finishBatch; no bind variables (the framework runs the locator outside this scope)
		return Database.getQueryLocator(
			'SELECT Id FROM Subscription25__Schedulable_Class__c WHERE Name = \'Batch_JobDispatcher\' LIMIT 1', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startRound(this.dispatcher);
	}

	/**
	 * Schedules the default dispatcher every 5 minutes (12 hourly schedules, :00 to :55).
	 * Leave the Subscription25__Schedulable_Class__c record on Schedulable = false without Cron String.
	 */
	public static void scheduleEvery5Minutes() {
		for (Integer minute = 0; minute < 60; minute += 5) {
			String cron = '0 ' + minute + ' ' + HOURS + ' * * ?';
			System.schedule('GoMeddo Subscription - Batch_JobDispatcher - ' + cron, cron, new Batch_JobDispatcher());
		}
	}
}
