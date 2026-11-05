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
    /** Type of a saved Stripe payment method (card, sepa_debit, bacs_debit, …): webhook payloads only carry its id. */
    public static String paymentMethodType(String stripeAccountId, String paymentMethodId) {
        return (String) call('GET', '/v1/payment_methods/' + paymentMethodId, stripeAccountId, null, null).get('type');
    }

    /**
     * Stores the type of a newly saved payment method on the Account (Svc_StripeEventProcessor runs in a trigger and
     * can't call out). A card has no mandate, so a mandate left from an earlier direct debit method is cleared.
     */
    public class TypeJob implements Queueable, Database.AllowsCallouts {
        private final Map<Id, String> paymentMethodByAccount;
        private final Map<Id, String> stripeAccountByAccount;
        public TypeJob(Map<Id, String> paymentMethodByAccount, Map<Id, String> stripeAccountByAccount) {
            this.paymentMethodByAccount = paymentMethodByAccount;
            this.stripeAccountByAccount = stripeAccountByAccount;
        }

        public void execute(QueueableContext ctx) {
            List<Account> updates = new List<Account>();
            for (Account a : [SELECT Id, PayProv_PaymentMethodId__c FROM Account WHERE Id IN :paymentMethodByAccount.keySet() WITH SYSTEM_MODE]) {
                String pm = paymentMethodByAccount.get(a.Id);
                if (pm != a.PayProv_PaymentMethodId__c) continue; // replaced since
                try {
                    String type = paymentMethodType(stripeAccountByAccount.get(a.Id), pm);
                    Account u = new Account(Id = a.Id, PayProv_PaymentMethodType__c = type);
                    if (CARD.equals(type)) u.PayProv_MandateId__c = null;
                    updates.add(u);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Svc_PaymentIntent.TypeJob ' + a.Id + ': ' + e.getMessage());
                }
            }
            if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        }
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
