/**
 * 20261106 TRi Phase 2 of the Odoo invoice intake: books an Odoo invoice (Svc_OdooInvoiceIntake, External_ID__c 'ODOO-<nr>') in the
 * financial system of an Exact administration (01 = Netherlands, 04 = United Kingdom), without sending anything: Odoo sent it already.
 * There is no Exact sales order behind these invoices, so this posts a salesinvoice/SalesInvoices directly (the Exact order helpers of
 * Util_FinancialSystem_Invoice, which look up by order number, are not used).
 *
 * Exact decides the invoice number (SalesInvoices.InvoiceNumber: "assigned at entry or at printing depending on setting"); it cannot be
 * supplied, so the Odoo number is offered in YourRef + Description and the invoice keeps the Odoo number in Invoice_Number__c.
 * Business_Entities__c.FinSysInvoiceNumberMethod__c says when Exact numbers:
 *  - Import: at entry (on create), the number is read straight back from the POST / a GET by invoice id;
 *  - Print: at printing; PrintedSalesInvoices is called (every send flag false, so nothing is sent), then the number is read back.
 * The Exact invoice id and number are stored in FinSysInvoiceId__c / FinSysInvoiceNumber__c (raw, no prefix); a number that differs
 * from the Odoo number is reported in the result (it is expected for Exact numbering: the two numbers both exist then).
 * Blocked in a sandbox unless the administration has an acceptance environment (Util_System.isFinancialSyncAllowed, and the
 * production-division backstop in Util_FinancialSystem.doRequest). Items must exist in Exact (never created here).
 */
public without sharing class Svc_OdooExactSync {
	public static final String EXTERNAL_ID_PREFIX = 'ODOO-';
	public static final String METHOD_IMPORT = 'Import';
	public static final String METHOD_PRINT = 'Print';
	private static final Integer JOURNAL_TYPE_SALES = 20;
	private static final String INVOICE_ENDPOINT = 'api/v1/{0}/salesinvoice/SalesInvoices';
	private static final String INVOICE_GET_ENDPOINT = 'api/v1/{0}/bulk/salesinvoice/SalesInvoices';
	private static final String PRINT_ENDPOINT = 'api/v1/{0}/salesinvoice/PrintedSalesInvoices';
	private static final String JOURNAL_ENDPOINT = 'api/v1/{0}/financial/Journals';

	public class SyncException extends Exception {}

	private static List<Subscription25__Administration_Product__c> pendingCache = new List<Subscription25__Administration_Product__c>();

	public class Result {
		public Id invoiceId;
		public Boolean success = false;
		public Boolean skipped = false;
		public String message;
		public String exactInvoiceId;
		public String exactInvoiceNumber;
	}

	/** Invoices that still have to be booked in the financial system (batch candidates). */
	public static Database.QueryLocator candidates() {
		return Database.getQueryLocator([
			SELECT Id FROM Subscription25__Invoice__c
			WHERE Subscription25__External_ID__c LIKE 'ODOO-%' AND FinSysInvoiceId__c = null
				AND Subscription25__Administration__r.Subscription25__Synchronisation__c = :Util_FinancialSystem.SYNC_EXACT
				AND Subscription25__Administration__r.Subscription25__Active__c = true
				AND Subscription25__Account__r.FinancialIdAccount__c != null
				AND (FinSysNextAttempt__c = null OR FinSysNextAttempt__c <= :System.now())
			WITH SYSTEM_MODE
			ORDER BY CreatedDate
		]);
	}

	public static Result sync(Id invoiceId) {
		Result res = new Result();
		res.invoiceId = invoiceId;
		Subscription25__Invoice__c inv = load(invoiceId);
		Event_Log__c log = Util_Event.getLog(null, 'S', 'E', 'Invoice', 'odoo2Exact', invoiceId, inv.Name, null);
		Subscription25__Administration__c admin = inv.Subscription25__Administration__r;
		try {
			if (inv.Subscription25__External_ID__c == null || !inv.Subscription25__External_ID__c.startsWith(EXTERNAL_ID_PREFIX)) {
				throw new SyncException('Not an Odoo invoice');
			}
			if (String.isNotBlank(inv.FinSysInvoiceId__c)) {
				res.skipped = true;
				res.exactInvoiceId = inv.FinSysInvoiceId__c;
				res.exactInvoiceNumber = inv.FinSysInvoiceNumber__c;
				res.message = 'Already booked in the financial system';
				return res;
			}
			if (admin == null || admin.Subscription25__Synchronisation__c != Util_FinancialSystem.SYNC_EXACT || admin.Subscription25__Active__c != true) {
				throw new SyncException('The administration does not synchronise with Exact');
			}
			if (!Util_System.isFinancialSyncAllowed(admin)) {
				throw new SyncException('This is a sandbox and administration ' + admin.Name + ' has no acceptance environment configured - Exact sync is blocked.');
			}
			String method = numberMethod(admin);
			String account = inv.Subscription25__Account__r.FinancialIdAccount__c;
			if (String.isBlank(account)) {
				throw new SyncException('The account is not in Exact yet');
			}
			String odooNumber = inv.Subscription25__External_ID__c.substringAfter(EXTERNAL_ID_PREFIX);
			List<OrderItem> items = [
				SELECT Quantity, UnitPrice, Product_Name__c, Description, PricebookEntry.Product2Id, PricebookEntry.Product2.Name, PricebookEntry.Product2.ProductCode
				FROM OrderItem WHERE Order.Subscription25__Invoice__c = :invoiceId WITH SYSTEM_MODE ORDER BY OrderItemNumber
			];
			if (items.isEmpty()) {
				throw new SyncException('The invoice has no order lines');
			}
			Map<String, String> itemIds = itemIds(admin, items);
			String company = admin.Subscription25__Twinfield_Company_Code__c;

			// an earlier run may have posted it and failed afterwards: look it up by the Odoo number before posting again
			Map<String, Object> existing = find(admin, company, odooNumber, log.GUID__c);
			if (existing == null) {
				existing = post(admin, company, inv, account, odooNumber, items, itemIds, log.GUID__c);
			}
			String exactId = String.valueOf(existing.get('InvoiceID'));
			res.exactInvoiceId = exactId;
			String exactNumber = number(existing);

			Boolean printed = false;
			if (METHOD_PRINT == method) {
				// Exact numbers at printing (nothing is sent)
				print(admin, company, exactId, inv.Subscription25__Invoice_Date__c, log.GUID__c);
				printed = true;
				exactNumber = number(get(admin, company, exactId, log.GUID__c));
			} else if (String.isBlank(exactNumber)) {
				// numbered at entry: the POST response did not carry it, read it back
				exactNumber = number(get(admin, company, exactId, log.GUID__c));
			}
			res.exactInvoiceNumber = exactNumber;

			Subscription25__Invoice__c upd = new Subscription25__Invoice__c(Id = invoiceId, FinSysInvoiceId__c = exactId, FinSysNextAttempt__c = null,
				FinancialSystemLastSyncDate__c = System.now());
			if (String.isNotBlank(exactNumber)) {
				upd.FinSysInvoiceNumber__c = exactNumber;
			}
			if (printed) {
				upd.Subscription25__Finalized_In_Exact__c = true;
			}
			save(upd);
			if (!pendingCache.isEmpty()) {
				Database.update(pendingCache, false, AccessLevel.SYSTEM_MODE);
				pendingCache.clear();
			}
			res.success = true;
			res.message = 'Booked in Exact as ' + exactNumber + ' (' + method + '), Odoo number ' + odooNumber
				+ (exactNumber == odooNumber ? '' : '; Exact numbers the invoice itself, the Odoo number is in its reference');
		} catch (Exception e) {
			res.message = e.getMessage();
			log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			log.Message__c = e.getMessage() + '\n' + e.getStackTraceString();
			if (!(e instanceof Util_FinancialSystem.RateLimitException)) {
				// back off a day (the batch skips it until then)
				save(new Subscription25__Invoice__c(Id = invoiceId, FinSysNextAttempt__c = System.now().addDays(1)));
			}
		}
		Util_FinancialSystem.saveLogs(new List<Event_Log__c>{ log }, new Set<String>{ Util_FinancialSystem.namedCredential(admin, Util_FinancialSystem.CredentialPurpose.SYNC) }, log.GUID__c);
		return res;
	}

	private static Subscription25__Invoice__c load(Id invoiceId) {
		return [
			SELECT Id, Name, Subscription25__External_ID__c, Subscription25__Invoice_Date__c, Subscription25__Due_Date__c,
				Subscription25__Purchase_Order_Number__c, FinSysInvoiceId__c, FinSysInvoiceNumber__c,
				Subscription25__Account__r.FinancialIdAccount__c, Subscription25__Account__r.FinancialDebtorNumber__c,
				Subscription25__Administration__r.Id, Subscription25__Administration__r.Name, Subscription25__Administration__r.Reseller__c,
				Subscription25__Administration__r.Daily_Limit__c, Subscription25__Administration__r.FinancialRateLimitMaxPercentage__c,
				Subscription25__Administration__r.FinancialRateLimitRemaining__c, Subscription25__Administration__r.FinancialRateLimitResetOn__c,
				Subscription25__Administration__r.Acceptance_Environment_Available__c, Subscription25__Administration__r.Subscription25__Named_Credential__c,
				Subscription25__Administration__r.Subscription25__Twinfield_Company_Code__c, Subscription25__Administration__r.Subscription25__Synchronisation__c,
				Subscription25__Administration__r.Subscription25__Active__c
			FROM Subscription25__Invoice__c WHERE Id = :invoiceId WITH SYSTEM_MODE
		];
	}

	/** Print / Import of the administration's business entity; blank = not set up, no guessing. */
	private static String numberMethod(Subscription25__Administration__c admin) {
		List<Business_Entities__c> bes = [SELECT FinSysInvoiceNumberMethod__c FROM Business_Entities__c WHERE Reseller__c = :admin.Reseller__c WITH SYSTEM_MODE LIMIT 1];
		String method = bes.isEmpty() ? null : bes[0].FinSysInvoiceNumberMethod__c;
		if (method != METHOD_IMPORT && method != METHOD_PRINT) {
			throw new SyncException('Business Entity of reseller ' + admin.Reseller__c + ' has no invoice number method (Print / Import)');
		}
		return method;
	}

	/** Exact item GUID per product code: the administration product cache first, the rest from Exact; a missing item stops the sync. */
	private static Map<String, String> itemIds(Subscription25__Administration__c admin, List<OrderItem> items) {
		Set<Id> productIds = new Set<Id>();
		Set<String> codes = new Set<String>();
		for (OrderItem oi : items) {
			productIds.add(oi.PricebookEntry.Product2Id);
			codes.add(oi.PricebookEntry.Product2.ProductCode);
		}
		Map<String, String> ids = new Map<String, String>();
		List<Subscription25__Administration_Product__c> toCache = new List<Subscription25__Administration_Product__c>();
		List<Subscription25__Administration_Product__c> missing = new List<Subscription25__Administration_Product__c>();
		for (Subscription25__Administration_Product__c ap : [
				SELECT Id, Subscription25__Product__r.ProductCode, Exact_Id__c FROM Subscription25__Administration_Product__c
				WHERE Subscription25__Administration__c = :admin.Id AND Subscription25__Product__c IN :productIds WITH SYSTEM_MODE]) {
			if (String.isNotBlank(ap.Exact_Id__c)) {
				ids.put(ap.Subscription25__Product__r.ProductCode, ap.Exact_Id__c);
			} else {
				missing.add(ap);
			}
		}
		Set<String> unknown = new Set<String>(codes);
		unknown.removeAll(ids.keySet());
		if (!unknown.isEmpty()) {
			Map<String, String> found = Util_FinancialSystem_Order.getExactItemIds(admin, unknown);
			ids.putAll(found);
			for (Subscription25__Administration_Product__c ap : missing) {
				String id = found.get(ap.Subscription25__Product__r.ProductCode);
				if (String.isNotBlank(id)) {
					ap.Exact_Id__c = id;
					toCache.add(ap);
				}
			}
		}
		Set<String> stillMissing = new Set<String>(codes);
		stillMissing.removeAll(ids.keySet());
		if (!stillMissing.isEmpty()) {
			throw new SyncException('No Exact item for product code(s): ' + String.join(new List<String>(stillMissing), ', ') + ' (items are not created here)');
		}
		// saved after the last callout (no DML before a callout)
		pendingCache = toCache;
		return ids;
	}

	private static String salesJournal(Subscription25__Administration__c admin, String company, String guid) {
		String endpoint = String.format(JOURNAL_ENDPOINT, new List<String>{ company });
		List<Object> journals = results(Util_FinancialSystem.doRequest(admin, endpoint,
			new Map<String, String>{ '$select' => 'Code', '$filter' => 'Type eq ' + JOURNAL_TYPE_SALES }, 'GET', null, guid));
		if (journals.size() != 1) {
			throw new SyncException(journals.size() + ' sales journals found in Exact; exactly one is needed to book an Odoo invoice');
		}
		return String.valueOf(((Map<String, Object>) journals[0]).get('Code'));
	}

	@TestVisible
	private static Map<String, Object> post(Subscription25__Administration__c admin, String company, Subscription25__Invoice__c inv, String account,
			String odooNumber, List<OrderItem> items, Map<String, String> itemIds, String guid) {
		List<Map<String, Object>> lines = new List<Map<String, Object>>();
		for (OrderItem oi : items) {
			String name = String.isBlank(oi.Product_Name__c) ? oi.PricebookEntry.Product2.Name : oi.Product_Name__c;
			lines.add(new Map<String, Object>{
				'Item' => itemIds.get(oi.PricebookEntry.Product2.ProductCode),
				'Quantity' => oi.Quantity,
				'UnitPrice' => oi.UnitPrice,
				'Description' => name
			});
		}
		Map<String, Object> body = new Map<String, Object>{
			'Journal' => salesJournal(admin, company, guid),
			'InvoiceTo' => account,
			'OrderedBy' => account,
			'InvoiceDate' => Util_System.formatDate(inv.Subscription25__Invoice_Date__c, 'yyyy-MM-dd'),
			'YourRef' => odooNumber,
			'Description' => 'Odoo ' + odooNumber,
			'SalesInvoiceLines' => lines
		};
		String response = Util_FinancialSystem.doRequest(admin, String.format(INVOICE_ENDPOINT, new List<String>{ company }), null, 'POST', JSON.serialize(body), guid);
		Map<String, Object> created = (Map<String, Object>) JSON.deserializeUntyped(response);
		if (created.get('InvoiceID') == null) {
			throw new SyncException('Exact did not return an invoice id');
		}
		return created;
	}

	private static Map<String, Object> find(Subscription25__Administration__c admin, String company, String odooNumber, String guid) {
		List<Object> found = results(Util_FinancialSystem.doRequest(admin, String.format(INVOICE_GET_ENDPOINT, new List<String>{ company }),
			new Map<String, String>{ '$select' => 'InvoiceID,InvoiceNumber,Status', '$filter' => 'YourRef eq \'' + Util_FinancialSystem.odataString(odooNumber) + '\'' }, 'GET', null, guid));
		return found.isEmpty() ? null : (Map<String, Object>) found[0];
	}

	private static Map<String, Object> get(Subscription25__Administration__c admin, String company, String exactId, String guid) {
		List<Object> found = results(Util_FinancialSystem.doRequest(admin, String.format(INVOICE_GET_ENDPOINT, new List<String>{ company }),
			new Map<String, String>{ '$select' => 'InvoiceID,InvoiceNumber,Status', '$filter' => 'InvoiceID eq guid\'' + exactId + '\'' }, 'GET', null, guid));
		if (found.isEmpty()) {
			throw new SyncException('Invoice ' + exactId + ' not found in Exact');
		}
		return (Map<String, Object>) found[0];
	}

	private static void print(Subscription25__Administration__c admin, String company, String exactId, Date invoiceDate, String guid) {
		Map<String, Object> req = new Map<String, Object>{
			'InvoiceID' => exactId,
			'InvoiceDate' => Util_System.formatDate(invoiceDate, 'yyyy-MM-dd'),
			'SendEmailToCustomer' => false,
			'SendInvoiceToCustomerPostbox' => false,
			'SendOutputBasedOnAccount' => false
		};
		Util_FinancialSystem.doRequest(admin, String.format(PRINT_ENDPOINT, new List<String>{ company }), null, 'POST', JSON.serialize(req), guid);
	}

	private static String number(Map<String, Object> invoice) {
		Object n = invoice.get('InvoiceNumber');
		String s = n == null ? null : String.valueOf(n);
		return (String.isBlank(s) || s == 'null') ? null : s;
	}

	private static List<Object> results(String response) {
		if (String.isBlank(response)) {
			return new List<Object>();
		}
		Object parsed = JSON.deserializeUntyped(response);
		if (parsed instanceof List<Object>) {
			return (List<Object>) parsed;
		}
		if (parsed instanceof Map<String, Object>) {
			Object r = ((Map<String, Object>) parsed).get('results');
			return r instanceof List<Object> ? (List<Object>) r : new List<Object>();
		}
		return new List<Object>();
	}

	private static void save(Subscription25__Invoice__c upd) {
		Boolean curEru = Util_System.getEruIluvatar();
		if (!curEru) {
			Util_System.setEruIluvatar(true);
		}
		Database.update(upd, false, AccessLevel.SYSTEM_MODE);
		if (!curEru) {
			Util_System.setEruIluvatar(false);
		}
	}
}
