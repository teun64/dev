/**
 * 20261106 TRi Books the Odoo invoices of Exact administrations (NL, UK) in the financial system, see Svc_OdooExactSync.
 * Chained as a step of the Minut job dispatcher (JobDispatcherStep.Minut_OdooExactSync, inactive until switched on).
 * Manual run: Database.executeBatch(new Batch_OdooExactSync(), 1);
 */
global class Batch_OdooExactSync extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {
	// one invoice per transaction: a few callouts each (journal, items, post, print, read back)
	private static final Integer BATCH_SIZE = 1;

	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_OdooExactSync() {
		super('Batch_OdooExactSync');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		return Svc_OdooExactSync.candidates();
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		for (SObject inv : scope) {
			Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(inv.Id);
			System.debug(LoggingLevel.INFO, 'Odoo Exact sync ' + (res.success ? 'OK' : 'FAILED') + ' ' + res.invoiceId + ': ' + res.message);
		}
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_OdooExactSync');
	}
}
