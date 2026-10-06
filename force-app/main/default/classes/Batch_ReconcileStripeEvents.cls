/**
 * Backfills Account.PayProv_MandateId__c from any processed Stripe event that carries a mandate id
 * (mandate.updated, or a payment_intent./setup_intent. event whose payload included one) whose Account
 * resolution failed at trigger time - a same-transaction or cross-transaction ordering gap (the field a
 * later event needs hasn't landed on the Account yet), not something a trigger can fix by itself. Shares
 * its Account-resolution logic (Util_StripeEvent) with Svc_StripeEventProcessor, the trigger-time path.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name);
 * chained as a step of the Minut job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt) - it only
 * ever does real work on the handful of events that failed to resolve, so running it every 5 minutes
 * costs nothing extra and keeps the worst-case backfill latency low.
 */
global class Batch_ReconcileStripeEvents extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_ReconcileStripeEvents() {
        super('Batch_ReconcileStripeEvents');
    }

    public override Integer getBatchSize() {
        return 200;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        // no bind variables: the Subscription25 job framework runs the locator outside this method's scope.
        // No Type__c/Status__c filter needed: an inactive mandate.updated event never gets MandateId__c
        // populated in the first place (Svc_StripeEventProcessor.parseBody returns null before setting any
        // fields), so "has a MandateId__c" already implies a qualifying, authoritative event.
        return Database.getQueryLocator(
            'SELECT Id, CustomerId__c, PaymentMethodId__c, MandateId__c, Retries__c FROM stripeGC__Stripe_Event__c' +
            ' WHERE MandateId__c != null AND (CustomerId__c != null OR PaymentMethodId__c != null)' +
            ' ORDER BY CreatedDate ASC', AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
        List<stripeGC__Stripe_Event__c> events = (List<stripeGC__Stripe_Event__c>) scope;

        Set<String> customerIds = new Set<String>();
        Set<String> paymentMethodIds = new Set<String>();
        for (stripeGC__Stripe_Event__c evt : events) {
            if (String.isNotBlank(evt.CustomerId__c))      customerIds.add(evt.CustomerId__c);
            if (String.isNotBlank(evt.PaymentMethodId__c)) paymentMethodIds.add(evt.PaymentMethodId__c);
        }
        Util_StripeEvent.AccountResolution accountResolution = Util_StripeEvent.resolveAccounts(customerIds, paymentMethodIds);

        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        List<stripeGC__Stripe_Event__c> retryUpdates = new List<stripeGC__Stripe_Event__c>();

        for (stripeGC__Stripe_Event__c evt : events) {
            Id accId = accountResolution.resolve(evt.CustomerId__c, evt.PaymentMethodId__c);
            if (accId == null) {
                // Customer/payment method still hasn't landed on any Account (e.g. the setup/payment
                // event that sets it hasn't committed yet) - track attempts, pick it up next run.
                retryUpdates.add(new stripeGC__Stripe_Event__c(
                    Id         = evt.Id,
                    Retries__c = (evt.Retries__c == null ? 1 : evt.Retries__c + 1)
                ));
                continue;
            }
            accountUpdates.put(accId, new Account(Id = accId, PayProv_MandateId__c = evt.MandateId__c));
        }

        if (!accountUpdates.isEmpty()) update accountUpdates.values();
        if (!retryUpdates.isEmpty())   update retryUpdates;
    }

    public override void finishBatch(Database.BatchableContext bc) {
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_ReconcileStripeEvents');
    }
}
