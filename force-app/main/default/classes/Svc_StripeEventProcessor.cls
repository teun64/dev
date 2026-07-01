public without sharing class Svc_StripeEventProcessor {

    // ──────────────────────────────────────────────────────────────────────────
    // Entry point — called from Trigger_StripeEvent (after insert, bulk-safe)
    // ──────────────────────────────────────────────────────────────────────────
    public static void process(List<stripeGC__Stripe_Event__c> events) {

        // 1. Parse JSON for relevant events
        List<ParsedEvent> parsed = new List<ParsedEvent>();
        Set<String> customerIds    = new Set<String>();
        Set<String> paymentMethodIds = new Set<String>();
        Set<Id>     paymentSfIds   = new Set<Id>();

        for (stripeGC__Stripe_Event__c evt : events) {
            if (evt.processed__c || String.isBlank(evt.stripeGC__Request_Body__c)) continue;
            ParsedEvent p = parseBody(evt);
            if (p == null) continue;
            parsed.add(p);
            if (String.isNotBlank(p.customerId))      customerIds.add(p.customerId);
            if (String.isNotBlank(p.paymentMethodId)) paymentMethodIds.add(p.paymentMethodId);
            if (String.isNotBlank(p.paymentSfId)) {
                try { paymentSfIds.add((Id) p.paymentSfId); } catch (Exception ignored) {}
            }
        }
        if (parsed.isEmpty()) return;

        // 2. Bulk lookups
        Map<String, Id> customerToAccount = new Map<String, Id>();
        for (Account a : [SELECT Id, PayProv_CustomerId__c FROM Account
                          WHERE PayProv_CustomerId__c IN :customerIds]) {
            customerToAccount.put(a.PayProv_CustomerId__c, a.Id);
        }

        Map<String, Id> pmToAccount = new Map<String, Id>();
        if (!paymentMethodIds.isEmpty()) {
            for (Account a : [SELECT Id, PayProv_PaymentMethodId__c FROM Account
                              WHERE PayProv_PaymentMethodId__c IN :paymentMethodIds]) {
                pmToAccount.put(a.PayProv_PaymentMethodId__c, a.Id);
            }
        }

        Map<Id, Payment__c> paymentMap = new Map<Id, Payment__c>();
        if (!paymentSfIds.isEmpty()) {
            paymentMap = new Map<Id, Payment__c>([
                SELECT Id, Account__c, externalId__c, Amount_Gross__c, CurrencyIsoCode,
                       Account__r.Reseller_Name__c
                FROM Payment__c
                WHERE Id IN :paymentSfIds
            ]);
        }

        // Collect reseller codes for queue lookup and account IDs for contact lookup (failure cases)
        Set<Id>     paymentAccountIds = new Set<Id>();
        Set<String> resellerCodes     = new Set<String>();
        for (Payment__c p : paymentMap.values()) {
            paymentAccountIds.add(p.Account__c);
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
        if (!paymentAccountIds.isEmpty()) {
            for (AccountContactRelation r : [
                SELECT AccountId, ContactId
                FROM AccountContactRelation
                WHERE AccountId IN :paymentAccountIds
                  AND IsActive = true
                  AND (IsPaymentContact__c = true OR isMainContact__c = true)
                ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
            ]) {
                if (!accountToContact.containsKey(r.AccountId)) {
                    accountToContact.put(r.AccountId, r.ContactId);
                }
            }
        }

        // 3. Build DML collections
        List<stripeGC__Stripe_Event__c> eventUpdates  = new List<stripeGC__Stripe_Event__c>();
        Map<Id, Account>                accountMap     = new Map<Id, Account>();
        Map<Id, Payment__c>             paymentUpdates = new Map<Id, Payment__c>();
        List<Case>                      newCases       = new List<Case>();

        for (ParsedEvent p : parsed) {
            // 3a. Populate event custom fields
            stripeGC__Stripe_Event__c evtUpdate = new stripeGC__Stripe_Event__c(
                Id                   = p.eventId,
                type__c              = p.eventType,
                id__c                = p.objectId,
                customerid__c        = p.customerId,
                paymentmethodid__c   = p.paymentMethodId,
                mandateid__c         = p.mandateId,
                status__c            = p.objectStatus,
                error__c             = p.errorMessage,
                processed__c         = true
            );
            if (String.isNotBlank(p.paymentIntentId)) evtUpdate.paymentintentid__c = p.paymentIntentId;
            if (String.isNotBlank(p.setupIntentId))   evtUpdate.setupintentid__c   = p.setupIntentId;
            eventUpdates.add(evtUpdate);

            // 3b. Resolve Account ID
            Id accountId = null;
            if (String.isNotBlank(p.customerId) && customerToAccount.containsKey(p.customerId)) {
                accountId = customerToAccount.get(p.customerId);
            } else if (String.isNotBlank(p.paymentMethodId) && pmToAccount.containsKey(p.paymentMethodId)) {
                accountId = pmToAccount.get(p.paymentMethodId); // mandate.updated has no customer
            }

            if (accountId != null && (String.isNotBlank(p.paymentMethodId) || String.isNotBlank(p.mandateId))) {
                if (!accountMap.containsKey(accountId)) {
                    accountMap.put(accountId, new Account(Id = accountId));
                }
                Account acc = accountMap.get(accountId);
                if (String.isNotBlank(p.paymentMethodId)) acc.PayProv_PaymentMethodId__c = p.paymentMethodId;
                if (String.isNotBlank(p.mandateId))       acc.PayProv_MandateId__c       = p.mandateId;
            }

            // 3c. Payment status + Case
            if (String.isNotBlank(p.paymentSfId) && paymentMap.containsKey(p.paymentSfId)) {
                Payment__c payment = paymentMap.get(p.paymentSfId);
                String newStatus = statusForEvent(p.eventType);
                if (newStatus != null) {
                    paymentUpdates.put(payment.Id, new Payment__c(Id = payment.Id, Status__c = newStatus));
                }
                if (isFailure(p.eventType)) {
                    String queueName = 'gqPayment' + payment.Account__r?.Reseller_Name__c;
                    Id queueId   = resellerToQueue.get(queueName);
                    Id contactId = accountToContact.get(payment.Account__c);
                    newCases.add(buildFailureCase(payment, p.errorMessage, p.errorCode, queueId, contactId));
                }
            }
        }

        // 4. DML
        if (!eventUpdates.isEmpty())           update eventUpdates;
        if (!accountMap.isEmpty())             update accountMap.values();
        if (!paymentUpdates.isEmpty())         update paymentUpdates.values();
        if (!newCases.isEmpty())               insert newCases;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // JSON parsing
    // ──────────────────────────────────────────────────────────────────────────
    private static ParsedEvent parseBody(stripeGC__Stripe_Event__c evt) {
        try {
            Map<String, Object> body     = (Map<String, Object>) JSON.deserializeUntyped(evt.stripeGC__Request_Body__c);
            String              evtType  = evt.stripeGC__Event_Name__c;
            Map<String, Object> data     = (Map<String, Object>) body.get('data');
            if (data == null) return null;
            Map<String, Object> obj      = (Map<String, Object>) data.get('object');
            if (obj == null) return null;

            ParsedEvent p = new ParsedEvent();
            p.eventId     = evt.Id;
            p.eventType   = evtType;
            p.objectId    = (String) obj.get('id');
            p.objectStatus = (String) obj.get('status');

            if (evtType.startsWith('payment_intent.')) {
                p.paymentIntentId = p.objectId;
                p.customerId      = (String) obj.get('customer');
                p.paymentMethodId = (String) obj.get('payment_method');
                p.mandateId       = (String) obj.get('mandate');
                Map<String, Object> metadata = (Map<String, Object>) obj.get('metadata');
                if (metadata != null) p.paymentSfId = (String) metadata.get('PaymentID');
                Map<String, Object> err = (Map<String, Object>) obj.get('last_payment_error');
                if (err != null) {
                    p.errorCode    = (String) err.get('code');
                    p.errorMessage = (String) err.get('message');
                }

            } else if (evtType.startsWith('setup_intent.')) {
                p.setupIntentId   = p.objectId;
                p.customerId      = (String) obj.get('customer');
                p.paymentMethodId = (String) obj.get('payment_method');
                p.mandateId       = (String) obj.get('mandate');
                Map<String, Object> metadata = (Map<String, Object>) obj.get('metadata');
                if (metadata != null) p.paymentSfId = (String) metadata.get('PaymentID');
                Map<String, Object> err = (Map<String, Object>) obj.get('last_setup_error');
                if (err != null) {
                    p.errorCode    = (String) err.get('code');
                    p.errorMessage = (String) err.get('message');
                }

            } else if ('mandate.updated'.equals(evtType)) {
                // Only process when mandate becomes active
                if (!'active'.equals(p.objectStatus)) return null;
                p.mandateId       = p.objectId;
                p.paymentMethodId = (String) obj.get('payment_method');
                // No payment metadata — Account is resolved via payment_method lookup
            } else {
                return null; // unhandled event type
            }

            return p;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Svc_StripeEventProcessor.parseBody: ' + e.getMessage());
            return null;
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────────────────
    private static String statusForEvent(String evtType) {
        if ('payment_intent.processing'.equals(evtType))      return 'Processing';
        if ('payment_intent.succeeded'.equals(evtType))       return 'Collected';
        if ('payment_intent.payment_failed'.equals(evtType))  return 'Failed';
        if ('setup_intent.succeeded'.equals(evtType))         return 'Setup';
        if ('setup_intent.setup_failed'.equals(evtType))      return 'Failed';
        return null;
    }

    private static Boolean isFailure(String evtType) {
        return 'payment_intent.payment_failed'.equals(evtType) || 'setup_intent.setup_failed'.equals(evtType);
    }

    private static Case buildFailureCase(Payment__c p, String reason, String code, Id queueId, Id contactId) {
        String description =
            (String.isNotBlank(code)   ? 'Failure code: ' + code + '\n' : '') +
            (String.isNotBlank(reason) ? reason + '\n\n'                : '') +
            'Payment reference: ' + p.externalId__c + '\n' +
            'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c;

        Case c = new Case(
            AccountId   = p.Account__c,
            ContactId   = contactId,
            Subject     = 'Direct Debit failure – ' + p.externalId__c,
            Description = description,
            Origin      = 'Direct Debit',
            Status      = 'New'
        );
        if (queueId != null) c.OwnerId = queueId;
        return c;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Inner DTO
    // ──────────────────────────────────────────────────────────────────────────
    private class ParsedEvent {
        Id     eventId;
        String eventType;
        String objectId;
        String objectStatus;
        String paymentIntentId;
        String setupIntentId;
        String customerId;
        String paymentMethodId;
        String mandateId;
        String paymentSfId;    // Salesforce Payment__c record Id from metadata
        String errorCode;
        String errorMessage;
    }
}
