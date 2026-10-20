/**
 * Collects Stripe recurring payments (Type__c 'psp-recurring'; legacy 'psp-dd' until migrated) off-session against the mandate on the Account, on or after
 * the Collection_Date__c that rbb_Payment derives from Due_Date__c minus the DirectDebit_Method_Setting__mdt
 * processing time (working days).
 *   - New:   recurring payment, the Account already had a mandate when the payment was created.
 *   - Setup: first payment, the customer has completed the mandate setup since.
 * A successful request moves the payment to Processing; Svc_StripeEventProcessor takes it from there (Paid/Failed).
 * A Stripe error or missing configuration sets Failed and opens a Case in the reseller's gqPayment queue.
 * Each request carries an idempotency key (payment + collection date): if the status update after a successful
 * request fails, the next run gets the same PaymentIntent back from Stripe instead of charging twice. An intent
 * already stored on the payment (PayProv_PaymentIntentId__c) is checked first: processing/succeeded → only the
 * status is set; still open (customer never completed it) → canceled before the off-session debit.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name);
 * chained as a step of the Minut job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt).
 * Manual run: Database.executeBatch(new Batch_ProcessPayments(), 20);
 */
global class Batch_ProcessPayments extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Database.Stateful, Util_JobDispatcher.Step {

    private Integer processed = 0;
    private Integer failed = 0;
    private List<String> errors = new List<String>();

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_ProcessPayments() {
        super('Batch_ProcessPayments');
    }

    // every payment is one Stripe callout: max 100 callouts and 120 s callout time per transaction
    public override Integer getBatchSize() {
        return 20;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        // no bind variables: the Subscription25 job framework runs the locator outside this method's scope
        return Database.getQueryLocator(
            'SELECT Id, Name, Status__c, Collection_Date__c, CurrencyIsoCode, Amount_Gross__c, Account__c, PayProv_PaymentIntentId__c,' +
            ' Account__r.PayProv_CustomerId__c, Account__r.PayProv_PaymentMethodId__c, Account__r.PayProv_MandateId__c,' +
            ' Account__r.Reseller_Name__c, Administration__r.Reseller__c' +
            ' FROM Payment__c' +
            ' WHERE Type__c IN (\'psp-recurring\', \'psp-dd\')' +
            ' AND Status__c IN (\'New\', \'Setup\')' +
            ' AND Payment_Batch__c = null' +
            ' AND Collection_Date__c <= TODAY' +
            ' AND Account__r.PayProv_CustomerId__c != null' +
            ' AND Account__r.PayProv_PaymentMethodId__c != null' +
            ' AND Account__r.PayProv_MandateId__c != null' +
            ' ORDER BY Collection_Date__c ASC', AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
        List<Payment__c> payments = (List<Payment__c>) scope;

        Set<Id>     accountIds    = new Set<Id>();
        Set<String> resellerCodes = new Set<String>();
        Set<String> adminResellers = new Set<String>();
        for (Payment__c p : payments) {
            accountIds.add(p.Account__c);
            if (String.isNotBlank(p.Account__r?.Reseller_Name__c))   resellerCodes.add(p.Account__r.Reseller_Name__c);
            if (String.isNotBlank(p.Administration__r?.Reseller__c)) adminResellers.add(p.Administration__r.Reseller__c);
        }

        Map<String, Id> resellerToQueue = new Map<String, Id>();
        if (!resellerCodes.isEmpty()) {
            Set<String> queueNames = new Set<String>();
            for (String code : resellerCodes) queueNames.add('gqPayment' + code);
            for (Group g : [SELECT Id, DeveloperName FROM Group
                            WHERE Type = 'Queue' AND DeveloperName IN :queueNames WITH SYSTEM_MODE]) {
                resellerToQueue.put(g.DeveloperName, g.Id);
            }
        }

        Map<String, Business_Entities__c> resellerToBusinessEntity = new Map<String, Business_Entities__c>();
        if (!adminResellers.isEmpty()) {
            for (Business_Entities__c be : [
                SELECT Reseller__c, PayProv_Account__c, PayProv_DirectDebit_PaymentMethod__c
                FROM Business_Entities__c
                WHERE Reseller__c IN :adminResellers
                WITH SYSTEM_MODE
            ]) {
                resellerToBusinessEntity.put(be.Reseller__c, be);
            }
        }

        Map<Id, Id> accountToContact = new Map<Id, Id>();
        for (AccountContactRelation r : [
            SELECT AccountId, ContactId
            FROM AccountContactRelation
            WHERE AccountId IN :accountIds
              AND IsActive = true
              AND (IsPaymentContact__c = true OR isMainContact__c = true)
            WITH SYSTEM_MODE
            ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
        ]) {
            if (!accountToContact.containsKey(r.AccountId)) {
                accountToContact.put(r.AccountId, r.ContactId);
            }
        }

        List<Payment__c> statusUpdates = new List<Payment__c>();
        List<Case>       failureCases  = new List<Case>();

        for (Payment__c p : payments) {
            Business_Entities__c businessEntity = resellerToBusinessEntity.get(p.Administration__r?.Reseller__c);
            String  stripeAccountId = businessEntity?.PayProv_Account__c;
            String  ddMethod        = businessEntity?.PayProv_DirectDebit_PaymentMethod__c;
            Integer amountCents     = Svc_PaymentIntent.amountCents(p.Amount_Gross__c);
            if (String.isBlank(ddMethod)) ddMethod = 'sepa_debit';

            String preflightError = null;
            if (String.isBlank(stripeAccountId)) preflightError = 'No Stripe account configured on Business Entity.';
            else if (amountCents <= 0)            preflightError = 'Invalid payment amount (' + p.Amount_Gross__c + ').';

            if (preflightError != null) {
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Failed'));
                failureCases.add(buildFailureCase(p, preflightError, resellerToQueue, accountToContact));
                continue;
            }

            try {
                // an intent already stored on the payment (e.g. an upfront BACS intent the customer never completed)
                // is checked first: never a second debit next to one that is already on its way
                if (String.isNotBlank(p.PayProv_PaymentIntentId__c)) {
                    String storedStatus = (String) Svc_PaymentIntent.call(
                        'GET', '/v1/payment_intents/' + p.PayProv_PaymentIntentId__c, stripeAccountId, null, null).get('status');
                    Svc_PaymentIntent.Action a = Svc_PaymentIntent.decide(storedStatus);
                    if (a == Svc_PaymentIntent.Action.PROCESSED) {
                        statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Processing'));
                        continue;
                    }
                    if (a == Svc_PaymentIntent.Action.REUSE) {
                        Svc_PaymentIntent.call('POST', '/v1/payment_intents/' + p.PayProv_PaymentIntentId__c + '/cancel',
                            stripeAccountId, 'cancellation_reason=abandoned', null);
                    }
                }
                String paymentIntentId = issuePaymentIntent(
                    stripeAccountId,
                    p.Account__r.PayProv_CustomerId__c,
                    p.Account__r.PayProv_PaymentMethodId__c,
                    p.Account__r.PayProv_MandateId__c,
                    amountCents, p.CurrencyIsoCode, ddMethod, p.Id,
                    p.Id + '-' + String.valueOf(p.Collection_Date__c)
                );
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Processing', PayProv_PaymentIntentId__c = paymentIntentId));
            } catch (Exception e) {
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Failed'));
                failureCases.add(buildFailureCase(p, 'Stripe error: ' + e.getMessage(), resellerToQueue, accountToContact));
            }
        }

        // partial success: one failing record must not roll back the status of payments Stripe already accepted
        Map<Id, Payment__c> byId = new Map<Id, Payment__c>(payments);
        List<Database.SaveResult> results = Database.update(statusUpdates, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                if (statusUpdates[i].Status__c == 'Processing') processed++; else failed++;
            } else {
                addError(byId.get(statusUpdates[i].Id).Name + ' status ' + statusUpdates[i].Status__c + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
        if (!failureCases.isEmpty()) {
            for (Database.SaveResult r : Database.insert(failureCases, false, AccessLevel.SYSTEM_MODE)) {
                if (!r.isSuccess()) addError('Case: ' + r.getErrors()[0].getMessage());
            }
        }
    }

    public override void finishBatch(Database.BatchableContext bc) {
        System.debug(errors.isEmpty() ? LoggingLevel.INFO : LoggingLevel.ERROR,
            'Batch_ProcessPayments: processing ' + processed + ', failed ' + failed + ', errors ' + errors.size() + ' ' + errors);
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_ProcessPayments');
    }

    // ── Private ───────────────────────────────────────────────────────────────
    private void addError(String message) {
        if (errors.size() < 100) errors.add(message);
    }

    @TestVisible
    private static Case buildFailureCase(
        Payment__c p, String reason,
        Map<String, Id> resellerToQueue, Map<Id, Id> accountToContact
    ) {
        Id queueId   = resellerToQueue.get('gqPayment' + p.Account__r?.Reseller_Name__c);
        Id contactId = accountToContact.get(p.Account__c);
        Case c = new Case(
            AccountId   = p.Account__c,
            ContactId   = contactId,
            Subject     = 'Direct Debit collection failed – ' + p.Name,
            Description = reason + '\n\n'
                        + 'Payment: ' + p.Name + '\n'
                        + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c,
            Origin      = 'Direct Debit',
            Status      = 'New'
        );
        if (queueId != null) c.OwnerId = queueId;
        return c;
    }

    private static String issuePaymentIntent(
        String stripeAccountId, String customerId,
        String paymentMethodId, String mandateId,
        Integer amountCents, String currencyCode, String ddMethod, String paymentId, String idempotencyKey
    ) {
        List<String> body = new List<String>{
            'amount=' + amountCents,
            'currency=' + currencyCode.toLowerCase(),
            'customer=' + customerId,
            'payment_method_types[]=' + ddMethod,
            'payment_method=' + paymentMethodId,
            'mandate=' + mandateId,
            'confirm=true',
            'off_session=true',
            'metadata[PaymentID]=' + paymentId,
            'metadata[PaymentType]=Direct Debit'
        };
        return (String) Svc_PaymentIntent.call('POST', '/v1/payment_intents', stripeAccountId, String.join(body, '&'), idempotencyKey).get('id');
    }
}
