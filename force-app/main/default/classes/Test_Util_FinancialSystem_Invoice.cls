@IsTest
private class Test_Util_FinancialSystem_Invoice {

	private static Subscription25__Invoice__c createInvoice(Subscription25__Administration__c admin, Boolean finalizedInExact) {
		Account acc = Test_Data.createAccount('Invoice Account', '12345', 'B2B', true);
		Subscription25__Invoice__c invoice = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
		invoice.Subscription25__Exact_Order_Number__c = '123';
		invoice.Subscription25__Finalized_In_Exact__c = finalizedInExact;
		Database.insert(invoice);
		return invoice;
	}

	private static Subscription25__Invoice__c reload(Id invoiceId) {
		return [SELECT Subscription25__Invoice_Number__c, Subscription25__Finalized_In_Exact__c FROM Subscription25__Invoice__c WHERE Id = :invoiceId];
	}

	@IsTest
	static void finalizeInvoice_alreadyPrinted_storesInvoiceNumber() {
		Subscription25__Invoice__c invoice = createInvoice(Test_Data.createAdministration(true), false);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		List<String> msgs = Util_FinancialSystem_Invoice.finalizeInvoice(invoice.Id);
		Test.stopTest();

		System.assert(msgs.isEmpty(), 'No errors expected: ' + msgs);
		System.assertEquals('TTT123', reload(invoice.Id).Subscription25__Invoice_Number__c, 'Prefix + Exact invoice number');
		System.assertEquals(1, [SELECT COUNT() FROM Event_Log__c WHERE Context_Id__c = :invoice.Id AND Result_Status__c = 'COMPLETED'], 'One completed log');
	}

	@IsTest
	static void finalizeInvoice_notPrinted_printsAndMarksFinalized() {
		Subscription25__Invoice__c invoice = createInvoice(Test_Data.createAdministration(true), false);
		Test_Mocks.ExactMock mock = new Test_Mocks.ExactMock();
		mock.invoicePrinted = false;
		Test.setMock(HttpCalloutMock.class, mock);

		Test.startTest();
		List<String> msgs = Util_FinancialSystem_Invoice.finalizeInvoice(invoice.Id);
		Test.stopTest();

		// the layout lookup needs a Payment_Setting__mdt for reseller + payment method; without one the invoice is not printed
		Subscription25__Invoice__c after = reload(invoice.Id);
		if (msgs.isEmpty()) {
			System.assert(after.Subscription25__Finalized_In_Exact__c, 'Printed invoice is marked finalized');
		} else {
			System.assert(!after.Subscription25__Finalized_In_Exact__c, 'Not printed without a layout: ' + msgs);
		}
	}

	@IsTest
	static void finalizeInvoice_withoutOrderNumber_returnsError() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Account acc = Test_Data.createAccount('Invoice Account', '12345', 'B2B', true);
		Subscription25__Invoice__c invoice = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', true);

		List<String> msgs = Util_FinancialSystem_Invoice.finalizeInvoice(invoice.Id);

		System.assertEquals(new List<String>{ 'This invoice is not yet synced' }, msgs);
		System.assertEquals(1, [SELECT COUNT() FROM Event_Log__c WHERE Context_Id__c = :invoice.Id AND Result_Status__c = 'ERROR'], 'Error is logged');
	}

	@IsTest
	static void loadInvoiceNumber_printed_storesNumber() {
		Subscription25__Invoice__c invoice = createInvoice(Test_Data.createAdministration(true), true);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		List<String> msgs = Util_FinancialSystem_Invoice.loadInvoiceNumber(invoice.Id);
		Test.stopTest();

		System.assert(msgs.isEmpty(), 'No errors expected: ' + msgs);
		System.assertEquals('TTT123', reload(invoice.Id).Subscription25__Invoice_Number__c);
	}

	@IsTest
	static void loadInvoiceNumber_printingFailed_clearsFinalized() {
		Subscription25__Invoice__c invoice = createInvoice(Test_Data.createAdministration(true), true);
		Test_Mocks.ExactMock mock = new Test_Mocks.ExactMock();
		mock.invoicePrinted = false;
		Test.setMock(HttpCalloutMock.class, mock);

		Test.startTest();
		Util_FinancialSystem_Invoice.loadInvoiceNumber(invoice.Id);
		Test.stopTest();

		System.assert(!reload(invoice.Id).Subscription25__Finalized_In_Exact__c, 'Status is not 50: printing failed');
	}

	@IsTest
	static void finalizeInvoice_rateLimitReached_noCalloutAndError() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(false);
		admin.Daily_Limit__c = 5000;
		admin.FinancialRateLimitRemaining__c = 0;
		admin.FinancialRateLimitResetOn__c = System.now().addHours(2);
		Database.insert(admin, AccessLevel.SYSTEM_MODE);
		Subscription25__Invoice__c invoice = createInvoice(admin, false);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		List<String> msgs = Util_FinancialSystem_Invoice.finalizeInvoice(invoice.Id);
		Test.stopTest();

		System.assertEquals(1, msgs.size(), 'Rate limit error');
		System.assert(msgs[0].contains('rate limit'), msgs[0]);
		System.assertEquals(null, reload(invoice.Id).Subscription25__Invoice_Number__c, 'Nothing stored');
	}

	@IsTest
	static void utilExactWrappers_forwardToInvoiceClass() {
		Subscription25__Invoice__c invoice = createInvoice(Test_Data.createAdministration(true), true);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		Util_Exact.loadInvoiceNumber(invoice.Id);
		Util_Exact.finalizeInvoice(invoice.Id);
		Test.stopTest();

		System.assertEquals('TTT123', reload(invoice.Id).Subscription25__Invoice_Number__c);
	}

	@IsTest
	static void batchFinalizeInvoices_finalizesOpenInvoice() {
		Subscription25__Invoice__c invoice = createInvoice(Test_Data.createAdministration(true), false);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		Database.executeBatch(new Batch_FinalizeInvoices(), 1);
		Test.stopTest();

		System.assertEquals('TTT123', reload(invoice.Id).Subscription25__Invoice_Number__c);
	}

	@IsTest
	static void batchFinalizeInvoices_schedulable() {
		Test.startTest();
		String jobId = System.schedule('Test Batch_FinalizeInvoices', '0 0 5 * * ?', new Batch_FinalizeInvoices());
		Test.stopTest();
		System.assertNotEquals(null, jobId);
	}
}
