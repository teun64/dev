/**
 * 20261105 TRi Picks up the Odoo invoice e-mails on Email-to-Case (invoicing@ mailboxes, case still New, last 30 days)
 * and processes them with Svc_OdooInvoiceIntake (Factur-X from the PDF -> Account / Contact / Product / Sub25 Invoice /
 * Order; case -> Processed). The subject check (reference, no reply) is done in the service.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name);
 * chained as a step of the Minut job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt).
 * Manual run: Database.executeBatch(new Batch_OdooInvoiceIntake(), 1);
 */
global class Batch_OdooInvoiceIntake extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {
	// one e-mail per transaction: the Account / Order / Invoice automation takes most of the 100 SOQL queries
	private static final Integer BATCH_SIZE = 1;
	private static final Integer LOOKBACK_DAYS = 30;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_OdooInvoiceIntake() {
		super('Batch_OdooInvoiceIntake');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		return Database.getQueryLocator(
			'SELECT Id FROM EmailMessage'
			+ ' WHERE Incoming = true AND Parent.Status = \'' + Svc_OdooInvoiceIntake.CASE_STATUS_NEW + '\''
			+ ' AND FromAddress IN (\'' + String.join(new List<String>(Svc_OdooInvoiceIntake.SENDERS), '\',\'') + '\')'
			+ ' AND (Subject LIKE \'%(Ref %\' OR Subject LIKE \'%(Réf %\')'
			+ ' AND CreatedDate = LAST_N_DAYS:' + LOOKBACK_DAYS
			+ ' ORDER BY CreatedDate ASC', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		for (Svc_OdooInvoiceIntake.Result res : Svc_OdooInvoiceIntake.process(new Map<Id, SObject>(scope).keySet())) {
			System.debug(LoggingLevel.INFO, 'Odoo intake ' + res.status + ' ' + res.caseId + ' ' + res.invoiceNumber + ': ' + res.message);
		}
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_OdooInvoiceIntake');
	}
}
