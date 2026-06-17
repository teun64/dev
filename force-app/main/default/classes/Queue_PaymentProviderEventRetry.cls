public class Queue_PaymentProviderEventRetry implements Queueable {

    private List<Id> eventIds;

    public Queue_PaymentProviderEventRetry(List<stripeGC__Stripe_Event__c> events) {
        this.eventIds = new List<Id>();
        for (stripeGC__Stripe_Event__c evt : events) {
            this.eventIds.add(evt.Id);
        }
    }

public void execute(QueueableContext context) {

    List<stripeGC__Stripe_Event__c> events = [
        SELECT Id,
               Processed__c,
               Retries__c,
               Error__c,
               stripeGC__Request_Body__c,
               stripeGC__Stripe_Event_Id__c,
               stripeGC__Stripe_Account__c
        FROM stripeGC__Stripe_Event__c
        WHERE Id IN :eventIds
    ];

    if (!events.isEmpty()) {
        Util_PaymentProvider.handleEvents(events);
    }
}
}