/**
 * 20261102 TRi Posts the Stripe payouts of each Business Entity with Stripe posting settings to the financial system
 * (Exact): one journal entry per payout (Util_FinancialSystemStripePosting). Polls Stripe for paid payouts since
 * FinSysStripePostingFrom__c, so no webhook events are needed; failed postings are retried.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name);
 * chained as a step of the Day job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt).
 * Manual run: Database.executeBatch(new Batch_FinancialSystemStripePostings(), 1);
 */
global class Batch_FinancialSystemStripePostings extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {
	// one Business Entity (= one Stripe account) per execute: its callouts fill the transaction
	private static final Integer BATCH_SIZE = 1;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemStripePostings() {
		super('Batch_FinancialSystemStripePostings');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		return Database.getQueryLocator(
			'SELECT Id FROM Business_Entities__c WHERE FinSysStripePostingFrom__c != null AND PayProv_Account__c != null ORDER BY Reseller__c',
			AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		for (SObject be : scope) {
			Util_FinancialSystemStripePosting.run(be.Id);
		}
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemStripePostings');
	}
}
