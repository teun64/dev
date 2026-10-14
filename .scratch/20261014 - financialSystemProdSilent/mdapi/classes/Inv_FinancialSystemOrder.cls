/**
 * Flow entry point for the order sync to the financial system.
 * Default: flag the orders for Batch_FinancialSystemOrderSync. syncNow = true: create them in Exact now
 * (callouts - not from a record-triggered flow).
 */
public without sharing class Inv_FinancialSystemOrder {
	public class Request {
		@InvocableVariable(label='Order Id' required=true)
		public Id orderId;
		@InvocableVariable(label='Sync now' description='true: sync immediately (not from a record-triggered flow); false/empty: flag for the batch')
		public Boolean syncNow;
	}

	public class Response {
		@InvocableVariable(label='Success')
		public Boolean success;
		@InvocableVariable(label='Message')
		public String message;
	}

	@InvocableMethod(label='Sync Order to Financial System' description='Flags the order for the financial system sync, or syncs it now' category='FinancialSystem')
	public static List<Response> syncOrders(List<Request> requests) {
		Set<Id> flagIds = new Set<Id>();
		Set<Id> nowIds = new Set<Id>();
		for (Request req : requests) {
			if (req.syncNow == true) {
				nowIds.add(req.orderId);
			} else {
				flagIds.add(req.orderId);
			}
		}
		if (!flagIds.isEmpty()) {
			Util_FinancialSystem_Order.flagOrders(flagIds);
		}
		Map<Id, Util_FinancialSystem_Order.Result> results = nowIds.isEmpty()
			? new Map<Id, Util_FinancialSystem_Order.Result>()
			: Util_FinancialSystem_Order.syncOrders(nowIds, false);
		List<Response> responses = new List<Response>();
		for (Request req : requests) {
			Response res = new Response();
			if (req.syncNow == true) {
				Util_FinancialSystem_Order.Result r = results.get(req.orderId);
				res.success = r != null && r.success;
				res.message = r == null ? 'Order not found.'
					: (r.success ? 'This order (' + req.orderId + ') is synced to the financial system.' : String.join(r.messages, '\n'));
			} else {
				res.success = true;
				res.message = 'The order is queued for the financial system and is created there within a few minutes.';
			}
			responses.add(res);
		}
		return responses;
	}
}
