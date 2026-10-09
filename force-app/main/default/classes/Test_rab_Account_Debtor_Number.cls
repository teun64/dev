/**
 * Tests the record-triggered flow rab_Account_Debtor_Number (one Subscription25 debtor number per account)
 * and the validation rule vr_FinancialDebtorNumberClear.
 */
@IsTest
private class Test_rab_Account_Debtor_Number {

	@TestSetup
	static void setup() {
		Test_Data.createAdministration(true); // External_ID__c = 1 (Netherlands)
		Subscription25__Administration__c adminUK = Test_Data.createAdministration(false);
		adminUK.Name = 'United Kingdom';
		adminUK.External_ID__c = 6;
		adminUK.Subscription25__Twinfield_Company_Code__c = '1234509877';
		adminUK.Reseller__c = '6';
		adminUK.Subscription25__Invoice_Number_Prefix__c = 'UKT';
		Database.insert(adminUK);
		Account acc = Test_Data.createAccount('Debtor Test', '12345', 'B2B', true);
		Contact con = Test_Data.createContact(acc.Id, 'Invoice', '0612345678', 'invoice@test.nl', true);
		AccountContactRelation acr = [SELECT Id FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :con.Id];
		Database.update(new AccountContactRelation(Id = acr.Id, Roles = 'Invoice', FinancialIdContact__c = 'contact-guid'), AccessLevel.SYSTEM_MODE);
	}

	static Account account() {
		return [SELECT Id FROM Account WHERE Name = 'Debtor Test' LIMIT 1];
	}

	static List<Subscription25__Debtor_Number__c> debtorNumbers(Id accId) {
		return [
			SELECT Subscription25__Administration__r.External_ID__c, Subscription25__Composite_Key__c, Subscription25__Debtor_Number__c,
				Exact_ID__c, Exact_Contact_ID__c, Exact_Invoice_Address_ID__c, Exact_Bank_Account_ID__c, Exact_Mandate_ID__c
			FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :accId WITH SYSTEM_MODE
		];
	}

	@IsTest
	static void debtorNumberSet_createsRecordWithExactIds() {
		Account acc = account();
		Test.startTest();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555', FinancialIdAccount__c = 'acc-guid',
			FinancialIdInvoiceAddress__c = 'inv-guid', FinancialIdBankAccount__c = 'bank-guid', FinancialIdBankMandate__c = 'mandate-guid'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		List<Subscription25__Debtor_Number__c> debNrs = debtorNumbers(acc.Id);
		System.assertEquals(1, debNrs.size());
		Subscription25__Debtor_Number__c debNr = debNrs[0];
		System.assertEquals('55555', debNr.Subscription25__Debtor_Number__c);
		System.assertEquals(1, debNr.Subscription25__Administration__r.External_ID__c);
		System.assert(debNr.Subscription25__Composite_Key__c.startsWith(String.valueOf(acc.Id)), debNr.Subscription25__Composite_Key__c);
		System.assertEquals('acc-guid', debNr.Exact_ID__c);
		System.assertEquals('contact-guid', debNr.Exact_Contact_ID__c, 'From the relation with the Invoice role');
		System.assertEquals('inv-guid', debNr.Exact_Invoice_Address_ID__c);
		System.assertEquals('bank-guid', debNr.Exact_Bank_Account_ID__c);
		System.assertEquals('mandate-guid', debNr.Exact_Mandate_ID__c);
	}

	@IsTest
	static void existingIds_keptUnlessAccountChanges() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555'), AccessLevel.SYSTEM_MODE);
		Subscription25__Debtor_Number__c debNr = [SELECT Id FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :acc.Id];
		Database.update(new Subscription25__Debtor_Number__c(Id = debNr.Id, Exact_ID__c = 'old-guid', Exact_Contact_ID__c = 'old-contact'), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		// number change only: the ids already on the debtor number stay
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55556'), AccessLevel.SYSTEM_MODE);
		System.assertEquals('old-guid', debtorNumbers(acc.Id)[0].Exact_ID__c);
		// an Exact id change alone does not run the flow
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'new-guid'), AccessLevel.SYSTEM_MODE);
		System.assertEquals('old-guid', debtorNumbers(acc.Id)[0].Exact_ID__c);
		// a new debtor number together with a new Exact account (new account in Exact): taken over, including the contact
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55557', FinancialIdAccount__c = 'newer-guid'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		Subscription25__Debtor_Number__c after = debtorNumbers(acc.Id)[0];
		System.assertEquals('55557', after.Subscription25__Debtor_Number__c);
		System.assertEquals('newer-guid', after.Exact_ID__c);
		System.assertEquals('contact-guid', after.Exact_Contact_ID__c);
	}

	@IsTest
	static void financialEntityChange_replacesRecord() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555'), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Database.update(new Account(Id = acc.Id, Reseller_Name__c = '6'), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		List<Subscription25__Debtor_Number__c> debNrs = debtorNumbers(acc.Id);
		System.assertEquals(1, debNrs.size(), 'Only one debtor number per account: the old administration is deleted');
		System.assertEquals(6, debNrs[0].Subscription25__Administration__r.External_ID__c);
	}

	@IsTest
	static void clearDebtorNumber_blockedWhileLinkedToExact() {
		Account acc = account();
		Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = '55555', FinancialIdAccount__c = 'acc-guid'), AccessLevel.SYSTEM_MODE);

		Database.SaveResult blocked = Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = null), false, AccessLevel.SYSTEM_MODE);
		System.assert(!blocked.isSuccess(), 'Clearing the number while linked to Exact is not allowed');

		Database.SaveResult allowed = Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = null, FinancialIdAccount__c = null), false, AccessLevel.SYSTEM_MODE);
		System.assert(allowed.isSuccess(), 'Clearing both together (Replace Debtor Number) is allowed');
	}
}
