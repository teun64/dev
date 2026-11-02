@IsTest
private class Test_Util_FinancialSystemStripePosting {

	// Stripe: Svc_PaymentIntent.mockResponses (stripeGC itself can't be mocked). Exact: ExactPostingMock below.
	// Payout po_X: pi_A € 500.00 (fee 1.35, Salesforce payment with an Exact invoice), pi_unknown € 400.00 (fee 1.50,
	// no Salesforce payment), a Stripe fee of € 2.00 → payout 500 - 1.35 + 400 - 1.50 - 2.00 = € 895.15.

	private class ExactPostingMock implements HttpCalloutMock {
		Integer journalType = 90;
		Boolean existingEntry = false;
		Boolean failPost = false;
		List<String> posted = new List<String>();

		public HttpResponse respond(HttpRequest req) {
			String ep = req.getEndpoint();
			HttpResponse res = new HttpResponse();
			res.setStatusCode(200);
			if (ep.contains('/financial/Journals')) {
				res.setBody('{"d":{"results":[{"Code":"26","Type":' + journalType + '}]}}');
			} else if (ep.contains('/financial/GLAccounts')) {
				res.setBody('{"d":{"results":[{"ID":"gl-fee","Code":"470710"},{"ID":"gl-transit","Code":"100099"},{"ID":"gl-suspense","Code":"210000"}]}}');
			} else if (ep.contains('TransactionLines')) {
				res.setBody(existingEntry ? '{"d":{"results":[{"EntryID":"entry-old","EntryNumber":26000007}]}}' : '{"d":{"results":[]}}');
			} else if (req.getMethod() == 'POST' && failPost) {
				res.setStatusCode(400);
				res.setBody('{"error":{"code":"","message":{"lang":"","value":"Period is closed"}}}');
			} else if (req.getMethod() == 'POST') {
				posted.add(req.getBody());
				res.setStatusCode(201);
				res.setBody('{"d":{"EntryID":"entry-new","EntryNumber":26000001}}');
			} else {
				res.setBody('{"d":{"results":[]}}');
			}
			return res;
		}
	}

	@TestSetup
	static void makeData() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		stripeGC__Stripe_Account__c sa = new stripeGC__Stripe_Account__c(Name = 'Test Stripe');
		Database.insert(sa, AccessLevel.SYSTEM_MODE);
		// the Stripe account belongs on the Administration: Sync_Administration_to_Business_Entity copies it to the
		// Business Entity on every Administration save (e.g. the rate limit update after a run)
		admin.PayProv_Account__c = sa.Id;
		Database.update(admin, AccessLevel.SYSTEM_MODE);
		// that flow may already have made the reseller's Business Entity: configure that one
		List<Business_Entities__c> existing = [SELECT Id FROM Business_Entities__c WHERE Reseller__c = '1' LIMIT 1];
		Business_Entities__c be = existing.isEmpty() ? new Business_Entities__c(Name = 'Netherlands (test)', Reseller__c = '1') : existing[0];
		be.PayProv_Account__c = sa.Id;
		be.FinSysStripeJournalCode__c = '26';
		be.FinSysStripeFeeGLCode__c = '470710';
		be.FinSysStripeTransitGLCode__c = '100099';
		be.FinSysStripeSuspenseGLCode__c = '210000';
		be.FinSysStripePostingFrom__c = Date.newInstance(2026, 11, 1);
		Database.upsert(be, AccessLevel.SYSTEM_MODE);

		Account acc = Test_Data.createAccount('Stripe Posting BV', '9071', 'B2B', false);
		insert acc;
		acc.FinancialIdAccount__c = 'acc-guid';
		update acc;
		Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', false);
		inv.Subscription25__Invoice_Number__c = 'TTT26100042';
		inv.FinSysInvoiceNumber__c = '26100042';
		Database.insert(inv, AccessLevel.SYSTEM_MODE);
		Database.insert(new Payment__c(
			Account__c = acc.Id, Administration__c = admin.Id, Invoice__c = inv.Id, Type__c = 'psp-recurring',
			Status__c = 'Paid', CurrencyIsoCode = 'EUR', Amount_Gross__c = 500, Request_Date__c = Date.today(),
			PayProv_PaymentIntentId__c = 'pi_A'
		), AccessLevel.SYSTEM_MODE);
		Database.insert(new Subscription25__Schedulable_Class__c(
			Name = 'Batch_FinancialSystemStripePostings', Subscription25__Unique_Name__c = 'Batch_FinancialSystemStripePostings'
		), AccessLevel.SYSTEM_MODE);
	}

	private static Id businessEntityId() {
		return [SELECT Id FROM Business_Entities__c WHERE FinSysStripeJournalCode__c != null LIMIT 1].Id;
	}

	private static List<String> stripePayoutX() {
		return new List<String>{
			'{"data":[{"id":"po_X","amount":89515,"currency":"eur","arrival_date":1762128000,"status":"paid"}],"has_more":false}',
			'{"data":['
				+ '{"id":"txn_1","type":"charge","amount":50000,"fee":135,"net":49865,"source":{"id":"py_1","object":"charge","payment_intent":"pi_A"}},'
				+ '{"id":"txn_2","type":"charge","amount":40000,"fee":150,"net":39850,"source":{"id":"py_2","object":"charge","payment_intent":"pi_unknown"}},'
				+ '{"id":"txn_3","type":"stripe_fee","amount":-200,"fee":0,"net":-200,"source":null},'
				+ '{"id":"txn_4","type":"payout","amount":-89515,"fee":0,"net":-89515,"source":"po_X"}'
				+ '],"has_more":false}'
		};
	}

	private static String logs() {
		List<String> logs = new List<String>();
		for (Event_Log__c l : [SELECT Result_Status__c, Message__c FROM Event_Log__c WHERE Action__c = 'postStripePayouts' ORDER BY CreatedDate]) logs.add(l.Result_Status__c + ': ' + l.Message__c);
		return String.join(logs, ' || ');
	}

	private static FinSysPosting__c posting() {
		List<FinSysPosting__c> found = [SELECT Id, Status__c, StripePayoutId__c, Amount__c, GrossAmount__c, FeeAmount__c, SuspenseAmount__c, ArrivalDate__c,
			FinSysEntryNumber__c, Attempts__c, NextAttempt__c, LastError__c,
			(SELECT StripeBalanceTransactionId__c, Booking__c, Payment__c, Invoice__c, FinSysInvoiceNumber__c, Amount__c, SuspenseReason__c FROM Lines__r ORDER BY StripeBalanceTransactionId__c)
			FROM FinSysPosting__c WHERE StripePayoutId__c = 'po_X'];
		if (found.isEmpty()) {
			List<String> logs = new List<String>();
			for (Event_Log__c l : [SELECT Result_Status__c, Message__c FROM Event_Log__c WHERE Action__c = 'postStripePayouts']) logs.add(l.Result_Status__c + ': ' + l.Message__c);
			System.assert(false, 'No posting for po_X; logs: ' + logs);
		}
		return found[0];
	}

	private static List<Object> postedLines(ExactPostingMock mock, String key) {
		Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.posted[0]);
		System.assertEquals('26', body.get('JournalCode'));
		System.assertEquals('EUR', body.get('Currency'));
		return (List<Object>) body.get(key);
	}

	private static Map<String, Object> line(List<Object> lines, Integer i) {
		return (Map<String, Object>) lines[i];
	}

	@IsTest
	static void generalJournal_postsOneBalancedEntryPerPayout() {
		ExactPostingMock mock = new ExactPostingMock();
		Test.setMock(HttpCalloutMock.class, mock);
		Svc_PaymentIntent.mockResponses = stripePayoutX();

		Test.startTest();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		Test.stopTest();

		FinSysPosting__c p = posting();
		System.assertEquals('Posted', p.Status__c, 'Error: ' + p.LastError__c);
		System.assertEquals('26000001', p.FinSysEntryNumber__c);
		System.assertEquals(895.15, p.Amount__c);
		System.assertEquals(900.00, p.GrossAmount__c, 'Customer payments only');
		System.assertEquals(4.85, p.FeeAmount__c, 'Fees 1.35 + 1.50 + the 2.00 Stripe fee');
		System.assertEquals(400.00, p.SuspenseAmount__c, 'pi_unknown has no Salesforce payment');
		System.assertEquals(Date.newInstance(2025, 11, 3), p.ArrivalDate__c);
		System.assertEquals(3, p.Lines__r.size(), 'The payout movement itself is not a line');
		System.assertEquals('Invoice', p.Lines__r[0].Booking__c);
		System.assertEquals('26100042', p.Lines__r[0].FinSysInvoiceNumber__c);
		System.assertNotEquals(null, p.Lines__r[0].Payment__c);
		System.assertEquals('Suspense', p.Lines__r[1].Booking__c);
		System.assert(p.Lines__r[1].SuspenseReason__c.contains('pi_unknown'), p.Lines__r[1].SuspenseReason__c);
		System.assertEquals('Fee', p.Lines__r[2].Booking__c);

		List<Object> lines = postedLines(mock, 'GeneralJournalEntryLines');
		System.assertEquals(4, lines.size(), 'Debtor, suspense, fees, transit');
		System.assertEquals('acc-guid', line(lines, 0).get('Account'));
		System.assertEquals(26100042, line(lines, 0).get('OurRef'), 'Raw Exact invoice number closes the invoice');
		System.assertEquals(-500.00, Decimal.valueOf(String.valueOf(line(lines, 0).get('AmountFC'))), 'Gross amount credits the debtor');
		System.assertEquals('gl-suspense', line(lines, 1).get('GLAccount'));
		System.assertEquals(-400.00, Decimal.valueOf(String.valueOf(line(lines, 1).get('AmountFC'))));
		System.assertEquals('gl-fee', line(lines, 2).get('GLAccount'));
		System.assertEquals(4.85, Decimal.valueOf(String.valueOf(line(lines, 2).get('AmountFC'))));
		System.assertEquals('gl-transit', line(lines, 3).get('GLAccount'));
		System.assertEquals(895.15, Decimal.valueOf(String.valueOf(line(lines, 3).get('AmountFC'))));
		System.assertEquals('Stripe payout po_X', line(lines, 3).get('Description'));
		Decimal total = 0;
		for (Object o : lines) total += Decimal.valueOf(String.valueOf(((Map<String, Object>) o).get('AmountFC')));
		System.assertEquals(0, total, 'Entry balances');
	}

	@IsTest
	static void bankJournal_amountsAreMoneyIntoTheBank() {
		ExactPostingMock mock = new ExactPostingMock();
		mock.journalType = 12;
		Test.setMock(HttpCalloutMock.class, mock);
		Svc_PaymentIntent.mockResponses = stripePayoutX();

		Test.startTest();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		Test.stopTest();

		System.assertEquals('Posted', posting().Status__c, 'Error: ' + posting().LastError__c);
		List<Object> lines = postedLines(mock, 'BankEntryLines');
		System.assertEquals(500.00, Decimal.valueOf(String.valueOf(line(lines, 0).get('AmountFC'))), 'Payment = money in');
		System.assertEquals(-4.85, Decimal.valueOf(String.valueOf(line(lines, 2).get('AmountFC'))), 'Fees = money out');
		System.assertEquals(-895.15, Decimal.valueOf(String.valueOf(line(lines, 3).get('AmountFC'))), 'Payout = money out');
	}

	@IsTest
	static void alreadyInExact_adoptedNotPostedAgain() {
		ExactPostingMock mock = new ExactPostingMock();
		mock.existingEntry = true;
		Test.setMock(HttpCalloutMock.class, mock);
		Svc_PaymentIntent.mockResponses = stripePayoutX();

		Test.startTest();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		Test.stopTest();

		FinSysPosting__c p = posting();
		System.assertEquals('Posted', p.Status__c);
		System.assertEquals('26000007', p.FinSysEntryNumber__c, 'The entry Exact already has');
		System.assertEquals(0, mock.posted.size(), 'Never posted twice');
	}

	@IsTest
	static void exactRejects_failedThenRetriedFromStoredLines() {
		ExactPostingMock mock = new ExactPostingMock();
		mock.failPost = true;
		Test.setMock(HttpCalloutMock.class, mock);
		Svc_PaymentIntent.mockResponses = stripePayoutX();
		Util_FinancialSystemStripePosting.run(businessEntityId());

		FinSysPosting__c p = posting();
		System.assertEquals('Failed', p.Status__c);
		System.assertEquals(1, p.Attempts__c);
		System.assert(p.LastError__c.contains('Period is closed'), p.LastError__c);
		System.assertEquals(3, p.Lines__r.size(), 'Lines kept for the retry');
		System.assertEquals(1, [SELECT COUNT() FROM Event_Log__c WHERE Action__c = 'postStripePayouts' AND Result_Status__c = 'ERROR']);

		p.NextAttempt__c = System.now().addMinutes(-1);
		Database.update(p, AccessLevel.SYSTEM_MODE);
		mock.failPost = false;
		// the retry needs no Stripe call for the stored payout; the payout list is empty now
		Svc_PaymentIntent.mockResponses = new List<String>{ '{"data":[],"has_more":false}' };

		Test.startTest();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		Test.stopTest();

		System.assertEquals('Posted', posting().Status__c, posting().LastError__c + ' / ' + logs());
		System.assertEquals(4, postedLines(mock, 'GeneralJournalEntryLines').size());
	}

	@IsTest
	static void alreadyPosted_skipped() {
		ExactPostingMock mock = new ExactPostingMock();
		Test.setMock(HttpCalloutMock.class, mock);
		Svc_PaymentIntent.mockResponses = stripePayoutX();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		System.assertEquals(1, mock.posted.size());

		Svc_PaymentIntent.mockResponses = new List<String>{ stripePayoutX()[0] };
		Svc_PaymentIntent.sentBodies.clear();
		Test.startTest();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		Test.stopTest();

		System.assertEquals(1, mock.posted.size(), 'po_X not posted again');
		System.assertEquals(1, Svc_PaymentIntent.sentBodies.size(), 'Only the payout list, no balance transactions: ' + logs());
	}

	@IsTest
	static void payoutDoesNotAddUp_failedWithoutLines() {
		ExactPostingMock mock = new ExactPostingMock();
		Test.setMock(HttpCalloutMock.class, mock);
		List<String> responses = stripePayoutX();
		responses[0] = responses[0].replace('89515', '89999');
		Svc_PaymentIntent.mockResponses = responses;

		Test.startTest();
		Util_FinancialSystemStripePosting.run(businessEntityId());
		Test.stopTest();

		FinSysPosting__c p = [SELECT Status__c, LastError__c, (SELECT Id FROM Lines__r) FROM FinSysPosting__c WHERE StripePayoutId__c = 'po_X'];
		System.assertEquals('Failed', p.Status__c);
		System.assert(p.LastError__c.contains('does not add up'), p.LastError__c);
		System.assertEquals(0, p.Lines__r.size(), 'Rebuilt from Stripe on the retry');
		System.assertEquals(0, mock.posted.size());
	}

	@IsTest
	static void missingSettings_loggedNothingPosted() {
		Business_Entities__c be = [SELECT Id FROM Business_Entities__c WHERE FinSysStripeJournalCode__c != null LIMIT 1];
		be.FinSysStripeFeeGLCode__c = null;
		Database.update(be, AccessLevel.SYSTEM_MODE);
		ExactPostingMock mock = new ExactPostingMock();
		Test.setMock(HttpCalloutMock.class, mock);

		Test.startTest();
		Util_FinancialSystemStripePosting.run(be.Id);
		Test.stopTest();

		System.assertEquals(0, [SELECT COUNT() FROM FinSysPosting__c]);
		Event_Log__c log = [SELECT Result_Status__c, Message__c FROM Event_Log__c WHERE Action__c = 'postStripePayouts'];
		System.assertEquals('ERROR', log.Result_Status__c);
		System.assert(log.Message__c.contains('fee G/L code'), log.Message__c);
	}

	@IsTest
	static void batch_runsPerBusinessEntity() {
		ExactPostingMock mock = new ExactPostingMock();
		Test.setMock(HttpCalloutMock.class, mock);
		Svc_PaymentIntent.mockResponses = stripePayoutX();

		Test.startTest();
		Database.executeBatch(new Batch_FinancialSystemStripePostings(), 1);
		Test.stopTest();

		System.assertEquals('Posted', posting().Status__c, 'Error: ' + posting().LastError__c);
	}

	@IsTest
	static void sharedStripeAccount_postedOnceByLowestReseller() {
		Business_Entities__c nl = [SELECT Id, PayProv_Account__c FROM Business_Entities__c WHERE FinSysStripeJournalCode__c != null LIMIT 1];
		Business_Entities__c be3 = new Business_Entities__c(Name = 'Belgium (test)', Reseller__c = '3', PayProv_Account__c = nl.PayProv_Account__c,
			FinSysStripeJournalCode__c = '26', FinSysStripeFeeGLCode__c = '470710', FinSysStripeTransitGLCode__c = '100099',
			FinSysStripeSuspenseGLCode__c = '210000', FinSysStripePostingFrom__c = Date.newInstance(2026, 11, 1));
		Database.insert(be3, AccessLevel.SYSTEM_MODE);
		Test.setMock(HttpCalloutMock.class, new ExactPostingMock());

		Test.startTest();
		Util_FinancialSystemStripePosting.run(be3.Id);
		Test.stopTest();

		System.assertEquals(0, [SELECT COUNT() FROM FinSysPosting__c]);
		System.assert(logs().contains('already posted by'), logs());
	}
}
