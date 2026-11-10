/**
 * Dunning cycle of a failed payment-provider payment (Type__c psp-recurring / psp-dd, collected off-session by
 * Batch_ProcessPayments). Dunning_Step__c drives it; each step has its own rab_Payment_Dunning_* flow:
 *   1. Retry Planned      mail 1 "failed, we retry on <Retry Date>"; Batch_ProcessPayments retries once on day 4
 *   2. Payment Requested  mail 2 "failed again, pay via the link" (Pay) or "renew your payment details" (Renew)
 *   3. Final Notice       5 days later, still open: mail 3, last warning, services suspended after <Suspension Date>
 *   4. Suspension Case    5 days later, still open: Case in the reseller's gqPayment queue, the agent takes action
 * Every new failure moves the payment one step on (next); the flows' scheduled paths move it on when the customer
 * does nothing (advance). Paying (Processing/Paid) ends the cycle: the flows only act while the payment is Failed or
 * Reversed and still on the step they were started for.
 * A permanent failure (expired/lost card, closed account, revoked mandate) skips the retry: the saved method is
 * cleared from the Account (Renew) so the customer enters new payment details on the payment page. A reversal or a
 * 3-D Secure payment that was never confirmed skips the retry too, but keeps the method (Pay).
 * No Case for the early steps: the customer is mailed instead, the suspension Case is the only one.
 */
public without sharing class Svc_PaymentDunning {

    public static final String STEP_RETRY      = 'Retry Planned';
    public static final String STEP_REQUESTED  = 'Payment Requested';
    public static final String STEP_FINAL      = 'Final Notice';
    public static final String STEP_SUSPENSION = 'Suspension Case';

    public static final String ACTION_PAY   = 'Pay';
    public static final String ACTION_RENEW = 'Renew';

    public static final String MODE_MAIL    = 'mail';
    public static final String MODE_ADVANCE = 'advance';

    public static final Integer RETRY_DAYS      = 4;
    public static final Integer SUSPENSION_DAYS = 5;

    /** Payment types in the cycle: the ones Batch_ProcessPayments collects off-session. */
    public static final Set<String> TYPES = new Set<String>{ 'psp-recurring', 'psp-dd' };
    /** Statuses of a payment that is still open in the cycle. */
    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'Failed', 'Reversed' };

    private enum Kind { RETRY, PAY, RENEW }

    // Stripe code / decline_code that mean the saved method can't be charged again: renew the payment details
    @TestVisible
    private static final Set<String> RENEW_CODES = new Set<String>{
        // card
        'expired_card', 'lost_card', 'stolen_card', 'pickup_card', 'restricted_card', 'incorrect_number', 'invalid_number',
        'invalid_account', 'card_not_supported', 'invalid_expiry_month', 'invalid_expiry_year', 'new_account_information_available',
        'revocation_of_authorization', 'revocation_of_all_authorizations', 'stop_payment_order',
        // direct debit (SEPA / Bacs)
        'account_closed', 'no_account', 'invalid_account_number', 'bank_account_restricted', 'bank_account_unusable',
        'bank_account_declined', 'bank_ownership_changed', 'debit_not_authorized', 'debit_authorization_not_match',
        'incorrect_account_holder_name', 'branch_does_not_exist'
    };

    // no automatic retry, the method stays: the customer has to act (3-D Secure, dispute, contact their bank)
    @TestVisible
    private static final Set<String> PAY_CODES = new Set<String>{
        'authentication_required', 'payment_intent_authentication_failure', 'debit_disputed', 'refer_to_customer', 'account_frozen'
    };

    private static final Map<String, String> TEMPLATE_BY_STEP = new Map<String, String>{
        STEP_RETRY + '|' + ACTION_PAY       => 'paymentRetryPlanned_',
        STEP_REQUESTED + '|' + ACTION_PAY   => 'paymentFailedPay_',
        STEP_REQUESTED + '|' + ACTION_RENEW => 'paymentFailedRenew_',
        STEP_FINAL + '|' + ACTION_PAY       => 'paymentFinalNotice_',
        STEP_FINAL + '|' + ACTION_RENEW     => 'paymentFinalNotice_'
    };

    // ── Classification ────────────────────────────────────────────────────────
    private static Kind classify(String code, String declineCode, Boolean reversal) {
        if (reversal == true) return Kind.PAY;
        if (RENEW_CODES.contains(code) || RENEW_CODES.contains(declineCode)) return Kind.RENEW;
        if (PAY_CODES.contains(code) || PAY_CODES.contains(declineCode)) return Kind.PAY;
        return Kind.RETRY;
    }

    /** True when the failure refuses the saved method for good: the caller clears it from the Account (clearMethods). */
    public static Boolean isPermanent(String code, String declineCode) {
        return classify(code, declineCode, false) == Kind.RENEW;
    }

    /** The specific reason: a card's decline_code (insufficient_funds, lost_card…) under code card_declined, else the code. */
    public static String failureCode(String code, String declineCode) {
        String reason = 'card_declined'.equals(code) && String.isNotBlank(declineCode) ? declineCode
            : String.isNotBlank(code) ? code : declineCode;
        return reason?.left(80);
    }

    // ── Next step on a failure ────────────────────────────────────────────────
    /**
     * Dunning fields for a payment that just failed (the caller sets the status): the first failure plans the retry
     * or goes straight to the link, every later failure moves one step on. Null for a payment outside the cycle.
     * current needs Type__c, Dunning_Step__c, Dunning_Action__c and externalId__c.
     */
    public static Payment__c next(Payment__c current, String code, String declineCode, Boolean reversal, String paymentIntentId) {
        if (current == null || !TYPES.contains(current.Type__c)) return null;
        Kind outcome = classify(code, declineCode, reversal);
        String step = current.Dunning_Step__c;
        String nextStep = step == null ? (outcome == Kind.RETRY ? STEP_RETRY : STEP_REQUESTED)
            : step == STEP_RETRY       ? STEP_REQUESTED
            : step == STEP_REQUESTED   ? STEP_FINAL
            : STEP_SUSPENSION;

        Payment__c u = new Payment__c(Id = current.Id, Dunning_Step__c = nextStep);
        u.Dunning_Action__c = outcome == Kind.RENEW || current.Dunning_Action__c == ACTION_RENEW ? ACTION_RENEW : ACTION_PAY;
        u.Retry_Date__c     = nextStep == STEP_RETRY ? Date.today().addDays(RETRY_DAYS) : null;
        if (nextStep == STEP_FINAL) u.Suspension_Date__c = Date.today().addDays(SUSPENSION_DAYS);
        String reason = failureCode(code, declineCode);
        if (String.isNotBlank(reason)) u.Failure_Code__c = reason;
        // the mails link to the payment page: an off-session payment may not have a token yet
        if (String.isBlank(current.externalId__c)) u.externalId__c = Svc_PaymentIntent.newToken(current.Id, paymentIntentId);
        return u;
    }

    /**
     * Clears a refused saved method from its Account (Renew): the payment page then asks for new payment details and
     * the batch skips the Account until they are saved. Only when the Account still has that same method, so a method
     * the customer saved since is never cleared. The type stays: it describes the last method on the invoices.
     */
    public static void clearMethods(Map<Id, String> refusedMethodByAccount) {
        if (refusedMethodByAccount == null || refusedMethodByAccount.isEmpty()) return;
        List<Account> updates = new List<Account>();
        for (Account a : [SELECT Id, PayProv_PaymentMethodId__c FROM Account
                          WHERE Id IN :refusedMethodByAccount.keySet() WITH SYSTEM_MODE]) {
            String refused = refusedMethodByAccount.get(a.Id);
            if (String.isBlank(refused) || refused != a.PayProv_PaymentMethodId__c) continue;
            updates.add(new Account(Id = a.Id, PayProv_PaymentMethodId__c = null, PayProv_MandateId__c = null,
                PayProv_CardExpiry__c = null, PayProv_CardWallet__c = null));
        }
        if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }

    // ── Flow entry (rab_Payment_Dunning_*) ────────────────────────────────────
    public class Request {
        @InvocableVariable(label='Payment Id' required=true)
        public Id paymentId;
        @InvocableVariable(label='Mode' description='mail (on entering the step) or advance (scheduled, when the customer did nothing)' required=true)
        public String mode;
        @InvocableVariable(label='Step' description='The Dunning Step the flow was started for; nothing happens when the payment has moved on' required=true)
        public String step;
    }

    @InvocableMethod(label='Payment Dunning' description='Mails the dunning step, creates the suspension Case, or moves a still-open payment to the next step.')
    public static void run(List<Request> requests) {
        Map<Id, Request> byPayment = new Map<Id, Request>();
        for (Request r : requests) if (r?.paymentId != null) byPayment.put(r.paymentId, r);
        if (byPayment.isEmpty()) return;

        List<Payment__c> toMail    = new List<Payment__c>();
        List<Payment__c> toCase    = new List<Payment__c>();
        List<Payment__c> toAdvance = new List<Payment__c>();
        for (Payment__c p : query(byPayment.keySet())) {
            Request r = byPayment.get(p.Id);
            // paid since, or already on another step: this flow interview is outdated
            if (!OPEN_STATUSES.contains(p.Status__c) || p.Dunning_Step__c != r.step) continue;
            if (MODE_ADVANCE.equals(r.mode))           toAdvance.add(p);
            else if (p.Dunning_Step__c == STEP_SUSPENSION) toCase.add(p);
            else                                       toMail.add(p);
        }
        if (!toMail.isEmpty())    mail(toMail);
        if (!toCase.isEmpty())    suspensionCases(toCase);
        if (!toAdvance.isEmpty()) advance(toAdvance);
    }

    private static List<Payment__c> query(Set<Id> ids) {
        return [
            SELECT Id, Name, Status__c, Type__c, externalId__c, CurrencyIsoCode, Amount_Gross__c, Account__c, Contact__c,
                   Account__r.Reseller_Name__c, Account__r.PayProv_PaymentMethodType__c,
                   Dunning_Step__c, Dunning_Action__c, Failure_Code__c, Retry_Date__c, Suspension_Date__c, AlertMessage__c,
                   Collection_Date__c, Invoice__r.Subscription25__Invoice_Number__c,
                   Administration__r.Subscription25__Organization_Wide_Email__c
            FROM Payment__c
            WHERE Id IN :ids
            WITH SYSTEM_MODE
        ];
    }

    private static void mail(List<Payment__c> payments) {
        Map<Id, String> templateBase = new Map<Id, String>();
        for (Payment__c p : payments) {
            String action = p.Dunning_Action__c == ACTION_RENEW ? ACTION_RENEW : ACTION_PAY;
            String base = TEMPLATE_BY_STEP.get(p.Dunning_Step__c + '|' + action);
            if (base != null) templateBase.put(p.Id, base);
        }
        Svc_PaymentActionRequired.sendTemplateMails(payments, templateBase, 'Dunning email');
    }

    /** Customer did nothing: Payment Requested → Final Notice, Final Notice → Suspension Case; a retry that never ran → Payment Requested. */
    private static void advance(List<Payment__c> payments) {
        List<Payment__c> updates = new List<Payment__c>();
        for (Payment__c p : payments) {
            Payment__c u = new Payment__c(Id = p.Id);
            if (p.Dunning_Step__c == STEP_RETRY) {
                u.Dunning_Step__c = STEP_REQUESTED;
                u.Retry_Date__c   = null;
            } else if (p.Dunning_Step__c == STEP_REQUESTED) {
                u.Dunning_Step__c    = STEP_FINAL;
                u.Suspension_Date__c = Date.today().addDays(SUSPENSION_DAYS);
            } else if (p.Dunning_Step__c == STEP_FINAL) {
                u.Dunning_Step__c = STEP_SUSPENSION;
            } else {
                continue;
            }
            updates.add(u);
        }
        if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }

    private static void suspensionCases(List<Payment__c> payments) {
        Map<Id, Id> contactByPayment = Svc_PaymentActionRequired.contacts(payments);
        Set<String> queueNames = new Set<String>();
        for (Payment__c p : payments) queueNames.add('gqPayment' + p.Account__r?.Reseller_Name__c);
        Map<String, Id> queueByName = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN :queueNames WITH SYSTEM_MODE]) {
            queueByName.put(g.DeveloperName, g.Id);
        }

        // one open Case per payment: a repeated flow run never adds a second one
        Set<String> subjects = new Set<String>();
        for (Payment__c p : payments) subjects.add(suspensionSubject(p));
        Set<String> open = new Set<String>();
        for (Case c : [SELECT Subject FROM Case WHERE Subject IN :subjects AND IsClosed = false WITH SYSTEM_MODE]) open.add(c.Subject);

        List<Case> cases = new List<Case>();
        for (Payment__c p : payments) {
            if (open.contains(suspensionSubject(p))) continue;
            Case c = new Case(
                AccountId   = p.Account__c,
                ContactId   = contactByPayment.get(p.Id),
                Subject     = suspensionSubject(p),
                Description = 'The payment is still open after the dunning cycle: the customer was mailed that the payment failed, '
                            + (p.Dunning_Action__c == ACTION_RENEW ? 'asked to renew the payment details' : 'asked to pay via the payment link')
                            + ' and given a final notice that the services would be suspended after '
                            + (p.Suspension_Date__c == null ? 'the notice period' : p.Suspension_Date__c.format()) + '.\n'
                            + 'Please take the appropriate action (suspend the services). The customer still has to pay this payment.\n'
                            + (String.isNotBlank(p.AlertMessage__c) ? 'NOTE - a dunning mail could not be sent: ' + p.AlertMessage__c + '\n' : '')
                            + '\n'
                            + (String.isNotBlank(p.Failure_Code__c) ? 'Failure code: ' + p.Failure_Code__c + '\n' : '')
                            + 'Payment: ' + p.Name + '\n'
                            + (String.isNotBlank(p.Invoice__r?.Subscription25__Invoice_Number__c) ? 'Invoice: ' + p.Invoice__r.Subscription25__Invoice_Number__c + '\n' : '')
                            + 'Payment reference: ' + p.externalId__c + '\n'
                            + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c,
                Origin      = 'Direct Debit',
                Status      = 'New'
            );
            Id queueId = queueByName.get('gqPayment' + p.Account__r?.Reseller_Name__c);
            if (queueId != null) c.OwnerId = queueId;
            cases.add(c);
        }
        if (!cases.isEmpty()) Database.insert(cases, false, AccessLevel.SYSTEM_MODE);
    }

    /**
     * The customer paid (Processing/Paid) after the suspension Case was created: a dated line on that open Case, so
     * the agent doesn't suspend - or reinstates - a customer who has paid. payments need Name and Dunning_Step__c.
     */
    public static void notePaid(List<Payment__c> payments, String status) {
        Map<String, Payment__c> bySubject = new Map<String, Payment__c>();
        for (Payment__c p : payments) {
            if (p?.Dunning_Step__c == STEP_SUSPENSION && String.isNotBlank(p.Name)) bySubject.put(suspensionSubject(p), p);
        }
        if (bySubject.isEmpty()) return;
        List<Case> updates = new List<Case>();
        for (Case c : [SELECT Id, Subject, Description FROM Case WHERE Subject IN :bySubject.keySet() AND IsClosed = false WITH SYSTEM_MODE]) {
            c.Description = ((c.Description == null ? '' : c.Description) + '\n\n' + System.now().format('yyyy-MM-dd HH:mm')
                + ' PAID: the customer has paid this payment (status ' + status + '). Do not suspend the services, or reinstate them.').left(32000);
            updates.add(c);
        }
        if (!updates.isEmpty()) Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }

    @TestVisible
    private static String suspensionSubject(Payment__c p) {
        return 'Suspend service – failing payment – ' + p.Name;
    }
}
