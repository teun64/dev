/**
 * Status loop (Account.Status__c -> platforms): pushes the account (incl. statusId) to every platform that has a
 * platform id (extId_N__c) for the account and is enabled in Label.PlatformStatusSyncPlatforms (comma separated platform
 * numbers). The platform responds through Rest_UpsertAccount with its own status (extStatus_N__c).
 * Util_Platform.syncAccount does DML after its callout, so every job syncs one account/platform and chains the rest.
 */
public without sharing class Queue_PlatformStatusSync implements Queueable, Database.AllowsCallouts {
	@TestVisible
	private static Boolean runInTest = false;

	private List<Queue_PlatformStatusSync.Item> items;

	public class Item {
		public Id accountId;
		public String platformId;

		public Item(Id accountId, String platformId) {
			this.accountId = accountId;
			this.platformId = platformId;
		}
	}

	public Queue_PlatformStatusSync(List<Queue_PlatformStatusSync.Item> items) {
		this.items = items;
	}

	// platform numbers that receive the account status, e.g. '1' or '1,3'
	public static Set<String> getEnabledPlatforms() {
		Set<String> platforms = new Set<String>();
		for (String p : String.valueOf(System.Label.PlatformStatusSyncPlatforms).split(',')) {
			if (String.isNotBlank(p)) {
				platforms.add(p.trim());
			}
		}
		return platforms;
	}

	public static List<Queue_PlatformStatusSync.Item> buildItems(Set<Id> accountIds) {
		List<Queue_PlatformStatusSync.Item> items = new List<Queue_PlatformStatusSync.Item>();
		Set<String> enabled = Queue_PlatformStatusSync.getEnabledPlatforms();
		if (enabled.isEmpty() || (accountIds == null) || accountIds.isEmpty()) {
			return items;
		}
		for (Account acc : [
			SELECT Id, extId_1__c, extId_2__c, extId_3__c, extId_4__c, extId_5__c, extId_6__c
			FROM Account
			WHERE Id IN :accountIds
			WITH SYSTEM_MODE
		]) {
			for (Integer n = 1; n <= 6; n++) {
				String platformId = String.valueOf(n);
				if (enabled.contains(platformId) && String.isNotBlank((String) acc.get('extId_' + platformId + '__c'))) {
					items.add(new Queue_PlatformStatusSync.Item(acc.Id, platformId));
				}
			}
		}
		return items;
	}

	public static Id enqueue(Set<Id> accountIds) {
		List<Queue_PlatformStatusSync.Item> items = Queue_PlatformStatusSync.buildItems(accountIds);
		if (items.isEmpty() || (Test.isRunningTest() && !Queue_PlatformStatusSync.runInTest)) {
			return null;
		}
		if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
			System.debug(LoggingLevel.ERROR, 'Queue_PlatformStatusSync: queueable limit reached, status not pushed for ' + accountIds);
			return null;
		}
		return System.enqueueJob(new Queue_PlatformStatusSync(items));
	}

	public void execute(QueueableContext context) {
		if ((this.items == null) || this.items.isEmpty()) {
			return;
		}
		Queue_PlatformStatusSync.Item item = this.items.remove(0);
		try {
			// Util_Platform logs the result (Event_Log__c, action sync2Platform)
			Util_Platform.syncAccount(item.accountId, item.platformId);
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'Queue_PlatformStatusSync: ' + item.accountId + ' / platform ' + item.platformId + ': ' + e.getMessage());
		}
		if (!this.items.isEmpty() && !Test.isRunningTest()) {
			System.enqueueJob(new Queue_PlatformStatusSync(this.items));
		}
	}
}
