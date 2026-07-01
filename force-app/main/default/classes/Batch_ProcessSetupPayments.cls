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

        Set<String> resellerCodes = new Set<String>();
        for (SObject s : scope) {
            Payment__c p = (Payment__c) s;
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

        for (SObject s : scope) {
            Payment__c p = (Payment__c) s;
            String ddMethod = p.Administration__r?.PayProv_DirectDebit_PaymentMethod__c;
            if (String.isBlank(ddMethod)) ddMethod = 'sepa_debit';
            Integer amountCents = p.Amount_Gross__c != null ? (Integer)(p.Amount_Gross__c * 100) : 0;

            try {
                issuePaymentIntent(
                    p.Administration__r?.PayProv_Account__c,
                    p.Account__r?.PayProv_CustomerId__c,
                    p.Account__r?.PayProv_PaymentMethodId__c,
                    p.Account__r?.PayProv_MandateId__c,
                    amountCents, p.CurrencyIsoCode, ddMethod, p.Id
                );
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Processing'));
            } catch (Exception e) {
                statusUpdates.add(new Payment__c(Id = p.Id, Status__c = 'Failed'));
                Id queueId = resellerToQueue.get('gqPayment' + p.Account__r?.Reseller_Name__c);
                Case c = new Case(
                    AccountId   = p.Account__c,
                    Subject     = 'Direct Debit collection failed – ' + p.externalId__c,
                    Description = 'Stripe error: ' + e.getMessage(),
                    Origin      = 'Direct Debit',
                    Status      = 'New'
                );
                if (queueId != null) c.OwnerId = queueId;
                failureCases.add(c);
            }
        }

        if (!statusUpdates.isEmpty()) update statusUpdates;
        if (!failureCases.isEmpty())  insert failureCases;
    }

    public override void finishBatch(Database.BatchableContext bc) {}

    // ── Private ───────────────────────────────────────────────────────────────
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
