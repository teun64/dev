/**
 * Reconciles payment-provider payments that stay Processing because their final Stripe webhook event never arrived
 * (lost for good, or delivered out of order). Stripe retries a webhook for up to 3 days, so only payments that have
 * been Processing (unchanged) for more than 3 days are checked: their PaymentIntent is read from Stripe and, when it
 * reached a final state, that state is fed back as a Stripe event record, so Svc_StripeEventProcessor applies it
 * exactly like a live webhook (status, interaction, Cases). Still processing after 14 days: AlertMessage__c for follow-up.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name) and chained
 * as a step of the Day job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt Day_ReconcileProcessingPayments).
 */
global class Batch_ReconcileProcessingPayments extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {

    @TestVisible private static final Integer STALE_ALERT_DAYS = 14;

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_ReconcileProcessingPayments() {
        super('Batch_ReconcileProcessingPayments');
    }

    // every payment is one Stripe callout
    public override Integer getBatchSize() {
        return 20;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        // no bind variables: the Subscription25 job framework runs the locator outside this method's scope
        return Database.getQueryLocator(
            'SELECT Id, Name, Status__c, PayProv_PaymentIntentId__c, LastModifiedDate, Administration__r.Reseller__c' +
            ' FROM Payment__c' +
            ' WHERE Type__c IN (\'psp-recurring\', \'psp-dd\', \'psp-immediate\')' +
            ' AND Status__c = \'Processing\'' +
            ' AND PayProv_PaymentIntentId__c != null' +
            ' AND LastModifiedDate < LAST_N_DAYS:3' +
            ' ORDER BY LastModifiedDate ASC', AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
        List<stripeGC__Stripe_Event__c> events = new List<stripeGC__Stripe_Event__c>();
        List<Payment__c> alerts = new List<Payment__c>();

        for (Payment__c p : (List<Payment__c>) scope) {
            String stripeAccountId = Svc_PaymentIntent.businessEntityFor(p)?.PayProv_Account__c;
            Map<String, Object> intent;
            try {
                intent = Svc_PaymentIntent.call('GET', '/v1/payment_intents/' + p.PayProv_PaymentIntentId__c, stripeAccountId, null, null);
            } catch (Exception e) {
                alerts.add(new Payment__c(Id = p.Id, AlertMessage__c = ('Reconcile: Stripe lookup failed: ' + e.getMessage()).left(255)));
                continue;
            }
            String eventName = eventFor(intent);
            if (eventName != null) {
                events.add(new stripeGC__Stripe_Event__c(
                    stripeGC__Event_Name__c     = eventName,
                    stripeGC__Stripe_Account__c = stripeAccountId,
                    stripeGC__Request_Body__c   = JSON.serialize(new Map<String, Object>{
                        'type' => eventName,
                        'data' => new Map<String, Object>{ 'object' => intent }
                    })
                ));
            } else if (p.LastModifiedDate < System.now().addDays(-STALE_ALERT_DAYS)) {
                alerts.add(new Payment__c(Id = p.Id, AlertMessage__c = 'Reconcile: still ' + intent.get('status') + ' at Stripe after '
                    + STALE_ALERT_DAYS + ' days (' + p.PayProv_PaymentIntentId__c + ')'));
            }
        }

        // the trigger on the event records runs Svc_StripeEventProcessor
        if (!events.isEmpty()) Database.insert(events, AccessLevel.SYSTEM_MODE);
        if (!alerts.isEmpty()) Database.update(alerts, false, AccessLevel.SYSTEM_MODE);
    }

    /** Webhook event that matches the intent's final state; null while it is still on its way. */
    @TestVisible
    private static String eventFor(Map<String, Object> intent) {
        String status = (String) intent?.get('status');
        if (status == 'succeeded') return 'payment_intent.succeeded';
        if (status == 'requires_payment_method' && intent.get('last_payment_error') != null) return 'payment_intent.payment_failed';
        return null;
    }

    public override void finishBatch(Database.BatchableContext bc) {
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_ReconcileProcessingPayments');
    }
}
