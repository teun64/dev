/**
 * Creates flagged orders (SyncToFinancialSystem__c, set by the user's sync action) in the financial system
 * (Exact Online) and activates them. Orders wait while their account is not in Exact yet; failures are
 * retried with back-off; stays within the batch share of the daily API limit.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name).
 */
global class Batch_FinancialSystemOrderSync extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {
	// one POST per order (+ one item lookup per administration per chunk)
	private static final Integer BATCH_SIZE = 20;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemOrderSync() {
		super('Batch_FinancialSystemOrderSync');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		String now = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
		return Database.getQueryLocator(
			'SELECT Id FROM Order WHERE SyncToFinancialSystem__c = true'
			+ ' AND (FinancialSyncNextAttempt__c = null OR FinancialSyncNextAttempt__c <= ' + now + ')'
			+ ' ORDER BY FinancialSyncAttempts__c ASC NULLS FIRST, CreatedDate ASC', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Util_FinancialSystem_Order.syncOrders(new Map<Id, SObject>(scope).keySet(), true);
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemOrderSync');
	}
}
