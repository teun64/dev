/**
 * 20261111 TRi The one generic batch the job dispatcher calls (JobDispatcherStep Minut_FinancialSystemFinalizeInvoices) to
 * finalise invoices in the financial system. It does no callouts: in finishBatch it picks the administrations that have
 * something to do - sync enabled, an own finalize Named Credential on the Business Entity, invoices due, capacity left in
 * the finalize limit - and starts Batch_FinancialSystemFinalizeAdmin for the first one; every admin batch starts the
 * next one from its finish, and the last one hands over to the dispatcher's next step. Nothing to do = next step at once.
 * Entities without a finalize credential stay on the legacy path (Subscription25 Job_FinalizeInvoicesInExact).
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name; acc/prod
 * (Sub25 v2.66) need the record); chained as the last step of the Minut dispatcher.
 * Manual run: Database.executeBatch(new Batch_FinancialSystemFinalizeInvoices(), 1);
 */
global class Batch_FinancialSystemFinalizeInvoices extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {
	public static final String CLASS_NAME = 'Batch_FinancialSystemFinalizeInvoices';

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemFinalizeInvoices() {
		super('Batch_FinancialSystemFinalizeInvoices');
	}

	public override Integer getBatchSize() {
		return 1;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// one row so the framework runs finishBatch, where the work is picked
		return Database.getQueryLocator('SELECT Id FROM Organization LIMIT 1', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {}

	public override void finishBatch(Database.BatchableContext bc) {
		List<Id> queue = Batch_FinancialSystemFinalizeInvoices.pickAdministrations();
		if (queue.isEmpty()) {
			Util_JobDispatcher.startNext(this.dispatcher, CLASS_NAME);
			return;
		}
		Id first = queue.remove(0);
		Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(first, queue, this.dispatcher, 1), 1);
	}

	/**
	 * Administrations that need a finalize run now. Empty while an admin batch is still open (a long previous run) and per
	 * administration while its continuation is scheduled, so there is never a second instance for the same administration.
	 */
	@TestVisible
	private static List<Id> pickAdministrations() {
		List<Id> result = new List<Id>();
		if (![SELECT Id FROM AsyncApexJob
				WHERE JobType = 'BatchApex' AND ApexClass.Name = :Batch_FinancialSystemFinalizeAdmin.CLASS_NAME
					AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
				LIMIT 1].isEmpty()) {
			return result;
		}
		for (Subscription25__Administration__c admin : [
				SELECT Id, Name, Reseller__c, Subscription25__Active__c, Subscription25__Synchronisation__c, Subscription25__Named_Credential__c,
					Subscription25__Twinfield_Company_Code__c, Acceptance_Environment_Available__c,
					Daily_Limit__c, FinancialRateLimitMaxPercentage__c, FinancialRateLimitRemaining__c, FinancialRateLimitResetOn__c
				FROM Subscription25__Administration__c
				WHERE Subscription25__Active__c = true AND Subscription25__Synchronisation__c = :Util_FinancialSystem.SYNC_EXACT
				WITH SYSTEM_MODE
				ORDER BY Reseller__c]) {
			if (Util_FinancialSystem.isSyncEnabled(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE)
					&& !Batch_FinancialSystemFinalizeAdmin.isContinuationScheduled(admin.Id)
					&& Util_FinancialSystem.getLimits(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE).hasBatchCapacity(Batch_FinancialSystemFinalizeAdmin.CALLS_PER_INVOICE)
					&& Batch_FinancialSystemFinalizeAdmin.hasWork(admin.Id)) {
				result.add(admin.Id);
			}
		}
		return result;
	}
}
