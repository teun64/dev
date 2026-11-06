/**
 * 20261105 TRi Odoo invoice intake: turns the Odoo invoice e-mails that arrive through Email-to-Case on the invoicing@
 * mailboxes into Salesforce records.
 * Candidate: incoming e-mail from an invoicing@ sender, subject "... (Ref|Réf nnnnnnnn)" (no reply/forward), case still New.
 * Source: the Factur-X XML embedded in the Odoo invoice PDF (Svc_FacturX).
 * Per e-mail, all or nothing (savepoint):
 *  - company/reseller from the Odoo number prefix: 01 -> 1 (NL), 02 -> 4 (Echoes FR), 03 -> 5 (DE), 04 -> 6 (UK)
 *  - Account: match within the reseller on VAT, CoC (SIREN/SIRET), name + postal code; else create
 *    (PrimaryBrand__c = 'E' and Sales_Channel__c = 'Echoes' on create only, existing accounts are never changed)
 *  - Contact: by the buyer e-mail of the Factur-X (own domains skipped); name derived from first.last@ e-mails
 *  - Product2 per line code (no code: the line name is code and name) + price book entry + administration product
 *  - Subscription25__Invoice__c: DRAFT, Email_Status SENT, not synced (phase 2 = Exact with the Odoo number)
 *  - Order + OrderItems: service period = calendar month of the invoice date
 *  - a copy of the e-mail (RelatedToId; a received e-mail cannot be re-linked) and all attachments (ContentDocumentLink)
 *    are linked to the invoice
 *    (Subscription25__PDF_Attachment_Name__c is never set: the package breaks on direct edits)
 *  - Case -> Processed + account/contact + an internal comment
 * Exact administrations (NL/UK, DE in prod) need a debtor number first: the account is flagged for the Exact account sync
 * and the case stays New without comment (WAITING); a next run creates the invoice.
 * Failure: rollback, case stays New with one internal "[Odoo intake]" comment; cases with that comment are skipped
 * (delete the comment to retry). An Odoo number that already exists only closes the case (duplicate).
 * Runs from Batch_OdooInvoiceIntake (Minut job dispatcher).
 */
public without sharing class Svc_OdooInvoiceIntake {
	public class IntakeException extends Exception {}

	public static final String MARKER = '[Odoo intake]';
	public static final String CASE_STATUS_NEW = 'New';
	public static final String CASE_STATUS_PROCESSED = 'Processed';
	public static final String EXTERNAL_ID_PREFIX = 'ODOO-';
	public static final Set<String> SENDERS = new Set<String>{
		'invoicing@echoes.solutions', 'invoicing@movingintelligence.nl', 'invoicing@movingintelligence.co.uk', 'invoicing@movingintelligence.de'
	};
	// our own domains: never used as a customer contact e-mail
	public static final Set<String> OWN_DOMAINS = new Set<String>{
		'echoes.solutions', 'movingintelligence.nl', 'movingintelligence.com', 'movingintelligence.co.uk', 'movingintelligence.de', 'movingintelligence.eu'
	};
	public static final Map<String, String> RESELLER_BY_PREFIX = new Map<String, String>{ '01' => '1', '02' => '4', '03' => '7', '04' => '6' };
	// mirror of rbb_Account.fFinancialEntity (billing country -> customer entity), used when the Odoo company's entity is refused
	private static final Map<String, String> RESELLER_BY_COUNTRY = new Map<String, String>{
		'NL' => '1', 'GR' => '2', 'BE' => '1', 'FR' => '4', 'AT' => '5', 'CH' => '5', 'DE' => '5', 'GB' => '6', 'IE' => '6'
	};
	private static final Map<String, String> LANGUAGE_BY_RESELLER = new Map<String, String>{ '1' => 'nl', '4' => 'fr', '5' => 'de', '6' => 'en', '7' => 'de' };
	private static final Map<String, String> VAT_COUNTRY_BY_RESELLER = new Map<String, String>{ '1' => 'NL', '4' => 'FR', '5' => 'DE', '6' => 'UK', '7' => 'DE' };
	private static final Map<String, String> VAT_CURRENCY_BY_RESELLER = new Map<String, String>{ '1' => 'EUR', '4' => 'EUR', '5' => 'EUR', '6' => 'GBP', '7' => 'EUR' };

	private static final Pattern REF_PATTERN = Pattern.compile('\\((?:Ref|R\u00e9f)\\.?\\s*(\\d{8})\\)');
	private static final Pattern REPLY_PATTERN = Pattern.compile('(?i)^\\s*(re|tr|fw|fwd|aw|wg|antw)\\s*:.*');
	private static final Pattern CODE_PREFIX_PATTERN = Pattern.compile('^\\[[^\\]]*\\]\\s*');
	private static final Pattern NAME_PART_PATTERN = Pattern.compile('^[A-Za-z\u00C0-\u00FF\\-]{2,}$');
	private static final Set<String> GENERIC_EMAIL_WORDS = new Set<String>{
		'info', 'admin', 'account', 'compta', 'factur', 'invoic', 'billing', 'finance', 'financ', 'buchhalt', 'rechnung', 'payable',
		'crediteur', 'debiteur', 'support', 'contact', 'office', 'sales', 'reply', 'service', 'boekhoud', 'fleet', 'achats', 'purchas',
		'inkoop', 'team', 'mail', 'bureau', 'secretar', 'direction', 'gestion', 'location', 'agence'
	};

	public class Result {
		public Id emailMessageId;
		public Id caseId;
		public Id invoiceId;
		public String invoiceNumber;
		public String status; // PROCESSED, DUPLICATE, WAITING, FAILED, SKIPPED
		public String message;
		public List<String> notes = new List<String>();

		public Result(EmailMessage em) {
			this.emailMessageId = em.Id;
			this.caseId = em.ParentId;
		}
	}

	/** Odoo invoice number from the subject, or null when the subject is a reply/forward or carries no reference. */
	public static String getRef(String subject) {
		if (String.isBlank(subject) || REPLY_PATTERN.matcher(subject).matches()) {
			return null;
		}
		Matcher m = REF_PATTERN.matcher(subject);
		return m.find() ? m.group(1) : null;
	}

	public static Boolean isCandidate(EmailMessage em) {
		return em != null && em.Incoming && em.ParentId != null && String.isNotBlank(em.FromAddress)
			&& SENDERS.contains(em.FromAddress.trim().toLowerCase()) && getRef(em.Subject) != null;
	}

	public static List<Result> process(Set<Id> emailMessageIds) {
		return process(emailMessageIds, false);
	}

	/** dryRun: everything is created and checked, then rolled back; no comment is written. */
	public static List<Result> process(Set<Id> emailMessageIds, Boolean dryRun) {
		List<Result> results = new List<Result>();
		List<EmailMessage> emails = [
			SELECT Id, ParentId, Subject, FromAddress, Incoming, MessageDate
			FROM EmailMessage WHERE Id IN :emailMessageIds WITH SYSTEM_MODE ORDER BY CreatedDate
		];
		Set<Id> caseIds = new Set<Id>();
		for (EmailMessage em : emails) {
			caseIds.add(em.ParentId);
		}
		Set<Id> markedCases = new Set<Id>();
		for (CaseComment cc : [SELECT ParentId, CommentBody FROM CaseComment WHERE ParentId IN :caseIds WITH SYSTEM_MODE]) {
			if (cc.CommentBody != null && cc.CommentBody.startsWith(MARKER)) {
				markedCases.add(cc.ParentId);
			}
		}
		for (EmailMessage em : emails) {
			Result res = new Result(em);
			if (!isCandidate(em)) {
				res.status = 'SKIPPED';
				res.message = 'not an Odoo invoice e-mail';
			} else if (markedCases.contains(em.ParentId)) {
				res.status = 'SKIPPED';
				res.message = 'case already has an ' + MARKER + ' comment';
			} else {
				processOne(em, res, dryRun);
				markedCases.add(em.ParentId);
			}
			results.add(res);
		}
		return results;
	}

	private static void processOne(EmailMessage em, Result res, Boolean dryRun) {
		String ref = getRef(em.Subject);
		res.invoiceNumber = ref;
		Savepoint sp = Database.setSavepoint();
		try {
			Case c = [SELECT Id, Status FROM Case WHERE Id = :em.ParentId WITH SYSTEM_MODE];
			if (c.Status != CASE_STATUS_NEW) {
				res.status = 'SKIPPED';
				res.message = 'case status is ' + c.Status;
				return;
			}
			List<ContentVersion> files = getEmailFiles(em.Id);
			Svc_FacturX.Invoice fx = readFacturX(files, ref);
			res.invoiceNumber = fx.invoiceNumber;

			List<Subscription25__Invoice__c> existing = [
				SELECT Id, Name, Subscription25__Account__c, Subscription25__Contact_Person__c
				FROM Subscription25__Invoice__c WHERE Subscription25__External_ID__c = :EXTERNAL_ID_PREFIX + fx.invoiceNumber
				WITH SYSTEM_MODE LIMIT 1
			];
			if (!existing.isEmpty()) {
				Subscription25__Invoice__c inv = existing[0];
				copyEmailToInvoice(em.Id, inv.Id, files);
				closeCase(c.Id, inv.Subscription25__Account__c, inv.Subscription25__Contact_Person__c);
				res.status = 'DUPLICATE';
				res.invoiceId = inv.Id;
				res.message = 'Odoo invoice ' + fx.invoiceNumber + ' already exists as ' + inv.Name + '; nothing created, e-mail linked to it';
				addComment(c.Id, MARKER + ' Duplicate: ' + res.message);
				finish(sp, res, dryRun);
				return;
			}

			String reseller = RESELLER_BY_PREFIX.get(fx.invoiceNumber.left(2));
			if (reseller == null) {
				throw new IntakeException('Unknown Odoo number prefix ' + fx.invoiceNumber.left(2) + ' (expected 01/02/03/04)');
			}
			List<Subscription25__Administration__c> admins = [
				SELECT Id, Name, Reseller__c, Subscription25__Synchronisation__c FROM Subscription25__Administration__c WHERE Reseller__c = :reseller WITH SYSTEM_MODE LIMIT 1
			];
			if (admins.isEmpty()) {
				throw new IntakeException('No administration for reseller ' + reseller);
			}
			Subscription25__Administration__c admin = admins[0];
			String currencyCode = String.isBlank(fx.currencyCode) ? VAT_CURRENCY_BY_RESELLER.get(reseller) : fx.currencyCode;

			Account acc = findOrCreateAccount(fx, reseller, res);
			Contact con = findOrCreateContact(fx, acc, res);
			if (waitForDebtorNumber(acc, admin, res)) {
				// account (+ contact) stay; the invoice follows on a next run once the Exact sync made the debtor number
				finish(sp, res, dryRun);
				return;
			}
			Map<String, PricebookEntry> pbeByCode = ensureProducts(fx, admin, reseller, currencyCode, res);

			Subscription25__Invoice__c inv = createInvoice(fx, em, acc, con, admin, currencyCode);
			createOrder(fx, inv, acc, admin, currencyCode, pbeByCode, res);
			verifyTotals(fx, inv.Id, res);

			linkFiles(files, inv.Id);
			copyEmailToInvoice(em.Id, inv.Id, files);
			closeCase(c.Id, acc.Id, con?.Id);

			inv = [SELECT Id, Name FROM Subscription25__Invoice__c WHERE Id = :inv.Id WITH SYSTEM_MODE];
			res.status = 'PROCESSED';
			res.invoiceId = inv.Id;
			res.message = 'Odoo invoice ' + fx.invoiceNumber + ' -> ' + inv.Name + ' (' + admin.Name + ', ' + fx.lines.size() + ' lines, net '
				+ currencyCode + ' ' + fx.taxBasisTotal + ')';
			addComment(c.Id, MARKER + ' Processed: ' + res.message + (res.notes.isEmpty() ? '' : '\n- ' + String.join(res.notes, '\n- ')));
			finish(sp, res, dryRun);
		} catch (Exception e) {
			Database.rollback(sp);
			res.status = 'FAILED';
			res.message = (e instanceof IntakeException || e instanceof Svc_FacturX.FacturXException)
				? e.getMessage() : e.getTypeName() + ': ' + e.getMessage();
			if (!dryRun) {
				try {
					addComment(em.ParentId, MARKER + ' Not processed (Odoo ' + (res.invoiceNumber == null ? '?' : res.invoiceNumber) + '): '
						+ res.message.left(3000) + '\nDelete this comment to retry.');
				} catch (Exception ce) {
					res.message += ' | comment failed: ' + ce.getMessage();
				}
			}
		}
	}

	/**
	 * An administration synced with Exact needs a debtor number for the account before the package accepts an invoice or
	 * order; it comes from the Exact account sync (FinancialDebtorNumber__c -> rab_Account_Debtor_Number). Flags the
	 * account for that sync (Minut_FinancialSystemAccountSync) and returns true (WAITING) when it is missing.
	 */
	private static Boolean waitForDebtorNumber(Account acc, Subscription25__Administration__c admin, Result res) {
		if (admin.Subscription25__Synchronisation__c != 'Exact') {
			// no Exact environment: nothing to wait for, the debtor number is made up (same record as an Exact one)
			ensureFakeDebtorNumber(acc, admin, res);
			return false;
		}
		Integer debtorNumbers = [
			SELECT COUNT() FROM Subscription25__Debtor_Number__c
			WHERE Subscription25__Account__c = :acc.Id AND Subscription25__Administration__c = :admin.Id WITH SYSTEM_MODE
		];
		if (debtorNumbers > 0) {
			return false;
		}
		if (acc.Reseller_Name__c != null && VAT_COUNTRY_BY_RESELLER.containsKey(acc.Reseller_Name__c)
				&& RESELLER_BY_PREFIX.values().contains(acc.Reseller_Name__c) && acc.Reseller_Name__c != admin.Reseller__c) {
			// the Exact account sync goes to the account's own entity: the debtor number for this administration never comes
			throw new IntakeException('Account ' + acc.Name + ' belongs to reseller ' + acc.Reseller_Name__c + ', the invoice to ' + admin.Name
				+ ' (reseller ' + admin.Reseller__c + '): no debtor number possible, handle manually');
		}
		Account state = [
			SELECT Name, SyncToFinancialSystem__c, FinancialSyncBlocked__c, FinancialSyncLastError__c FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE
		];
		if (state.FinancialSyncBlocked__c) {
			throw new IntakeException('Account ' + state.Name + ' has no debtor number for ' + admin.Name + ' and its Exact sync is blocked: '
				+ state.FinancialSyncLastError__c);
		}
		if (!state.SyncToFinancialSystem__c) {
			Util_FinancialSystemAccount.flagAccounts(new Set<Id>{ acc.Id }, false);
		}
		res.status = 'WAITING';
		res.message = 'Account ' + state.Name + ' has no debtor number for ' + admin.Name + ' yet: flagged for the Exact account sync, '
			+ 'the invoice follows on a next run';
		return true;
	}

	/**
	 * Administration without Exact: the account gets a Subscription25 debtor number record anyway, so every administration is
	 * handled the same. The number is made from the account Id without its first 6 and last 3 characters (the record number
	 * stays). It lives on Subscription25__Debtor_Number__c only, never on Account.FinancialDebtorNumber__c (that one feeds
	 * Exact and Stripe). An account that already has a record (e.g. the real number of another administration) is left alone:
	 * the package takes the first record of an account.
	 */
	private static void ensureFakeDebtorNumber(Account acc, Subscription25__Administration__c admin, Result res) {
		List<Subscription25__Debtor_Number__c> existing = [
			SELECT Subscription25__Administration__c FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c = :acc.Id WITH SYSTEM_MODE
		];
		if (!existing.isEmpty()) {
			return;
		}
		String accountId = String.valueOf(acc.Id);
		Database.insert(new Subscription25__Debtor_Number__c(
			Subscription25__Account__c = acc.Id,
			Subscription25__Administration__c = admin.Id,
			Subscription25__Debtor_Number__c = accountId.substring(6, 15),
			Subscription25__Composite_Key__c = accountId + String.valueOf(admin.Id)
		), AccessLevel.SYSTEM_MODE);
		res.notes.add('Debtor number ' + accountId.substring(6, 15) + ' made up for ' + admin.Name + ' (no Exact environment)');
	}

	private static void finish(Savepoint sp, Result res, Boolean dryRun) {
		if (dryRun) {
			Database.rollback(sp);
			res.message = '[dry-run] ' + res.message;
		}
	}

	private static List<ContentVersion> getEmailFiles(Id emailMessageId) {
		Set<Id> docIds = new Set<Id>();
		for (ContentDocumentLink cdl : [
			SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :emailMessageId WITH SYSTEM_MODE
		]) {
			docIds.add(cdl.ContentDocumentId);
		}
		if (docIds.isEmpty()) {
			return new List<ContentVersion>();
		}
		return [
			SELECT Id, ContentDocumentId, Title, FileExtension FROM ContentVersion
			WHERE ContentDocumentId IN :docIds AND IsLatest = true WITH SYSTEM_MODE ORDER BY CreatedDate
		];
	}

	/** The Factur-X of the PDF that belongs to the reference (PDF titled with the reference first). */
	private static Svc_FacturX.Invoice readFacturX(List<ContentVersion> files, String ref) {
		List<ContentVersion> pdfs = new List<ContentVersion>();
		List<ContentVersion> others = new List<ContentVersion>();
		for (ContentVersion cv : files) {
			if (cv.FileExtension == null || cv.FileExtension.toLowerCase() != 'pdf') {
				continue;
			}
			if (cv.Title != null && cv.Title.contains(ref)) {
				pdfs.add(cv);
			} else {
				others.add(cv);
			}
		}
		pdfs.addAll(others);
		if (pdfs.isEmpty()) {
			throw new IntakeException('No PDF attachment on the e-mail');
		}
		String found = null;
		for (ContentVersion cv : pdfs) {
			Blob data = [SELECT VersionData FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE].VersionData;
			String xml = Svc_FacturX.extractXml(data);
			data = null;
			if (xml == null) {
				continue;
			}
			Svc_FacturX.Invoice fx = Svc_FacturX.parse(xml);
			if (fx.invoiceNumber == ref) {
				return fx;
			}
			found = fx.invoiceNumber;
		}
		throw new IntakeException(found == null
			? 'No Factur-X data found in the PDF attachment(s)'
			: 'The Factur-X in the PDF is invoice ' + found + ', the subject says ' + ref);
	}

	@TestVisible
	private static String normalizeVat(String vat) {
		return String.isBlank(vat) ? null : vat.replaceAll('[^A-Za-z0-9]', '').toUpperCase();
	}

	/** Same reseller first, then the oldest. */
	// entities that keep their own accounts: a customer of Echoes France (4) or Echoes GmbH (7) is a separate account from the same
	// customer under any other entity (user decision 2026-11-06); all other entities share accounts
	private static final Set<String> SEPARATE_ENTITIES = new Set<String>{ '4', '7' };

	@TestVisible
	private static Account pick(List<Account> found, String reseller) {
		List<Account> usable = new List<Account>();
		for (Account a : found) {
			Boolean sameWorld = SEPARATE_ENTITIES.contains(reseller) ? a.Reseller_Name__c == reseller : !SEPARATE_ENTITIES.contains(a.Reseller_Name__c);
			if (sameWorld) {
				usable.add(a);
			}
		}
		for (Account a : usable) {
			if (a.Reseller_Name__c == reseller) {
				return a;
			}
		}
		return usable.isEmpty() ? null : usable[0];
	}

	private static Account matched(Account acc, String how, String reseller, Result res) {
		// a reseller that differs from the Odoo company's is no problem here: Exact administrations stop it in waitForDebtorNumber,
		// the others (4, 7) have no financial system behind them
		res.notes.add('Account ' + acc.Name + ' matched on ' + how);
		return acc;
	}

	/**
	 * Match on VAT, CoC (SIREN/SIRET), name + postal code (any entity, the Odoo company's own preferred), except for Echoes France (4)
	 * and Echoes GmbH (7): they only match accounts of their own entity, and no other entity matches theirs (separate accounts, see
	 * pick); else create.
	 * rbb_Account derives the reseller from the billing country on create; the Odoo company's reseller is set back with an
	 * update (vr_FinancialEntityChange: sysadmin / cp_AllowFinancialEntityChange); when that is refused the country's stays.
	 */
	private static Account findOrCreateAccount(Svc_FacturX.Invoice fx, String reseller, Result res) {
		Svc_FacturX.Party b = fx.buyer;
		if (String.isBlank(b.name)) {
			throw new IntakeException('The Factur-X has no customer name');
		}
		String vat = normalizeVat(b.vatNumber);
		if (vat != null) {
			Set<String> vats = new Set<String>{ vat, b.vatNumber.trim() };
			Account found = pick([
				SELECT Id, Name, Reseller_Name__c FROM Account WHERE VAT_Number__c IN :vats WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 20
			], reseller);
			if (found != null) {
				return matched(found, 'VAT ' + vat, reseller, res);
			}
		}
		if (String.isNotBlank(b.legalId)) {
			String legalId = b.legalId.replaceAll('\\s', '');
			Set<String> ids = new Set<String>{ legalId };
			if (legalId.length() == 14 && legalId.isNumeric()) {
				ids.add(legalId.left(9)); // SIRET -> SIREN
			}
			Account found = pick([
				SELECT Id, Name, Reseller_Name__c FROM Account WHERE CoC_Number__c IN :ids WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 20
			], reseller);
			if (found != null) {
				return matched(found, 'CoC ' + legalId, reseller, res);
			}
		}
		String name = b.name.trim();
		String postalCode = String.isBlank(b.postalCode) ? null : b.postalCode.trim();
		Account byName = pick([
			SELECT Id, Name, Reseller_Name__c FROM Account WHERE Name = :name AND BillingPostalCode = :postalCode
			WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 20
		], reseller);
		if (byName != null) {
			return matched(byName, 'name + postal code', reseller, res);
		}

		Account acc = new Account(
			Name = name.left(255),
			Reseller_Name__c = reseller,
			PrimaryBrand__c = 'E',
			Sales_Channel__c = 'Echoes',
			// Odoo invoices are paid by bank transfer; 08 is allowed for every reseller (the field default I8 is not for 6)
			Payment_Method_Contracts__c = '08',
			Payment_Method_Opportunities__c = '08',
			VAT_Number__c = vat,
			Phone = String.isBlank(b.phone) ? null : b.phone.left(40),
			BillingStreet = String.isBlank(b.street2) ? b.street : b.street + '\n' + b.street2,
			BillingPostalCode = postalCode,
			BillingCity = b.city,
			BillingCountryCode = Util_System.getISO2CountryCode(b.countryCode)
		);
		Database.SaveResult ins = Database.insert(acc, false, AccessLevel.SYSTEM_MODE);
		if (!ins.isSuccess()) {
			// e.g. a customer abroad: rbb_Account moves it to the country's entity, whose payment rules then refuse the
			// defaults of the given reseller; retry with the country's entity (rbb_Account derives it)
			String firstError = ins.getErrors()[0].getMessage();
			String countryReseller = RESELLER_BY_COUNTRY.get(acc.BillingCountryCode);
			if (countryReseller == null || countryReseller == reseller) {
				throw new IntakeException('Account ' + acc.Name + ' cannot be created: ' + firstError);
			}
			acc.Id = null;
			acc.Reseller_Name__c = countryReseller;
			Database.SaveResult retry = Database.insert(acc, false, AccessLevel.SYSTEM_MODE);
			if (!retry.isSuccess()) {
				throw new IntakeException('Account ' + acc.Name + ' cannot be created: ' + firstError + ' / ' + retry.getErrors()[0].getMessage());
			}
		}
		acc = [SELECT Id, Name, Reseller_Name__c, BillingCountryCode, Subscription25__Always_Apply_Domestic_VAT__c FROM Account WHERE Id = :acc.Id WITH SYSTEM_MODE];
		if ((fx.taxTotal == null || fx.taxTotal == 0) && acc.Subscription25__Always_Apply_Domestic_VAT__c) {
			// Odoo charged no VAT (export / reverse charge) but rbb_Account made a customer without VAT number domestic:
			// let the package apply the EU / non-EU rate like Odoo did (new accounts only)
			Database.update(new Account(Id = acc.Id, Subscription25__Always_Apply_Domestic_VAT__c = false), false, AccessLevel.SYSTEM_MODE);
		}
		if (acc.Reseller_Name__c != reseller) {
			String countryReseller = acc.Reseller_Name__c;
			Database.SaveResult sr = Database.update(new Account(Id = acc.Id, Reseller_Name__c = reseller), false, AccessLevel.SYSTEM_MODE);
			if (sr.isSuccess()) {
				acc.Reseller_Name__c = reseller;
				res.notes.add('Account ' + acc.Name + ' created (reseller ' + reseller + '; the country default ' + countryReseller + ' was overruled)');
			} else {
				res.notes.add('CHECK: account ' + acc.Name + ' created with reseller ' + countryReseller + ' (from its country); setting reseller '
					+ reseller + ' was refused: ' + sr.getErrors()[0].getMessage());
			}
		} else {
			res.notes.add('Account ' + acc.Name + ' created (reseller ' + reseller + ')');
		}
		// after the reseller is final: rbb_Account sets the language from the country / the running user on create, so set it here;
		// the buyer reference (the customer's own reference, the same on every invoice) is the account's invoice cost center
		Account details = new Account(Id = acc.Id, Sales_Language__c = languageFor(acc.Reseller_Name__c, acc.BillingCountryCode));
		if (String.isNotBlank(fx.buyerReference)) {
			details.Cost_Center_invoicing__c = fx.buyerReference.left(255);
		}
		Database.SaveResult dr = Database.update(details, false, AccessLevel.SYSTEM_MODE);
		if (!dr.isSuccess()) {
			res.notes.add('CHECK: language / cost center of account ' + acc.Name + ' not set: ' + dr.getErrors()[0].getMessage());
		}
		return acc;
	}

	/**
	 * Language of a new account: the reseller's language when the customer's country belongs to that reseller, otherwise English;
	 * German resellers (5, 7): always German.
	 */
	@TestVisible
	private static String languageFor(String reseller, String countryCode) {
		if (reseller == '5' || reseller == '7') {
			return 'de';
		}
		String language = LANGUAGE_BY_RESELLER.get(reseller);
		return language != null && RESELLER_BY_COUNTRY.get(countryCode) == reseller ? language : 'en';
	}

	private static Contact findOrCreateContact(Svc_FacturX.Invoice fx, Account acc, Result res) {
		String email = String.isBlank(fx.buyer.email) ? null : fx.buyer.email.trim().toLowerCase();
		if (email == null || !email.contains('@') || OWN_DOMAINS.contains(email.substringAfter('@'))) {
			res.notes.add('No customer e-mail in the Factur-X' + (email == null ? '' : ' (' + email + ' is our own)') + ': no contact linked');
			return null;
		}
		List<Contact> existing = [SELECT Id, Name, AccountId FROM Contact WHERE Email = :email WITH SYSTEM_MODE ORDER BY CreatedDate];
		for (Contact c : existing) {
			if (c.AccountId == acc.Id) {
				res.notes.add('Contact ' + c.Name + ' (' + email + ') found');
				return c;
			}
		}
		if (!existing.isEmpty()) {
			// e-mail addresses are unique on Contact: relate the existing contact to this account
			Contact c = existing[0];
			List<AccountContactRelation> acr = [
				SELECT Id FROM AccountContactRelation WHERE AccountId = :acc.Id AND ContactId = :c.Id WITH SYSTEM_MODE LIMIT 1
			];
			if (acr.isEmpty()) {
				Database.insert(new AccountContactRelation(AccountId = acc.Id, ContactId = c.Id), AccessLevel.SYSTEM_MODE);
			}
			res.notes.add('Contact ' + c.Name + ' (' + email + ') exists on another account: related to ' + acc.Name);
			return c;
		}
		List<String> names = nameFromEmail(email);
		Contact c = new Contact(AccountId = acc.Id, Email = email);
		if (names != null) {
			c.FirstName = names[0];
			c.LastName = names[1];
		} else {
			String contactName = fx.buyer.contactName;
			c.LastName = (String.isNotBlank(contactName) && contactName.trim() != fx.buyer.name?.trim() ? contactName.trim() : acc.Name).left(80);
		}
		Database.insert(c, AccessLevel.SYSTEM_MODE);
		res.notes.add('Contact ' + (c.FirstName == null ? '' : c.FirstName + ' ') + c.LastName + ' (' + email + ') created');
		return c;
	}

	/** first.last@ / first_last@ -> [First, Last]; null for generic mailboxes. */
	@TestVisible
	private static List<String> nameFromEmail(String email) {
		if (String.isBlank(email) || !email.contains('@')) {
			return null;
		}
		String local = email.substringBefore('@').toLowerCase();
		for (String word : GENERIC_EMAIL_WORDS) {
			if (local.contains(word)) {
				return null;
			}
		}
		List<String> parts = local.split('[._]');
		if (parts.size() < 2) {
			return null;
		}
		List<String> capitalized = new List<String>();
		for (String part : parts) {
			if (!NAME_PART_PATTERN.matcher(part).matches()) {
				return null;
			}
			List<String> sub = new List<String>();
			for (String s : part.split('-')) {
				sub.add(s.capitalize());
			}
			capitalized.add(String.join(sub, '-'));
		}
		String first = capitalized.remove(0);
		return new List<String>{ first, String.join(capitalized, ' ') };
	}

	@TestVisible
	private static String lineCode(Svc_FacturX.Line l) {
		String code = String.isNotBlank(l.code) ? l.code.trim() : productName(l);
		if (String.isBlank(code)) {
			throw new IntakeException('Invoice line ' + l.lineId + ' has no product code and no name');
		}
		return code.left(255);
	}

	@TestVisible
	private static String productName(Svc_FacturX.Line l) {
		String name = String.isNotBlank(l.name) ? l.name : l.description;
		return name == null ? null : CODE_PREFIX_PATTERN.matcher(name.trim()).replaceFirst('').left(255);
	}

	/** Product2 + active standard price book entry (in the invoice currency) + administration product per line code. */
	private static Map<String, PricebookEntry> ensureProducts(Svc_FacturX.Invoice fx, Subscription25__Administration__c admin, String reseller,
			String currencyCode, Result res) {
		Map<String, Svc_FacturX.Line> lineByCode = new Map<String, Svc_FacturX.Line>();
		for (Svc_FacturX.Line l : fx.lines) {
			String key = lineCode(l).toLowerCase();
			if (!lineByCode.containsKey(key)) {
				lineByCode.put(key, l);
			}
		}
		Map<String, Product2> productByCode = new Map<String, Product2>();
		for (Product2 p : [
			SELECT Id, Name, ProductCode, IsActive FROM Product2 WHERE ProductCode IN :lineByCode.keySet()
			WITH SYSTEM_MODE ORDER BY IsActive DESC, CreatedDate ASC
		]) {
			String key = p.ProductCode.toLowerCase();
			if (!productByCode.containsKey(key)) {
				productByCode.put(key, p);
			}
		}
		List<Product2> newProducts = new List<Product2>();
		for (String key : lineByCode.keySet()) {
			if (!productByCode.containsKey(key)) {
				Svc_FacturX.Line l = lineByCode.get(key);
				Product2 p = new Product2(Name = productName(l), ProductCode = lineCode(l), IsActive = true,
					Description = l.description, CurrencyIsoCode = currencyCode);
				newProducts.add(p);
				productByCode.put(key, p);
			}
		}
		if (!newProducts.isEmpty()) {
			Database.insert(newProducts, AccessLevel.SYSTEM_MODE);
			List<String> codes = new List<String>();
			for (Product2 p : newProducts) {
				codes.add(p.ProductCode);
			}
			res.notes.add('Products created: ' + String.join(codes, ', '));
		}
		Set<Id> productIds = new Set<Id>();
		for (Product2 p : productByCode.values()) {
			productIds.add(p.Id);
		}

		Id pricebookId = getStandardPricebookId();
		Map<Id, PricebookEntry> pbeByProduct = new Map<Id, PricebookEntry>();
		List<PricebookEntry> toActivate = new List<PricebookEntry>();
		for (PricebookEntry pbe : [
			SELECT Id, Product2Id, IsActive FROM PricebookEntry
			WHERE Pricebook2Id = :pricebookId AND Product2Id IN :productIds AND CurrencyIsoCode = :currencyCode WITH SYSTEM_MODE
		]) {
			pbeByProduct.put(pbe.Product2Id, pbe);
			if (!pbe.IsActive) {
				pbe.IsActive = true;
				toActivate.add(pbe);
			}
		}
		if (!toActivate.isEmpty()) {
			Database.update(toActivate, AccessLevel.SYSTEM_MODE);
		}
		List<PricebookEntry> newPbes = new List<PricebookEntry>();
		for (Id productId : productIds) {
			if (!pbeByProduct.containsKey(productId)) {
				PricebookEntry pbe = new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = productId, UnitPrice = 0,
					IsActive = true, CurrencyIsoCode = currencyCode);
				newPbes.add(pbe);
				pbeByProduct.put(productId, pbe);
			}
		}
		if (!newPbes.isEmpty()) {
			Database.insert(newPbes, AccessLevel.SYSTEM_MODE);
		}

		Set<Id> withAdminProduct = new Set<Id>();
		for (Subscription25__Administration_Product__c ap : [
			SELECT Subscription25__Product__c FROM Subscription25__Administration_Product__c
			WHERE Subscription25__Administration__c = :admin.Id AND Subscription25__Product__c IN :productIds WITH SYSTEM_MODE
		]) {
			withAdminProduct.add(ap.Subscription25__Product__c);
		}
		List<Subscription25__Administration_Product__c> newAdminProducts = new List<Subscription25__Administration_Product__c>();
		Map<String, Id> vatRates;
		for (Id productId : productIds) {
			if (withAdminProduct.contains(productId)) {
				continue;
			}
			if (vatRates == null) {
				vatRates = new Map<String, Id>();
				for (Subscription25__VATRate__c vr : [SELECT Id, Name FROM Subscription25__VATRate__c WITH SYSTEM_MODE]) {
					vatRates.put(vr.Name, vr.Id);
				}
			}
			String country = VAT_COUNTRY_BY_RESELLER.get(reseller);
			String vatCurrency = VAT_CURRENCY_BY_RESELLER.get(reseller);
			Id defaultRate = vatRates.get(country + ' - VAT high rate');
			if (defaultRate == null) {
				throw new IntakeException('VAT rate "' + country + ' - VAT high rate" not found');
			}
			newAdminProducts.add(new Subscription25__Administration_Product__c(
				Subscription25__Administration__c = admin.Id,
				Subscription25__Product__c = productId,
				CurrencyIsoCode = vatCurrency,
				Subscription25__VATRate__c = defaultRate,
				Subscription25__VATRate_EU__c = vatRates.get(vatCurrency + ' - Sell within the EU'),
				Subscription25__VATRate_Non_EU__c = vatRates.get(vatCurrency + ' - Sell outside the EU'),
				Subscription25__VATRate_Exempt__c = vatRates.get(vatCurrency + ' - No VAT'),
				Subscription25__ICP_Performance_Type__c = 'SERVICES'
			));
		}
		if (!newAdminProducts.isEmpty()) {
			Database.insert(newAdminProducts, AccessLevel.SYSTEM_MODE);
		}

		Map<String, PricebookEntry> result = new Map<String, PricebookEntry>();
		for (String key : productByCode.keySet()) {
			result.put(key, pbeByProduct.get(productByCode.get(key).Id));
		}
		return result;
	}

	private static Id getStandardPricebookId() {
		if (Test.isRunningTest()) {
			return Test.getStandardPricebookId();
		}
		return [SELECT Id FROM Pricebook2 WHERE IsStandard = true WITH SYSTEM_MODE LIMIT 1].Id;
	}

	private static Subscription25__Invoice__c createInvoice(Svc_FacturX.Invoice fx, EmailMessage em, Account acc, Contact con,
			Subscription25__Administration__c admin, String currencyCode) {
		String seller = fx.seller.name == null ? '' : fx.seller.name;
		Subscription25__Invoice__c inv = new Subscription25__Invoice__c(
			Subscription25__Account__c = acc.Id,
			Subscription25__Administration__c = admin.Id,
			Subscription25__Contact_Person__c = con?.Id,
			Subscription25__Invoice_Date__c = fx.issueDate,
			Subscription25__Due_Date__c = fx.dueDate,
			Subscription25__Status__c = 'DRAFT',
			Subscription25__Create_As_Draft__c = true,
			Subscription25__Invoice_Number__c = fx.invoiceNumber,
			Subscription25__Email_Status__c = 'SENT',
			Subscription25__UBL_Email_Status__c = 'WILL_NOT_BE_SENT',
			Subscription25__Sync_State__c = 'NOT_APPLICABLE',
			Subscription25__External_ID__c = EXTERNAL_ID_PREFIX + fx.invoiceNumber,
			// with a VAT number the package applies intra-EU 0%: only when Odoo itself charged no VAT (reverse charge / export)
			Subscription25__VAT_Number__c = (fx.taxTotal == null || fx.taxTotal == 0) ? normalizeVat(fx.buyer.vatNumber) : null,
			Subscription25__Purchase_Order_Number__c = fx.buyerOrderReference == fx.invoiceNumber ? null : fx.buyerOrderReference,
			Subscription25__Description__c = 'Odoo ' + (fx.isCreditNote() ? 'credit note ' : 'invoice ') + fx.invoiceNumber + ' (' + seller + ')',
			Invoice_Description__c = 'Odoo ' + fx.invoiceNumber,
			Sales_Channel__c = seller.containsIgnoreCase('echoes') ? 'Echoes' : 'Moving Intelligence',
			Email_SendDate__c = em.MessageDate == null ? Date.today() : em.MessageDate.date(),
			CurrencyIsoCode = currencyCode
		);
		Database.insert(inv, AccessLevel.SYSTEM_MODE);
		return inv;
	}

	private static void createOrder(Svc_FacturX.Invoice fx, Subscription25__Invoice__c inv, Account acc, Subscription25__Administration__c admin,
			String currencyCode, Map<String, PricebookEntry> pbeByCode, Result res) {
		Date startDate = fx.issueDate.toStartOfMonth();
		Date endDate = startDate.addMonths(1).addDays(-1);
		Order ord = new Order(
			AccountId = acc.Id,
			Pricebook2Id = getStandardPricebookId(),
			EffectiveDate = startDate,
			EndDate = endDate,
			Status = 'Draft',
			Subscription25__Invoice__c = inv.Id,
			Subscription25__Administration__c = admin.Id,
			Subscription25__Invoice_Date__c = fx.issueDate,
			OrderReferenceNumber = fx.invoiceNumber,
			PoNumber = fx.buyerOrderReference == null || fx.buyerOrderReference == fx.invoiceNumber ? null : fx.buyerOrderReference.left(80),
			Description = 'Odoo ' + (fx.isCreditNote() ? 'credit note ' : 'invoice ') + fx.invoiceNumber,
			CurrencyIsoCode = currencyCode
		);
		Database.insert(ord, AccessLevel.SYSTEM_MODE);

		Decimal sign = fx.isCreditNote() ? -1 : 1;
		List<OrderItem> items = new List<OrderItem>();
		for (Svc_FacturX.Line l : fx.lines) {
			if ((l.quantity == null || l.quantity == 0) && (l.lineTotal == null || l.lineTotal == 0)) {
				res.notes.add('Line ' + l.lineId + ' (' + productName(l) + ') skipped: quantity 0');
				continue;
			}
			PricebookEntry pbe = pbeByCode.get(lineCode(l).toLowerCase());
			String description = String.isNotBlank(l.description) ? l.description : l.name;
			items.add(new OrderItem(
				OrderId = ord.Id,
				PricebookEntryId = pbe.Id,
				Product2Id = pbe.Product2Id,
				Quantity = l.quantity * sign,
				UnitPrice = l.unitPrice == null ? 0 : l.unitPrice,
				ServiceDate = startDate,
				EndDate = endDate,
				Subscription25__VAT_Percentage__c = l.vatPercent,
				Description = description == null ? null : description.left(255)
			));
		}
		Database.insert(items, AccessLevel.SYSTEM_MODE);

		// complete (lines with the VAT of Odoo): activate. Linking the order to the invoice only afterwards would let the package
		// recalculate the line VAT (0% for an EU customer with a VAT number on the NL-based administration) and break the gross
		ord.Status = 'Activated';
		Database.update(ord, AccessLevel.SYSTEM_MODE);
	}

	/** Net total must match Odoo (else rollback); a VAT/gross difference only gives a note. */
	private static void verifyTotals(Svc_FacturX.Invoice fx, Id invoiceId, Result res) {
		Subscription25__Invoice__c inv = [
			SELECT Subscription25__Total_Amount__c, Subscription25__Gross_Amount__c FROM Subscription25__Invoice__c WHERE Id = :invoiceId WITH SYSTEM_MODE
		];
		Decimal sign = fx.isCreditNote() ? -1 : 1;
		Decimal expectedNet = (fx.taxBasisTotal != null ? fx.taxBasisTotal : fx.lineTotal);
		if (expectedNet != null) {
			expectedNet *= sign;
			Decimal net = inv.Subscription25__Total_Amount__c == null ? 0 : inv.Subscription25__Total_Amount__c;
			if (Math.abs(net - expectedNet) > 0.01) {
				throw new IntakeException('Net total differs: Salesforce ' + net + ', Odoo ' + expectedNet);
			}
		}
		if (fx.grandTotal != null) {
			Decimal expectedGross = fx.grandTotal * sign;
			Decimal gross = inv.Subscription25__Gross_Amount__c == null ? 0 : inv.Subscription25__Gross_Amount__c;
			if (Math.abs(gross - expectedGross) > 0.01) {
				// Odoo calculates VAT on the invoice total per rate, Salesforce per line: a few cents of rounding is expected
				Boolean rounding = Math.abs(gross - expectedGross) <= 0.01 * fx.lines.size();
				res.notes.add((rounding ? 'VAT rounding (Odoo: on the total, Salesforce: per line): ' : 'CHECK VAT: ') + 'gross in Salesforce ' + gross + ', Odoo ' + expectedGross);
			}
		}
	}

	private static void linkFiles(List<ContentVersion> files, Id invoiceId) {
		Set<Id> docIds = new Set<Id>();
		for (ContentVersion cv : files) {
			docIds.add(cv.ContentDocumentId);
		}
		if (docIds.isEmpty()) {
			return;
		}
		for (ContentDocumentLink cdl : [
			SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :invoiceId AND ContentDocumentId IN :docIds WITH SYSTEM_MODE
		]) {
			docIds.remove(cdl.ContentDocumentId);
		}
		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		for (Id docId : docIds) {
			links.add(new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = invoiceId, ShareType = 'V', Visibility = 'AllUsers'));
		}
		Database.insert(links, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * RelatedToId of a received e-mail cannot be changed, so the invoice gets a copy of the e-mail (activity on the
	 * invoice); the original stays on the case.
	 */
	private static void copyEmailToInvoice(Id emailMessageId, Id invoiceId, List<ContentVersion> files) {
		EmailMessage src = [
			SELECT Subject, FromAddress, FromName, ToAddress, CcAddress, BccAddress, TextBody, HtmlBody, MessageDate, Headers
			FROM EmailMessage WHERE Id = :emailMessageId WITH SYSTEM_MODE
		];
		// files can only be attached to a draft e-mail: insert as draft, attach, then set to read
		EmailMessage copy = new EmailMessage(
			RelatedToId = invoiceId,
			Incoming = true,
			Status = '5', // draft
			Subject = src.Subject,
			FromAddress = src.FromAddress,
			FromName = src.FromName,
			ToAddress = src.ToAddress,
			CcAddress = src.CcAddress,
			BccAddress = src.BccAddress,
			TextBody = src.TextBody,
			HtmlBody = src.HtmlBody,
			MessageDate = src.MessageDate,
			Headers = src.Headers
		);
		Database.insert(copy, AccessLevel.SYSTEM_MODE);
		linkFiles(files, copy.Id);
		copy.Status = '1'; // read
		Database.update(copy, AccessLevel.SYSTEM_MODE);
	}

	private static void closeCase(Id caseId, Id accountId, Id contactId) {
		Case c = new Case(Id = caseId, Status = CASE_STATUS_PROCESSED);
		if (accountId != null) {
			c.AccountId = accountId;
		}
		if (contactId != null) {
			c.ContactId = contactId;
		}
		Database.update(c, AccessLevel.SYSTEM_MODE);
	}

	private static void addComment(Id caseId, String body) {
		Database.insert(new CaseComment(ParentId = caseId, CommentBody = body.left(4000), IsPublished = false), AccessLevel.SYSTEM_MODE);
	}
}
