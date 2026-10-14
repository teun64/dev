@IsTest
private class Test_FinancialSystemFlows {
	// Financial-system behaviour of the flows rab_Account_Debtor_Number, rbb_Account and rbb_AccountContactRelation
	// and the validation rule vr_FinancialDebtorNumberClear. Deployed when those go live in prod (go-live), not with
	// the packages that precede them.

	@TestSetup
	static void setup() {
		Test_Util_FinancialSystemAccount.setup();
	}

	@IsTest
	static void debtorNumber_changeOnAccount_upsertsRecord() {
		Account acc = Test_Util_FinancialSystemAccount.account();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555'), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55556'), AccessLevel.SYSTEM_MODE);
		List<Subscription25__Debtor_Number__c> debNrs = [SELECT Subscription25__Debtor_Number__c FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :acc.Id WITH SYSTEM_MODE];
		System.assertEquals(1, debNrs.size(), 'One record per account + administration');
		System.assertEquals('55556', debNrs[0].Subscription25__Debtor_Number__c);
	}

	@IsTest
	static void rbbAccount_nameChangeOnSyncedAccount_setsFlag() {
		Account acc = Test_Util_FinancialSystemAccount.account();
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'acc-guid-flow', SyncToFinancialSystem__c = false, FinancialSyncAttempts__c = 3), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Database.update(new Account(Id = acc.Id, Name = 'Sync Account Renamed'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		Account after = Test_Util_FinancialSystemAccount.account();
		System.assertEquals(true, after.SyncToFinancialSystem__c, 'rbb_Account flags the name change');
		System.assertEquals(0, after.FinancialSyncAttempts__c, 'Back-off reset by a new change');
	}

	@IsTest
	static void rbbRelation_roleChangeOfExactContact_setsFlag() {
		Contact second = Test_Util_FinancialSystemAccount.syncedAccountWithSecondContact();
		AccountContactRelation acr = Test_Util_FinancialSystemAccount.relation(second.Id);
		Database.update(new AccountContactRelation(Id = acr.Id, FinancialIdContact__c = 'con-guid-second', Roles = 'Digital', Sync_To_Financial_System__c = false), AccessLevel.SYSTEM_MODE);
		Database.update(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = false), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Database.update(new AccountContactRelation(Id = acr.Id, Roles = null), AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		System.assertEquals(true, Test_Util_FinancialSystemAccount.relation(second.Id).Sync_To_Financial_System__c, 'rbb_AccountContactRelation flags the role change');
	}

	@IsTest
	static void clearDebtorNumber_blockedWhileLinkedToExact() {
		Account acc = Test_Util_FinancialSystemAccount.account();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555', FinancialIdAccount__c = 'acc-guid'), AccessLevel.SYSTEM_MODE);

		Database.SaveResult blocked = Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = null), false, AccessLevel.SYSTEM_MODE);
		System.assert(!blocked.isSuccess(), 'Clearing the number while linked to Exact is not allowed');

		Database.SaveResult allowed = Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = null, FinancialIdAccount__c = null), false, AccessLevel.SYSTEM_MODE);
		System.assert(allowed.isSuccess(), 'Clearing both together (Replace Debtor Number) is allowed');
	}
}
