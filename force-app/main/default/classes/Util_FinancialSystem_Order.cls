/**
 * Order sync to the financial system (Exact Online), bulkified. Successor of Util_Exact.syncOrder.
 *
 * syncOrders() handles many orders in one transaction: all callouts first, then one DML phase.
 *  - item GUIDs are cached on Subscription25__Administration_Product__c.Exact_Id__c; missing ones are
 *    fetched with ONE OR-filtered GET per administration for all orders in the chunk
 *  - one POST per order (the lines go inside the sales order)
 *  - the account's Exact ids come from the Account (FinancialIdAccount__c) and the main contact's
 *    AccountContactRelation (FinancialIdContact__c); an account that is not in Exact yet is queued for
 *    Batch_FinancialSystemAccountSync and the order waits (no failed attempt counted)
 *  - success: Exact_Id__c, Exact_Order_Number__c, Status = Activated, SyncToFinancialSystem__c cleared
 *  - failures keep the flag and are retried with exponential back-off
 */
public without sharing class Util_FinancialSystem_Order {
	private static final String ORDER_ENDPOINT = 'api/v1/{0}/salesorder/SalesOrders';
	private static final String ARTICLE_GET_ENDPOINT = 'api/v1/{0}/bulk/Logistics/Items';
	public static final String STATUS_ACTIVATED = 'Activated';
	private static final Integer WAIT_FOR_ACCOUNT_MINUTES = 15;

	public class Result {
		public Id orderId;
		public Boolean success = false;
		public Boolean postponed = false;
		public Integer calls = 0;
		public List<String> messages = new List<String>();
	}

	// ---------------------------------------------------------------- entry points

	public static List<String> syncOrder(Id orderId) {
		return Util_FinancialSystem_Order.syncOrders(new Set<Id>{ orderId }, false).get(orderId).messages;
	}

	/**
	 * Marks the orders for the next Batch_FinancialSystemOrderSync run (and resets the back-off).
	 */
	public static void flagOrders(Set<Id> orderIds) {
		List<Order> orders = new List<Order>();
		for (Id ordId : orderIds) {
			orders.add(new Order(Id = ordId, SyncToFinancialSystem__c = true, FinancialSyncAttempts__c = 0, FinancialSyncNextAttempt__c = null));
		}
		Database.update(orders, false, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * Creates the orders in the financial system. batchMode = true: stay within the batch budget.
	 */
	public static Map<Id, Result> syncOrders(Set<Id> orderIds, Boolean batchMode) {
		Map<Id, Result> results = new Map<Id, Result>();
		List<Util_FinancialSystem_Order.Ctx> contexts = Util_FinancialSystem_Order.load(orderIds);
		Set<Id> accountsToQueue = new Set<Id>();
		Set<Id> limitedAdmins = new Set<Id>();

		// 1. validate, resolve administration + account ids
		List<Util_FinancialSystem_Order.Ctx> ready = new List<Util_FinancialSystem_Order.Ctx>();
		for (Util_FinancialSystem_Order.Ctx ctx : contexts) {
			results.put(ctx.ord.Id, ctx.result);
			try {
				Util_FinancialSystem_Order.prepare(ctx, accountsToQueue);
				if (!ctx.done) {
					ready.add(ctx);
				}
			} catch (Util_System.CustomException e) {
				ctx.fail(e.getMessage(), Util_Event.LogResultStatus.ERROR);
			} catch (Exception e) {
				ctx.fail('Unhandled exception occurred: ' + e.getMessage(), Util_Event.LogResultStatus.UNHANDLED_EXCEPTION);
			}
		}

		// 2. item GUIDs: cached ones from the administration products, the rest with one GET per administration
		Map<Id, Map<String, String>> itemIdsByAdmin = new Map<Id, Map<String, String>>();
		List<Subscription25__Administration_Product__c> adminProdsToUpdate = new List<Subscription25__Administration_Product__c>();
		try {
			Util_FinancialSystem_Order.resolveItems(ready, itemIdsByAdmin, adminProdsToUpdate, batchMode, limitedAdmins);
		} catch (Util_FinancialSystem.RateLimitException e) {
			for (Util_FinancialSystem_Order.Ctx ctx : ready) {
				ctx.postpone(e.getMessage(), null);
			}
			ready.clear();
		}

		// 3. one POST per order
		for (Util_FinancialSystem_Order.Ctx ctx : ready) {
			if (ctx.done) {
				continue;
			}
			try {
				if (limitedAdmins.contains(ctx.admin.Id)) {
					ctx.postpone('Rate limit reached for ' + ctx.admin.Name + '; retried in a next run.', null);
					continue;
				}
				Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(ctx.admin);
				if (!(batchMode ? lim.hasBatchCapacity(1) : lim.hasCapacity(1))) {
					ctx.postpone('No financial system capacity left for ' + ctx.admin.Name + '; retried in a next run.', null);
					if (batchMode) {
						limitedAdmins.add(ctx.admin.Id);
					}
					continue;
				}
				Util_FinancialSystem_Order.postOrder(ctx, itemIdsByAdmin.get(ctx.admin.Id));
			} catch (Util_FinancialSystem.RateLimitException e) {
				ctx.postpone(e.getMessage(), null);
				limitedAdmins.add(ctx.admin.Id);
			} catch (Util_System.CustomException e) {
				ctx.fail(e.getMessage(), Util_Event.LogResultStatus.ERROR);
			} catch (Util_System.FinancialSyncException e) {
				ctx.fail(e.getMessage(), Util_Event.LogResultStatus.ERROR);
			} catch (Exception e) {
				ctx.fail('Unhandled exception occurred: ' + e.getMessage() + ' ' + e.getStackTraceString(), Util_Event.LogResultStatus.UNHANDLED_EXCEPTION);
			}
		}

		Util_FinancialSystem_Order.save(contexts, adminProdsToUpdate, accountsToQueue);
		return results;
	}

	// ---------------------------------------------------------------- context

	private class Ctx {
		Order ord;
		Account acct;
		String exactContactId;
		Subscription25__Administration__c admin;
		Event_Log__c log;
		Result result = new Result();
		Boolean done = false;
		Boolean failed = false;
		Datetime waitUntil;

		void postpone(String message, Datetime until) {
			this.done = true;
			this.result.postponed = true;
			this.result.messages.add(message);
			this.waitUntil = until;
			this.log.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
			this.log.Integration_Status__c = Util_Event.LogEventStatus.PENDING.name();
			this.log.Message__c += message + '\n';
		}

		void fail(String message, Util_Event.LogResultStatus status) {
			this.done = true;
			this.failed = true;
			this.result.messages.add(message);
			this.log.Result_Status__c = status.name();
			this.log.Message__c += message + '\n';
		}
	}

	private static List<Util_FinancialSystem_Order.Ctx> load(Set<Id> orderIds) {
		List<Order> orders = [
			SELECT Id, OrderNumber, Status, Type, Exact_Id__c, Exact_Order_Number__c, Payment_Method__c, Payment_Method_Result__c, Payment_Reference__c,
				Sales_Channel__c, Reseller__c, AccountId, SyncToFinancialSystem__c, FinancialSyncAttempts__c,
				Opportunity.Name, Opportunity.Customer_Reference__c, Opportunity.Installation_Notes__c,
				Opportunity.Sales_Contact__c, Opportunity.Sales_Contact__r.Name, Opportunity.Sales_Contact__r.Email, Opportunity.Sales_Contact__r.Phone,
				Account.Exact_Account_Name__c, Account.Reseller_Name__c, Account.Contact_Person__c, Account.Bank_Account_Number__c,
				Account.FinancialIdAccount__c, Account.FinancialDebtorNumber__c,
				(SELECT Id, UnitPrice, Quantity, Product_Name__c, Product_Code_Customer__c, Partner_Code__c,
					PricebookEntry.Product2Id, PricebookEntry.Product2.Name, PricebookEntry.Product2.ProductCode,
					PricebookEntry.Product2.Generate_Partner_Code__c, PricebookEntry.Product2.RecordType.DeveloperName
				FROM OrderItems ORDER BY OrderItemNumber)
			FROM Order
			WHERE Id IN :orderIds
			WITH SYSTEM_MODE
		];

		Map<Id, Id> mainContactByAccount = new Map<Id, Id>();
		for (Order ord : orders) {
			if (ord.Account?.Contact_Person__c != null) {
				mainContactByAccount.put(ord.AccountId, ord.Account.Contact_Person__c);
			}
		}
		Map<Id, String> exactContactByAccount = new Map<Id, String>();
		for (AccountContactRelation acr : [
				SELECT AccountId, ContactId, FinancialIdContact__c FROM AccountContactRelation
				WHERE AccountId IN :mainContactByAccount.keySet() AND ContactId IN :mainContactByAccount.values()
				WITH SYSTEM_MODE]) {
			if (mainContactByAccount.get(acr.AccountId) == acr.ContactId) {
				exactContactByAccount.put(acr.AccountId, acr.FinancialIdContact__c);
			}
		}

		List<Util_FinancialSystem_Order.Ctx> contexts = new List<Util_FinancialSystem_Order.Ctx>();
		for (Order ord : orders) {
			Util_FinancialSystem_Order.Ctx ctx = new Util_FinancialSystem_Order.Ctx();
			ctx.ord = ord;
			ctx.acct = ord.Account;
			ctx.exactContactId = exactContactByAccount.get(ord.AccountId);
			ctx.result.orderId = ord.Id;
			ctx.log = Util_Event.getLog(null, 'S', 'E', 'Order', 'sync2Exact', ord.Id, String.valueOf(ord.OrderNumber), null);
			contexts.add(ctx);
		}
		return contexts;
	}

	private static void prepare(Util_FinancialSystem_Order.Ctx ctx, Set<Id> accountsToQueue) {
		Order ord = ctx.ord;
		if (String.isNotBlank(ord.Exact_Id__c)) {
			// already in Exact: nothing to send, the flag is cleared
			ctx.done = true;
			ctx.result.messages.add('This order was already synchronised');
			return;
		}
		if (ctx.acct == null || String.isBlank(ctx.acct.Reseller_Name__c)) {
			throw new Util_System.CustomException('The order has no account with a reseller.');
		}
		Subscription25__Administration__c admin = Util_FinancialSystem.getAdministrationForReseller(ctx.acct.Reseller_Name__c);
		if (admin == null || ((admin.Subscription25__Synchronisation__c != Util_FinancialSystem.SYNC_EXACT || !admin.Subscription25__Active__c) && admin.Reseller__c != '1')) {
			throw new Util_System.CustomException('This accounts reseller does not synchronize with Exact');
		}
		ctx.admin = admin;
		if (!Util_System.isFinancialSyncAllowed(admin)) {
			throw new Util_System.CustomException('This is a sandbox and administration ' + admin.Name + ' has no acceptance environment configured - Exact sync is blocked.');
		}
		if (String.isBlank(ctx.acct.FinancialIdAccount__c) || String.isBlank(ctx.acct.FinancialDebtorNumber__c) || String.isBlank(ctx.exactContactId)) {
			accountsToQueue.add(ord.AccountId);
			ctx.postpone('The account (' + ctx.acct.Exact_Account_Name__c + ') is not synchronised with Exact yet (debtor number or contact person missing); it is queued for the account sync, the order waits.',
				System.now().addMinutes(WAIT_FOR_ACCOUNT_MINUTES));
			return;
		}
		if (ord.OrderItems == null || ord.OrderItems.isEmpty()) {
			throw new Util_System.CustomException('The order has no order products.');
		}
	}

	private static void resolveItems(List<Util_FinancialSystem_Order.Ctx> ready, Map<Id, Map<String, String>> itemIdsByAdmin,
			List<Subscription25__Administration_Product__c> adminProdsToUpdate, Boolean batchMode, Set<Id> limitedAdmins) {
		Map<Id, Subscription25__Administration__c> admins = new Map<Id, Subscription25__Administration__c>();
		Set<Id> productIds = new Set<Id>();
		for (Util_FinancialSystem_Order.Ctx ctx : ready) {
			if (ctx.done) {
				continue;
			}
			admins.put(ctx.admin.Id, ctx.admin);
			for (OrderItem oi : ctx.ord.OrderItems) {
				productIds.add(oi.PricebookEntry.Product2Id);
			}
		}
		if (admins.isEmpty()) {
			return;
		}
		Map<Id, List<Subscription25__Administration_Product__c>> missingByAdmin = new Map<Id, List<Subscription25__Administration_Product__c>>();
		for (Subscription25__Administration_Product__c ap : [
				SELECT Id, Subscription25__Administration__c, Subscription25__Product__c, Subscription25__Product__r.ProductCode, Exact_Id__c
				FROM Subscription25__Administration_Product__c
				WHERE Subscription25__Administration__c IN :admins.keySet() AND Subscription25__Product__c IN :productIds
				WITH SYSTEM_MODE]) {
			Id adminId = ap.Subscription25__Administration__c;
			if (!itemIdsByAdmin.containsKey(adminId)) {
				itemIdsByAdmin.put(adminId, new Map<String, String>());
			}
			if (String.isBlank(ap.Exact_Id__c)) {
				if (!missingByAdmin.containsKey(adminId)) {
					missingByAdmin.put(adminId, new List<Subscription25__Administration_Product__c>());
				}
				missingByAdmin.get(adminId).add(ap);
			} else {
				itemIdsByAdmin.get(adminId).put(ap.Subscription25__Product__r.ProductCode, ap.Exact_Id__c);
			}
		}
		for (Id adminId : missingByAdmin.keySet()) {
			Subscription25__Administration__c admin = admins.get(adminId);
			Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(admin);
			if (!(batchMode ? lim.hasBatchCapacity(1) : lim.hasCapacity(1))) {
				limitedAdmins.add(adminId);
				continue;
			}
			Set<String> codes = new Set<String>();
			for (Subscription25__Administration_Product__c ap : missingByAdmin.get(adminId)) {
				codes.add(ap.Subscription25__Product__r.ProductCode);
			}
			Map<String, String> found = Util_FinancialSystem_Order.getExactItemIds(admin, codes);
			for (Subscription25__Administration_Product__c ap : missingByAdmin.get(adminId)) {
				String exactId = found.get(ap.Subscription25__Product__r.ProductCode);
				if (String.isNotBlank(exactId)) {
					ap.Exact_Id__c = exactId;
					adminProdsToUpdate.add(ap);
					itemIdsByAdmin.get(adminId).put(ap.Subscription25__Product__r.ProductCode, exactId);
				}
			}
		}
	}

	/**
	 * Exact item GUIDs for the given item codes (one OR-filtered GET).
	 */
	public static Map<String, String> getExactItemIds(Subscription25__Administration__c admin, Set<String> codes) {
		List<String> codeFilters = new List<String>();
		for (String code : codes) {
			codeFilters.add('Code eq \'' + code.replace('\'', '\'\'') + '\'');
		}
		Map<String, String> params = new Map<String, String>{
			'$select' => 'ID,Code',
			'$filter' => String.join(codeFilters, ' or ')
		};
		String endpoint = String.format(ARTICLE_GET_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
		String response = Util_FinancialSystem.doRequest(admin, endpoint, params, 'GET', null, null);
		Util_FinancialSystem_Order.ExactItems allItems = (Util_FinancialSystem_Order.ExactItems) JSON.deserialize(response, Util_FinancialSystem_Order.ExactItems.class);
		Map<String, String> itemIds = new Map<String, String>();
		if (allItems != null && allItems.results != null) {
			for (Util_FinancialSystem_Order.ExactItem item : allItems.results) {
				itemIds.put(item.Code, item.ID);
			}
		}
		return itemIds;
	}

	private static void postOrder(Util_FinancialSystem_Order.Ctx ctx, Map<String, String> itemIds) {
		Order ord = ctx.ord;
		Map<String, String> ids = itemIds == null ? new Map<String, String>() : itemIds;
		Set<String> missing = new Set<String>();
		for (OrderItem oi : ord.OrderItems) {
			if (!ids.containsKey(oi.PricebookEntry.Product2.ProductCode)) {
				missing.add(oi.PricebookEntry.Product2.ProductCode);
			}
		}
		if (!missing.isEmpty()) {
			throw new Util_System.CustomException('Some of the order items are not available in exact: ' + String.join(new List<String>(missing), ', '));
		}
		// a direct debit order without a bank account is invoiced "on account"
		if (String.isBlank(ord.Payment_Method__c)
				|| (ord.Payment_Method__c.left(1) == 'I' && String.isBlank(ctx.acct.Bank_Account_Number__c))) {
			ord.Payment_Method__c = '08';
		}
		Util_FinancialSystem_Order.ExactOrder body = new Util_FinancialSystem_Order.ExactOrder(ctx, ids);
		String endpoint = String.format(ORDER_ENDPOINT, new List<String>{ ctx.admin.Subscription25__Twinfield_Company_Code__c });
		String response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), ctx.log.GUID__c);
		ctx.result.calls++;
		Util_FinancialSystem_Order.ExactOrderResponse created = (Util_FinancialSystem_Order.ExactOrderResponse) JSON.deserialize(response, Util_FinancialSystem_Order.ExactOrderResponse.class);
		ord.Exact_Id__c = created.OrderID;
		ord.Exact_Order_Number__c = created.OrderNumber != null ? String.valueOf(created.OrderNumber) : '';
		ctx.result.success = true;
		ctx.done = true;
	}

	// ---------------------------------------------------------------- DML phase

	private static void save(List<Util_FinancialSystem_Order.Ctx> contexts, List<Subscription25__Administration_Product__c> adminProdsToUpdate, Set<Id> accountsToQueue) {
		List<Order> orders = new List<Order>();
		List<Event_Log__c> logs = new List<Event_Log__c>();
		Set<String> namedCredentials = new Set<String>();
		for (Util_FinancialSystem_Order.Ctx ctx : contexts) {
			Order ord = ctx.ord;
			Order upd = new Order(Id = ord.Id);
			if (ctx.admin != null) {
				namedCredentials.add(ctx.admin.Subscription25__Named_Credential__c);
			}
			if (ctx.result.success) {
				upd.Exact_Id__c = ord.Exact_Id__c;
				upd.Exact_Order_Number__c = ord.Exact_Order_Number__c;
				upd.Payment_Method__c = ord.Payment_Method__c;
				upd.Status = STATUS_ACTIVATED;
				upd.SyncToFinancialSystem__c = false;
				upd.FinancialSyncAttempts__c = 0;
				upd.FinancialSyncNextAttempt__c = null;
				upd.FinancialSyncLastError__c = null;
				ctx.log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
			} else if (!ctx.failed && !ctx.result.postponed) {
				// already synchronised
				upd.SyncToFinancialSystem__c = false;
				upd.FinancialSyncLastError__c = null;
				ctx.log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
			} else if (ctx.result.postponed) {
				upd.FinancialSyncNextAttempt__c = ctx.waitUntil;
				upd.FinancialSyncLastError__c = String.join(ctx.result.messages, ' | ').left(255);
			} else {
				Integer attempts = (ord.FinancialSyncAttempts__c == null ? 0 : ord.FinancialSyncAttempts__c.intValue()) + 1;
				upd.FinancialSyncAttempts__c = attempts;
				upd.FinancialSyncNextAttempt__c = Util_FinancialSystem.nextAttempt(attempts);
				upd.FinancialSyncLastError__c = String.join(ctx.result.messages, ' | ').left(255);
				upd.SyncToFinancialSystem__c = true;
				ctx.log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
			}
			ctx.log.extId__c = ord.Exact_Id__c;
			ctx.log.Message__c = (ctx.log.Message__c + 'Calls: ' + ctx.result.calls).left(131072);
			orders.add(upd);
			logs.add(ctx.log);
		}
		if (!adminProdsToUpdate.isEmpty()) {
			Database.update(adminProdsToUpdate, false, AccessLevel.SYSTEM_MODE);
		}
		List<Database.SaveResult> srs = Database.update(orders, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < srs.size(); i++) {
			if (!srs[i].isSuccess()) {
				Util_FinancialSystem_Order.Ctx ctx = contexts[i];
				String msg = 'Saving the order failed: ' + srs[i].getErrors()[0].getMessage();
				ctx.result.success = false;
				ctx.result.messages.add(msg);
				ctx.log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
				ctx.log.Message__c += '\n' + msg;
				if (String.isNotBlank(ctx.ord.Exact_Id__c)) {
					// the order exists in Exact: at least store its id so it is never created twice
					Database.update(new Order(Id = ctx.ord.Id, Exact_Id__c = ctx.ord.Exact_Id__c, Exact_Order_Number__c = ctx.ord.Exact_Order_Number__c,
						SyncToFinancialSystem__c = false, FinancialSyncLastError__c = msg.left(255)), false, AccessLevel.SYSTEM_MODE);
				}
			}
		}
		if (!accountsToQueue.isEmpty()) {
			Set<Id> notFlagged = new Set<Id>();
			for (Account acct : [SELECT Id FROM Account WHERE Id IN :accountsToQueue AND SyncToFinancialSystem__c = false WITH SYSTEM_MODE]) {
				notFlagged.add(acct.Id);
			}
			if (!notFlagged.isEmpty()) {
				Util_FinancialSystemAccount.flagAccounts(notFlagged);
			}
		}
		Util_FinancialSystem.saveLimits();
		Util_FinancialSystem.saveLogs(logs, namedCredentials, null);
	}

	// ---------------------------------------------------------------- Exact payloads

	private class ExactOrderResponse {
		String OrderID;
		Integer OrderNumber;
	}

	@TestVisible
	private class ExactOrder {
		String InvoiceTo;
		String OrderedBy;
		String OrderedByContactPerson;
		Datetime OrderDate;
		String PaymentCondition;
		String PaymentReference;
		String Description;
		String Remarks;
		String SalesChannel;
		String YourRef;
		String WarehouseID;
		List<Util_FinancialSystem_Order.ExactOrderLine> SalesOrderLines;

		ExactOrder(Util_FinancialSystem_Order.Ctx ctx, Map<String, String> itemIds) {
			Order ord = ctx.ord;
			this.InvoiceTo = ctx.acct.FinancialIdAccount__c;
			this.OrderedBy = ctx.acct.FinancialIdAccount__c;
			this.OrderedByContactPerson = ctx.exactContactId;
			this.OrderDate = Datetime.now();
			this.PaymentCondition = ord.Payment_Method_Result__c;
			this.PaymentReference = String.isBlank(ord.Payment_Reference__c) ? null : ord.Payment_Reference__c;
			this.Description = ord.Opportunity?.Name;
			this.YourRef = ord.Opportunity?.Customer_Reference__c;
			this.Remarks = '';
			if (ord.Opportunity?.Sales_Contact__c != null && ord.Opportunity.Sales_Contact__c != ctx.acct.Contact_Person__c) {
				List<String> ll = new List<String>{ ord.Opportunity.Sales_Contact__r.Name };
				if (ord.Opportunity.Sales_Contact__r.Email != null) {
					ll.add(ord.Opportunity.Sales_Contact__r.Email);
				}
				if (ord.Opportunity.Sales_Contact__r.Phone != null) {
					ll.add(ord.Opportunity.Sales_Contact__r.Phone);
				}
				this.Remarks = String.join(ll, '\r\n');
			}
			String warehouseId = '';
			if (ord.Reseller__c == '1') {
				this.SalesChannel = Util_FinancialSystem.getExactRelationId(ctx.admin.Id, 'SC', ord.Sales_Channel__c);
				warehouseId = Util_FinancialSystem.getExactRelationId(ctx.admin.Id, 'WH', ord.Sales_Channel__c);
			}
			this.WarehouseID = String.isNotBlank(warehouseId) ? warehouseId : ctx.admin.Warehouse_Exact_Id__c;
			this.SalesOrderLines = new List<Util_FinancialSystem_Order.ExactOrderLine>();
			Integer i = 0;
			for (OrderItem oi : ord.OrderItems) {
				i++;
				this.SalesOrderLines.add(new Util_FinancialSystem_Order.ExactOrderLine(ord, oi, i, itemIds));
			}
		}
	}

	private class ExactOrderLine {
		String Item;
		Decimal Quantity;
		Decimal UnitPrice;
		String CustomerItemCode;
		String Description;
		String Notes;

		ExactOrderLine(Order ord, OrderItem oi, Integer i, Map<String, String> itemIds) {
			this.Item = itemIds.get(oi.PricebookEntry.Product2.ProductCode);
			this.Quantity = oi.Quantity;
			this.UnitPrice = oi.UnitPrice;
			this.Description = (oi.Product_Code_Customer__c != null) ? oi.Product_Code_Customer__c + ' ' : '';
			this.Description += (oi.Product_Name__c != null) ? oi.Product_Name__c : oi.PricebookEntry.Product2.Name;
			if (oi.Partner_Code__c != null && oi.PricebookEntry.Product2.RecordType.DeveloperName == 'SubscriptionP' && oi.PricebookEntry.Product2.Generate_Partner_Code__c) {
				this.Notes = '--------------------------------------------------------------------------------\n';
				this.Notes += 'Partner code : ' + oi.Partner_Code__c + '\n';
				this.Notes += '--------------------------------------------------------------------------------\n';
			} else {
				this.Notes = '';
			}
			if (i == 1 && !String.isBlank(ord.Opportunity?.Installation_Notes__c)) {
				this.Notes += ord.Opportunity.Installation_Notes__c;
			}
		}
	}

	private class ExactItems {
		List<Util_FinancialSystem_Order.ExactItem> results;
	}

	private class ExactItem {
		String Code;
		String ID;
	}
}
