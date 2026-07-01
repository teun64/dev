global class Batch_ProcessSetupPayments extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts {

    private static final String CONTEXT_NAME = 'Direct Debit Setup Payment Collection';

    // ── Constructor ───────────────────────────────────────────────────────────
    global Batch_ProcessSetupPayments() {
        super('Batch_ProcessSetupPayments');
    }

    // ── Framework overrides ───────────────────────────────────────────────────
    public override Integer getBatchSize() {
        return 50;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, externalId__c, CurrencyIsoCode, Amount_Gross__c,
                   Account__c,
                   Account__r.PayProv_CustomerId__c,
                   Account__r.PayProv_PaymentMethodId__c,
                   Account__r.PayProv_MandateId__c,
                   Account__r.Reseller_Name__c,
                   Administration__r.PayProv_Account__c,
                   Administration__r.PayProv_DirectDebit_PaymentMethod__c
            FROM Payment__c
            WHERE Status__c = 'Setup'
              AND Account__r.PayProv_PaymentMethodId__c != null
              AND Account__r.PayProv_MandateId__c != null
        ]);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
        List<Payment__c> statusUpdates = new List<Payment__c>();
        List<Case>       failureCases  = new List<Case>();

        Set<Id>     accountIds    = new Set<Id>();
        Set<String> resellerCodes = new Set<String>();
        for (SObject s : scope) {
            Payment__c p = (Payment__c) s;
            accountIds.add(p.Account__c);
            if (String.isNotBlank(p.Account__r?.Reseller_Name__c)) {
                resellerCodes.add(p.Account__r.Reseller_Name__c);
            }
        }
        Map<String, Id> resellerToQueue = new Map<String, Id>();
        if (!resellerCodes.isEmpty()) {
            Set<String> queueNames = new Set<String>();
            for (String code : resellerCodes) queueNames.add('gqPayment' + code);
            for (Group g : [SELECT Id, DeveloperName FROM Group
                            WHERE Type = 'Queue' AND DeveloperName IN :queueNames]) {
                resellerToQueue.put(g.DeveloperName, g.Id);
            }
        }
        Map<Id, Id> accountToContact = new Map<Id, Id>();
        for (AccountContactRelation r : [
            SELECT AccountId, ContactId
            FROM AccountContactRelation
            WHERE AccountId IN :accountIds
              AND IsActive = true
              AND (IsPaymentContact__c = true OR isMainContact__c = true)
            ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
        ]) {
            if (!accountToContact.containsKey(r.AccountId)) {
                accountToContact.put(r.AccountId, r.ContactId);
            }
        }

        for (SObject s : scope) {
            Payment__c p = (Payment__c) s;
            String  stripeAccountId = p.Administration__r?.PayProv_Account__c;
            String  ddMethod        = p.Administration__r?.PayProv_DirectDebit_PaymentMethod__c;
            Integer amountCents     = p.Amount_Gross__c != null ? (Integer)(p.Amount_Gross__c * 100) : 0;
            if (String.isBlank(ddMethod)) ddMethod = 'sepa_debit';

            String preflightError = null;
            if (String.isBlank(stripeAccountId)) preflightError = 'No Stripe account configured on Administration.';
            else if (amountCents <= 0)            preflightError = 'Invalid payment amount (' + p.Amount_Gross__c + ').';

            if (preflightError != null) {
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Failed'));
                failureCases.add(buildFailureCase(p, preflightError, resellerToQueue, accountToContact));
                continue;
            }

            try {
                issuePaymentIntent(
                    stripeAccountId,
                    p.Account__r?.PayProv_CustomerId__c,
                    p.Account__r?.PayProv_PaymentMethodId__c,
                    p.Account__r?.PayProv_MandateId__c,
                    amountCents, p.CurrencyIsoCode, ddMethod, p.Id
                );
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Processing'));
            } catch (Exception e) {
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Failed'));
                failureCases.add(buildFailureCase(p, 'Stripe error: ' + e.getMessage(), resellerToQueue, accountToContact));
            }
        }

        if (!statusUpdates.isEmpty()) update statusUpdates;
        if (!failureCases.isEmpty())  insert failureCases;
    }

    public override void finishBatch(Database.BatchableContext bc) {}

    // ── Private ───────────────────────────────────────────────────────────────
    private static Case buildFailureCase(
        Payment__c p, String reason,
        Map<String, Id> resellerToQueue, Map<Id, Id> accountToContact
    ) {
        Id queueId   = resellerToQueue.get('gqPayment' + p.Account__r?.Reseller_Name__c);
        Id contactId = accountToContact.get(p.Account__c);
        Case c = new Case(
            AccountId   = p.Account__c,
            ContactId   = contactId,
            Subject     = 'Direct Debit collection failed – ' + p.externalId__c,
            Description = reason + '\n\n'
                        + 'Payment reference: ' + p.externalId__c + '\n'
                        + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c,
            Origin      = 'Direct Debit',
            Status      = 'New'
        );
        if (queueId != null) c.OwnerId = queueId;
        return c;
    }

    private static void issuePaymentIntent(
        String stripeAccountId, String customerId,
        String paymentMethodId, String mandateId,
        Integer amountCents, String currencyCode, String ddMethod, String paymentId
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
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method      = 'POST';
        params.endpoint    = '/v1/payment_intents';
        params.accountId   = stripeAccountId;
        params.requestBody = String.join(body, '&');

        List<String> results = stripeGC.AgnosticInvocable.callStripeEndpoint(
            new List<stripeGC.RawInvocableParameters>{ params }
        );
        if (results == null || results.isEmpty()) throw new CalloutException('No response from Stripe');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(results[0]);
        if (parsed.containsKey('error')) {
            Map<String, Object> err = (Map<String, Object>) parsed.get('error');
            throw new CalloutException((String) err.get('message'));
        }
    }
}
