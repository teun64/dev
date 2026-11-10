/**
 * Asks the customer to renew a saved card before it is charged after its expiry date. Picks the open card payments
 * (Type__c psp-recurring / psp-dd, Status New) whose collection date is still ahead and lies after the Account's card
 * expiry, or whose card expiry is not known yet. The card is read from Stripe first: Stripe's card updater may have
 * renewed it (same payment method id, new expiry), and a wallet card (Apple Pay / Google Pay) is renewed by the card
 * network, so neither gets a mail. Still expiring before the collection date: Card_Renewal_Requested__c is set and the
 * payment contact gets paymentCardExpiring_<NL/DE/EN> with the payment link, where the customer saves new payment
 * details (Ctrl_Payment 'renewCard'); Batch_ProcessPayments then collects with them on the collection date.
 * A card that is not renewed fails on the collection date and goes into the dunning cycle (Svc_PaymentDunning, Renew).
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name) and chained
 * as a step of the Day job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt Day_CardExpiryCheck).
 * Manual run: Database.executeBatch(new Batch_CardExpiryCheck(), 20);
 */
global class Batch_CardExpiryCheck extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {

    @TestVisible private static final String TEMPLATE_BASE = 'paymentCardExpiring_';

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_CardExpiryCheck() {
        super('Batch_CardExpiryCheck');
    }

    // every payment can be one Stripe callout
    public override Integer getBatchSize() {
        return 20;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        // no bind variables: the Subscription25 job framework runs the locator outside this method's scope
        return Database.getQueryLocator(
            'SELECT Id, Name, Status__c, Type__c, externalId__c, Collection_Date__c, Account__c, Contact__c, PayProv_PaymentIntentId__c,' +
            ' Account__r.PayProv_PaymentMethodId__c, Account__r.PayProv_CardExpiry__c, Administration__r.Reseller__c,' +
            ' Administration__r.Subscription25__Organization_Wide_Email__c' +
            ' FROM Payment__c' +
            ' WHERE Type__c IN (\'psp-recurring\', \'psp-dd\')' +
            ' AND Status__c = \'New\'' +
            ' AND Card_Renewal_Requested__c = null' +
            ' AND Collection_Date__c > TODAY' +
            ' AND Account__r.PayProv_PaymentMethodType__c = \'card\'' +
            ' AND Account__r.PayProv_PaymentMethodId__c != null' +
            ' AND Account__r.PayProv_CardWallet__c = null' +
            ' AND (Account__r.PayProv_CardExpiry__c = null OR Card_Expires_Before_Collection__c = true)' +
            ' ORDER BY Collection_Date__c ASC', AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
        List<Payment__c> payments = (List<Payment__c>) scope;

        // 1. callouts first: the card as Stripe has it now, once per Account
        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        for (Payment__c p : payments) {
            if (accountUpdates.containsKey(p.Account__c)) continue;
            Business_Entities__c be = Svc_PaymentIntent.businessEntityFor(p);
            if (String.isBlank(be?.PayProv_Account__c)) continue;
            try {
                Account u = new Account(Id = p.Account__c);
                Svc_PaymentIntent.applyCardDetails(u, Svc_PaymentIntent.paymentMethod(be.PayProv_Account__c, p.Account__r.PayProv_PaymentMethodId__c));
                accountUpdates.put(p.Account__c, u);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Batch_CardExpiryCheck ' + p.Name + ': ' + e.getMessage());
            }
        }

        // 2. still expiring before the collection date: ask for new payment details
        // one mail per Account (the earliest collection, the scope is ordered by it); its other payments are flagged too
        List<Payment__c> toMail = new List<Payment__c>();
        List<Payment__c> paymentUpdates = new List<Payment__c>();
        Set<Id> mailedAccounts = new Set<Id>();
        for (Payment__c p : payments) {
            Account card = accountUpdates.get(p.Account__c);
            if (card == null || card.PayProv_CardWallet__c != null || card.PayProv_CardExpiry__c == null
                    || card.PayProv_CardExpiry__c >= p.Collection_Date__c) continue;
            Payment__c u = new Payment__c(Id = p.Id, Card_Renewal_Requested__c = Date.today());
            if (String.isBlank(p.externalId__c)) {
                u.externalId__c = Svc_PaymentIntent.newToken(p.Id, 'card-renewal');
                p.externalId__c = u.externalId__c;
            }
            paymentUpdates.add(u);
            if (mailedAccounts.add(p.Account__c)) toMail.add(p);
        }

        if (!accountUpdates.isEmpty()) Database.update(accountUpdates.values(), false, AccessLevel.SYSTEM_MODE);
        if (!paymentUpdates.isEmpty()) Database.update(paymentUpdates, false, AccessLevel.SYSTEM_MODE);
        if (!toMail.isEmpty()) {
            Map<Id, String> templateBase = new Map<Id, String>();
            for (Payment__c p : toMail) templateBase.put(p.Id, TEMPLATE_BASE);
            Svc_PaymentActionRequired.sendTemplateMails(toMail, templateBase, 'Card renewal email');
        }
    }

    public override void finishBatch(Database.BatchableContext bc) {
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_CardExpiryCheck');
    }
}
