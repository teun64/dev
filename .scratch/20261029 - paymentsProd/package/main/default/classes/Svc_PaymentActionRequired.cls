/**
 * Payments waiting for the customer's 3-D Secure confirmation (Status__c 'Action Required', set by Batch_ProcessPayments
 * or Svc_StripeEventProcessor after an authentication_required decline of an off-session charge).
 *
 * Called by rab_Payment_Action_Required:
 *  - mail     (right away)   → email with the payment link; the page lets the customer confirm the same PaymentIntent
 *  - reminder (day 3)        → same email again
 *  - expire   (day 7)        → Failed + one Case in the reseller's gqPayment queue
 * Each step only acts on payments that are still Action Required.
 *
 * Templates (Classic, by Name like the setup mail): paymentAuthenticationRequired_NL / _DE / _FR / _EN, sender =
 * the Administration's org-wide address. A missing template or address leaves the reason in AlertMessage__c.
 */
public without sharing class Svc_PaymentActionRequired {

    public static final String STEP_MAIL     = 'mail';
    public static final String STEP_REMINDER = 'reminder';
    public static final String STEP_EXPIRE   = 'expire';

    @TestVisible private static final String TEMPLATE_BASE = 'paymentAuthenticationRequired_';

    public class Request {
        @InvocableVariable(label='Payment Id' required=true)
        public Id paymentId;
        @InvocableVariable(label='Step' description='mail, reminder or expire' required=true)
        public String step;
    }

    @InvocableMethod(label='Payment Action Required' description='Mails the 3-D Secure payment link, reminds, or expires a payment that is still Action Required.')
    public static void run(List<Request> requests) {
        Set<Id> mailIds   = new Set<Id>();
        Set<Id> expireIds = new Set<Id>();
        for (Request r : requests) {
            if (r?.paymentId == null) continue;
            (STEP_EXPIRE.equals(r.step) ? expireIds : mailIds).add(r.paymentId);
        }
        Set<Id> allIds = new Set<Id>(mailIds);
        allIds.addAll(expireIds);
        if (allIds.isEmpty()) return;

        List<Payment__c> waiting = [
            SELECT Id, Name, Status__c, externalId__c, CurrencyIsoCode, Amount_Gross__c,
                   Account__c, Account__r.Reseller_Name__c, Account__r.PayProv_PaymentMethodType__c,
                   Contact__c,
                   Administration__r.Subscription25__Organization_Wide_Email__c
            FROM Payment__c
            WHERE Id IN :allIds AND Status__c = :Svc_PaymentIntent.STATUS_ACTION_REQUIRED
            WITH SYSTEM_MODE
        ];
        List<Payment__c> toMail   = new List<Payment__c>();
        List<Payment__c> toExpire = new List<Payment__c>();
        for (Payment__c p : waiting) (expireIds.contains(p.Id) ? toExpire : toMail).add(p);

        if (!toMail.isEmpty())   sendMail(toMail);
        if (!toExpire.isEmpty()) expire(toExpire);
    }

    // ── Mail ──────────────────────────────────────────────────────────────────
    private static void sendMail(List<Payment__c> payments) {
        Map<Id, Id> contactByPayment = contacts(payments);
        Set<Id> contactIds = new Set<Id>(contactByPayment.values());
        Map<Id, String> languageByContact = new Map<Id, String>();
        for (Contact c : [SELECT Id, Language__c FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE]) {
            languageByContact.put(c.Id, TEXT_LANGUAGE.get(c.Language__c) != null ? TEXT_LANGUAGE.get(c.Language__c) : 'EN');
        }
        Map<String, Id> templateByName = new Map<String, Id>();
        for (EmailTemplate t : [SELECT Id, Name FROM EmailTemplate WHERE Name LIKE :TEMPLATE_BASE + '%' WITH SYSTEM_MODE]) {
            templateByName.put(t.Name, t.Id);
        }

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<Payment__c> mailed  = new List<Payment__c>();
        Map<Id, Payment__c> alerts = new Map<Id, Payment__c>();
        for (Payment__c p : payments) {
            Id contactId = contactByPayment.get(p.Id);
            String language = contactId == null ? 'EN' : languageByContact.get(contactId);
            Id templateId = templateByName.containsKey(TEMPLATE_BASE + language)
                ? templateByName.get(TEMPLATE_BASE + language) : templateByName.get(TEMPLATE_BASE + 'EN');
            String orgWide = p.Administration__r?.Subscription25__Organization_Wide_Email__c;
            String missing = contactId == null ? 'no contact'
                : templateId == null ? 'no email template'
                : String.isBlank(orgWide) ? 'no org-wide address' : null;
            if (missing != null) {
                alerts.put(p.Id, new Payment__c(Id = p.Id, AlertMessage__c = 'Authentication email not sent: ' + missing + ' found.'));
                continue;
            }
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTemplateId(templateId);
            m.setTargetObjectId(contactId);
            m.setWhatId(p.Id);
            m.setOrgWideEmailAddressId(orgWide);
            m.setSaveAsActivity(true);
            mails.add(m);
            mailed.add(p);
        }

        if (!mails.isEmpty()) {
            List<Messaging.SendEmailResult> results = Messaging.sendEmail(mails, false);
            for (Integer i = 0; i < results.size(); i++) {
                Payment__c p = mailed[i];
                alerts.put(p.Id, new Payment__c(Id = p.Id, AlertMessage__c = results[i].isSuccess()
                    ? null
                    : ('Authentication email not sent: ' + results[i].getErrors()[0].getMessage()).left(255)));
            }
        }
        if (!alerts.isEmpty()) Database.update(alerts.values(), false, AccessLevel.SYSTEM_MODE);
    }

    // Contact__c.Language__c is a country code: same mapping as afl_PaymentDirectDebitSetup_SendMail.fMailTemplate
    private static final Map<String, String> TEXT_LANGUAGE = new Map<String, String>{
        'NL' => 'NL', 'BE' => 'NL', 'AN' => 'NL',
        'DE' => 'DE', 'AT' => 'DE', 'CH' => 'DE', 'LU' => 'DE',
        'FR' => 'FR',
        'GB' => 'EN', 'EN' => 'EN'
    };

    // ── Expire ────────────────────────────────────────────────────────────────
    private static void expire(List<Payment__c> payments) {
        Map<Id, Id> contactByPayment = contacts(payments);
        Set<String> queueNames = new Set<String>();
        for (Payment__c p : payments) queueNames.add('gqPayment' + p.Account__r?.Reseller_Name__c);
        Map<String, Id> queueByName = new Map<String, Id>();
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN :queueNames WITH SYSTEM_MODE]) {
            queueByName.put(g.DeveloperName, g.Id);
        }

        List<Payment__c> updates = new List<Payment__c>();
        List<Case> cases = new List<Case>();
        for (Payment__c p : payments) {
            updates.add(new Payment__c(Id = p.Id, Status__c = 'Failed'));
            Boolean isCard = Svc_PaymentIntent.CARD.equals(p.Account__r?.PayProv_PaymentMethodType__c);
            Case c = new Case(
                AccountId   = p.Account__c,
                ContactId   = contactByPayment.get(p.Id),
                Subject     = (isCard ? 'Card payment failure – ' : 'Direct Debit failure – ') + p.Name,
                Description = 'The bank asked the customer to confirm this payment (3-D Secure), and the customer did not '
                            + 'confirm it within 7 days of the payment link email.\n\n'
                            + 'Payment: ' + p.Name + '\n'
                            + 'Payment reference: ' + p.externalId__c + '\n'
                            + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c,
                Origin      = 'Direct Debit',
                Status      = 'New'
            );
            Id queueId = queueByName.get('gqPayment' + p.Account__r?.Reseller_Name__c);
            if (queueId != null) c.OwnerId = queueId;
            cases.add(c);
        }
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        Database.insert(cases, false, AccessLevel.SYSTEM_MODE);
    }

    // Payment contact on the payment, else the account's payment / main contact
    private static Map<Id, Id> contacts(List<Payment__c> payments) {
        Map<Id, Id> byPayment = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Payment__c p : payments) {
            if (p.Contact__c != null) byPayment.put(p.Id, p.Contact__c);
            else if (p.Account__c != null) accountIds.add(p.Account__c);
        }
        if (accountIds.isEmpty()) return byPayment;
        Map<Id, Id> byAccount = new Map<Id, Id>();
        for (AccountContactRelation r : [
            SELECT AccountId, ContactId FROM AccountContactRelation
            WHERE AccountId IN :accountIds AND IsActive = true AND (IsPaymentContact__c = true OR isMainContact__c = true)
            WITH SYSTEM_MODE
            ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
        ]) {
            if (!byAccount.containsKey(r.AccountId)) byAccount.put(r.AccountId, r.ContactId);
        }
        for (Payment__c p : payments) {
            if (!byPayment.containsKey(p.Id) && byAccount.containsKey(p.Account__c)) byPayment.put(p.Id, byAccount.get(p.Account__c));
        }
        return byPayment;
    }
}
