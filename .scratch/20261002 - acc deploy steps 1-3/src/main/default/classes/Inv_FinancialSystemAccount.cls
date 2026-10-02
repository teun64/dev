/**
 * Flow entry point for the account sync to the financial system.
 * Default: flag the accounts for Batch_FinancialSystemAccountSync (safe in record-triggered flows).
 * syncNow = true: sync immediately (callouts) - only from a screen flow, button or other async context.
 */
public without sharing class Inv_FinancialSystemAccount {
	public class Request {
		@InvocableVariable(label='Account Id' required=true)
		public Id accountId;
		@InvocableVariable(label='Sync now' description='true: sync immediately (not from a record-triggered flow); false/empty: flag for the batch')
		public Boolean syncNow;
	}

	public class Response {
		@InvocableVariable(label='Success')
		public Boolean success;
		@InvocableVariable(label='Message')
		public String message;
	}

	@InvocableMethod(label='Sync Account to Financial System' description='Flags the account for the financial system sync, or syncs it now' category='FinancialSystem')
	public static List<Response> syncAccounts(List<Request> requests) {
		Set<Id> flagIds = new Set<Id>();
		Set<Id> nowIds = new Set<Id>();
		for (Request req : requests) {
			if (req.syncNow == true) {
				nowIds.add(req.accountId);
			} else {
				flagIds.add(req.accountId);
			}
		}
		if (!flagIds.isEmpty()) {
			Util_FinancialSystemAccount.flagAccounts(flagIds);
		}
		Map<Id, Util_FinancialSystemAccount.Result> results = nowIds.isEmpty()
			? new Map<Id, Util_FinancialSystemAccount.Result>()
			: Util_FinancialSystemAccount.syncAccounts(nowIds, false);

		List<Response> responses = new List<Response>();
		for (Request req : requests) {
			Response res = new Response();
			if (req.syncNow == true) {
				Util_FinancialSystemAccount.Result r = results.get(req.accountId);
				res.success = r != null && r.success;
				res.message = r == null ? 'Account not found.'
					: (r.success ? 'This account (' + req.accountId + ') is synced to the financial system.' : String.join(r.messages, '\n'));
			} else {
				res.success = true;
				res.message = 'The account is queued for the financial system sync.';
			}
			responses.add(res);
		}
		return responses;
	}
}
