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

	private static Boolean flaggedAfter(Account change) {
		Database.update(change, AccessLevel.SYSTEM_MODE);
		return [SELECT SyncToFinancialSystem__c FROM Account WHERE Id = :change.Id WITH SYSTEM_MODE].SyncToFinancialSystem__c;
	}

	@IsTest
	static void rbbAccount_newAccountInSalesforce_staysManual() {
		Account acc = Test_Data.createAccount('Manual New', (String) null, 'B2B', false);
		acc.Reseller_Name__c = '1';
		acc.Payment_Method_Contracts__c = '08';
		Test.startTest();
		Database.insert(acc, AccessLevel.SYSTEM_MODE);
		Test.stopTest();
		System.assertEquals(false, [SELECT SyncToFinancialSystem__c FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE].SyncToFinancialSystem__c,
			'Only new accounts from the platforms (miAPIIntegration) sync automatically');
	}

	@IsTest
	static void rbbAccount_accountNotInExact_changesStayManual() {
		Account acc = Test_Util_FinancialSystemAccount.account();
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = null, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Boolean flagged = flaggedAfter(new Account(Id = acc.Id, Bank_Account_Number__c = 'NL91ABNA0417164300', BillingCity = 'Elders'));
		Test.stopTest();
		System.assertEquals(false, flagged, 'Not in Exact: manual');
	}

	@IsTest
	static void rbbAccount_invoiceAndShippingAddress_onlyWhenDifferentAddressIsUsed() {
		Account acc = Test_Util_FinancialSystemAccount.account();
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'acc-guid-flow', useInvoiceAddress__c = false, useShippingAddress__c = false),
			AccessLevel.SYSTEM_MODE);
		// switching the "different address" checkboxes is itself a change that syncs: start clean
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		Test.startTest();
		System.assertEquals(false, flaggedAfter(new Account(Id = acc.Id, InvoiceAddress__Street__s = 'Factuurweg 9', InvoiceAddress__City__s = 'Plaats')), 'Invoice address not in use');
		System.assertEquals(false, flaggedAfter(new Account(Id = acc.Id, ShippingStreet = 'Leverweg 3')), 'Delivery address not in use');
		System.assertEquals(true, flaggedAfter(new Account(Id = acc.Id, useInvoiceAddress__c = true)), 'Different invoice address switched on');
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		System.assertEquals(true, flaggedAfter(new Account(Id = acc.Id, InvoiceAddress__City__s = 'Elders')), 'Invoice address in use and changed');
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		Database.update(new Account(Id = acc.Id, SyncToFinancialSystem__c = false), AccessLevel.SYSTEM_MODE);
		System.assertEquals(true, flaggedAfter(new Account(Id = acc.Id, Billing_Email__c = 'nieuw@sync.test')), 'Exact account email');
		Test.stopTest();
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
