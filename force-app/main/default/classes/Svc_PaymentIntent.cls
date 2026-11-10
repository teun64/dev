/**
 * One Stripe intent per Payment__c, created once and reused (Stripe best practice), so opening the payment link
 * again never creates a second PaymentIntent.
 *   - BACS (no mandate yet): PaymentIntent with setup_future_usage=off_session, confirmed by the customer on the
 *     payment page (BACS mandates can't be collected with a SetupIntent in the Payment Element).
 *   - SEPA / ACH (no mandate yet): SetupIntent that collects the mandate; Batch_ProcessPayments debits later.
 * The intent id lives on PayProv_PaymentIntentId__c / PayProv_SetupIntentId__c. A stored intent is looked up in
 * Stripe and its live status decides: still open → reuse, processing/succeeded → done, canceled → one new intent.
 * Every intent also offers card (with Apple Pay / Google Pay as wallets): a saved card is charged off-session the same
 * way as a mandate, without one. The saved method's type lands on Account.PayProv_PaymentMethodType__c (TypeJob).
 * Created upfront by afl_Payment_Direct_Debit_Setup (prepare → PrepareJob, async because that flow may already
 * have done DML) and on demand by Ctrl_Payment; both use the same idempotency key and request body, so a race
 * between them still returns one intent.
 * 20261102 TRi every intent carries the financial system (Exact) references for invoice matching (finSysParams):
 * FinSysAccountId, FinSysAccountDebtorNumber, FinSysDivision and, on a PaymentIntent, FinSysInvoiceId,
 * FinSysInvoiceNumber (raw Exact number, without the Salesforce prefix) + description "Invoice <Invoice Number>".
 * Callers select FINSYS fields on the payment (queryPayments, Ctrl_Payment, Batch_ProcessPayments).
 */
public without sharing class Svc_PaymentIntent {

    public enum Action { REUSE, PROCESSED, CREATE }

    public class Checkout {
        public String  mode;            // 'payment' (BACS) or 'setup' (SEPA/ACH)
        public String  clientSecret;
        public Boolean processed = false;
        public String  intentId;
        public Boolean isNew = false;   // caller stores intentId on the payment
        public String  bankTransferUrl; // pay-now: waiting for the customer's bank transfer (Stripe's hosted instructions)
    }

    public class StripeException extends Exception {}

    private static final Integer JOB_CHUNK = 40;

    public static final String CARD = 'card';

    // Off-session charge the customer's bank wants authenticated (3-D Secure): the payment waits for the customer
    public static final String STATUS_ACTION_REQUIRED = 'Action Required';
    public static final String AUTHENTICATION_REQUIRED = 'authentication_required';

    /** The parts of a Stripe error the payment flow acts on. */
    public class StripeError {
        public String code;
        public String declineCode;
        public String paymentIntentId;
        public String paymentMethodId;
    }

    /**
     * stripeGC throws non-2xx answers as "Stripe callout error: {json}"; this reads code and intent back out of it.
     * Null when the message carries no Stripe error JSON (e.g. a configuration error).
     */
    public static StripeError stripeError(Exception e) {
        String message = e?.getMessage();
        if (String.isBlank(message) || !message.contains('{')) return null;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(message.substring(message.indexOf('{')));
            Map<String, Object> err  = (Map<String, Object>) body.get('error');
            if (err == null) return null;
            StripeError se = new StripeError();
            se.code = (String) err.get('code');
            se.declineCode = (String) err.get('decline_code');
            Map<String, Object> intent = (Map<String, Object>) err.get('payment_intent');
            if (intent != null) se.paymentIntentId = (String) intent.get('id');
            Map<String, Object> method = (Map<String, Object>) err.get('payment_method');
            if (method != null) se.paymentMethodId = (String) method.get('id');
            return se;
        } catch (Exception parseError) {
            return null;
        }
    }

    /**
     * Payment link token (Payment__c.externalId__c), same format as afl_Payment_Direct_Debit_Setup: 32 hex (MD5).
     * Derived from payment + intent so the batch and the webhook, which can both set Action Required, write the same one.
     */
    public static String newToken(Id paymentId, String paymentIntentId) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', Blob.valueOf(paymentId + '-' + paymentIntentId)));
    }

    /** A saved method the batch can charge off-session: a card, or a direct debit method with its mandate. */
    public static Boolean hasUsableMethod(Account a) {
        if (a == null || String.isBlank(a.PayProv_PaymentMethodId__c)) return false;
        return CARD.equals(a.PayProv_PaymentMethodType__c) || String.isNotBlank(a.PayProv_MandateId__c);
    }

    // ── Upfront creation (afl_Payment_Direct_Debit_Setup) ────────────────────
    @InvocableMethod(label='Prepare Payment Provider Intent' description='Creates (or reuses) the Stripe intent of each payment asynchronously.')
    public static void prepare(List<Id> paymentIds) {
        Set<Id> ids = new Set<Id>();
        for (Id i : paymentIds) if (i != null) ids.add(i);
        if (!ids.isEmpty()) System.enqueueJob(new PrepareJob(new List<Id>(ids)));
    }

    public class PrepareJob implements Queueable, Database.AllowsCallouts {
        private final List<Id> paymentIds;
        public PrepareJob(List<Id> paymentIds) { this.paymentIds = paymentIds; }

        public void execute(QueueableContext ctx) {
            List<Id> now  = new List<Id>();
            List<Id> rest = new List<Id>();
            for (Id i : paymentIds) (now.size() < JOB_CHUNK ? now : rest).add(i);

            List<Payment__c> updates = new List<Payment__c>();
            for (Payment__c p : queryPayments(new Set<Id>(now))) {
                // with a mandate on file the batch collects off-session: no customer-facing intent needed
                if (hasUsableMethod(p.Account__r)) continue;
                if (String.isBlank(p.Account__r?.PayProv_CustomerId__c)) continue;
                if (p.Status__c == 'Processing' || p.Status__c == 'Paid' || p.Status__c == 'Collected') continue;
                try {
                    Checkout c = getOrCreate(p, businessEntityFor(p));
                    Payment__c u = storeUpdate(p, c);
                    if (u != null) updates.add(u);
                } catch (Exception e) {
                    // the payment page retries on demand
                    System.debug(LoggingLevel.ERROR, 'Svc_PaymentIntent.PrepareJob ' + p.Name + ': ' + e.getMessage());
                }
            }
            if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
            if (!rest.isEmpty() && !Test.isRunningTest()) System.enqueueJob(new PrepareJob(rest));
        }
    }

    // ── Get or create the customer-facing intent ──────────────────────────────
    public static Checkout getOrCreate(Payment__c p, Business_Entities__c businessEntity) {
        String accountId = businessEntity?.PayProv_Account__c;
        String ddMethod  = businessEntity?.PayProv_DirectDebit_PaymentMethod__c;
        if (String.isBlank(ddMethod)) ddMethod = 'sepa_debit';

        Checkout c = new Checkout();
        Boolean isBacs  = 'bacs_debit'.equals(ddMethod);
        c.mode          = isBacs ? 'payment' : 'setup';
        String endpoint = isBacs ? '/v1/payment_intents' : '/v1/setup_intents';
        String stored   = isBacs ? p.PayProv_PaymentIntentId__c : p.PayProv_SetupIntentId__c;
        Integer amount  = amountCents(p.Amount_Gross__c);

        if (String.isNotBlank(stored)) {
            Map<String, Object> intent = call('GET', endpoint + '/' + stored, accountId, null, null);
            Action a = decide((String) intent.get('status'));
            if (a == Action.PROCESSED) {
                c.processed = true;
                c.intentId  = stored;
                return c;
            }
            if (a == Action.REUSE) {
                List<String> changes = new List<String>();
                if (isBacs && intent.get('amount') != null && Integer.valueOf(String.valueOf(intent.get('amount'))) != amount) {
                    changes.add('amount=' + amount);
                }
                // 20261028 TRi an intent created before card / Apple Pay / Google Pay (phase 2) only offers direct debit: add card
                String types = missingTypesUpdate(intent, ddMethod);
                if (types != null) changes.add(types);
                // 20261102 TRi created before the Exact ids were known (or before they were sent at all): add them
                String finSys = finSysUpdate(intent, p, isBacs);
                if (finSys != null) changes.add(finSys);
                if (!changes.isEmpty()) {
                    intent = call('POST', endpoint + '/' + stored, accountId, String.join(changes, '&'), null);
                }
                c.intentId     = stored;
                c.clientSecret = (String) intent.get('client_secret');
                return c;
            }
        }

        String body = isBacs
            ? paymentIntentBody(p.Id, p.Account__r?.PayProv_CustomerId__c, amount, p.CurrencyIsoCode, ddMethod)
            : setupIntentBody(p.Id, p.Account__r?.PayProv_CustomerId__c, ddMethod);
        List<String> finSys = finSysParams(p, isBacs);
        if (!finSys.isEmpty()) body += '&' + String.join(finSys, '&');
        // a canceled predecessor needs its own key, otherwise Stripe would hand back the canceled intent
        Map<String, Object> created = call('POST', endpoint, accountId, body,
            'payprov-' + p.Id + '-' + (String.isBlank(stored) ? 'first' : stored));
        c.intentId     = (String) created.get('id');
        c.clientSecret = (String) created.get('client_secret');
        c.isNew        = c.intentId != stored;
        return c;
    }

    // ── Dunning: pay now on the payment page ──────────────────────────────────
    public static final String PAY_NOW = 'paynow';

    /**
     * A failed payment in the dunning cycle (Svc_PaymentDunning) is paid on the payment page: one on-session
     * PaymentIntent, tagged metadata[Checkout]=paynow (payNowTypes):
     *   - Pay (the saved method stays): what pays right away - card (with Apple Pay / Google Pay), iDEAL (EUR, Dutch
     *     customers) and bank transfer (Stripe customer balance); no direct debit, it would only tell days later whether
     *     it failed again. Only a card is saved for the next invoices; iDEAL and a bank transfer are one-off.
     *   - Renew (the saved method was refused for good): a renewal of the recurring method - the business entity's
     *     direct debit or a card, saved for the next invoices (setup_future_usage); no iDEAL or bank transfer.
     * A later visit reuses the pay-now intent; one that waits for a bank transfer returns its instructions instead.
     * Any other open intent of the payment (the declined off-session charge, an unconfirmed 3-D Secure one, a pay-now
     * intent with other methods) is canceled first; a succeeded one of a reversed payment gets a new one too.
     */
    public static Checkout getOrCreatePayNow(Payment__c p, Business_Entities__c businessEntity) {
        String accountId = businessEntity?.PayProv_Account__c;
        List<String> types = payNowTypes(p, businessEntity?.PayProv_DirectDebit_PaymentMethod__c);
        Boolean renew = p.Dunning_Action__c == Svc_PaymentDunning.ACTION_RENEW;

        Checkout c = new Checkout();
        c.mode = 'payment';
        String stored = p.PayProv_PaymentIntentId__c;
        if (String.isNotBlank(stored)) {
            Map<String, Object> intent   = call('GET', '/v1/payment_intents/' + stored, accountId, null, null);
            Map<String, Object> metadata = (Map<String, Object>) intent.get('metadata');
            Boolean payNow = metadata != null && PAY_NOW.equals(metadata.get('Checkout'));
            Action a = decide((String) intent.get('status'));
            String transferUrl = bankTransferUrl(intent);
            if (payNow && a == Action.PROCESSED) {
                c.processed = true;
                c.intentId  = stored;
                return c;
            }
            if (payNow && transferUrl != null) {
                c.intentId        = stored;
                c.bankTransferUrl = transferUrl;
                return c;
            }
            List<Object> offered = (List<Object>) intent.get('payment_method_types');
            if (payNow && a == Action.REUSE && offered != null && new Set<Object>(offered).equals(new Set<Object>((List<Object>) types))) {
                c.intentId     = stored;
                c.clientSecret = (String) intent.get('client_secret');
                return c;
            }
            if (a == Action.REUSE) {
                call('POST', '/v1/payment_intents/' + stored + '/cancel', accountId, 'cancellation_reason=abandoned', null);
            }
        }

        List<String> body = new List<String>{
            'amount=' + amountCents(p.Amount_Gross__c),
            'currency=' + p.CurrencyIsoCode.toLowerCase(),
            'customer=' + p.Account__r?.PayProv_CustomerId__c
        };
        for (String t : types) body.add('payment_method_types[]=' + t);
        if (renew) {
            // the new recurring method (direct debit or card) is saved for the next invoices
            body.add('setup_future_usage=off_session');
        } else {
            // only a card is saved; iDEAL and a bank transfer are one-off payments
            body.add('payment_method_options[card][setup_future_usage]=off_session');
            body.add('payment_method_options[customer_balance][funding_type]=bank_transfer');
            if ('GBP'.equalsIgnoreCase(p.CurrencyIsoCode)) {
                body.add('payment_method_options[customer_balance][bank_transfer][type]=gb_bank_transfer');
            } else {
                body.add('payment_method_options[customer_balance][bank_transfer][type]=eu_bank_transfer');
                body.add('payment_method_options[customer_balance][bank_transfer][eu_bank_transfer][country]=' + transferCountry(p));
            }
        }
        body.add('metadata[PaymentID]=' + p.Id);
        body.add('metadata[PaymentType]=Direct Debit');
        body.add('metadata[Checkout]=' + PAY_NOW);
        body.addAll(finSysParams(p, true));
        Map<String, Object> created = call('POST', '/v1/payment_intents', accountId, String.join(body, '&'),
            'payprov-' + p.Id + '-' + PAY_NOW + '-' + (String.isBlank(stored) ? 'first' : stored));
        c.intentId     = (String) created.get('id');
        c.clientSecret = (String) created.get('client_secret');
        c.isNew        = c.intentId != stored;
        return c;
    }

    public static final String IDEAL = 'ideal';
    private static final Set<String> EU_TRANSFER_COUNTRIES = new Set<String>{ 'BE', 'DE', 'ES', 'FR', 'IE', 'NL' };

    /** Renew: the direct debit method + card. Pay: card, iDEAL for a Dutch customer paying in EUR, bank transfer. */
    @TestVisible
    private static List<String> payNowTypes(Payment__c p, String ddMethod) {
        if (p.Dunning_Action__c == Svc_PaymentDunning.ACTION_RENEW) {
            return new List<String>{ String.isBlank(ddMethod) ? 'sepa_debit' : ddMethod, CARD };
        }
        List<String> types = new List<String>{ CARD };
        if ('EUR'.equalsIgnoreCase(p.CurrencyIsoCode) && 'NL'.equals(p.Account__r?.BillingCountryCode)) types.add(IDEAL);
        types.add('customer_balance');
        return types;
    }

    // EU bank transfers need the country of the bank account Stripe hands out: the customer's, else NL
    private static String transferCountry(Payment__c p) {
        String country = p.Account__r?.BillingCountryCode;
        return EU_TRANSFER_COUNTRIES.contains(country) ? country : 'NL';
    }

    /** Hosted bank transfer instructions of an intent that waits for the customer's transfer, else null. */
    @TestVisible
    private static String bankTransferUrl(Map<String, Object> intent) {
        Map<String, Object> next = (Map<String, Object>) intent?.get('next_action');
        Map<String, Object> transfer = next == null ? null : (Map<String, Object>) next.get('display_bank_transfer_instructions');
        return transfer == null ? null : (String) transfer.get('hosted_instructions_url');
    }

    @TestVisible private static final String RENEWAL = 'renewal';

    /**
     * The saved card expires before the payment's collection date (Batch_CardExpiryCheck): a SetupIntent that saves new
     * details without charging anything (card, plus the direct debit method except Bacs, which can't be set up without
     * a payment). Batch_ProcessPayments collects with them on the collection date. Tagged metadata[Checkout]=renewal.
     */
    public static Checkout getOrCreateRenewal(Payment__c p, Business_Entities__c businessEntity) {
        String accountId = businessEntity?.PayProv_Account__c;
        String ddMethod  = businessEntity?.PayProv_DirectDebit_PaymentMethod__c;
        if (String.isBlank(ddMethod)) ddMethod = 'sepa_debit';

        Checkout c = new Checkout();
        c.mode = 'setup';
        String stored = p.PayProv_SetupIntentId__c;
        if (String.isNotBlank(stored)) {
            Map<String, Object> intent   = call('GET', '/v1/setup_intents/' + stored, accountId, null, null);
            Map<String, Object> metadata = (Map<String, Object>) intent.get('metadata');
            Action a = decide((String) intent.get('status'));
            if (metadata != null && RENEWAL.equals(metadata.get('Checkout')) && a != Action.CREATE) {
                c.intentId     = stored;
                c.processed    = a == Action.PROCESSED;
                c.clientSecret = (String) intent.get('client_secret');
                return c;
            }
        }
        List<String> body = new List<String>{
            'customer=' + p.Account__r?.PayProv_CustomerId__c,
            'usage=off_session',
            'payment_method_types[]=' + CARD,
            'metadata[PaymentID]=' + p.Id,
            'metadata[Checkout]=' + RENEWAL
        };
        if (!'bacs_debit'.equals(ddMethod)) body.add(2, 'payment_method_types[]=' + ddMethod);
        body.addAll(finSysParams(p, false));
        Map<String, Object> created = call('POST', '/v1/setup_intents', accountId, String.join(body, '&'),
            'payprov-' + p.Id + '-' + RENEWAL + '-' + (String.isBlank(stored) ? 'first' : stored));
        c.intentId     = (String) created.get('id');
        c.clientSecret = (String) created.get('client_secret');
        c.isNew        = c.intentId != stored;
        return c;
    }

    /** payment_method_types update for a reused intent that lacks card, or null when it already offers it. */
    @TestVisible
    private static String missingTypesUpdate(Map<String, Object> intent, String ddMethod) {
        List<Object> types = (List<Object>) intent?.get('payment_method_types');
        if (types == null || types.contains(CARD)) return null;
        return 'payment_method_types[]=' + ddMethod + '&payment_method_types[]=' + CARD;
    }

    /** Field update that stores a newly created intent on the payment, or null when nothing changed. */
    public static Payment__c storeUpdate(Payment__c p, Checkout c) {
        if (c == null || !c.isNew || String.isBlank(c.intentId)) return null;
        Payment__c u = new Payment__c(Id = p.Id);
        if ('payment'.equals(c.mode)) u.PayProv_PaymentIntentId__c = c.intentId;
        else                          u.PayProv_SetupIntentId__c   = c.intentId;
        return u;
    }

    /** Live Stripe status of a stored intent → what to do with it. Unknown statuses never create a second intent. */
    @TestVisible
    public static Action decide(String status) {
        if (String.isBlank(status) || status == 'canceled') return Action.CREATE;
        if (status == 'requires_payment_method' || status == 'requires_confirmation' || status == 'requires_action') return Action.REUSE;
        return Action.PROCESSED;
    }

    @TestVisible
    private static String paymentIntentBody(Id paymentId, String customerId, Integer amount, String currencyCode, String ddMethod) {
        return String.join(new List<String>{
            'amount=' + amount,
            'currency=' + currencyCode.toLowerCase(),
            'customer=' + customerId,
            'payment_method_types[]=' + ddMethod,
            'payment_method_types[]=' + CARD,
            // first BACS payment also creates the mandate for later off-session debits
            'setup_future_usage=off_session',
            'metadata[PaymentID]=' + paymentId,
            'metadata[PaymentType]=Direct Debit'
        }, '&');
    }

    @TestVisible
    private static String setupIntentBody(Id paymentId, String customerId, String ddMethod) {
        return String.join(new List<String>{
            'customer=' + customerId,
            'usage=off_session',
            'payment_method_types[]=' + ddMethod,
            'payment_method_types[]=' + CARD,
            'metadata[PaymentID]=' + paymentId
        }, '&');
    }

    // ── Financial system (Exact) references ───────────────────────────────────
    // fixed order: the same payment always gives the same body (idempotency keys)
    private static final List<String> FINSYS_KEYS = new List<String>{
        'FinSysAccountId', 'FinSysAccountDebtorNumber', 'FinSysInvoiceId', 'FinSysInvoiceNumber', 'FinSysDivision'
    };

    /**
     * Exact references of the payment: blank values are left out, the invoice ones only for a PaymentIntent, and the
     * division (which makes ids and numbers unambiguous) only next to at least one of them.
     */
    @TestVisible
    private static Map<String, String> finSysMetadata(Payment__c p, Boolean isPaymentIntent) {
        Map<String, String> m = new Map<String, String>{
            'FinSysAccountId'           => p.Account__r?.FinancialIdAccount__c,
            'FinSysAccountDebtorNumber' => p.Account__r?.FinancialDebtorNumber__c?.trim()
        };
        if (isPaymentIntent) {
            m.put('FinSysInvoiceId',     p.Invoice__r?.FinSysInvoiceId__c);
            m.put('FinSysInvoiceNumber', p.Invoice__r?.FinSysInvoiceNumber__c);
        }
        Map<String, String> result = new Map<String, String>();
        for (String k : FINSYS_KEYS) if (String.isNotBlank(m.get(k))) result.put(k, m.get(k));
        String division = p.Administration__r?.Subscription25__Twinfield_Company_Code__c;
        if (!result.isEmpty() && String.isNotBlank(division)) result.put('FinSysDivision', division);
        return result;
    }

    /** Form-encoded metadata (+ description on a PaymentIntent) for a request body; empty when nothing is known. */
    public static List<String> finSysParams(Payment__c p, Boolean isPaymentIntent) {
        List<String> params = new List<String>();
        Map<String, String> m = finSysMetadata(p, isPaymentIntent);
        for (String k : FINSYS_KEYS) {
            if (m.containsKey(k)) params.add('metadata[' + k + ']=' + EncodingUtil.urlEncode(m.get(k), 'UTF-8'));
        }
        String invoiceNumber = p.Invoice__r?.Subscription25__Invoice_Number__c;
        if (isPaymentIntent && String.isNotBlank(invoiceNumber)) {
            params.add('description=' + EncodingUtil.urlEncode('Invoice ' + invoiceNumber, 'UTF-8'));
        }
        return params;
    }

    /** Update for a reused intent whose Exact references are missing or outdated, or null when they're current. */
    @TestVisible
    private static String finSysUpdate(Map<String, Object> intent, Payment__c p, Boolean isPaymentIntent) {
        Map<String, Object> current = (Map<String, Object>) intent?.get('metadata');
        Map<String, String> wanted = finSysMetadata(p, isPaymentIntent);
        for (String k : wanted.keySet()) {
            if (current == null || !wanted.get(k).equals(String.valueOf(current.get(k)))) {
                return String.join(finSysParams(p, isPaymentIntent), '&');
            }
        }
        return null;
    }

    /** Writes the Exact references onto an existing PaymentIntent: metadata + description only, nothing else changes. */
    public static void updateFinSysMetadata(String stripeAccountId, Payment__c p) {
        List<String> params = finSysParams(p, true);
        if (params.isEmpty() || String.isBlank(p.PayProv_PaymentIntentId__c)) return;
        call('POST', '/v1/payment_intents/' + p.PayProv_PaymentIntentId__c, stripeAccountId, String.join(params, '&'), null);
    }

    /** Writes the account's Exact references (FinSysAccountId, FinSysAccountDebtorNumber, FinSysDivision) onto its Stripe Customer. */
    public static void updateCustomerFinSysMetadata(String stripeAccountId, Payment__c p) {
        List<String> params = finSysParams(p, false);
        if (params.isEmpty() || String.isBlank(p.Account__r?.PayProv_CustomerId__c)) return;
        call('POST', '/v1/customers/' + p.Account__r.PayProv_CustomerId__c, stripeAccountId, String.join(params, '&'), null);
    }

    public static Integer amountCents(Decimal amount) {
        return amount != null ? (amount * 100).round(System.RoundingMode.HALF_UP).intValue() : 0;
    }

    // ── Saved payment method type ─────────────────────────────────────────────
    /** A saved Stripe payment method (type, card details): webhook payloads only carry its id. */
    public static Map<String, Object> paymentMethod(String stripeAccountId, String paymentMethodId) {
        return call('GET', '/v1/payment_methods/' + paymentMethodId, stripeAccountId, null, null);
    }

    /** Type of a saved Stripe payment method (card, sepa_debit, bacs_debit, …). */
    public static String paymentMethodType(String stripeAccountId, String paymentMethodId) {
        return (String) paymentMethod(stripeAccountId, paymentMethodId).get('type');
    }

    /**
     * Card expiry (last day of the expiry month) and wallet of a saved method onto the Account update. A wallet card
     * (Apple Pay / Google Pay) gets no expiry: the card network renews its token. Not a card: both empty.
     */
    public static void applyCardDetails(Account u, Map<String, Object> method) {
        Map<String, Object> card   = CARD.equals(method?.get('type')) ? (Map<String, Object>) method.get('card') : null;
        Map<String, Object> wallet = card == null ? null : (Map<String, Object>) card.get('wallet');
        u.PayProv_CardWallet__c = wallet == null ? null : (String) wallet.get('type');
        u.PayProv_CardExpiry__c = null;
        if (card != null && wallet == null && card.get('exp_year') != null && card.get('exp_month') != null) {
            Date first = Date.newInstance(Integer.valueOf(String.valueOf(card.get('exp_year'))), Integer.valueOf(String.valueOf(card.get('exp_month'))), 1);
            u.PayProv_CardExpiry__c = first.addMonths(1).addDays(-1);
        }
    }

    /**
     * Stores the type of a newly saved payment method on the Account (Svc_StripeEventProcessor runs in a trigger and
     * can't call out). A card has no mandate, so a mandate left from an earlier direct debit method is cleared.
     * 20261109 TRi also the card's expiry and wallet (Batch_CardExpiryCheck), and the mandate of a direct debit method
     * saved by a payment (the pay-now link): a SEPA mandate created that way sends no mandate event, and the Account
     * would keep the previous method's mandate. It is read from the intent's charge.
     */
    public class TypeJob implements Queueable, Database.AllowsCallouts {
        private final Map<Id, String> paymentMethodByAccount;
        private final Map<Id, String> stripeAccountByAccount;
        private final Map<Id, String> intentByAccount;
        private final Set<Id> payNowAccounts;
        public TypeJob(Map<Id, String> paymentMethodByAccount, Map<Id, String> stripeAccountByAccount) {
            this(paymentMethodByAccount, stripeAccountByAccount, new Map<Id, String>(), new Set<Id>());
        }
        public TypeJob(Map<Id, String> paymentMethodByAccount, Map<Id, String> stripeAccountByAccount, Map<Id, String> intentByAccount) {
            this(paymentMethodByAccount, stripeAccountByAccount, intentByAccount, new Set<Id>());
        }
        public TypeJob(Map<Id, String> paymentMethodByAccount, Map<Id, String> stripeAccountByAccount, Map<Id, String> intentByAccount, Set<Id> payNowAccounts) {
            this.paymentMethodByAccount = paymentMethodByAccount;
            this.stripeAccountByAccount = stripeAccountByAccount;
            this.intentByAccount        = intentByAccount == null ? new Map<Id, String>() : intentByAccount;
            this.payNowAccounts         = payNowAccounts == null ? new Set<Id>() : payNowAccounts;
        }

        public void execute(QueueableContext ctx) {
            List<Account> updates = new List<Account>();
            for (Account a : [SELECT Id, PayProv_PaymentMethodId__c FROM Account WHERE Id IN :paymentMethodByAccount.keySet() WITH SYSTEM_MODE]) {
                String pm = paymentMethodByAccount.get(a.Id);
                if (payNowAccounts.contains(a.Id)) {
                    try {
                        Account u = payNowMethod(a.Id, pm);
                        if (u != null) updates.add(u);
                    } catch (Exception e) {
                        System.debug(LoggingLevel.ERROR, 'Svc_PaymentIntent.TypeJob pay-now ' + a.Id + ': ' + e.getMessage());
                    }
                    continue;
                }
                if (pm != a.PayProv_PaymentMethodId__c) continue; // replaced since
                try {
                    Map<String, Object> method = paymentMethod(stripeAccountByAccount.get(a.Id), pm);
                    String type = (String) method.get('type');
                    Account u = new Account(Id = a.Id, PayProv_PaymentMethodType__c = type);
                    applyCardDetails(u, method);
                    if (CARD.equals(type)) u.PayProv_MandateId__c = null;
                    else if (intentByAccount.containsKey(a.Id)) {
                        String mandate = chargeMandate(stripeAccountByAccount.get(a.Id), intentByAccount.get(a.Id), type);
                        if (String.isNotBlank(mandate)) u.PayProv_MandateId__c = mandate;
                    }
                    updates.add(u);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Svc_PaymentIntent.TypeJob ' + a.Id + ': ' + e.getMessage());
                }
            }
            if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        }

        /**
         * What a pay-now payment leaves on the Account for the next invoices: a card as itself; a direct debit (Renew)
         * with the mandate of its charge; iDEAL or a bank transfer nothing - the Account keeps what it had.
         */
        private Account payNowMethod(Id accountId, String pm) {
            String stripeAccountId = stripeAccountByAccount.get(accountId);
            Map<String, Object> method = paymentMethod(stripeAccountId, pm);
            String type = (String) method.get('type');
            if (CARD.equals(type)) {
                Account u = new Account(Id = accountId, PayProv_PaymentMethodId__c = pm, PayProv_PaymentMethodType__c = CARD, PayProv_MandateId__c = null);
                applyCardDetails(u, method);
                return u;
            }
            if ('sepa_debit'.equals(type) || 'bacs_debit'.equals(type)) {
                String mandate = chargeMandate(stripeAccountId, intentByAccount.get(accountId), type);
                if (String.isBlank(mandate)) return null;
                return new Account(Id = accountId, PayProv_PaymentMethodId__c = pm, PayProv_MandateId__c = mandate,
                    PayProv_PaymentMethodType__c = type, PayProv_CardExpiry__c = null, PayProv_CardWallet__c = null);
            }
            return null;
        }
    }

    /** latest_charge.payment_method_details.<type> of a PaymentIntent. */
    private static Map<String, Object> chargeDetails(String stripeAccountId, String paymentIntentId, String type) {
        Map<String, Object> intent  = call('GET', '/v1/payment_intents/' + paymentIntentId + '?expand[]=latest_charge', stripeAccountId, null, null);
        Map<String, Object> charge  = intent.get('latest_charge') instanceof Map<String, Object> ? (Map<String, Object>) intent.get('latest_charge') : null;
        Map<String, Object> details = charge == null ? null : (Map<String, Object>) charge.get('payment_method_details');
        return details == null ? null : (Map<String, Object>) details.get(type);
    }

    /** Mandate of a direct debit payment: latest_charge.payment_method_details.<type>.mandate of the PaymentIntent. */
    @TestVisible
    private static String chargeMandate(String stripeAccountId, String paymentIntentId, String type) {
        Map<String, Object> method = chargeDetails(stripeAccountId, paymentIntentId, type);
        return method == null ? null : (String) method.get('mandate');
    }

    // ── Stripe call (stripeGC) ────────────────────────────────────────────────
    // tests: queued Stripe responses (stripeGC's callout can't be mocked) and the request bodies sent
    @TestVisible private static List<String> mockResponses;
    @TestVisible private static List<String> sentBodies = new List<String>();

    public static Map<String, Object> call(String method, String endpoint, String stripeAccountId, String body, String idempotencyKey) {
        if (Test.isRunningTest() && mockResponses != null && !mockResponses.isEmpty()) {
            sentBodies.add(method + ' ' + endpoint + (body != null ? ' ' + body : ''));
            return parse(mockResponses.remove(0));
        }
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method      = method;
        params.endpoint    = endpoint;
        params.accountId   = stripeAccountId;
        params.requestBody = body;
        if (String.isNotBlank(idempotencyKey)) params.idempotencyKey = idempotencyKey;

        List<String> results = stripeGC.AgnosticInvocable.callStripeEndpoint(new List<stripeGC.RawInvocableParameters>{ params });
        if (results == null || results.isEmpty()) throw new StripeException('No response from Stripe');
        return parse(results[0]);
    }

    @TestVisible
    private static Map<String, Object> parse(String response) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(response);
        if (parsed.containsKey('error')) {
            Map<String, Object> err = (Map<String, Object>) parsed.get('error');
            throw new StripeException((String) err.get('message'));
        }
        return parsed;
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    public static List<Payment__c> queryPayments(Set<Id> ids) {
        return [
            SELECT Id, Name, Status__c, Amount_Gross__c, CurrencyIsoCode,
                   PayProv_PaymentIntentId__c, PayProv_SetupIntentId__c,
                   Account__r.PayProv_CustomerId__c, Account__r.PayProv_MandateId__c, Account__r.PayProv_PaymentMethodId__c,
                   Account__r.PayProv_PaymentMethodType__c, Administration__r.Reseller__c,
                   Invoice__c, Invoice__r.Subscription25__Invoice_Number__c, Invoice__r.FinSysInvoiceId__c, Invoice__r.FinSysInvoiceNumber__c,
                   Account__r.FinancialIdAccount__c, Account__r.FinancialDebtorNumber__c,
                   Administration__r.Subscription25__Twinfield_Company_Code__c
            FROM Payment__c
            WHERE Id IN :ids
            WITH SYSTEM_MODE
        ];
    }

    /** Payments of these invoices, with the fields finSysParams / updateCustomerFinSysMetadata read. */
    public static List<Payment__c> queryPaymentsOfInvoices(Set<Id> invoiceIds) {
        return [
            SELECT Id, Name, PayProv_PaymentIntentId__c, Administration__r.Reseller__c, Account__c, Account__r.PayProv_CustomerId__c,
                   Invoice__c, Invoice__r.Subscription25__Invoice_Number__c, Invoice__r.FinSysInvoiceId__c, Invoice__r.FinSysInvoiceNumber__c,
                   Account__r.FinancialIdAccount__c, Account__r.FinancialDebtorNumber__c,
                   Administration__r.Subscription25__Twinfield_Company_Code__c
            FROM Payment__c
            WHERE Invoice__c IN :invoiceIds
            WITH SYSTEM_MODE
        ];
    }

    private static Map<String, Business_Entities__c> businessEntities;

    public static Business_Entities__c businessEntityFor(Payment__c p) {
        if (businessEntities == null) {
            businessEntities = new Map<String, Business_Entities__c>();
            for (Business_Entities__c be : [
                SELECT Reseller__c, PayProv_Account__c, PayProv_DirectDebit_PaymentMethod__c
                FROM Business_Entities__c WITH SYSTEM_MODE
            ]) {
                businessEntities.put(be.Reseller__c, be);
            }
        }
        return businessEntities.get(p.Administration__r?.Reseller__c);
    }
}
