/**
 * Contact update: pushes changed contacts (AccountContactRelation.Sync_To_Financial_System__c, set by
 * rau_Contact_AccountContactRelation) to the financial system (Exact Online) without a full account sync.
 * See Util_FinancialSystemAccount.syncFlaggedContacts. Runs before Batch_FinancialSystemAccountSync in the
 * dispatcher, so accounts it flags are synchronised in the same round.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name).
 */
global class Batch_FinancialSystemContactSync extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {
	// one call per relation: keeps a queueable well below the 100 callouts / 120 s callout time per transaction
	private static final Integer BATCH_SIZE = 25;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemContactSync() {
		super('Batch_FinancialSystemContactSync');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		return Database.getQueryLocator(
			'SELECT Id FROM AccountContactRelation WHERE Sync_To_Financial_System__c = true'
			+ ' AND Account.SyncToFinancialSystem__c = false ORDER BY AccountId', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Util_FinancialSystemAccount.syncFlaggedContacts(new Map<Id, SObject>(scope).keySet(), true);
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemContactSync');
	}
}
