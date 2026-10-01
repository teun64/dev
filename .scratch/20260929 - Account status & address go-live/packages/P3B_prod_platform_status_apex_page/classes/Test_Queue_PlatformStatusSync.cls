@isTest
private class Test_Queue_PlatformStatusSync {
	private static Account createAccount(String extId1, String extId3) {
		Account acc = Test_Data.createAccount('Status Loop', (String) null, 'B2B', true);
		Database.update(new Account(Id = acc.Id, extId_1__c = extId1, extId_3__c = extId3), AccessLevel.SYSTEM_MODE);
		return acc;
	}

	@isTest
	private static void testBuildItemsOnlyEnabledPlatformsWithId() {
		Account acc = createAccount('sl1', 'sl3');
		Account noId = createAccount(null, null);
		Set<String> enabled = Queue_PlatformStatusSync.getEnabledPlatforms();

		Test.startTest();
		List<Queue_PlatformStatusSync.Item> items = Queue_PlatformStatusSync.buildItems(new Set<Id>{ acc.Id, noId.Id });
		Test.stopTest();

		Integer expected = (enabled.contains('1') ? 1 : 0) + (enabled.contains('3') ? 1 : 0);
		System.assertEquals(expected, items.size(), 'one item per enabled platform that has a platform id');
		for (Queue_PlatformStatusSync.Item item : items) {
			System.assertEquals(acc.Id, item.accountId, 'accounts without platform id are skipped');
		}
		System.assertEquals(0, Queue_PlatformStatusSync.buildItems(new Set<Id>()).size());
	}

	@isTest
	private static void testStatusChangePushesToPlatform() {
		Account acc = createAccount('sl1', null);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.PlatformMock());
		Queue_PlatformStatusSync.runInTest = true;

		Test.startTest();
		Id jobId = Queue_PlatformStatusSync.enqueue(new Set<Id>{ acc.Id });
		Test.stopTest();

		if (Queue_PlatformStatusSync.getEnabledPlatforms().contains('1')) {
			System.assertNotEquals(null, jobId, 'job enqueued for platform 1');
			System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE Id = :jobId].Status);
		} else {
			System.assertEquals(null, jobId, 'platform 1 not enabled');
		}
	}

	@isTest
	private static void testInvocable() {
		Account acc = createAccount('sl1', null);
		Inv_syncPlatformStatus.Request r = new Inv_syncPlatformStatus.Request();
		r.accountId = acc.Id;

		Test.startTest();
		Inv_syncPlatformStatus.syncPlatformStatus(new List<Inv_syncPlatformStatus.Request>{ r });
		Test.stopTest();

		System.assertEquals(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'Queue_PlatformStatusSync'], 'no callouts in other tests unless runInTest is set');
	}

	@isTest
	private static void testExecuteWithoutItems() {
		Test.startTest();
		System.enqueueJob(new Queue_PlatformStatusSync(new List<Queue_PlatformStatusSync.Item>()));
		Test.stopTest();
		System.assert(true);
	}
}
