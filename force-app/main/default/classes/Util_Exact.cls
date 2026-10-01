/**
 * Legacy entry points of the Exact integration, kept as thin forwarders until all callers use the new classes:
 *  - account : Util_FinancialSystemAccount (+ Batch_FinancialSystemAccountSync)
 *  - order   : Util_FinancialSystem_Order (+ Batch_FinancialSystemOrderSync)
 *  - invoice : Util_FinancialSystem_Invoice
 * The generic request/rate-limit layer is Util_FinancialSystem. To be removed once nothing references it.
 */
public without sharing class Util_Exact {

	// ---------------------------------------------------------------- account

	/** Queues the account for Batch_FinancialSystemAccountSync (@future: safe from Account triggers). */
	@future
	public static void syncAccountAsync(Id acctId, String logGUID){
		Util_FinancialSystemAccount.flagAccounts(new Set<Id>{ acctId });
	}

	@future
	public static void syncAccountAsync(Id acctId){
		Util_FinancialSystemAccount.flagAccounts(new Set<Id>{ acctId });
	}

	/** Syncs the account now (callouts). */
	public static List<String> syncAccount(Id acctId){
		return Util_FinancialSystemAccount.syncAccount(acctId);
	}

	public static List<String> syncAccount(Id acctId, String logGUID){
		return Util_FinancialSystemAccount.syncAccount(acctId);
	}

	// ---------------------------------------------------------------- order

	/** Queues the order for Batch_FinancialSystemOrderSync. */
	@future
	public static void syncOrderAsync(Id orderId, String logGUID){
		Util_FinancialSystem_Order.flagOrders(new Set<Id>{ orderId });
	}

	@future
	public static void syncOrderAsync(Id orderId){
		Util_FinancialSystem_Order.flagOrders(new Set<Id>{ orderId });
	}

	/** Creates the order in Exact now (callouts). */
	public static List<String> syncOrder(Id orderId){
		return Util_FinancialSystem_Order.syncOrder(orderId);
	}

	public static List<String> syncOrder(Id orderId, String logGUID){
		return Util_FinancialSystem_Order.syncOrder(orderId);
	}

	// ---------------------------------------------------------------- invoice

	public static List<String> finalizeInvoice(Id invoiceId){
		return Util_FinancialSystem_Invoice.finalizeInvoice(invoiceId);
	}

	public static List<String> finalizeInvoice(Id invoiceId, String logGUID){
		return Util_FinancialSystem_Invoice.finalizeInvoice(invoiceId, logGUID);
	}

	public static List<String> loadInvoiceNumber(Id invoiceid){
		return Util_FinancialSystem_Invoice.loadInvoiceNumber(invoiceid);
	}

	public static List<String> loadInvoiceNumber(Id invoiceid, String logGUID){
		return Util_FinancialSystem_Invoice.loadInvoiceNumber(invoiceid, logGUID);
	}
}
