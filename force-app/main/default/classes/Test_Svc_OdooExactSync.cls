@isTest
private class Test_Svc_OdooExactSync {
	/** Exact as the service talks to it; numberAtEntry = the journal numbers when the invoice is entered (Import), else at printing. */
	private class Mock implements HttpCalloutMock {
		Boolean numberAtEntry = false;
		Boolean knownItems = true;
		Boolean alreadyPosted = false;
		Boolean printed = false;
		Integer posts = 0;
		Integer prints = 0;

		public HttpResponse respond(HttpRequest req) {
			String url = req.getEndpoint();
			String body = '{"d":{}}';
			if (url.contains('PrintedSalesInvoices')) {
				prints++;
				printed = true;
				body = '{"d":{"ID":"print"}}';
			} else if (url.contains('SalesInvoices') && req.getMethod() == 'POST') {
				posts++;
				body = '{"d":{"InvoiceID":"inv-1"' + (numberAtEntry ? ',"InvoiceNumber":5001' : '') + '}}';
			} else if (url.contains('SalesInvoices')) {
				Boolean byOdoo = url.contains('YourRef');
				String nr = (numberAtEntry || printed) ? '"InvoiceNumber":5001,' : '';
				body = (byOdoo && !alreadyPosted) ? '{"d":{"results":[]}}' : '{"d":{"results":[{' + nr + '"InvoiceID":"inv-1","Status":' + (printed ? 50 : 10) + '}]}}';
			} else if (url.contains('Journals')) {
				body = '{"d":{"results":[{"Code":"70"}]}}';
			} else if (url.contains('Items')) {
				body = knownItems ? '{"d":{"results":[{"Code":"FMC880NL","ID":"item-1"}]}}' : '{"d":{"results":[]}}';
			}
			HttpResponse res = new HttpResponse();
			res.setStatusCode(req.getMethod() == 'POST' ? 201 : 200);
			res.setBody(body);
			return res;
		}
	}

	private static Id invoice(String method, Boolean sandboxAdmin) {
		Subscription25__Administration__c admin = Test_Data.createAdministration(false);
		admin.Acceptance_Environment_Available__c = sandboxAdmin;
		Database.insert(admin);
		List<Business_Entities__c> bes = [SELECT Id FROM Business_Entities__c WHERE Reseller__c = '1' LIMIT 1];
		Business_Entities__c be = bes.isEmpty() ? new Business_Entities__c(Name = 'NL test', Reseller__c = '1') : bes[0];
		be.FinSysInvoiceNumberMethod__c = method;
		Database.upsert(be);
		Account acc = Test_Data.createAccount('Odoo Exact', '9990100', 'B2B', true);
		Database.update(new Account(Id = acc.Id, FinancialIdAccount__c = 'acc-guid'), false);
		Test_Data.createDebtorNumber(admin.Id, acc.Id, true);
		Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
		inv.Subscription25__External_ID__c = 'ODOO-01250436';
		Database.insert(inv);
		Product2 prod = Test_Data.createProduct('FMC880NL', 'FMC880NL', 'EXT100', 'SubscriptionP', true);
		Subscription25__VATRate__c vat = Test_Data.createVATRate('NL 21', 21, true, true);
		Test_Data.createAdministrationProduct(admin.Id, prod.Id, vat.Id, true);
		PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 10, true);
		Order ord = Test_Data.createOrder(acc.Id, admin.Id, Date.today(), false);
		ord.Subscription25__Invoice__c = inv.Id;
		Database.insert(ord);
		Test_Data.createOrderItem(ord.Id, pbe.Id, 10, true);
		return inv.Id;
	}

	private static Subscription25__Invoice__c reload(Id id) {
		return [SELECT FinSysInvoiceId__c, FinSysInvoiceNumber__c, Subscription25__Finalized_In_Exact__c, Subscription25__Invoice_Number__c, FinSysNextAttempt__c FROM Subscription25__Invoice__c WHERE Id = :id];
	}

	@isTest
	static void importMethodTakesTheNumberAtEntryWithoutPrinting() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Mock mock = new Mock();
		mock.numberAtEntry = true;
		Test.setMock(HttpCalloutMock.class, mock);

		Test.startTest();
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Test.stopTest();

		Assert.isTrue(res.success, res.message);
		Assert.areEqual(1, mock.posts);
		Assert.areEqual(0, mock.prints, 'numbered at entry: nothing to print');
		Subscription25__Invoice__c inv = reload(invId);
		Assert.areEqual('inv-1', inv.FinSysInvoiceId__c);
		Assert.areEqual('5001', inv.FinSysInvoiceNumber__c);
		Assert.isFalse(inv.Subscription25__Finalized_In_Exact__c);
		Assert.isTrue(res.message.contains('Odoo number 01250436'), res.message);
	}

	@isTest
	static void printMethodPrintsWithoutSendingAndReadsTheNumberBack() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_PRINT, true);
		Mock mock = new Mock();
		Test.setMock(HttpCalloutMock.class, mock);

		Test.startTest();
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Test.stopTest();

		Assert.isTrue(res.success, res.message);
		Assert.areEqual(1, mock.prints);
		Subscription25__Invoice__c inv = reload(invId);
		Assert.areEqual('5001', inv.FinSysInvoiceNumber__c, 'read back after printing');
		Assert.isTrue(inv.Subscription25__Finalized_In_Exact__c);
		Assert.isNull(inv.Subscription25__Invoice_Number__c, 'the Salesforce invoice number is not touched here');
	}

	@isTest
	static void aSecondRunDoesNotPostAgain() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Mock mock = new Mock();
		mock.numberAtEntry = true;
		Test.setMock(HttpCalloutMock.class, mock);
		Test.startTest();
		Svc_OdooExactSync.sync(invId);
		Svc_OdooExactSync.Result again = Svc_OdooExactSync.sync(invId);
		Assert.isTrue(again.skipped);
		Assert.areEqual(1, mock.posts);
	}

	@isTest
	static void anInvoiceAlreadyInExactIsFoundNotPostedTwice() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Mock mock = new Mock();
		mock.numberAtEntry = true;
		mock.alreadyPosted = true;
		Test.setMock(HttpCalloutMock.class, mock);
		Test.startTest();
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Assert.isTrue(res.success, res.message);
		Assert.areEqual(0, mock.posts, 'found by its Odoo reference');
		Assert.areEqual('inv-1', reload(invId).FinSysInvoiceId__c);
	}

	@isTest
	static void aMissingItemStopsTheSyncAndBacksOff() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Mock mock = new Mock();
		mock.knownItems = false;
		Test.setMock(HttpCalloutMock.class, mock);
		Test.startTest();
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Assert.isFalse(res.success);
		Assert.isTrue(res.message.contains('No Exact item'), res.message);
		Assert.areEqual(0, mock.posts);
		Assert.isNotNull(reload(invId).FinSysNextAttempt__c, 'retried tomorrow');
	}

	@isTest
	static void noNumberMethodStopsTheSync() {
		Id invId = invoice(null, true);
		Test.setMock(HttpCalloutMock.class, new Mock());
		Test.startTest();
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Assert.isFalse(res.success);
		Assert.isTrue(res.message.contains('no invoice number method'), res.message);
	}

	@isTest
	static void aSandboxWithoutAcceptanceEnvironmentIsBlocked() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, false);
		Mock mock = new Mock();
		Test.setMock(HttpCalloutMock.class, mock);
		Test.startTest();
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Assert.isFalse(res.success);
		Assert.isTrue(res.message.contains('blocked'), res.message);
		Assert.areEqual(0, mock.posts);
	}

	@isTest
	static void onlyOdooInvoicesAreHandled() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Database.update(new Subscription25__Invoice__c(Id = invId, Subscription25__External_ID__c = 'OTHER-1'));
		Svc_OdooExactSync.Result res = Svc_OdooExactSync.sync(invId);
		Assert.isFalse(res.success);
		Assert.areEqual('Not an Odoo invoice', res.message);
	}

	@isTest
	static void batchBooksTheCandidate() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Mock mock = new Mock();
		mock.numberAtEntry = true;
		Test.setMock(HttpCalloutMock.class, mock);
		Test.startTest();
		Batch_OdooExactSync batch = new Batch_OdooExactSync();
		batch.setDispatcher(null);
		Assert.areEqual(1, batch.getBatchSize());
		batch.executeBatch(null, new List<SObject>{ new Subscription25__Invoice__c(Id = invId) });
		Test.stopTest();
		Assert.areEqual('inv-1', reload(invId).FinSysInvoiceId__c);
	}

	@isTest
	static void batchStartsForOdooInvoicesOnly() {
		Id invId = invoice(Svc_OdooExactSync.METHOD_IMPORT, true);
		Database.QueryLocator ql = Svc_OdooExactSync.candidates();
		Assert.isNotNull(ql);
		Assert.isNotNull(new Batch_OdooExactSync().startBatch(null));
	}
}
