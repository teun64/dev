public without sharing class Svc_StripeEventProcessor {

    private static final Set<String> REVERSAL_CODES = new Set<String>{
        'payment_reversed',    // BACS
        'sepa_debit_reversal'  // SEPA
    };

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
            p.stripeAccountId = evt.stripeGC__Stripe_Account__c;
            parsed.add(p);
            if (String.isNotBlank(p.customerId))      customerIds.add(p.customerId);
            if (String.isNotBlank(p.paymentMethodId)) paymentMethodIds.add(p.paymentMethodId);
            if (String.isNotBlank(p.paymentSfId)) {
                try { paymentSfIds.add((Id) p.paymentSfId); } catch (Exception ignored) { p.paymentSfId = null; }
            }
        }
        if (parsed.isEmpty()) return;

        // 2. Bulk lookups
        Util_StripeEvent.AccountResolution accountResolution = Util_StripeEvent.resolveAccounts(customerIds, paymentMethodIds);

        Map<Id, Payment__c> paymentMap = new Map<Id, Payment__c>();
        if (!paymentSfIds.isEmpty()) {
            paymentMap = new Map<Id, Payment__c>([
                SELECT Id, Name, Status__c, Account__c, externalId__c, Amount_Gross__c, CurrencyIsoCode, PayProv_PaymentIntentId__c,
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
        // PaymentIntent each payment is bound to (stored, or set by an earlier event in this same run)
        Map<Id, String>                 boundIntent    = new Map<Id, String>();
        Set<String>                     duplicateCased = new Set<String>();
        // saved payment method per account, typed afterwards by Svc_PaymentIntent.TypeJob (needs a callout)
        Map<Id, String>                 savedMethod              = new Map<Id, String>();
        Map<Id, String>                 savedMethodStripeAccount = new Map<Id, String>();

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
            Id accountId = accountResolution.resolve(p.customerId, p.paymentMethodId);

            if (accountId != null && (String.isNotBlank(p.paymentMethodId) || String.isNotBlank(p.mandateId))) {
                if (!accountMap.containsKey(accountId)) {
                    accountMap.put(accountId, new Account(Id = accountId));
                }
                Account acc = accountMap.get(accountId);
                if (String.isNotBlank(p.paymentMethodId)) acc.PayProv_PaymentMethodId__c = p.paymentMethodId;
                if (String.isNotBlank(p.mandateId))       acc.PayProv_MandateId__c       = p.mandateId;
                if (String.isNotBlank(p.paymentMethodId) && String.isNotBlank(p.stripeAccountId)) {
                    savedMethod.put(accountId, p.paymentMethodId);
                    savedMethodStripeAccount.put(accountId, p.stripeAccountId);
                }
            }

            // 3c. Payment status + Case
            Id resolvedPaymentId = String.isNotBlank(p.paymentSfId) ? (Id) p.paymentSfId : null;
            if (resolvedPaymentId != null && paymentMap.containsKey(resolvedPaymentId)) {
                Payment__c payment = paymentMap.get(resolvedPaymentId);
                String queueName = 'gqPayment' + payment.Account__r?.Reseller_Name__c;
                Id queueId   = resellerToQueue.get(queueName);
                Id contactId = accountToContact.get(payment.Account__c);

                // A payment is bound to one PaymentIntent. Once that intent is debiting (Processing/Paid/Collected),
                // an event of another intent is a second debit for the same payment: flag it once for follow-up
                // (refund) and leave the payment alone. Before that, a newer intent simply replaces an open one
                // (e.g. Batch_ProcessPayments cancels an abandoned checkout intent and debits off-session).
                if (!boundIntent.containsKey(payment.Id)) boundIntent.put(payment.Id, payment.PayProv_PaymentIntentId__c);
                String bound = boundIntent.get(payment.Id);
                String currentStatus = paymentUpdates.containsKey(payment.Id) ? paymentUpdates.get(payment.Id).Status__c : payment.Status__c;
                if (String.isNotBlank(p.paymentIntentId) && String.isNotBlank(bound) && p.paymentIntentId != bound
                        && DEBITING_STATUSES.contains(currentStatus)) {
                    if (isCharge(p.eventType) && duplicateCased.add(p.paymentIntentId)) {
                        newCases.add(buildDuplicateCase(payment, p.paymentIntentId, bound, queueId, contactId));
                    }
                    continue;
                }

                String newStatus = statusForEvent(p.eventType, p.errorCode);
                if (newStatus != null) {
                    Payment__c pu = new Payment__c(Id = payment.Id, Status__c = newStatus);
                    if (String.isNotBlank(p.paymentIntentId)) {
                        pu.PayProv_PaymentIntentId__c = p.paymentIntentId;
                        boundIntent.put(payment.Id, p.paymentIntentId);
                    }
                    if (String.isNotBlank(p.setupIntentId)) pu.PayProv_SetupIntentId__c = p.setupIntentId;
                    // customer completed the checkout / debit started: ends the D+2/D+4 reminders
                    if ('setup_intent.succeeded'.equals(p.eventType) || isCharge(p.eventType)) {
                        pu.Interaction_Status__c = 'Request Processed by Customer';
                    }
                    if ('setup_intent.succeeded'.equals(p.eventType) || 'payment_intent.succeeded'.equals(p.eventType)) {
                        pu.Processed_Date__c = Date.today();
                    }
                    paymentUpdates.put(payment.Id, pu);
                }
                if (isFailure(p.eventType, p.errorCode)) {
                    newCases.add(buildFailureCase(payment, p.errorMessage, p.errorCode, queueId, contactId));
                }
                if (isReversal(p.eventType, p.errorCode)) {
                    newCases.add(buildReversalCase(payment, p.errorCode, queueId, contactId));
                }
            }
        }

        // before the account update: compares against the method the account had so far
        enqueueTypeJob(savedMethod, savedMethodStripeAccount);

        // 4. DML
        if (!eventUpdates.isEmpty())   update eventUpdates;
        if (!accountMap.isEmpty())     update accountMap.values();
        if (!paymentUpdates.isEmpty()) Database.update(paymentUpdates.values(), AccessLevel.SYSTEM_MODE);
        if (!newCases.isEmpty())       insert newCases;
    }

    /** Only for a method that is new on the account or not typed yet: repeat charges reuse the same, typed method. */
    private static void enqueueTypeJob(Map<Id, String> savedMethod, Map<Id, String> savedMethodStripeAccount) {
        if (savedMethod.isEmpty()) return;
        for (Account a : [SELECT Id, PayProv_PaymentMethodId__c, PayProv_PaymentMethodType__c FROM Account
                          WHERE Id IN :savedMethod.keySet() WITH SYSTEM_MODE]) {
            if (String.isNotBlank(a.PayProv_PaymentMethodType__c) && a.PayProv_PaymentMethodId__c == savedMethod.get(a.Id)) {
                savedMethod.remove(a.Id);
            }
        }
        if (savedMethod.isEmpty() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) return;
        System.enqueueJob(new Svc_PaymentIntent.TypeJob(savedMethod, savedMethodStripeAccount));
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
    private static String statusForEvent(String evtType, String errorCode) {
        if ('payment_intent.processing'.equals(evtType))      return 'Processing';
        if ('payment_intent.succeeded'.equals(evtType))       return 'Paid';
        if ('payment_intent.payment_failed'.equals(evtType))  return REVERSAL_CODES.contains(errorCode) ? 'Reversed' : 'Failed';
        if ('setup_intent.succeeded'.equals(evtType))         return 'Setup';
        if ('setup_intent.setup_failed'.equals(evtType))      return 'Failed';
        return null;
    }

    private static final Set<String> DEBITING_STATUSES = new Set<String>{ 'Processing', 'Paid', 'Collected' };

    private static Boolean isCharge(String evtType) {
        return 'payment_intent.processing'.equals(evtType) || 'payment_intent.succeeded'.equals(evtType);
    }

    private static Case buildDuplicateCase(Payment__c p, String duplicateIntentId, String boundIntentId, Id queueId, Id contactId) {
        Case c = new Case(
            AccountId   = p.Account__c,
            ContactId   = contactId,
            Subject     = 'Direct Debit charged twice – ' + p.Name,
            Description = 'A second Stripe PaymentIntent was charged for this payment. Check it in Stripe and refund the duplicate.\n\n'
                        + 'Payment: ' + p.Name + '\n'
                        + 'Payment Intent of the payment: ' + boundIntentId + '\n'
                        + 'Duplicate Payment Intent: ' + duplicateIntentId + '\n'
                        + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c,
            Origin      = 'Direct Debit',
            Status      = 'New'
        );
        if (queueId != null) c.OwnerId = queueId;
        return c;
    }

    private static Boolean isFailure(String evtType, String errorCode) {
        return ('payment_intent.payment_failed'.equals(evtType) && !REVERSAL_CODES.contains(errorCode))
            || 'setup_intent.setup_failed'.equals(evtType);
    }

    private static Boolean isReversal(String evtType, String errorCode) {
        return 'payment_intent.payment_failed'.equals(evtType) && REVERSAL_CODES.contains(errorCode);
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

    private static Case buildReversalCase(Payment__c p, String reason, Id queueId, Id contactId) {
        String description =
            (String.isNotBlank(reason) ? 'Reversal code: ' + reason + '\n\n' : '') +
            'Payment reference: ' + p.externalId__c + '\n' +
            'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c;

        Case c = new Case(
            AccountId   = p.Account__c,
            ContactId   = contactId,
            Subject     = 'Direct Debit reversal – ' + p.externalId__c,
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
        Id     stripeAccountId; // stripeGC__Stripe_Account__c of the event (= Business_Entities__c.PayProv_Account__c)
        String errorCode;
        String errorMessage;
    }
}
