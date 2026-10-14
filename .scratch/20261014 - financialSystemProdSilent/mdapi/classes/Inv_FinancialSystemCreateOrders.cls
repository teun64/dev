/**
 * Creates the order(s) of an opportunity from afl_Opportuntity_Create_Order: one Order per financial system
 * warehouse, because Exact allows one warehouse per sales order (1 Salesforce Order = 1 Exact sales order).
 * Warehouse of a product: the Administration Product warehouse, otherwise the administration default
 * (Util_FinancialSystemWarehouse); only the order stores it. Products without a warehouse (administration without
 * warehouses) go together in one order, as before. The orders are flagged for the financial system sync
 * (SyncToFinancialSystem__c): the job dispatcher sends them to Exact.
 * All or nothing: on any failure everything is rolled back and the error goes to the flow's fault path.
 */
public without sharing class Inv_FinancialSystemCreateOrders {
	public class Request {
		@InvocableVariable(label='Order' description='Order to create (not inserted): copied to every warehouse order' required=true)
		public Order order;
		@InvocableVariable(label='Order Products' description='Order products to create (not inserted, no OrderId)' required=true)
		public List<OrderItem> orderItems;
	}

	public class Response {
		@InvocableVariable(label='Main Order Id' description='The order of the first order product')
		public String orderId;
		@InvocableVariable(label='Order Ids')
		public List<String> orderIds;
		@InvocableVariable(label='Message')
		public String message;
	}

	@InvocableMethod(label='Create Orders per Warehouse' description='Creates one order per financial system warehouse with its order products' category='FinancialSystem')
	public static List<Response> createOrders(List<Request> requests) {
		List<Response> responses = new List<Response>();
		for (Request req : requests) {
			responses.add(Inv_FinancialSystemCreateOrders.createOrders(req.order, req.orderItems));
		}
		return responses;
	}

	private static Response createOrders(Order template, List<OrderItem> lines) {
		if (template == null || lines == null || lines.isEmpty()) {
			throw new Util_System.CustomException('No order or order products to create.');
		}
		Response existing = Inv_FinancialSystemCreateOrders.existingOrders(template);
		if (existing != null) {
			return existing;
		}
		Subscription25__Administration__c admin = Util_FinancialSystemWarehouse.getAdministrations(new Set<Id>{ template.AccountId }).get(template.AccountId);
		Map<String, String> warehouses = new Map<String, String>();
		if (admin != null) {
			Set<Id> productIds = new Set<Id>();
			for (OrderItem oi : lines) {
				if (oi.Product2Id != null) {
					productIds.add(oi.Product2Id);
				}
			}
			warehouses = Util_FinancialSystemWarehouse.getProductWarehouses(new List<Subscription25__Administration__c>{ admin }, productIds);
		}

		// group the lines per warehouse, in the order of the lines
		Map<String, List<OrderItem>> linesByWarehouse = new Map<String, List<OrderItem>>();
		List<String> warehouseOrder = new List<String>();
		for (OrderItem oi : lines) {
			String warehouse = admin != null && oi.Product2Id != null ? warehouses.get(Util_FinancialSystemWarehouse.key(admin.Id, oi.Product2Id)) : null;
			warehouse = String.isBlank(warehouse) ? '' : warehouse;
			if (!linesByWarehouse.containsKey(warehouse)) {
				linesByWarehouse.put(warehouse, new List<OrderItem>());
				warehouseOrder.add(warehouse);
			}
			linesByWarehouse.get(warehouse).add(oi);
		}

		Savepoint sp = Database.setSavepoint();
		try {
			List<Order> orders = new List<Order>();
			for (String warehouse : warehouseOrder) {
				Order ord = template.clone(false, true, false, false);
				ord.FinancialSystemIdWarehouse__c = String.isBlank(warehouse) ? null : warehouse;
				// sent to the financial system by the job dispatcher (Minut order sync step), as Util_FinancialSystem_Order.flagOrders
				ord.SyncToFinancialSystem__c = true;
				ord.FinancialSyncAttempts__c = 0;
				orders.add(ord);
			}
			Database.insert(orders, AccessLevel.SYSTEM_MODE);

			List<OrderItem> toInsert = new List<OrderItem>();
			for (Integer i = 0; i < warehouseOrder.size(); i++) {
				for (OrderItem oi : linesByWarehouse.get(warehouseOrder[i])) {
					oi.OrderId = orders[i].Id;
					toInsert.add(oi);
				}
			}
			Database.insert(toInsert, AccessLevel.SYSTEM_MODE);

			// as before: set the product names on the created order products
			List<OrderItem> toUpdate = new List<OrderItem>();
			for (OrderItem oi : toInsert) {
				toUpdate.add(new OrderItem(Id = oi.Id, setProductName__c = true));
			}
			Database.update(toUpdate, AccessLevel.SYSTEM_MODE);

			Response res = new Response();
			res.orderId = orders[0].Id;
			res.orderIds = new List<String>();
			for (Order ord : orders) {
				res.orderIds.add(ord.Id);
			}
			res.message = orders.size() == 1 ? 'Order created.' : orders.size() + ' orders created (one per warehouse).';
			return res;
		} catch (Exception e) {
			Database.rollback(sp);
			throw new Util_System.CustomException(e.getMessage());
		}
	}

	/**
	 * Duplicate guard: rau_Opportunity can publish Create_Order twice for one Closed Won (a second save in the same
	 * transaction), and the two runs come in parallel. The opportunity lock makes the second run wait for the first
	 * to commit; it then finds the orders and creates nothing.
	 */
	@TestVisible
	private static Response existingOrders(Order template) {
		if (template.OpportunityId == null) {
			return null;
		}
		List<Opportunity> locked = [SELECT Id FROM Opportunity WHERE Id = :template.OpportunityId WITH SYSTEM_MODE FOR UPDATE];
		List<Order> orders = [
			SELECT Id FROM Order WHERE OpportunityId = :template.OpportunityId AND Type = :template.Type
			WITH SYSTEM_MODE ORDER BY CreatedDate, OrderNumber
		];
		if (locked.isEmpty() || orders.isEmpty()) {
			return null;
		}
		Response res = new Response();
		res.orderId = orders[0].Id;
		res.orderIds = new List<String>();
		for (Order ord : orders) {
			res.orderIds.add(ord.Id);
		}
		res.message = 'Orders already created for this opportunity (' + orders.size() + '); nothing created.';
		return res;
	}
}
