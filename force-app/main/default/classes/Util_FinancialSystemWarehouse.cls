/**
 * Financial system (Exact) warehouses: Exact allows one warehouse per sales order, so an order (FinancialSystemIdWarehouse__c,
 * pvs_FinancialSystemWarehouse) holds the products of one warehouse only.
 * Warehouse of a product: the Administration Product's warehouse, otherwise the administration default.
 * The Exact GUID of a warehouse differs per org and is mapped on Exact_Relation_Setting__c (WH rows).
 */
public with sharing class Util_FinancialSystemWarehouse {

	public static final String RELATION_WAREHOUSE = 'WH';

	private static Map<Id, Map<String, String>> exactIds;

	/**
	 * Administration (as used by the financial system sync: via the account's reseller) per account.
	 */
	public static Map<Id, Subscription25__Administration__c> getAdministrations(Set<Id> accountIds) {
		Map<Id, Subscription25__Administration__c> adminByAccount = new Map<Id, Subscription25__Administration__c>();
		Map<Id, String> resellerByAccount = new Map<Id, String>();
		for (Account acct : [SELECT Id, Reseller_Name__c FROM Account WHERE Id IN :accountIds AND Reseller_Name__c != null WITH SYSTEM_MODE]) {
			resellerByAccount.put(acct.Id, acct.Reseller_Name__c);
		}
		Set<Id> adminIds = new Set<Id>();
		Map<Id, Id> adminIdByAccount = new Map<Id, Id>();
		for (Id acctId : resellerByAccount.keySet()) {
			Subscription25__Administration__c admin = Util_FinancialSystem.getAdministrationForReseller(resellerByAccount.get(acctId));
			if (admin != null) {
				adminIds.add(admin.Id);
				adminIdByAccount.put(acctId, admin.Id);
			}
		}
		Map<Id, Subscription25__Administration__c> admins = new Map<Id, Subscription25__Administration__c>([
			SELECT Id, Name, Reseller__c, FinancialSystemIdWarehouse__c FROM Subscription25__Administration__c WHERE Id IN :adminIds WITH SYSTEM_MODE
		]);
		for (Id acctId : adminIdByAccount.keySet()) {
			adminByAccount.put(acctId, admins.get(adminIdByAccount.get(acctId)));
		}
		return adminByAccount;
	}

	/**
	 * Warehouse per product for the given administrations: Administration Product warehouse, otherwise the
	 * administration default. Key: administration id + product id. Products without either are left out.
	 */
	public static Map<String, String> getProductWarehouses(List<Subscription25__Administration__c> admins, Set<Id> productIds) {
		Map<String, String> result = new Map<String, String>();
		Map<Id, Subscription25__Administration__c> adminById = new Map<Id, Subscription25__Administration__c>();
		for (Subscription25__Administration__c admin : admins) {
			if (admin != null) {
				adminById.put(admin.Id, admin);
			}
		}
		for (Subscription25__Administration_Product__c ap : [
				SELECT Subscription25__Administration__c, Subscription25__Product__c, FinancialSystemIdWarehouse__c
				FROM Subscription25__Administration_Product__c
				WHERE Subscription25__Administration__c IN :adminById.keySet() AND Subscription25__Product__c IN :productIds
					AND FinancialSystemIdWarehouse__c != null
				WITH SYSTEM_MODE]) {
			result.put(key(ap.Subscription25__Administration__c, ap.Subscription25__Product__c), ap.FinancialSystemIdWarehouse__c);
		}
		for (Subscription25__Administration__c admin : adminById.values()) {
			if (String.isBlank(admin.FinancialSystemIdWarehouse__c)) {
				continue;
			}
			for (Id productId : productIds) {
				String k = key(admin.Id, productId);
				if (!result.containsKey(k)) {
					result.put(k, admin.FinancialSystemIdWarehouse__c);
				}
			}
		}
		return result;
	}

	public static String key(Id adminId, Id productId) {
		return String.valueOf(adminId) + String.valueOf(productId);
	}

	/**
	 * Exact warehouse GUID of a warehouse value in the given administration (Exact_Relation_Setting__c WH row).
	 * Null when not mapped.
	 */
	public static String getExactId(Id adminId, String warehouse) {
		if (adminId == null || String.isBlank(warehouse)) {
			return null;
		}
		if (Util_FinancialSystemWarehouse.exactIds == null) {
			Util_FinancialSystemWarehouse.exactIds = new Map<Id, Map<String, String>>();
			for (Exact_Relation_Setting__c sett : [
					SELECT Administration__c, FinancialSystemIdWarehouse__c, Exact_ID__c FROM Exact_Relation_Setting__c
					WHERE Classification__c = :RELATION_WAREHOUSE AND FinancialSystemIdWarehouse__c != null AND Exact_ID__c != null
					WITH SYSTEM_MODE]) {
				if (!Util_FinancialSystemWarehouse.exactIds.containsKey(sett.Administration__c)) {
					Util_FinancialSystemWarehouse.exactIds.put(sett.Administration__c, new Map<String, String>());
				}
				Util_FinancialSystemWarehouse.exactIds.get(sett.Administration__c).put(sett.FinancialSystemIdWarehouse__c, sett.Exact_ID__c);
			}
		}
		Map<String, String> byWarehouse = Util_FinancialSystemWarehouse.exactIds.get(adminId);
		return byWarehouse == null ? null : byWarehouse.get(warehouse);
	}

	// ---------------------------------------------------------------- split (repair)

	public static final Set<String> SPLIT_ORDER_TYPES = Util_FinancialSystem_Order.SYNC_ORDER_TYPES;

	/**
	 * Repairs draft Hardware / Opportunity orders that are not in Exact yet: the order gets the warehouse API name
	 * of its first product and keeps the products of that warehouse; the products of every other warehouse move to a
	 * new draft order of that warehouse (copy of the order, same opportunity). Order products can not change order,
	 * so a move is a copy + delete. Per order all or nothing. Returns per order the result message.
	 */
	public static Map<Id, String> splitOrders(Set<Id> orderIds) {
		Map<Id, String> results = new Map<Id, String>();
		List<String> orderFields = Util_FinancialSystemWarehouse.copyFields(Order.SObjectType);
		List<String> lineFields = Util_FinancialSystemWarehouse.copyFields(OrderItem.SObjectType);
		Set<Id> ids = orderIds;
		Set<String> types = SPLIT_ORDER_TYPES;
		List<Order> orders = Database.queryWithBinds(
			'SELECT Id, Status, ' + String.join(orderFields, ', ') + ', (SELECT Id, ' + String.join(lineFields, ', ') + ' FROM OrderItems ORDER BY OrderItemNumber)'
				+ ' FROM Order WHERE Id IN :ids AND Status = \'Draft\' AND Exact_Id__c = null AND Type IN :types',
			new Map<String, Object>{ 'ids' => ids, 'types' => types }, AccessLevel.SYSTEM_MODE);

		Set<Id> accountIds = new Set<Id>();
		Set<Id> productIds = new Set<Id>();
		for (Order ord : orders) {
			accountIds.add(ord.AccountId);
			for (OrderItem oi : ord.OrderItems) {
				productIds.add(oi.Product2Id);
			}
		}
		Map<Id, Subscription25__Administration__c> adminByAccount = Util_FinancialSystemWarehouse.getAdministrations(accountIds);
		Map<String, String> warehouses = Util_FinancialSystemWarehouse.getProductWarehouses(adminByAccount.values(), productIds);

		for (Order ord : orders) {
			Subscription25__Administration__c admin = adminByAccount.get(ord.AccountId);
			if (admin == null) {
				results.put(ord.Id, 'No administration: skipped.');
				continue;
			}
			// warehouse per product, in the order of the products
			Map<String, List<OrderItem>> linesByWarehouse = new Map<String, List<OrderItem>>();
			List<String> warehouseOrder = new List<String>();
			for (OrderItem oi : ord.OrderItems) {
				String wh = warehouses.get(Util_FinancialSystemWarehouse.key(admin.Id, oi.Product2Id));
				wh = String.isBlank(wh) ? '' : wh;
				if (!linesByWarehouse.containsKey(wh)) {
					linesByWarehouse.put(wh, new List<OrderItem>());
					warehouseOrder.add(wh);
				}
				linesByWarehouse.get(wh).add(oi);
			}
			// the order keeps its own warehouse when it has products of it, otherwise the warehouse of its first product;
			// products without a warehouse stay on the order
			String keep = String.isNotBlank(ord.FinancialSystemIdWarehouse__c) && linesByWarehouse.containsKey(ord.FinancialSystemIdWarehouse__c)
				? ord.FinancialSystemIdWarehouse__c : null;
			for (String wh : warehouseOrder) {
				if (keep == null && String.isNotBlank(wh)) {
					keep = wh;
				}
			}
			List<String> moveTo = new List<String>();
			for (String wh : warehouseOrder) {
				if (String.isNotBlank(wh) && wh != keep) {
					moveTo.add(wh);
				}
			}
			if (keep == ord.FinancialSystemIdWarehouse__c && moveTo.isEmpty()) {
				results.put(ord.Id, 'OK: one warehouse (' + keep + ').');
				continue;
			}

			Savepoint sp = Database.setSavepoint();
			try {
				Database.update(new Order(Id = ord.Id, FinancialSystemIdWarehouse__c = keep), AccessLevel.SYSTEM_MODE);
				List<String> created = new List<String>();
				if (!moveTo.isEmpty()) {
					List<Order> newOrders = new List<Order>();
					List<OrderItem> toDelete = new List<OrderItem>();
					for (String wh : moveTo) {
						Order copy = (Order) Util_FinancialSystemWarehouse.copy(ord, orderFields);
						copy.Status = 'Draft';
						copy.FinancialSystemIdWarehouse__c = wh;
						newOrders.add(copy);
						toDelete.addAll(linesByWarehouse.get(wh));
					}
					Database.insert(newOrders, AccessLevel.SYSTEM_MODE);
					// delete first: Partner_Code__c is unique and moves with the product
					Database.delete(toDelete, AccessLevel.SYSTEM_MODE);
					List<OrderItem> newLines = new List<OrderItem>();
					for (Integer i = 0; i < moveTo.size(); i++) {
						for (OrderItem oi : linesByWarehouse.get(moveTo[i])) {
							OrderItem copy = (OrderItem) Util_FinancialSystemWarehouse.copy(oi, lineFields);
							copy.OrderId = newOrders[i].Id;
							newLines.add(copy);
						}
						created.add(moveTo[i] + ': ' + newOrders[i].Id);
					}
					Database.insert(newLines, AccessLevel.SYSTEM_MODE);
				}
				results.put(ord.Id, 'Repaired: warehouse ' + keep + (created.isEmpty() ? '' : '; moved to ' + String.join(created, ', ')) + '.');
			} catch (Exception e) {
				Database.rollback(sp);
				results.put(ord.Id, 'Failed: ' + e.getMessage());
			}
		}
		return results;
	}

	// standard fields copied to the new order / order product (describe isCreateable() depends on the running user's
	// field permissions, so it is not used: the batch user may not see every field, the copy must be complete)
	private static final Map<Schema.SObjectType, List<String>> STANDARD_COPY_FIELDS = new Map<Schema.SObjectType, List<String>>{
		Order.SObjectType => new List<String>{ 'AccountId', 'BillToContactId', 'BillingCity', 'BillingCountryCode', 'BillingPostalCode', 'BillingStateCode',
			'BillingStreet', 'CompanyAuthorizedById', 'CompanyAuthorizedDate', 'ContractId', 'CurrencyIsoCode', 'CustomerAuthorizedById',
			'CustomerAuthorizedDate', 'Description', 'EffectiveDate', 'EndDate', 'Name', 'OpportunityId', 'OrderReferenceNumber', 'OwnerId', 'PoDate',
			'PoNumber', 'Pricebook2Id', 'QuoteId', 'ShipToContactId', 'ShippingCity', 'ShippingCountryCode', 'ShippingPostalCode', 'ShippingStateCode',
			'ShippingStreet', 'Type' },
		OrderItem.SObjectType => new List<String>{ 'Description', 'EndDate', 'PricebookEntryId', 'Product2Id', 'Quantity', 'QuoteLineItemId',
			'ServiceDate', 'UnitPrice' }
	};

	// fields to copy: the standard ones above + every writable custom field except unique / external ids
	// (Partner_Code__c is unique but moves with the order product)
	private static List<String> copyFields(Schema.SObjectType objType) {
		List<String> fields = new List<String>(STANDARD_COPY_FIELDS.get(objType));
		for (Schema.SObjectField f : objType.getDescribe().fields.getMap().values()) {
			Schema.DescribeFieldResult d = f.getDescribe();
			if (d.isCustom() && !d.isCalculated() && !d.isAutoNumber() && ((!d.isUnique() && !d.isExternalId()) || d.getName() == 'Partner_Code__c')) {
				fields.add(d.getName());
			}
		}
		return fields;
	}

	private static SObject copy(SObject source, List<String> fields) {
		SObject target = source.getSObjectType().newSObject();
		for (String f : fields) {
			if (source.get(f) != null) {
				target.put(f, source.get(f));
			}
		}
		return target;
	}
}
