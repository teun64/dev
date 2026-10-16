/**
 * Go-live marker of the financial system sync: an account with FinancialSyncForce__c (Exact data possibly out of date)
 * is pushed in full before its next invoice. Daily, this step queues those accounts (SyncToFinancialSystem__c) whose
 * active contract is invoiced within DAYS_AHEAD days; Batch_FinancialSystemAccountSync pushes them under its rate limit
 * share and clears the marker. Orders do the same on their own (Util_FinancialSystem_Order waits for the account).
 * Spreads the push over the invoice moments instead of all accounts at once. No callouts.
 * Dispatcher step (JobDispatcherStep__mdt Day_FinancialSystemForceSync).
 */
global class Batch_FinancialSystemForceSync extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {
	@TestVisible
	private static final Integer DAYS_AHEAD = 7;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemForceSync() {
		super('Batch_FinancialSystemForceSync');
	}

	public override Integer getBatchSize() {
		return 200;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		String until = String.valueOf(Date.today().addDays(DAYS_AHEAD));
		return Database.getQueryLocator(
			'SELECT Id FROM Account WHERE FinancialSyncForce__c = true AND SyncToFinancialSystem__c = false'
			+ ' AND FinancialSyncBlocked__c = false AND FinancialIdAccount__c != null'
			+ ' AND Id IN (SELECT AccountId FROM Contract WHERE Status = \'Activated\' AND Subscription25__Next_Date__c <= ' + until + ')',
			AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Util_FinancialSystemAccount.flagAccounts(new Map<Id, SObject>(scope).keySet());
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemForceSync');
	}
}
