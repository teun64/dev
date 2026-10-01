@IsTest
private class Test_Util_FinancialSystem {

	/** Mock that answers with a fixed status/body and Exact rate-limit headers. */
	private class LimitMock implements HttpCalloutMock {
		private Integer status;
		private String body;
		private Integer dailyLimit;
		private Integer dailyRemaining;
		public Integer calls = 0;
		LimitMock(Integer status, String body, Integer dailyLimit, Integer dailyRemaining) {
			this.status = status;
			this.body = body;
			this.dailyLimit = dailyLimit;
			this.dailyRemaining = dailyRemaining;
		}
		public HttpResponse respond(HttpRequest req) {
			this.calls++;
			HttpResponse res = new HttpResponse();
			res.setStatusCode(this.status);
			res.setBody(this.body);
			res.setHeader('X-RateLimit-Limit', String.valueOf(this.dailyLimit));
			res.setHeader('X-RateLimit-Remaining', String.valueOf(this.dailyRemaining));
			res.setHeader('X-RateLimit-Reset', String.valueOf(System.now().addHours(6).getTime()));
			res.setHeader('X-RateLimit-Minutely-Remaining', '59');
			res.setHeader('X-RateLimit-Minutely-Reset', String.valueOf(System.now().addSeconds(30).getTime()));
			return res;
		}
	}

	private static Subscription25__Administration__c admin() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(false);
		admin.Subscription25__Synchronisation__c = 'Exact';
		Database.insert(admin, AccessLevel.SYSTEM_MODE);
		return [
			SELECT Id, Name, Subscription25__Active__c, Subscription25__Synchronisation__c, Subscription25__Named_Credential__c,
				Acceptance_Environment_Available__c, Daily_Limit__c, FinancialRateLimitMaxPercentage__c,
				FinancialRateLimitRemaining__c, FinancialRateLimitResetOn__c, FinancialRateLimitCheckedOn__c
			FROM Subscription25__Administration__c WHERE Id = :admin.Id WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void doRequest_success_returnsPayloadAndTracksLimits() {
		Subscription25__Administration__c adm = admin();
		Test.setMock(HttpCalloutMock.class, new LimitMock(200, '{"d":{"ID":"abc","Modified":"x"}}', 5000, 4321));

		Test.startTest();
		String response = Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'GET', null, null);
		Util_FinancialSystem.saveLimits();
		Test.stopTest();

		Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(response);
		System.assertEquals('abc', d.get('ID'));
		System.assert(!d.containsKey('Modified'), 'Fields that break deserialization are stripped');
		Subscription25__Administration__c after = [SELECT Daily_Limit__c, FinancialRateLimitRemaining__c, FinancialRateLimitResetOn__c, FinancialRateLimitCheckedOn__c FROM Subscription25__Administration__c WHERE Id = :adm.Id WITH SYSTEM_MODE];
		System.assertEquals(5000, after.Daily_Limit__c);
		System.assertEquals(4321, after.FinancialRateLimitRemaining__c);
		System.assertNotEquals(null, after.FinancialRateLimitResetOn__c);
		System.assertNotEquals(null, after.FinancialRateLimitCheckedOn__c);
	}

	@IsTest
	static void doRequest_noContent_returnsEmpty() {
		Subscription25__Administration__c adm = admin();
		Test.setMock(HttpCalloutMock.class, new LimitMock(204, '', 5000, 4000));
		Test.startTest();
		System.assertEquals('', Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'PUT', '{}', null));
		Test.stopTest();
	}

	@IsTest
	static void doRequest_exactError_throwsWithMessage() {
		Subscription25__Administration__c adm = admin();
		Test.setMock(HttpCalloutMock.class, new LimitMock(400, '{"error":{"code":"","message":{"lang":"","value":"Invalid VAT"}}}', 5000, 4000));
		Test.startTest();
		try {
			Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'POST', '{}', null);
			System.assert(false, 'Exception expected');
		} catch (Util_System.FinancialSyncException e) {
			System.assertEquals('Invalid VAT', e.getMessage());
		}
	}

	@IsTest
	static void doRequest_httpErrorWithoutJson_throws() {
		Subscription25__Administration__c adm = admin();
		Test.setMock(HttpCalloutMock.class, new LimitMock(502, '<html>Bad gateway</html>', 5000, 4000));
		Test.startTest();
		try {
			Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'GET', null, null);
			System.assert(false, 'Exception expected');
		} catch (Util_System.FinancialSyncException e) {
			System.assert(e.getMessage().contains('502'), e.getMessage());
		}
	}

	@IsTest
	static void doRequest_429_throwsRateLimitAndBlocksNextCall() {
		Subscription25__Administration__c adm = admin();
		LimitMock mock = new LimitMock(429, '', 5000, 0);
		Test.setMock(HttpCalloutMock.class, mock);
		Test.startTest();
		try {
			Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'GET', null, null);
			System.assert(false, 'Exception expected');
		} catch (Util_FinancialSystem.RateLimitException e) {
			System.assert(Util_FinancialSystem.getLimits(adm).limited);
		}
		try {
			Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'GET', null, null);
			System.assert(false, 'Exception expected');
		} catch (Util_FinancialSystem.RateLimitException e) {
			System.assertEquals(1, mock.calls, 'No second callout while limited');
		}
	}

	@IsTest
	static void doRequest_notAllowedFromSandbox_throwsWithoutCallout() {
		Subscription25__Administration__c adm = admin();
		adm.Acceptance_Environment_Available__c = false;
		LimitMock mock = new LimitMock(200, '{"d":{}}', 5000, 4000);
		Test.setMock(HttpCalloutMock.class, mock);
		if (!Util_System.isSandbox()) {
			System.assertEquals(true, Util_System.isFinancialSyncAllowed(adm), 'Production is always allowed');
			return;
		}
		try {
			Util_FinancialSystem.doRequest(adm, 'api/v1/1/crm/Accounts', null, 'GET', null, null);
			System.assert(false, 'Exception expected');
		} catch (Util_System.FinancialSyncException e) {
			System.assertEquals(0, mock.calls, 'Guard stops the callout');
		}
		System.assertEquals(false, Util_FinancialSystem.isSyncEnabled(adm));
	}

	@IsTest
	static void limits_batchCapacity_respectsMaxPercentage() {
		Subscription25__Administration__c adm = admin();
		adm.Daily_Limit__c = 1000;
		adm.FinancialRateLimitRemaining__c = 150; // 850 used
		adm.FinancialRateLimitResetOn__c = System.now().addHours(3);
		adm.FinancialRateLimitMaxPercentage__c = 90; // 900 allowed
		Util_FinancialSystem.Limits lim = new Util_FinancialSystem.Limits(adm);

		System.assertEquals(true, lim.hasBatchCapacity(50), '850 + 50 = 900 fits');
		System.assertEquals(false, lim.hasBatchCapacity(51), '850 + 51 > 900');
		System.assertEquals(true, lim.hasCapacity(150), 'Hard limit: 150 remaining');
		System.assertEquals(false, lim.hasCapacity(151));
		System.assertEquals(85.0, lim.usedPercentage());
	}

	@IsTest
	static void limits_expiredStoredValues_areIgnored() {
		Subscription25__Administration__c adm = admin();
		adm.Daily_Limit__c = 1000;
		adm.FinancialRateLimitRemaining__c = 0;
		adm.FinancialRateLimitResetOn__c = System.now().addMinutes(-1);
		Util_FinancialSystem.Limits lim = new Util_FinancialSystem.Limits(adm);
		System.assertEquals(true, lim.hasBatchCapacity(10), 'After the reset the stored remaining no longer counts');
		System.assertEquals(Util_FinancialSystem.DEFAULT_MAX_PERCENTAGE, new Util_FinancialSystem.Limits(new Subscription25__Administration__c()).maxPercentage);
	}

	@IsTest
	static void odataString_escapesAndNormalises() {
		System.assertEquals(EncodingUtil.urlEncode('O\'\'Brien BV', 'UTF-8'), Util_FinancialSystem.odataString('  O\'Brien\t BV* '));
		System.assertEquals(null, Util_FinancialSystem.odataString(null));
	}

	@IsTest
	static void getAdministrationForReseller_blank_returnsNull() {
		System.assertEquals(null, Util_FinancialSystem.getAdministrationForReseller(null));
	}

	@IsTest
	static void rateLimitCheck_storesLimitsAndWarnsAboveMaximum() {
		Subscription25__Administration__c adm = admin();
		// previous state: 95% used, above the 90% maximum
		Database.update(new Subscription25__Administration__c(Id = adm.Id, Daily_Limit__c = 1000, FinancialRateLimitRemaining__c = 50,
			FinancialRateLimitResetOn__c = System.now().addHours(1), FinancialRateLimitMaxPercentage__c = 90), AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new LimitMock(200, '{"d":{"results":[{"CurrentDivision":1}]}}', 5000, 4990));

		Test.startTest();
		Batch_FinancialSystemRateLimitCheck.check(new Set<Id>{ adm.Id });
		Test.stopTest();

		Subscription25__Administration__c after = [SELECT Daily_Limit__c, FinancialRateLimitRemaining__c FROM Subscription25__Administration__c WHERE Id = :adm.Id WITH SYSTEM_MODE];
		System.assertEquals(5000, after.Daily_Limit__c);
		System.assertEquals(4990, after.FinancialRateLimitRemaining__c);
		Event_Log__c log = [SELECT Result_Status__c, Message__c FROM Event_Log__c WHERE Action__c = 'RateLimitCheck'];
		System.assertEquals('WARNING', log.Result_Status__c, log.Message__c);
	}

	@IsTest
	static void rateLimitCheck_batchRuns() {
		Subscription25__Administration__c adm = admin();
		Database.insert(new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemRateLimitCheck', Subscription25__Unique_Name__c = 'Batch_FinancialSystemRateLimitCheck'), AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new LimitMock(200, '{"d":{"results":[]}}', 5000, 4999));

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemRateLimitCheck());
		Test.stopTest();

		System.assertEquals(4999, [SELECT FinancialRateLimitRemaining__c FROM Subscription25__Administration__c WHERE Id = :adm.Id WITH SYSTEM_MODE].FinancialRateLimitRemaining__c);
	}
}
