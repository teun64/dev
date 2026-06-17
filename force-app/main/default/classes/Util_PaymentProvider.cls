public with sharing class Util_PaymentProvider {

    public static final Integer MAX_RETRIES = 3;

    public static void handleEvents(List<stripeGC__Stripe_Event__c> events) {
        if (events.isEmpty()) return;

        List<stripeGC__Stripe_Event__c> eventUpdates = new List<stripeGC__Stripe_Event__c>();
        List<stripeGC__Stripe_Event__c> retryEvents = new List<stripeGC__Stripe_Event__c>();

        // STEP 1: Parse & normalize (ONLY ONCE)
        for (stripeGC__Stripe_Event__c evt : events) {

            if (evt.Processed__c) continue;

            try {
                if (String.isBlank(evt.stripeGC__Request_Body__c)) {
                    throw new PaymentProviderEventException('Empty payload');
                }

                Map<String, Object> payload =
                    (Map<String, Object>) JSON.deserializeUntyped(evt.stripeGC__Request_Body__c);

                Map<String, Object> req = (Map<String, Object>) payload.get('request');
                Map<String, Object> data = (Map<String, Object>) payload.get('data');
                Map<String, Object> obj = data != null ? (Map<String, Object>) data.get('object') : null;
                Map<String, Object> meta = obj != null ? (Map<String, Object>) obj.get('metadata') : null;

                if (obj == null) {
                    throw new PaymentProviderEventException('Missing data.object');
                }

                // Core Stripe fields

                evt.Type__c = (String) payload.get('type');
                evt.Object__c = (String) obj.get('object');
                evt.Id__c = (String) obj.get('id');
                evt.Status__c = (String) obj.get('status');
                evt.CustomerId__c = (String) obj.get('customer');
                evt.PaymentMethodId__c = (String) obj.get('payment_method');
                evt.MandateId__c = (String) obj.get('mandate');
                evt.SetupIntentId__c = (String) obj.get('setup_intent');
                evt.PaymentIntentId__c = (String) obj.get('payment_intent');


                if (evt.Type__c != null) {
                    if (evt.Object__c == 'setup_intent') {
                        evt.SetupIntentId__c = evt.Id__c;
                    } else if (evt.Object__c == 'payment_intent') {
                        evt.PaymentIntentId__c = evt.Id__c;
                    }
                }

                evt.Error__c = null;

            } catch (Exception e) {
                evt.Error__c = e.getMessage();
                evt.Retries__c = incrementRetry(evt.Retries__c);
                retryEvents.add(evt);
            }

            eventUpdates.add(evt);
        }

        if (!eventUpdates.isEmpty()) {
            update eventUpdates;
        }

        // STEP 2: Process business logic (only successfully parsed events)
        processEvents(events);

        // STEP 3: Retry failed parses
        enqueueRetries(retryEvents);
    }

    private static void processEvents(List<stripeGC__Stripe_Event__c> events) {

        Map<String, stripeGC__Stripe_Event__c> setupEvents = new Map<String, stripeGC__Stripe_Event__c>();
        Map<String, stripeGC__Stripe_Event__c> paymentFailEvents = new Map<String, stripeGC__Stripe_Event__c>();

        for (stripeGC__Stripe_Event__c evt : events) {

            if (evt.Processed__c) continue;
            if (evt.Error__c != null) continue;

            if (evt.Type__c == 'setup_intent.succeeded') {
                setupEvents.put(evt.CustomerId__c, evt);
            }
            else if (evt.Type__c == 'payment_intent.payment_failed') {
                paymentFailEvents.put(evt.CustomerId__c, evt);
            }
        }

        handleSetupIntent(setupEvents.values());
        handlePaymentFailed(paymentFailEvents.values());
    }

    // ------------------------
    // SETUP INTENT
    // ------------------------
    private static void handleSetupIntent(List<stripeGC__Stripe_Event__c> events) {

        if (events.isEmpty()) return;

        Set<String> customerIds = new Set<String>();
        for (stripeGC__Stripe_Event__c evt : events) {
            if (evt.CustomerId__c != null) {
                customerIds.add(evt.CustomerId__c);
            }
        }

        Map<String, Account> accounts = new Map<String, Account>();
        for (Account acc : [
            SELECT Id, PayProv_CustomerId__c
            FROM Account
            WHERE PayProv_CustomerId__c IN :customerIds
        ]) {
            accounts.put(acc.PayProv_CustomerId__c, acc);
        }

        List<Account> accUpdates = new List<Account>();
        List<stripeGC__Stripe_Event__c> evtUpdates = new List<stripeGC__Stripe_Event__c>();

        for (stripeGC__Stripe_Event__c evt : events) {

            Account acc = accounts.get(evt.CustomerId__c);
            if (acc == null) continue;

            acc.PayProv_PaymentMethodId__c = evt.PaymentMethodId__c;
            acc.PayProv_MandateId__c = evt.MandateId__c;
            acc.PayProv_Mandate_Status__c = 'Active';
            acc.PayProv_AccountId__c = evt.stripeGC__Stripe_Account__c;

            accUpdates.add(acc);

            evt.Processed__c = true;
            evtUpdates.add(evt);
        }

        if (!accUpdates.isEmpty()) update accUpdates;
        if (!evtUpdates.isEmpty()) update evtUpdates;
    }

    // ------------------------
    // PAYMENT FAILED
    // ------------------------
    private static void handlePaymentFailed(List<stripeGC__Stripe_Event__c> events) {

        if (events.isEmpty()) return;

        Set<String> customerIds = new Set<String>();
        for (stripeGC__Stripe_Event__c evt : events) {
            if (evt.CustomerId__c != null) {
                customerIds.add(evt.CustomerId__c);
            }
        }

        Map<String, Payment__c> paymentsByCustomer = new Map<String, Payment__c>();

        for (Payment__c p : [
            SELECT Id, Account__r.PayProv_CustomerId__c, Status__c
            FROM Payment__c
            WHERE Account__r.PayProv_CustomerId__c IN :customerIds
            AND Status__c != 'Closed'
            ORDER BY CreatedDate DESC
        ]) {
            if (!paymentsByCustomer.containsKey(p.Account__r.PayProv_CustomerId__c)) {
                paymentsByCustomer.put(p.Account__r.PayProv_CustomerId__c, p);
            }
        }

        List<Payment__c> paymentUpdates = new List<Payment__c>();
        List<stripeGC__Stripe_Event__c> evtUpdates = new List<stripeGC__Stripe_Event__c>();
        List<stripeGC__Stripe_Event__c> retryEvents = new List<stripeGC__Stripe_Event__c>();

        for (stripeGC__Stripe_Event__c evt : events) {

            Payment__c payment = paymentsByCustomer.get(evt.CustomerId__c);

            if (payment != null) {
                payment.Status__c = 'Failed';
                paymentUpdates.add(payment);
            }

            evt.Retries__c = incrementRetry(evt.Retries__c);
            retryEvents.add(evt);
            evtUpdates.add(evt);
        }

        if (!paymentUpdates.isEmpty()) update paymentUpdates;
        if (!evtUpdates.isEmpty()) update evtUpdates;

        enqueueRetries(retryEvents);
    }

    // ------------------------
    // RETRY HELPERS
    // ------------------------
    private static Decimal incrementRetry(Decimal current) {
        return (current == null ? 0 : current) + 1;
    }

    private static void enqueueRetries(List<stripeGC__Stripe_Event__c> events) {
        if (!events.isEmpty()) {
            System.enqueueJob(new Queue_PaymentProviderEventRetry(events));
        }
    }


    /*
    {"type":"setup_intent.created","request":{"idempotency_key":"cb2ab6e9-00a0-4923-97ea-0aeab6c524d9","id":"req_tfUx5KX755xfjR"},"pending_webhooks":1,"livemode":false,"data":{"object":{"usage":"off_session","status":"requires_payment_method","single_use_mandate":null,"payment_method_types":["bacs_debit"],"payment_method_options":{},"payment_method_configuration_details":null,"payment_method":null,"on_behalf_of":null,"next_action":null,"metadata":{},"mandate":null,"livemode":false,"latest_attempt":null,"last_setup_error":null,"flow_directions":null,"excluded_payment_method_types":null,"description":null,"customer_account":null,"customer":"cus_UDgTD1Pr2ZisuP","created":1775132021,"client_secret":"seti_1THk81KBFNlFAI2pyqX8d4mF_secret_UGGfvJvJ7LgS5QIzASLeFM6e9eGsExT","cancellation_reason":null,"automatic_payment_methods":null,"application":null,"object":"setup_intent","id":"seti_1THk81KBFNlFAI2pyqX8d4mF"}},"created":1775132021,"api_version":"2022-11-15","object":"event","id":"evt_1THk81KBFNlFAI2pB2JVENOX"}
    */
    // ------------------------
    // EXCEPTION
    // ------------------------
    public class PaymentProviderEventException extends Exception {}
}