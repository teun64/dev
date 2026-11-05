/**
 * 20261102 TRi Fills the financial system (Exact) invoice id + raw invoice number (FinSysInvoiceId__c /
 * FinSysInvoiceNumber__c) on printed invoices and writes them, with the account's Exact id and debtor number, into the
 * Stripe metadata of the invoice's open or past PaymentIntent (FinSysInvoiceId, FinSysInvoiceNumber, FinSysAccountId,
 * FinSysAccountDebtorNumber, FinSysDivision + description); the account references also go onto the Stripe Customer.
 * This is what invoice matching in Stripe / Exact keys on.
 * New intents get the same metadata at creation (Svc_PaymentIntent, Batch_ProcessPayments); this step fills the
 * invoices finalised by the legacy Util_Exact (Batch_FinalizeInvoices, which stays untouched) and the backlog.
 * Scope: payment methods in PAYMENT_METHODS (pi / pr for now). Runs before Minut_ProcessPayments, so an off-session
 * charge (only after the invoice email went out) already carries the ids. A failed lookup backs off a day
 * (FinSysNextAttempt__c).
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name);
 * chained as a step of the Minut job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt).
 * Manual run: Database.executeBatch(new Batch_FinancialSystemInvoiceIds(), 20);
 */
global class Batch_FinancialSystemInvoiceIds extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {
	// one Exact GET per invoice + per payment at most a Stripe Customer and a PaymentIntent POST: within 100 callouts
	private static final Integer BATCH_SIZE = 20;

	@TestVisible
	private static final Set<String> PAYMENT_METHODS = new Set<String>{ 'pi', 'pr' };
	private static final String CREATED_FROM = '2026-09-01T00:00:00Z';

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemInvoiceIds() {
		super('Batch_FinancialSystemInvoiceIds');
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		String now = System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
		return Database.getQueryLocator(
			'SELECT Id FROM Subscription25__Invoice__c'
			+ ' WHERE FinSysInvoiceId__c = null'
			+ ' AND Subscription25__Invoice_Number__c != null AND Subscription25__Exact_Order_Number__c != null'
			+ ' AND Payment_Method_Result__c IN (\'' + String.join(new List<String>(PAYMENT_METHODS), '\',\'') + '\')'
			+ ' AND (FinSysNextAttempt__c = null OR FinSysNextAttempt__c <= ' + now + ')'
			// indexed lower bound: Payment_Method_Result__c is a cross-object formula; pi/pr exist since 2026-10
			+ ' AND CreatedDate >= ' + CREATED_FROM
			+ ' ORDER BY FinSysNextAttempt__c ASC NULLS FIRST, CreatedDate ASC', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Batch_FinancialSystemInvoiceIds.process(new Map<Id, SObject>(scope).keySet());
	}

	/** Exact lookups first, then the Stripe updates, then all DML (no callout may follow a DML statement). */
	@TestVisible
	private static void process(Set<Id> invoiceIds) {
		// read before any callout: the payments whose PaymentIntent gets the ids
		List<Payment__c> payments = Svc_PaymentIntent.queryPaymentsOfInvoices(invoiceIds);

		List<Event_Log__c> logs = new List<Event_Log__c>();
		Set<String> namedCredentials = new Set<String>();
		List<Subscription25__Invoice__c> changed = Util_FinancialSystem_Invoice.loadFinSysIds(invoiceIds, logs, namedCredentials);

		Map<Id, Subscription25__Invoice__c> filled = new Map<Id, Subscription25__Invoice__c>();
		for (Subscription25__Invoice__c inv : changed) {
			if (String.isNotBlank(inv.FinSysInvoiceId__c)) filled.put(inv.Id, inv);
		}

		Set<Id> customersDone = new Set<Id>();
		for (Payment__c p : payments) {
			Subscription25__Invoice__c inv = filled.get(p.Invoice__c);
			if (inv == null) continue;
			p.Invoice__r.FinSysInvoiceId__c     = inv.FinSysInvoiceId__c;
			p.Invoice__r.FinSysInvoiceNumber__c = inv.FinSysInvoiceNumber__c;
			String stripeAccountId = Svc_PaymentIntent.businessEntityFor(p)?.PayProv_Account__c;
			// the Customer once per account: keeps a changed debtor number current with every new invoice
			if (customersDone.add(p.Account__c)) {
				try {
					Svc_PaymentIntent.updateCustomerFinSysMetadata(stripeAccountId, p);
				} catch (Exception e) {
					System.debug(LoggingLevel.ERROR, 'Batch_FinancialSystemInvoiceIds customer of ' + p.Name + ': ' + e.getMessage());
				}
			}
			try {
				Svc_PaymentIntent.updateFinSysMetadata(stripeAccountId, p);
			} catch (Exception e) {
				// the ids are stored anyway; the intent of this payment just lacks them (e.g. canceled meanwhile)
				System.debug(LoggingLevel.ERROR, 'Batch_FinancialSystemInvoiceIds ' + p.Name + ' ' + p.PayProv_PaymentIntentId__c + ': ' + e.getMessage());
			}
		}

		if (!changed.isEmpty()) {
			List<Database.SaveResult> results = Util_FinancialSystem_Invoice.saveInvoices(changed);
			for (Integer i = 0; i < results.size(); i++) {
				if (!results[i].isSuccess()) {
					System.debug(LoggingLevel.ERROR, 'Batch_FinancialSystemInvoiceIds ' + changed[i].Id + ': ' + results[i].getErrors()[0].getMessage());
				}
			}
		}
		Util_FinancialSystem.saveLimits();
		Util_FinancialSystem.saveLogs(logs, namedCredentials, null);
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemInvoiceIds');
	}
}
