/**
 * 20261102 TRi Posts Stripe payouts to the financial system (Exact Online): one journal entry per payout, built from
 * the payout's Stripe balance transactions (Batch_FinancialSystemStripePostings, Day step, one Business Entity per execute).
 *
 * Entry per payout (all lines on the payout's arrival date):
 *   - per payment / refund / dispute: the debtor with the raw Exact invoice number (OurRef), so Exact closes (or reopens)
 *     the invoice; the gross amount, never netted with the fee. Without a matching Exact invoice: the suspense account.
 *   - Stripe fees of the whole payout on the fee account (one line).
 *   - the payout amount on the transit account (Kruisposten), matched there with the bank line.
 * The lines balance by themselves (payments - fees = payout), so the Stripe clearing account nets to 0 per payout.
 * Settings on the Business Entity (FinSysStripe*); journal type decides the endpoint: bank journal → BankEntries,
 * general journal → GeneralJournalEntries. Exact sign convention: general journal AmountFC = debit; bank journal
 * AmountFC = amount into the bank (= credit on the line's account).
 *
 * Idempotent: a payout is posted once (FinSysPosting__c.StripePayoutId__c unique); before posting, Exact is searched for
 * an entry line carrying the payout id, so a run that posted but failed to save never posts twice.
 * Order in one execute: callouts first (Stripe, Exact), all DML at the end (no callout may follow a DML statement).
 */
public without sharing class Util_FinancialSystemStripePosting {

	public class PostingException extends Exception {}

	// per execute: ~4 callouts per payout (balance transactions, duplicate check, post) within the 100 callout limit
	@TestVisible
	private static Integer maxPayoutsPerRun = 15;

	private static final Set<String> FEE_TYPES = new Set<String>{ 'stripe_fee', 'tax_fee', 'application_fee' };
	private static final Integer JOURNAL_TYPE_BANK = 12;
	private static final Integer DESCRIPTION_LENGTH = 60;

	/** Retries failed postings and posts the new payouts of one Business Entity. */
	public static void run(Id businessEntityId) {
		Business_Entities__c be = [
			SELECT Id, Name, Reseller__c, PayProv_Account__c, FinSysStripeJournalCode__c, FinSysStripeFeeGLCode__c,
				FinSysStripeTransitGLCode__c, FinSysStripeSuspenseGLCode__c, FinSysStripeFeeVATCode__c, FinSysStripePostingFrom__c
			FROM Business_Entities__c WHERE Id = :businessEntityId WITH SYSTEM_MODE
		];
		Subscription25__Administration__c admin = Util_FinancialSystemStripePosting.administrationFor(be.Reseller__c);
		Event_Log__c log = Util_Event.getLog(null, 'S', 'E', 'FinSysPosting__c', 'postStripePayouts', be.Id, be.Name, null);

		List<FinSysPosting__c> postings = new List<FinSysPosting__c>();
		// by payout id: an SObject key changes once the record has an Id
		Map<String, List<FinSysPostingLine__c>> newLines = new Map<String, List<FinSysPostingLine__c>>();
		try {
			// a Stripe account shared by several Business Entities (Belgium uses the Netherlands account) is posted once,
			// by the configured entity with the lowest reseller code
			for (Business_Entities__c other : [
				SELECT Name, Reseller__c FROM Business_Entities__c
				WHERE PayProv_Account__c = :be.PayProv_Account__c AND FinSysStripePostingFrom__c != null AND Id != :be.Id
				WITH SYSTEM_MODE
			]) {
				// Reseller__c is a picklist: compared here, SOQL doesn't order picklist values as text
				if (String.isBlank(be.Reseller__c) || other.Reseller__c >= be.Reseller__c) continue;
				throw new PostingException('Stripe account of ' + be.Name + ' is already posted by ' + other.Name + ': clear FinSysStripePostingFrom__c on one of them');
			}
			Util_FinancialSystemStripePosting.checkSettings(be, admin);
			Settings s = Util_FinancialSystemStripePosting.loadSettings(be, admin);

			// 1. failed earlier: rebuilt from the stored lines (or from Stripe when building itself failed)
			for (FinSysPosting__c p : [
				SELECT Id, StripePayoutId__c, ArrivalDate__c, Amount__c, FeeAmount__c, CurrencyIsoCode, Attempts__c,
					(SELECT Id, StripeBalanceTransactionId__c, StripeType__c, Booking__c, FinSysAccountId__c, FinSysInvoiceNumber__c,
						Amount__c, FeeAmount__c, Description__c FROM Lines__r)
				FROM FinSysPosting__c
				WHERE Business_Entity__c = :be.Id AND Status__c = 'Failed' AND (NextAttempt__c = null OR NextAttempt__c <= :System.now())
				WITH SYSTEM_MODE ORDER BY ArrivalDate__c LIMIT :maxPayoutsPerRun
			]) {
				List<FinSysPostingLine__c> lines = p.Lines__r;
				if (lines.isEmpty()) {
					lines = Util_FinancialSystemStripePosting.buildLinesOrFail(be, admin, p);
					if (lines != null) newLines.put(p.StripePayoutId__c, lines);
				}
				if (lines != null) Util_FinancialSystemStripePosting.post(s, p, lines);
				postings.add(p);
			}

			// 2. new payouts from Stripe
			Integer room = maxPayoutsPerRun - postings.size();
			for (Map<String, Object> payout : Util_FinancialSystemStripePosting.newPayouts(be, room)) {
				FinSysPosting__c p = Util_FinancialSystemStripePosting.buildPosting(be, admin, payout);
				List<FinSysPostingLine__c> lines = Util_FinancialSystemStripePosting.buildLinesOrFail(be, admin, p);
				if (lines != null) {
					newLines.put(p.StripePayoutId__c, lines);
					Util_FinancialSystemStripePosting.post(s, p, lines);
				}
				postings.add(p);
			}
		} catch (Util_FinancialSystem.RateLimitException e) {
			log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			log.Message__c = e.getMessage();
		} catch (Exception e) {
			log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			log.Message__c = e.getMessage() + '\n' + e.getStackTraceString();
		}

		// 3. DML
		List<String> saveErrors = Util_FinancialSystemStripePosting.save(postings, newLines);
		Integer posted = 0;
		Integer failed = 0;
		for (FinSysPosting__c p : postings) {
			if (p.Status__c == 'Posted') posted++; else failed++;
		}
		log.Message__c = (String.isBlank(log.Message__c) ? '' : log.Message__c + '\n')
			+ 'Payouts posted: ' + posted + ', failed: ' + failed + (saveErrors.isEmpty() ? '' : '\nSave errors: ' + String.join(saveErrors, '\n'));
		if (failed > 0 || !saveErrors.isEmpty()) log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
		Util_FinancialSystem.saveLimits();
		Util_FinancialSystem.saveLogs(new List<Event_Log__c>{ log }, new Set<String>{ admin?.Subscription25__Named_Credential__c }, null);
	}

	// ── Settings ──────────────────────────────────────────────────────────────

	@TestVisible
	private class Settings {
		Subscription25__Administration__c admin;
		Business_Entities__c be;
		Boolean bankJournal;
		Map<String, String> glIdByCode = new Map<String, String>();
	}

	private static void checkSettings(Business_Entities__c be, Subscription25__Administration__c admin) {
		List<String> missing = new List<String>();
		if (admin == null) missing.add('Administration for reseller ' + be.Reseller__c);
		if (String.isBlank(be.PayProv_Account__c)) missing.add('Stripe account');
		if (String.isBlank(be.FinSysStripeJournalCode__c)) missing.add('journal code');
		if (String.isBlank(be.FinSysStripeFeeGLCode__c)) missing.add('fee G/L code');
		if (String.isBlank(be.FinSysStripeTransitGLCode__c)) missing.add('transit G/L code');
		if (String.isBlank(be.FinSysStripeSuspenseGLCode__c)) missing.add('suspense G/L code');
		if (!missing.isEmpty()) throw new PostingException('Stripe posting settings missing on ' + be.Name + ': ' + String.join(missing, ', '));
	}

	/** Journal type and the G/L account ids (the API wants ids, the Business Entity holds the codes). */
	private static Settings loadSettings(Business_Entities__c be, Subscription25__Administration__c admin) {
		Settings s = new Settings();
		s.be = be;
		s.admin = admin;
		String base = 'api/v1/' + admin.Subscription25__Twinfield_Company_Code__c + '/financial/';

		List<Object> journals = Util_FinancialSystemStripePosting.results(Util_FinancialSystem.doRequest(admin, base + 'Journals',
			new Map<String, String>{ '$select' => 'Code,Type', '$filter' => 'Code eq \'' + be.FinSysStripeJournalCode__c + '\'' }, 'GET', null, null));
		if (journals.isEmpty()) throw new PostingException('Journal ' + be.FinSysStripeJournalCode__c + ' not found in the financial system');
		s.bankJournal = Integer.valueOf(String.valueOf(((Map<String, Object>) journals[0]).get('Type'))) == JOURNAL_TYPE_BANK;

		Set<String> codes = new Set<String>{ be.FinSysStripeFeeGLCode__c, be.FinSysStripeTransitGLCode__c, be.FinSysStripeSuspenseGLCode__c };
		List<String> filter = new List<String>();
		for (String c : codes) filter.add('Code eq \'' + c + '\'');
		for (Object o : Util_FinancialSystemStripePosting.results(Util_FinancialSystem.doRequest(admin, base + 'GLAccounts',
				new Map<String, String>{ '$select' => 'ID,Code', '$filter' => String.join(filter, ' or ') }, 'GET', null, null))) {
			Map<String, Object> gl = (Map<String, Object>) o;
			s.glIdByCode.put(String.valueOf(gl.get('Code')).trim(), (String) gl.get('ID'));
		}
		for (String c : codes) {
			if (!s.glIdByCode.containsKey(c)) throw new PostingException('G/L account ' + c + ' not found in the financial system');
		}
		return s;
	}

	private static Subscription25__Administration__c administrationFor(String reseller) {
		List<Subscription25__Administration__c> admins = [
			SELECT Id, Name, Reseller__c, CurrencyIsoCode, Daily_Limit__c, FinancialRateLimitMaxPercentage__c, FinancialRateLimitRemaining__c,
				FinancialRateLimitResetOn__c, Acceptance_Environment_Available__c, Subscription25__Named_Credential__c,
				Subscription25__Twinfield_Company_Code__c
			FROM Subscription25__Administration__c WHERE Reseller__c = :reseller WITH SYSTEM_MODE LIMIT 1
		];
		return admins.isEmpty() ? null : admins[0];
	}

	// ── Stripe ────────────────────────────────────────────────────────────────

	/** Paid payouts since FinSysStripePostingFrom__c that have no posting yet, oldest first. */
	@TestVisible
	private static List<Map<String, Object>> newPayouts(Business_Entities__c be, Integer max) {
		List<Map<String, Object>> found = new List<Map<String, Object>>();
		if (max <= 0) return found;
		Long fromEpoch = Datetime.newInstanceGmt(be.FinSysStripePostingFrom__c, Time.newInstance(0, 0, 0, 0)).getTime() / 1000;
		String after = null;
		do {
			Map<String, Object> page = Svc_PaymentIntent.call('GET', '/v1/payouts?status=paid&limit=100&arrival_date[gte]=' + fromEpoch
				+ (after == null ? '' : '&starting_after=' + after), be.PayProv_Account__c, null, null);
			List<Object> data = (List<Object>) page.get('data');
			for (Object o : data) found.add((Map<String, Object>) o);
			after = (data.isEmpty() || page.get('has_more') != true) ? null : (String) ((Map<String, Object>) data[data.size() - 1]).get('id');
		} while (after != null && found.size() < 1000);

		Set<String> ids = new Set<String>();
		for (Map<String, Object> p : found) ids.add((String) p.get('id'));
		for (FinSysPosting__c existing : [SELECT StripePayoutId__c FROM FinSysPosting__c WHERE StripePayoutId__c IN :ids WITH SYSTEM_MODE]) {
			ids.remove(existing.StripePayoutId__c);
		}
		List<Map<String, Object>> result = new List<Map<String, Object>>();
		// Stripe lists newest first: post in arrival order
		for (Integer i = found.size() - 1; i >= 0 && result.size() < max; i--) {
			if (ids.contains((String) found[i].get('id'))) result.add(found[i]);
		}
		return result;
	}

	/** All balance transactions of a payout except the payout itself, with their source expanded. */
	@TestVisible
	private static List<Map<String, Object>> balanceTransactions(String stripeAccountId, String payoutId) {
		List<Map<String, Object>> txns = new List<Map<String, Object>>();
		String after = null;
		do {
			Map<String, Object> page = Svc_PaymentIntent.call('GET', '/v1/balance_transactions?payout=' + payoutId + '&limit=100&expand[]=data.source'
				+ (after == null ? '' : '&starting_after=' + after), stripeAccountId, null, null);
			List<Object> data = (List<Object>) page.get('data');
			for (Object o : data) {
				Map<String, Object> t = (Map<String, Object>) o;
				if (!'payout'.equals(t.get('type'))) txns.add(t);
			}
			after = (data.isEmpty() || page.get('has_more') != true) ? null : (String) ((Map<String, Object>) data[data.size() - 1]).get('id');
		} while (after != null);
		return txns;
	}

	// ── Build ─────────────────────────────────────────────────────────────────

	private static FinSysPosting__c buildPosting(Business_Entities__c be, Subscription25__Administration__c admin, Map<String, Object> payout) {
		return new FinSysPosting__c(
			StripePayoutId__c = (String) payout.get('id'),
			Business_Entity__c = be.Id,
			Administration__c = admin.Id,
			Status__c = 'Pending',
			ArrivalDate__c = Datetime.newInstance(Long.valueOf(String.valueOf(payout.get('arrival_date'))) * 1000).dateGmt(),
			Amount__c = Util_FinancialSystemStripePosting.money(payout.get('amount')),
			CurrencyIsoCode = ((String) payout.get('currency')).toUpperCase(),
			Attempts__c = 0
		);
	}

	/** buildLines; a payout that can't be built is saved as Failed (no lines) and rebuilt on the next attempt. */
	private static List<FinSysPostingLine__c> buildLinesOrFail(Business_Entities__c be, Subscription25__Administration__c admin, FinSysPosting__c p) {
		try {
			return Util_FinancialSystemStripePosting.buildLines(be, admin, p);
		} catch (Util_FinancialSystem.RateLimitException e) {
			throw e;
		} catch (Exception e) {
			Util_FinancialSystemStripePosting.markFailed(p, e);
			return null;
		}
	}

	/** One line per balance transaction; payments matched to their Exact invoice through the PaymentIntent. */
	@TestVisible
	private static List<FinSysPostingLine__c> buildLines(Business_Entities__c be, Subscription25__Administration__c admin, FinSysPosting__c p) {
		List<Map<String, Object>> txns = Util_FinancialSystemStripePosting.balanceTransactions(be.PayProv_Account__c, p.StripePayoutId__c);

		Set<String> intentIds = new Set<String>();
		for (Map<String, Object> t : txns) {
			String pi = Util_FinancialSystemStripePosting.paymentIntentOf(t);
			if (pi != null) intentIds.add(pi);
		}
		Map<String, Payment__c> paymentByIntent = new Map<String, Payment__c>();
		for (Payment__c pay : [
			SELECT Id, PayProv_PaymentIntentId__c, Account__c, Account__r.FinancialIdAccount__c, Invoice__c,
				Invoice__r.Subscription25__Invoice_Number__c, Invoice__r.FinSysInvoiceNumber__c, Invoice__r.Subscription25__Administration__c
			FROM Payment__c WHERE PayProv_PaymentIntentId__c IN :intentIds WITH SYSTEM_MODE
		]) {
			paymentByIntent.put(pay.PayProv_PaymentIntentId__c, pay);
		}

		List<FinSysPostingLine__c> lines = new List<FinSysPostingLine__c>();
		Decimal gross = 0;
		Decimal fees = 0;
		Decimal suspense = 0;
		for (Map<String, Object> t : txns) {
			String type = (String) t.get('type');
			String pi = Util_FinancialSystemStripePosting.paymentIntentOf(t);
			Object src = t.get('source');
			FinSysPostingLine__c l = new FinSysPostingLine__c(
				StripeBalanceTransactionId__c = (String) t.get('id'),
				StripeSourceId__c = src instanceof Map<String, Object> ? (String) ((Map<String, Object>) src).get('id') : (String) src,
				StripePaymentIntentId__c = pi,
				StripeType__c = type,
				Amount__c = Util_FinancialSystemStripePosting.money(t.get('amount')),
				FeeAmount__c = Util_FinancialSystemStripePosting.money(t.get('fee')),
				NetAmount__c = Util_FinancialSystemStripePosting.money(t.get('net')),
				CurrencyIsoCode = p.CurrencyIsoCode
			);
			fees += l.FeeAmount__c;

			if (FEE_TYPES.contains(type)) {
				// a Stripe fee movement (negative amount) is a cost, not part of the customers' gross
				l.Booking__c = 'Fee';
				fees -= l.Amount__c;
			} else {
				gross += l.Amount__c;
				Payment__c pay = pi == null ? null : paymentByIntent.get(pi);
				String reason = Util_FinancialSystemStripePosting.suspenseReason(pi, pay, admin);
				if (reason == null) {
					l.Booking__c = 'Invoice';
					l.Payment__c = pay.Id;
					l.Invoice__c = pay.Invoice__c;
					l.Account__c = pay.Account__c;
					l.FinSysAccountId__c = pay.Account__r.FinancialIdAccount__c;
					l.FinSysInvoiceNumber__c = pay.Invoice__r.FinSysInvoiceNumber__c;
					l.Description__c = ('Stripe ' + pi + ' ' + pay.Invoice__r.Subscription25__Invoice_Number__c).left(DESCRIPTION_LENGTH);
				} else {
					l.Booking__c = 'Suspense';
					l.SuspenseReason__c = reason.left(255);
					l.Payment__c = pay?.Id;
					l.Invoice__c = pay?.Invoice__c;
					l.Account__c = pay?.Account__c;
					l.Description__c = ('Stripe ' + type + ' ' + (pi != null ? pi : l.StripeSourceId__c)).left(DESCRIPTION_LENGTH);
					suspense += l.Amount__c;
				}
			}
			lines.add(l);
		}
		p.GrossAmount__c = gross;
		p.FeeAmount__c = fees;
		p.SuspenseAmount__c = suspense;
		if (gross - fees != p.Amount__c) {
			throw new PostingException('Payout ' + p.StripePayoutId__c + ' does not add up: gross ' + gross + ' - fees ' + fees + ' <> payout ' + p.Amount__c);
		}
		return lines;
	}

	/** Why a movement can't be booked on its invoice, or null when it can. */
	private static String suspenseReason(String pi, Payment__c pay, Subscription25__Administration__c admin) {
		if (pi == null) return 'No PaymentIntent on this Stripe movement';
		if (pay == null) return 'No Salesforce payment for ' + pi;
		if (pay.Invoice__c == null) return 'Payment has no invoice';
		if (String.isBlank(pay.Invoice__r.FinSysInvoiceNumber__c)) return 'Invoice ' + pay.Invoice__r.Subscription25__Invoice_Number__c + ' has no Exact invoice number yet';
		if (!pay.Invoice__r.FinSysInvoiceNumber__c.isNumeric()) return 'Exact invoice number ' + pay.Invoice__r.FinSysInvoiceNumber__c + ' is not numeric';
		if (pay.Invoice__r.Subscription25__Administration__c != admin.Id) return 'Invoice belongs to another administration';
		if (String.isBlank(pay.Account__r?.FinancialIdAccount__c)) return 'Account has no Exact id';
		return null;
	}

	private static String paymentIntentOf(Map<String, Object> txn) {
		Object src = txn.get('source');
		if (!(src instanceof Map<String, Object>)) return null;
		Object pi = ((Map<String, Object>) src).get('payment_intent');
		if (pi instanceof Map<String, Object>) return (String) ((Map<String, Object>) pi).get('id');
		return (String) pi;
	}

	// ── Exact ─────────────────────────────────────────────────────────────────

	/** Posts the entry (unless Exact already has it) and sets the posting's status; never throws except on a rate limit. */
	private static void post(Settings s, FinSysPosting__c p, List<FinSysPostingLine__c> lines) {
		try {
			String base = 'api/v1/' + s.admin.Subscription25__Twinfield_Company_Code__c + '/';
			Map<String, Object> existing = Util_FinancialSystemStripePosting.findExisting(s, p);
			if (existing == null) {
				String endpoint = s.bankJournal ? 'financialtransaction/BankEntries' : 'generaljournalentry/GeneralJournalEntries';
				String response = Util_FinancialSystem.doRequest(s.admin, base + endpoint, null, 'POST',
					JSON.serialize(Util_FinancialSystemStripePosting.entry(s, p, lines)), null);
				existing = (Map<String, Object>) JSON.deserializeUntyped(response);
			}
			p.Status__c = 'Posted';
			p.FinSysEntryId__c = (String) existing.get('EntryID');
			p.FinSysEntryNumber__c = existing.get('EntryNumber') == null ? null : String.valueOf(existing.get('EntryNumber'));
			p.LastError__c = null;
			p.NextAttempt__c = null;
		} catch (Util_FinancialSystem.RateLimitException e) {
			throw e;
		} catch (Exception e) {
			Util_FinancialSystemStripePosting.markFailed(p, e);
		}
	}

	private static void markFailed(FinSysPosting__c p, Exception e) {
		p.Status__c = 'Failed';
		p.Attempts__c = (p.Attempts__c == null ? 0 : p.Attempts__c) + 1;
		p.NextAttempt__c = System.now().addHours(12);
		p.LastError__c = e.getMessage().left(32768);
	}

	/** The entry Exact already has for this payout (a run that posted but could not save), or null. */
	private static Map<String, Object> findExisting(Settings s, FinSysPosting__c p) {
		List<Object> found = Util_FinancialSystemStripePosting.results(Util_FinancialSystem.doRequest(s.admin,
			'api/v1/' + s.admin.Subscription25__Twinfield_Company_Code__c + '/financialtransaction/TransactionLines',
			new Map<String, String>{ '$select' => 'EntryID,EntryNumber', '$top' => '1',
				'$filter' => 'JournalCode eq \'' + s.be.FinSysStripeJournalCode__c + '\' and Description eq \'' + Util_FinancialSystemStripePosting.transitDescription(p) + '\'' },
			'GET', null, null));
		return found.isEmpty() ? null : (Map<String, Object>) found[0];
	}

	/** Exact entry body: debtor / suspense lines, one fee line, one transit line. */
	@TestVisible
	private static Map<String, Object> entry(Settings s, FinSysPosting__c p, List<FinSysPostingLine__c> lines) {
		String day = Datetime.newInstanceGmt(p.ArrivalDate__c, Time.newInstance(12, 0, 0, 0)).formatGmt('yyyy-MM-dd');
		List<Object> out = new List<Object>();
		Decimal feeDebit = 0;
		for (FinSysPostingLine__c l : lines) {
			feeDebit += l.FeeAmount__c;
			if (l.Booking__c == 'Fee') {
				feeDebit -= l.Amount__c;
				continue;
			}
			Map<String, Object> line = new Map<String, Object>{ 'Date' => day, 'Description' => l.Description__c };
			if (l.Booking__c == 'Invoice') {
				line.put('Account', l.FinSysAccountId__c);
				line.put('OurRef', Integer.valueOf(l.FinSysInvoiceNumber__c));
			} else {
				line.put('GLAccount', s.glIdByCode.get(s.be.FinSysStripeSuspenseGLCode__c));
			}
			// a payment credits the debtor
			line.put('AmountFC', Util_FinancialSystemStripePosting.amount(s, -l.Amount__c));
			out.add(line);
		}
		if (feeDebit != 0) {
			Map<String, Object> fee = new Map<String, Object>{
				'Date' => day, 'GLAccount' => s.glIdByCode.get(s.be.FinSysStripeFeeGLCode__c),
				'AmountFC' => Util_FinancialSystemStripePosting.amount(s, feeDebit),
				'Description' => ('Stripe fees ' + p.StripePayoutId__c).left(DESCRIPTION_LENGTH)
			};
			if (String.isNotBlank(s.be.FinSysStripeFeeVATCode__c)) fee.put('VATCode', s.be.FinSysStripeFeeVATCode__c);
			out.add(fee);
		}
		out.add(new Map<String, Object>{
			'Date' => day, 'GLAccount' => s.glIdByCode.get(s.be.FinSysStripeTransitGLCode__c),
			'AmountFC' => Util_FinancialSystemStripePosting.amount(s, p.Amount__c),
			'Description' => Util_FinancialSystemStripePosting.transitDescription(p)
		});
		return new Map<String, Object>{
			'JournalCode' => s.be.FinSysStripeJournalCode__c,
			'Currency' => p.CurrencyIsoCode,
			'FinancialYear' => p.ArrivalDate__c.year(),
			'FinancialPeriod' => p.ArrivalDate__c.month(),
			(s.bankJournal ? 'BankEntryLines' : 'GeneralJournalEntryLines') => out
		};
	}

	/** Debit amount → AmountFC: as is on a general journal; on a bank journal AmountFC is money into the bank (the opposite side). */
	private static Decimal amount(Settings s, Decimal debit) {
		return s.bankJournal ? -debit : debit;
	}

	@TestVisible
	private static String transitDescription(FinSysPosting__c p) {
		return ('Stripe payout ' + p.StripePayoutId__c).left(DESCRIPTION_LENGTH);
	}

	// ── Save ──────────────────────────────────────────────────────────────────

	private static List<String> save(List<FinSysPosting__c> postings, Map<String, List<FinSysPostingLine__c>> newLines) {
		List<String> errors = new List<String>();
		if (postings.isEmpty()) return errors;
		List<Database.UpsertResult> results = Database.upsert(postings, FinSysPosting__c.StripePayoutId__c, false, AccessLevel.SYSTEM_MODE);
		List<FinSysPostingLine__c> lines = new List<FinSysPostingLine__c>();
		for (Integer i = 0; i < results.size(); i++) {
			FinSysPosting__c p = postings[i];
			if (!results[i].isSuccess()) {
				// the Exact entry (if posted) is found again by findExisting on the next run
				errors.add(p.StripePayoutId__c + ' (Exact entry ' + p.FinSysEntryNumber__c + '): ' + results[i].getErrors()[0].getMessage());
				continue;
			}
			if (newLines.containsKey(p.StripePayoutId__c)) {
				for (FinSysPostingLine__c l : newLines.get(p.StripePayoutId__c)) {
					l.Posting__c = p.Id;
					lines.add(l);
				}
			}
		}
		for (Database.UpsertResult r : Database.upsert(lines, FinSysPostingLine__c.StripeBalanceTransactionId__c, false, AccessLevel.SYSTEM_MODE)) {
			if (!r.isSuccess()) errors.add('Line: ' + r.getErrors()[0].getMessage());
		}
		return errors;
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	/** Stripe amount in the smallest unit (cents / pence) → currency amount. */
	private static Decimal money(Object minor) {
		return minor == null ? 0 : (Decimal.valueOf(String.valueOf(minor)) / 100).setScale(2);
	}

	private static List<Object> results(String response) {
		Object parsed = String.isBlank(response) ? null : JSON.deserializeUntyped(response);
		if (parsed instanceof Map<String, Object> && ((Map<String, Object>) parsed).get('results') instanceof List<Object>) {
			return (List<Object>) ((Map<String, Object>) parsed).get('results');
		}
		return parsed instanceof List<Object> ? (List<Object>) parsed : new List<Object>();
	}
}
