@isTest
private class Test_Svc_OdooInvoiceIntake {
	private static final String SENDER = 'invoicing@echoes.solutions';

	@TestSetup
	static void makeData() {
		List<Subscription25__VATRate__c> rates = new List<Subscription25__VATRate__c>{
			Test_Data.createVATRate('FR - VAT high rate', 20, true, false),
			Test_Data.createVATRate('EUR - Sell within the EU', 0, false, false),
			Test_Data.createVATRate('EUR - Sell outside the EU', 0, false, false),
			Test_Data.createVATRate('EUR - No VAT', 0, false, false),
			Test_Data.createVATRate('NL - VAT high rate', 21, false, false)
		};
		Database.insert(rates, AccessLevel.SYSTEM_MODE);

		Subscription25__Administration__c admin = Test_Data.createAdministration(false);
		admin.Name = 'France (echoes)';
		admin.Reseller__c = '4';
		admin.External_ID__c = 4;
		admin.Subscription25__Billing_Country__c = 'FR';
		admin.Subscription25__Invoice_Number_Prefix__c = 'FR';
		admin.Subscription25__Synchronisation__c = null; // Echoes FR: no Exact
		admin.Subscription25__Named_Credential__c = null;
		admin.Subscription25__Twinfield_Company_Code__c = '4444409876';
		Subscription25__Administration__c adminNl = Test_Data.createAdministration(false); // reseller 1, synced with Exact
		adminNl.Name = 'Netherlands';
		Database.insert(new List<Subscription25__Administration__c>{ admin, adminNl }, AccessLevel.SYSTEM_MODE);

		Database.insert(new Subscription25__Schedulable_Class__c(
			Name = 'Batch_OdooInvoiceIntake',
			Subscription25__Unique_Name__c = 'Batch_OdooInvoiceIntake'
		), AccessLevel.SYSTEM_MODE);
	}

	/** Email-to-Case shape: case New + incoming e-mail + the Odoo PDF (Factur-X embedded) and a CSV as attachments. */
	private static EmailMessage createOdooEmail(String subject, String invoiceNumber, Blob pdf) {
		Case c = new Case(Subject = subject, Status = 'New', Origin = 'Email', SuppliedEmail = SENDER);
		Database.insert(c, AccessLevel.SYSTEM_MODE);
		EmailMessage em = new EmailMessage(ParentId = c.Id, Incoming = true, FromAddress = SENDER, ToAddress = SENDER,
			Subject = subject, TextBody = 'Here is your invoice', MessageDate = Datetime.newInstance(2026, 10, 1, 9, 0, 0));
		Database.insert(em, AccessLevel.SYSTEM_MODE);
		Database.insert(new List<ContentVersion>{
			new ContentVersion(Title = invoiceNumber, PathOnClient = invoiceNumber + '.pdf', VersionData = pdf, FirstPublishLocationId = em.Id),
			new ContentVersion(Title = 'vehicles', PathOnClient = 'vehicles.csv', VersionData = Blob.valueOf('a;b'), FirstPublishLocationId = em.Id)
		}, AccessLevel.SYSTEM_MODE);
		return em;
	}

	private static Blob pdf(String invoiceNumber, String email) {
		return Test_Svc_FacturX.samplePdf(Test_Svc_FacturX.sampleXml(invoiceNumber, '380', 'ACTION AUTOMOBILE', 'FR19483161238', email));
	}

	@isTest
	static void processesOdooInvoice() {
		EmailMessage em = createOdooEmail('Echoes Facture (Réf 02256232)', '02256232', pdf('02256232', 'mark.rice@example.com'));

		Test.startTest();
		List<Svc_OdooInvoiceIntake.Result> results = Svc_OdooInvoiceIntake.process(new Set<Id>{ em.Id });
		Test.stopTest();

		Assert.areEqual(1, results.size());
		Assert.areEqual('PROCESSED', results[0].status, results[0].message);

		Subscription25__Invoice__c inv = [
			SELECT Id, Subscription25__Status__c, Subscription25__Email_Status__c, Subscription25__Sync_State__c, Subscription25__Account__c,
				Subscription25__Contact_Person__c, Subscription25__Invoice_Date__c, Subscription25__Due_Date__c, Subscription25__Total_Amount__c,
				Subscription25__Purchase_Order_Number__c, Sales_Channel__c, Subscription25__PDF_Attachment_Name__c,
				Subscription25__Administration__r.Reseller__c
			FROM Subscription25__Invoice__c WHERE Subscription25__External_ID__c = 'ODOO-02256232'
		];
		Assert.areEqual('DRAFT', inv.Subscription25__Status__c);
		Assert.areEqual('SENT', inv.Subscription25__Email_Status__c);
		Assert.areEqual('NOT_APPLICABLE', inv.Subscription25__Sync_State__c);
		Assert.areEqual('4', inv.Subscription25__Administration__r.Reseller__c);
		Assert.areEqual(Date.newInstance(2026, 9, 30), inv.Subscription25__Invoice_Date__c);
		Assert.areEqual(Date.newInstance(2026, 10, 30), inv.Subscription25__Due_Date__c);
		Assert.areEqual(535.00, inv.Subscription25__Total_Amount__c);
		Assert.areEqual('PO-4711', inv.Subscription25__Purchase_Order_Number__c);
		Assert.areEqual('Echoes', inv.Sales_Channel__c);
		Assert.isNull(inv.Subscription25__PDF_Attachment_Name__c, 'the package PDF field is never set');

		Account acc = [SELECT Name, Reseller_Name__c, PrimaryBrand__c, VAT_Number__c, BillingCountryCode, BillingPostalCode FROM Account WHERE Id = :inv.Subscription25__Account__c];
		Assert.areEqual('ACTION AUTOMOBILE', acc.Name);
		Assert.areEqual('4', acc.Reseller_Name__c);
		Assert.areEqual('E', acc.PrimaryBrand__c);
		Assert.areEqual('FR19483161238', acc.VAT_Number__c);
		Assert.areEqual('FR', acc.BillingCountryCode);

		Contact con = [SELECT FirstName, LastName, Email, AccountId FROM Contact WHERE Id = :inv.Subscription25__Contact_Person__c];
		Assert.areEqual('Mark', con.FirstName);
		Assert.areEqual('Rice', con.LastName);
		Assert.areEqual('mark.rice@example.com', con.Email);
		Assert.areEqual(acc.Id, con.AccountId);

		Order ord = [SELECT EffectiveDate, EndDate, Status, (SELECT Quantity, UnitPrice, ServiceDate, EndDate, Product2.ProductCode FROM OrderItems ORDER BY Quantity DESC)
			FROM Order WHERE Subscription25__Invoice__c = :inv.Id];
		Assert.areEqual(Date.newInstance(2026, 9, 1), ord.EffectiveDate);
		Assert.areEqual(Date.newInstance(2026, 9, 30), ord.EndDate);
		Assert.areEqual('Draft', ord.Status);
		Assert.areEqual(3, ord.OrderItems.size());
		Assert.areEqual(-6, ord.OrderItems[2].Quantity);
		Assert.areEqual(Date.newInstance(2026, 9, 1), ord.OrderItems[0].ServiceDate);

		Map<String, Product2> products = new Map<String, Product2>();
		for (Product2 p : [SELECT Name, ProductCode FROM Product2]) {
			products.put(p.ProductCode, p);
		}
		Assert.areEqual('Monatlich Lizenz CarFleet', products.get('CarFleetDE').Name);
		Assert.areEqual('Formation', products.get('Formation').Name, 'a line without code: name is code and name');

		Assert.areEqual(em.ParentId, [SELECT ParentId FROM EmailMessage WHERE Id = :em.Id].ParentId, 'original stays on the case');
		EmailMessage copy = [SELECT Subject, FromAddress, Incoming FROM EmailMessage WHERE RelatedToId = :inv.Id];
		Assert.areEqual(em.Subject, copy.Subject);
		Assert.areEqual(SENDER, copy.FromAddress);
		Assert.areEqual(2, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :inv.Id], 'PDF + CSV linked to the invoice');

		Case c = [SELECT Status, AccountId, ContactId, (SELECT CommentBody FROM CaseComments) FROM Case WHERE Id = :em.ParentId];
		Assert.areEqual('Processed', c.Status);
		Assert.areEqual(acc.Id, c.AccountId);
		Assert.areEqual(con.Id, c.ContactId);
		Assert.isTrue(c.CaseComments[0].CommentBody.startsWith(Svc_OdooInvoiceIntake.MARKER + ' Processed'), c.CaseComments[0].CommentBody);
	}

	@isTest
	static void resendIsDuplicateAndAccountIsMatched() {
		EmailMessage first = createOdooEmail('Echoes Facture (Réf 02256232)', '02256232', pdf('02256232', 'compta@example.com'));
		EmailMessage resend = createOdooEmail('Echoes Facture (Réf 02256232)', '02256232', pdf('02256232', 'compta@example.com'));
		EmailMessage other = createOdooEmail('Echoes Invoice (Ref 02256300)', '02256300', pdf('02256300', 'compta@example.com'));

		List<Svc_OdooInvoiceIntake.Result> firstResult = Svc_OdooInvoiceIntake.process(new Set<Id>{ first.Id });
		Assert.areEqual('PROCESSED', firstResult[0].status, firstResult[0].message);
		System.debug('SOQL for one invoice: ' + Limits.getQueries());
		Test.startTest();
		List<Svc_OdooInvoiceIntake.Result> results = Svc_OdooInvoiceIntake.process(new Set<Id>{ resend.Id, other.Id });
		Test.stopTest();

		Map<Id, Svc_OdooInvoiceIntake.Result> byEmail = new Map<Id, Svc_OdooInvoiceIntake.Result>();
		for (Svc_OdooInvoiceIntake.Result r : results) {
			byEmail.put(r.emailMessageId, r);
		}
		Assert.areEqual('DUPLICATE', byEmail.get(resend.Id).status, byEmail.get(resend.Id).message);
		Assert.areEqual('PROCESSED', byEmail.get(other.Id).status, byEmail.get(other.Id).message);
		Assert.areEqual(2, [SELECT COUNT() FROM Subscription25__Invoice__c]);
		Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'ACTION AUTOMOBILE'], 'second invoice matched the account on VAT');
		Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'contact found by e-mail');
		Contact con = [SELECT FirstName, LastName FROM Contact];
		Assert.areEqual('ACTION AUTOMOBILE', con.LastName, 'generic mailbox: contact named after the account');
		Assert.areEqual('Processed', [SELECT Status FROM Case WHERE Id = :resend.ParentId].Status);
	}

	@isTest
	static void failureLeavesCaseNewWithOneComment() {
		EmailMessage em = createOdooEmail('Echoes Invoice (Ref 02256400)', '02256400', Blob.valueOf('%PDF-1.7 scanned, no Factur-X'));

		Test.startTest();
		List<Svc_OdooInvoiceIntake.Result> results = Svc_OdooInvoiceIntake.process(new Set<Id>{ em.Id });
		List<Svc_OdooInvoiceIntake.Result> retry = Svc_OdooInvoiceIntake.process(new Set<Id>{ em.Id });
		Test.stopTest();

		Assert.areEqual('FAILED', results[0].status);
		Assert.areEqual('SKIPPED', retry[0].status, 'a case with an intake comment is not retried');
		Case c = [SELECT Status, (SELECT CommentBody FROM CaseComments) FROM Case WHERE Id = :em.ParentId];
		Assert.areEqual('New', c.Status);
		Assert.areEqual(1, c.CaseComments.size());
		Assert.isTrue(c.CaseComments[0].CommentBody.contains('No Factur-X'), c.CaseComments[0].CommentBody);
		Assert.areEqual(0, [SELECT COUNT() FROM Subscription25__Invoice__c]);
	}

	@isTest
	static void dryRunCreatesNothing() {
		EmailMessage em = createOdooEmail('Echoes Facture (Réf 02256232)', '02256232', pdf('02256232', 'mark.rice@example.com'));

		Test.startTest();
		List<Svc_OdooInvoiceIntake.Result> results = Svc_OdooInvoiceIntake.process(new Set<Id>{ em.Id }, true);
		Test.stopTest();

		Assert.areEqual('PROCESSED', results[0].status, results[0].message);
		Assert.isTrue(results[0].message.startsWith('[dry-run]'));
		Assert.areEqual(0, [SELECT COUNT() FROM Subscription25__Invoice__c]);
		Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = 'ACTION AUTOMOBILE']);
		Assert.areEqual('New', [SELECT Status FROM Case WHERE Id = :em.ParentId].Status);
		Assert.areEqual(0, [SELECT COUNT() FROM CaseComment]);
	}

	@isTest
	static void batchPicksUpOnlyOdooInvoiceEmails() {
		EmailMessage invoice = createOdooEmail('Echoes Facture (Réf 02256232)', '02256232', pdf('02256232', 'mark.rice@example.com'));
		EmailMessage reply = createOdooEmail('RE: Echoes Facture (Réf 02256233)', '02256233', pdf('02256233', 'mark.rice@example.com'));

		Test.startTest();
		Database.executeBatch(new Batch_OdooInvoiceIntake(), 5); // one execute in a test: the reply is skipped cheaply
		Test.stopTest();

		Assert.areEqual('Processed', [SELECT Status FROM Case WHERE Id = :invoice.ParentId].Status);
		Assert.areEqual('New', [SELECT Status FROM Case WHERE Id = :reply.ParentId].Status, 'replies are left alone');
		Assert.areEqual(1, [SELECT COUNT() FROM Subscription25__Invoice__c]);
	}

	@isTest
	static void waitsForDebtorNumberOnExactAdministration() {
		EmailMessage em = createOdooEmail('Moving Intelligence B.V. Factuur (Ref 01250436)', '01250436', pdf('01250436', 'jan.de.boer@example.nl'));

		Test.startTest();
		List<Svc_OdooInvoiceIntake.Result> first = Svc_OdooInvoiceIntake.process(new Set<Id>{ em.Id });
		Account acc = [SELECT Id, Reseller_Name__c, SyncToFinancialSystem__c FROM Account WHERE Name = 'ACTION AUTOMOBILE'];
		Assert.areEqual('WAITING', first[0].status, first[0].message);
		Assert.areEqual('1', acc.Reseller_Name__c);
		Assert.isTrue(acc.SyncToFinancialSystem__c, 'flagged for the Exact account sync');
		Assert.areEqual(0, [SELECT COUNT() FROM Subscription25__Invoice__c]);
		Assert.areEqual(0, [SELECT COUNT() FROM CaseComment], 'no comment while waiting');

		// the Exact account sync delivered the debtor number
		Subscription25__Administration__c adminNl = [SELECT Id FROM Subscription25__Administration__c WHERE Reseller__c = '1'];
		Test_Data.createDebtorNumber(adminNl.Id, acc.Id, true);
		List<Svc_OdooInvoiceIntake.Result> second = Svc_OdooInvoiceIntake.process(new Set<Id>{ em.Id });
		Test.stopTest();

		Assert.areEqual('PROCESSED', second[0].status, second[0].message);
		List<String> names = new List<String>();
		for (Account a : [SELECT Name, Reseller_Name__c FROM Account]) {
			names.add(a.Name + '/' + a.Reseller_Name__c);
		}
		Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'ACTION AUTOMOBILE'], 'account matched on VAT on the second run: ' + names);
		Subscription25__Invoice__c inv = [SELECT Sales_Channel__c, Subscription25__Administration__c, Subscription25__Contact_Person__r.Name FROM Subscription25__Invoice__c];
		Assert.areEqual(adminNl.Id, inv.Subscription25__Administration__c);
		Assert.areEqual('Jan De Boer', inv.Subscription25__Contact_Person__r.Name);
		Assert.areEqual('Processed', [SELECT Status FROM Case WHERE Id = :em.ParentId].Status);
	}

	@isTest
	static void helpers() {
		Assert.areEqual('02256232', Svc_OdooInvoiceIntake.getRef('Echoes Facture (Réf 02256232)'));
		Assert.areEqual('01250436', Svc_OdooInvoiceIntake.getRef('Moving Intelligence B.V. Factuur (Ref 01250436)'));
		Assert.isNull(Svc_OdooInvoiceIntake.getRef('RE: Echoes Invoice (Ref 02256196)'));
		Assert.isNull(Svc_OdooInvoiceIntake.getRef('TR: Echoes GmbH Rechnung (Ref 03251983)'));
		Assert.isNull(Svc_OdooInvoiceIntake.getRef('Payment Reminder for Outstanding Invoice'));
		Assert.isNull(Svc_OdooInvoiceIntake.getRef(null));

		Assert.areEqual(new List<String>{ 'Mark', 'Rice' }, Svc_OdooInvoiceIntake.nameFromEmail('mark.rice@europcar.com'));
		Assert.areEqual(new List<String>{ 'Jean-Pierre', 'De Vries' }, Svc_OdooInvoiceIntake.nameFromEmail('jean-pierre.de.vries@example.nl'));
		Assert.isNull(Svc_OdooInvoiceIntake.nameFromEmail('respcompta.pagmarseille@groupe-maurin.com'));
		Assert.isNull(Svc_OdooInvoiceIntake.nameFromEmail('administratie@h4repair.nl'));
		Assert.isNull(Svc_OdooInvoiceIntake.nameFromEmail('jan-jito@hotmail.de'));
		Assert.isNull(Svc_OdooInvoiceIntake.nameFromEmail('j.2024@example.com'));

		Assert.areEqual('NL860995574B01', Svc_OdooInvoiceIntake.normalizeVat(' nl 8609.95574 B01'));
		Assert.isNull(Svc_OdooInvoiceIntake.normalizeVat(' '));

		EmailMessage notOdoo = new EmailMessage(Incoming = true, FromAddress = 'someone@example.com', Subject = 'Echoes Invoice (Ref 02256196)');
		Assert.isFalse(Svc_OdooInvoiceIntake.isCandidate(notOdoo));
	}
}
