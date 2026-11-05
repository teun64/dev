@IsTest
private class Test_Batch_FinancialSystemInvoiceIds {

	// Exact: Test_Mocks.ExactMock (InvoiceID "invoice_sync", InvoiceNumber "123", status 50).
	// Stripe: Svc_PaymentIntent.mockResponses (stripeGC itself can't be mocked).

	@TestSetup
	static void makeData() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Account acc = Test_Data.createAccount('Invoice Ids BV', '9061', 'B2B', false);
		insert acc;
		// rbb_Account wipes PayProv_* ids on a brand-new Account - set them with a separate update
		acc.PayProv_CustomerId__c = 'cus_ids001';
		acc.FinancialIdAccount__c = 'acc-guid';
		update acc;

		Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
		inv.Payment_Method__c = 'pr';
		inv.Subscription25__Exact_Order_Number__c = '123';
		inv.Subscription25__Invoice_Number__c = 'TTT123';
		Database.insert(inv, AccessLevel.SYSTEM_MODE);

		Database.insert(new Payment__c(
			Account__c                 = acc.Id,
			Administration__c          = admin.Id,
			Invoice__c                 = inv.Id,
			Type__c                    = 'psp-recurring',
			Status__c                  = 'Processing',
			CurrencyIsoCode            = 'EUR',
			Amount_Gross__c            = 13.50,
			Request_Date__c            = Date.today()
		), AccessLevel.SYSTEM_MODE);

		Database.insert(new Subscription25__Schedulable_Class__c(
			Name = 'Batch_FinancialSystemInvoiceIds',
			Subscription25__Unique_Name__c = 'Batch_FinancialSystemInvoiceIds'
		), AccessLevel.SYSTEM_MODE);
	}

	private static Subscription25__Invoice__c reload() {
		return [SELECT Id, FinSysInvoiceId__c, FinSysInvoiceNumber__c, FinSysNextAttempt__c, Subscription25__Invoice_Number__c
			FROM Subscription25__Invoice__c LIMIT 1];
	}

	private static void setIntent(String intentId) {
		Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
		p.PayProv_PaymentIntentId__c = intentId;
		Database.update(p, AccessLevel.SYSTEM_MODE);
	}

	@IsTest
	static void process_printedInvoice_storesIdsAndUpdatesStripe() {
		setIntent('pi_ids001');
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
		Svc_PaymentIntent.mockResponses = new List<String>{ '{"id":"cus_ids001"}', '{"id":"pi_ids001"}' };
		Id invoiceId = reload().Id;

		Test.startTest();
		Batch_FinancialSystemInvoiceIds.process(new Set<Id>{ invoiceId });
		Test.stopTest();

		Subscription25__Invoice__c inv = reload();
		System.assertEquals('invoice_sync', inv.FinSysInvoiceId__c, 'Exact InvoiceID stored');
		System.assertEquals('123', inv.FinSysInvoiceNumber__c, 'Raw Exact number, without the TTT prefix');
		System.assertEquals('TTT123', inv.Subscription25__Invoice_Number__c, 'Salesforce number unchanged');
		System.assertEquals(null, inv.FinSysNextAttempt__c);

		System.assertEquals(2, Svc_PaymentIntent.sentBodies.size(), 'Customer + PaymentIntent: ' + Svc_PaymentIntent.sentBodies);
		System.assert(Svc_PaymentIntent.sentBodies[0].startsWith('POST /v1/customers/cus_ids001 metadata[FinSysAccountId]=acc-guid'), Svc_PaymentIntent.sentBodies[0]);
		String pi = Svc_PaymentIntent.sentBodies[1];
		System.assert(pi.startsWith('POST /v1/payment_intents/pi_ids001 '), pi);
		System.assert(pi.contains('metadata[FinSysInvoiceId]=invoice_sync') && pi.contains('metadata[FinSysInvoiceNumber]=123')
			&& pi.contains('description=Invoice+TTT123'), pi);
	}

	@IsTest
	static void process_withoutIntent_onlyCustomerUpdated() {
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
		Svc_PaymentIntent.mockResponses = new List<String>{ '{"id":"cus_ids001"}' };

		Test.startTest();
		Batch_FinancialSystemInvoiceIds.process(new Set<Id>{ reload().Id });
		Test.stopTest();

		System.assertEquals('invoice_sync', reload().FinSysInvoiceId__c);
		System.assertEquals(1, Svc_PaymentIntent.sentBodies.size(), 'No PaymentIntent yet: only the Customer');
	}

	@IsTest
	static void process_stripeFails_idsStoredAnyway() {
		setIntent('pi_ids001');
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
		Svc_PaymentIntent.mockResponses = new List<String>{
			'{"error":{"message":"No such customer"}}',
			'{"error":{"message":"No such payment_intent"}}'
		};

		Test.startTest();
		Batch_FinancialSystemInvoiceIds.process(new Set<Id>{ reload().Id });
		Test.stopTest();

		System.assertEquals('invoice_sync', reload().FinSysInvoiceId__c, 'Stripe errors never block storing the ids');
	}

	@IsTest
	static void process_notFoundInExact_backsOff() {
		Test_Mocks.ExactMock mock = new Test_Mocks.ExactMock();
		mock.invoicePrinted = false;
		Test.setMock(HttpCalloutMock.class, mock);

		Test.startTest();
		Batch_FinancialSystemInvoiceIds.process(new Set<Id>{ reload().Id });
		Test.stopTest();

		Subscription25__Invoice__c inv = reload();
		System.assertEquals(null, inv.FinSysInvoiceId__c);
		System.assert(inv.FinSysNextAttempt__c > System.now(), 'Back-off set');
		System.assertEquals(0, Svc_PaymentIntent.sentBodies.size(), 'Nothing sent to Stripe');
		System.assertEquals(1, [SELECT COUNT() FROM Event_Log__c WHERE Context_Id__c = :inv.Id AND Result_Status__c = 'ERROR'], 'Failure logged');
	}

	@IsTest
	static void batch_selectsOnlyOpenPiPrInvoices() {
		Subscription25__Invoice__c inv = [SELECT Subscription25__Administration__c, Subscription25__Account__c FROM Subscription25__Invoice__c LIMIT 1];
		Subscription25__Invoice__c wire = Test_Data.createInvoice(inv.Subscription25__Administration__c, inv.Subscription25__Account__c, 'DRAFT', false);
		wire.Payment_Method__c = 'I8';
		wire.Subscription25__Exact_Order_Number__c = '124';
		wire.Subscription25__Invoice_Number__c = 'TTT124';
		Database.insert(wire, AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());
		Svc_PaymentIntent.mockResponses = new List<String>{ '{"id":"cus_ids001"}' };

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemInvoiceIds(), 20);
		Test.stopTest();

		System.assertEquals(1, [SELECT COUNT() FROM Subscription25__Invoice__c WHERE FinSysInvoiceId__c != null], 'Only the pr invoice');
		System.assertEquals(null, [SELECT FinSysInvoiceId__c FROM Subscription25__Invoice__c WHERE Id = :wire.Id].FinSysInvoiceId__c, 'I8 is out of scope');
	}

	@IsTest
	static void process_otherInvoiceInExact_backsOff() {
		Subscription25__Invoice__c inv = reload();
		inv.Subscription25__Invoice_Number__c = 'TTT999';
		Database.update(inv, AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new Test_Mocks.ExactMock());

		Test.startTest();
		Batch_FinancialSystemInvoiceIds.process(new Set<Id>{ inv.Id });
		Test.stopTest();

		inv = reload();
		System.assertEquals(null, inv.FinSysInvoiceId__c, 'Exact returned invoice 123 for this order, not 999: not stored');
		System.assert(inv.FinSysNextAttempt__c > System.now(), 'Back-off set');
		System.assertEquals(0, Svc_PaymentIntent.sentBodies.size(), 'Nothing sent to Stripe');
	}
}
