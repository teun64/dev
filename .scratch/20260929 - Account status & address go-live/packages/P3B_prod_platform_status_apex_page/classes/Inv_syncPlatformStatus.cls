public without sharing class Inv_syncPlatformStatus {
	@InvocableMethod(label='syncPlatformStatus' description='Pushes the account status (statusId) to every enabled platform that has a platform id for the account' category='Platform')
	public static void syncPlatformStatus(List<Inv_syncPlatformStatus.Request> requestList) {
		Set<Id> accountIds = new Set<Id>();
		for (Inv_syncPlatformStatus.Request r : requestList) {
			accountIds.add(r.accountId);
		}
		Queue_PlatformStatusSync.enqueue(accountIds);
	}

	public class Request {
		@InvocableVariable(label='accountId' description='The account whose status changed' required=true)
		public Id accountId;
	}
}
