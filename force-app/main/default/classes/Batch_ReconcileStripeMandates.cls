/**
 * Backfills Account.PayProv_MandateId__c from processed mandate.updated Stripe events whose
 * Account resolution failed at trigger time (Svc_StripeEventProcessor can only resolve the
 * Account via PayProv_PaymentMethodId__c for this event type, which may not have landed on the
 * Account yet when the event itself was processed - a same-transaction or cross-transaction
 * ordering gap, not something a trigger can fix by itself).
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name);
 * chained as a step of the Minut job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt).
 */
global class Batch_ReconcileStripeMandates extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_ReconcileStripeMandates() {
        super('Batch_ReconcileStripeMandates');
    }

    public override Integer getBatchSize() {
        return 200;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
        // no bind variables: the Subscription25 job framework runs the locator outside this method's scope
        return Database.getQueryLocator(
            'SELECT Id, PaymentMethodId__c, MandateId__c, Retries__c FROM stripeGC__Stripe_Event__c' +
            ' WHERE Type__c = \'mandate.updated\' AND Status__c = \'active\'' +
            ' AND MandateId__c != null AND PaymentMethodId__c != null' +
            ' ORDER BY CreatedDate ASC', AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
        List<stripeGC__Stripe_Event__c> events = (List<stripeGC__Stripe_Event__c>) scope;

        Set<String> paymentMethodIds = new Set<String>();
        for (stripeGC__Stripe_Event__c evt : events) paymentMethodIds.add(evt.PaymentMethodId__c);

        Map<String, Account> accountsByPaymentMethod = new Map<String, Account>();
        for (Account a : [
            SELECT Id, PayProv_PaymentMethodId__c, PayProv_MandateId__c
            FROM Account
            WHERE PayProv_PaymentMethodId__c IN :paymentMethodIds
        ]) {
            accountsByPaymentMethod.put(a.PayProv_PaymentMethodId__c, a);
        }

        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        List<stripeGC__Stripe_Event__c> retryUpdates = new List<stripeGC__Stripe_Event__c>();

        for (stripeGC__Stripe_Event__c evt : events) {
            Account acc = accountsByPaymentMethod.get(evt.PaymentMethodId__c);
            if (acc == null) {
                // Payment method still hasn't landed on any Account (e.g. the setup/payment
                // event that sets it hasn't committed yet) - track attempts, pick it up next run.
                retryUpdates.add(new stripeGC__Stripe_Event__c(
                    Id         = evt.Id,
                    Retries__c = (evt.Retries__c == null ? 1 : evt.Retries__c + 1)
                ));
                continue;
            }
            if (acc.PayProv_MandateId__c != evt.MandateId__c) {
                accountUpdates.put(acc.Id, new Account(Id = acc.Id, PayProv_MandateId__c = evt.MandateId__c));
            }
        }

        if (!accountUpdates.isEmpty()) update accountUpdates.values();
        if (!retryUpdates.isEmpty())   update retryUpdates;
    }

    public override void finishBatch(Database.BatchableContext bc) {
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_ReconcileStripeMandates');
    }
}
