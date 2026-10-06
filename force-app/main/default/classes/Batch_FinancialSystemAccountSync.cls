/**
 * Pushes flagged accounts (SyncToFinancialSystem__c) to the financial system (Exact Online), in bulk.
 * Retries failed accounts with back-off (FinancialSyncNextAttempt__c) and stays within the batch share
 * of the daily API limit (FinancialRateLimitMaxPercentage__c); accounts that do not fit wait for a next run.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name).
 */
global class Batch_FinancialSystemAccountSync extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {
	// up to ~10 calls per account: keeps a queueable well below the 100 callouts / 120 s callout time per transaction
	private static final Integer BATCH_SIZE = 5;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemAccountSync() {
		super('Batch_FinancialSystemAccountSync');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		String now = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
		return Database.getQueryLocator(
			'SELECT Id FROM Account WHERE SyncToFinancialSystem__c = true'
			+ ' AND (FinancialSyncNextAttempt__c = null OR FinancialSyncNextAttempt__c <= ' + now + ')'
			+ ' ORDER BY FinancialSyncAttempts__c ASC NULLS FIRST, LastModifiedDate ASC', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Util_FinancialSystemAccount.syncAccounts(new Map<Id, SObject>(scope).keySet(), true);
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemAccountSync');
	}
}
