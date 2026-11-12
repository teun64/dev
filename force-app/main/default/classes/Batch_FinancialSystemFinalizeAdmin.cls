/**
 * 20261111 TRi Finalises the invoices of ONE administration in the financial system (Exact Online) on the Business Entity's
 * own finalize credential (Util_FinancialSystem.CredentialPurpose.FINALIZE: own Named Credential, own API limit state).
 * Started by Batch_FinancialSystemFinalizeInvoices (one instance per administration with something to sync, one after the
 * other) or as a continuation of itself after the minutely limit was reached.
 * - Batch size 1: an invoice is 3 callouts + DML, and no callout may follow a DML statement.
 * - Before every invoice: Limits.hasBatchCapacity(CALLS_PER_INVOICE) = minutely reserve + max % of the daily limit. The minutely
 *   state of Exact is carried from execute to execute (Stateful); the daily state is stored on the Business Entity.
 * - Minutely limit reached: the rest of this run stops and this class schedules itself again after the reset
 *   (System.scheduleBatch), independent of the dispatcher chain, which carries on with the next administration.
 * - A failed invoice backs off (FinSysFinalizeAttempts__c / FinSysFinalizeNextAttempt__c, Util_FinancialSystem.nextAttempt).
 * Plain batch (no Subscription25 job framework): no Schedulable_Class__c record needed.
 * Manual run: Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(adminId), 1);
 */
public without sharing class Batch_FinancialSystemFinalizeAdmin implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
	public static final String CLASS_NAME = 'Batch_FinancialSystemFinalizeAdmin';
	public static final String CONTINUATION_PREFIX = 'Finalize invoices continuation - ';
	// finalize = GET invoice, POST print, GET invoice number
	public static final Integer CALLS_PER_INVOICE = 3;
	@TestVisible
	private static final Integer MAX_PER_RUN = 1000;
	@TestVisible
	private static final Integer MAX_ROUNDS = 60;

	private final Id adminId;
	// administrations still to do after this one (dispatcher chain); empty for a continuation
	private final List<Id> queue;
	private final String dispatcher;
	private final Integer round;

	// state across the executes
	@TestVisible
	private Boolean stopped = false;
	@TestVisible
	private Boolean minutelyBlocked = false;
	@TestVisible
	private Integer minutelyRemaining;
	@TestVisible
	private Long minutelyReset;
	@TestVisible
	private Integer processed = 0;
	@TestVisible
	private Integer failed = 0;

	public Batch_FinancialSystemFinalizeAdmin(Id adminId) {
		this(adminId, new List<Id>(), null, 1);
	}

	public Batch_FinancialSystemFinalizeAdmin(Id adminId, List<Id> queue, String dispatcher, Integer round) {
		this.adminId = adminId;
		this.queue = queue == null ? new List<Id>() : queue;
		this.dispatcher = dispatcher;
		this.round = round;
	}

	/** True when the administration has invoices to finalise that are not backing off. */
	public static Boolean hasWork(Id adminId) {
		Datetime now = System.now();
		return ![
			SELECT Id FROM Subscription25__Invoice__c
			WHERE Subscription25__Administration__c = :adminId
				AND Subscription25__Sync_State__c = 'COMPLETE'
				AND Subscription25__Exact_Order_Number__c != null
				AND (Subscription25__Finalized_In_Exact__c = false OR Subscription25__Invoice_Number__c = null)
				AND (FinSysFinalizeNextAttempt__c = null OR FinSysFinalizeNextAttempt__c <= :now)
			WITH SYSTEM_MODE
			LIMIT 1
		].isEmpty();
	}

	public static Subscription25__Administration__c getAdministration(Id adminId) {
		List<Subscription25__Administration__c> admins = [
			SELECT Id, Name, Reseller__c, Subscription25__Active__c, Subscription25__Synchronisation__c, Subscription25__Named_Credential__c,
				Subscription25__Twinfield_Company_Code__c, Acceptance_Environment_Available__c, Subscription25__Invoice_Number_Prefix__c,
				Daily_Limit__c, FinancialRateLimitMaxPercentage__c, FinancialRateLimitRemaining__c, FinancialRateLimitResetOn__c
			FROM Subscription25__Administration__c
			WHERE Id = :adminId
			WITH SYSTEM_MODE
		];
		return admins.isEmpty() ? null : admins[0];
	}

	/** How many invoices the daily share of the finalize credential still allows (capped per run). */
	@TestVisible
	private static Integer invoiceRoom(Subscription25__Administration__c admin) {
		Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE);
		if (lim.dailyRemaining == null || lim.dailyLimit == null) {
			return MAX_PER_RUN;
		}
		Integer allowed = (lim.dailyLimit * lim.maxPercentage / 100).intValue();
		Integer room = allowed - (lim.dailyLimit - lim.dailyRemaining);
		return Math.min(MAX_PER_RUN, Math.max(0, room / CALLS_PER_INVOICE));
	}

	public Database.QueryLocator start(Database.BatchableContext bc) {
		Subscription25__Administration__c admin = Batch_FinancialSystemFinalizeAdmin.getAdministration(this.adminId);
		Integer n = Util_FinancialSystem.isSyncEnabled(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE)
			? Batch_FinancialSystemFinalizeAdmin.invoiceRoom(admin) : 0;
		Datetime now = System.now();
		Id adminIdLocal = this.adminId;
		return Database.getQueryLocator([
			SELECT Id, Subscription25__Finalized_In_Exact__c, Subscription25__Invoice_Number__c, FinSysFinalizeAttempts__c
			FROM Subscription25__Invoice__c
			WHERE Subscription25__Administration__c = :adminIdLocal
				AND Subscription25__Sync_State__c = 'COMPLETE'
				AND Subscription25__Exact_Order_Number__c != null
				AND (Subscription25__Finalized_In_Exact__c = false OR Subscription25__Invoice_Number__c = null)
				AND (FinSysFinalizeNextAttempt__c = null OR FinSysFinalizeNextAttempt__c <= :now)
			WITH SYSTEM_MODE
			ORDER BY FinSysFinalizeNextAttempt__c ASC NULLS FIRST, CreatedDate ASC
			LIMIT :n
		]);
	}

	public void execute(Database.BatchableContext bc, List<SObject> scope) {
		if (this.stopped) {
			return;
		}
		Subscription25__Administration__c admin = Batch_FinancialSystemFinalizeAdmin.getAdministration(this.adminId);
		if (!Util_FinancialSystem.isSyncEnabled(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE)) {
			this.stopped = true;
			return;
		}
		Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(admin, Util_FinancialSystem.CredentialPurpose.FINALIZE);
		// the minutely window of Exact is not stored: carry it over from the previous execute
		lim.minutelyRemaining = this.minutelyRemaining;
		lim.minutelyReset = this.minutelyReset;
		for (SObject so : scope) {
			Subscription25__Invoice__c inv = (Subscription25__Invoice__c) so;
			if (!lim.hasBatchCapacity(CALLS_PER_INVOICE)) {
				this.stopped = true;
				this.minutelyBlocked = lim.isMinutelyBlocked(CALLS_PER_INVOICE);
				break;
			}
			this.finalizeOne(inv, lim);
		}
		this.minutelyRemaining = lim.minutelyRemaining;
		this.minutelyReset = lim.minutelyReset;
		Util_FinancialSystem.saveLimits();
	}

	private void finalizeOne(Subscription25__Invoice__c inv, Util_FinancialSystem.Limits lim) {
		if (String.isNotBlank(inv.Subscription25__Invoice_Number__c)) {
			// already has its number (the flag was never set): finalized, no Exact call
			Util_FinancialSystem_Invoice.saveInvoices(new List<Subscription25__Invoice__c>{
				new Subscription25__Invoice__c(Id = inv.Id, Subscription25__Finalized_In_Exact__c = true)
			});
			this.processed++;
			return;
		}
		List<String> msgs = inv.Subscription25__Finalized_In_Exact__c
			? Util_FinancialSystem_Invoice.loadInvoiceNumber(inv.Id, null, Util_FinancialSystem.CredentialPurpose.FINALIZE)
			: Util_FinancialSystem_Invoice.finalizeInvoice(inv.Id, null, Util_FinancialSystem.CredentialPurpose.FINALIZE);
		this.processed++;
		Subscription25__Invoice__c upd = new Subscription25__Invoice__c(Id = inv.Id);
		if (msgs.isEmpty()) {
			if (inv.FinSysFinalizeAttempts__c == null || inv.FinSysFinalizeAttempts__c == 0) {
				return;
			}
			upd.FinSysFinalizeAttempts__c = 0;
			upd.FinSysFinalizeNextAttempt__c = null;
		} else if (Util_FinancialSystem_Invoice.lastRateLimited) {
			// nothing to hold against the invoice: the next run continues here
			this.stopped = true;
			this.minutelyBlocked = true;
			return;
		} else {
			this.failed++;
			Integer attempts = (inv.FinSysFinalizeAttempts__c == null ? 0 : inv.FinSysFinalizeAttempts__c.intValue()) + 1;
			upd.FinSysFinalizeAttempts__c = attempts;
			upd.FinSysFinalizeNextAttempt__c = Util_FinancialSystem.nextAttempt(attempts);
		}
		Util_FinancialSystem_Invoice.saveInvoices(new List<Subscription25__Invoice__c>{ upd });
	}

	public void finish(Database.BatchableContext bc) {
		// the dispatcher chain never waits for a limit: a blocked administration continues on its own, the chain moves on
		if (this.minutelyBlocked && this.round < MAX_ROUNDS) {
			Batch_FinancialSystemFinalizeAdmin.scheduleContinuation(this.adminId, this.round + 1);
		}
		if (!this.queue.isEmpty()) {
			List<Id> rest = new List<Id>(this.queue);
			Id next = rest.remove(0);
			Database.executeBatch(new Batch_FinancialSystemFinalizeAdmin(next, rest, this.dispatcher, 1), 1);
		} else {
			Util_JobDispatcher.startNext(this.dispatcher, Batch_FinancialSystemFinalizeInvoices.CLASS_NAME);
		}
	}

	/** Runs this administration again after the minutely window. Skipped when already scheduled. */
	public static void scheduleContinuation(Id adminId, Integer round) {
		String name = CONTINUATION_PREFIX + adminId;
		if (Batch_FinancialSystemFinalizeAdmin.isContinuationScheduled(adminId)) {
			return;
		}
		System.scheduleBatch(new Batch_FinancialSystemFinalizeAdmin(adminId, new List<Id>(), null, round), name, 1, 1);
	}

	public static Boolean isContinuationScheduled(Id adminId) {
		String name = CONTINUATION_PREFIX + adminId;
		return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :name WITH SYSTEM_MODE] > 0;
	}
}
