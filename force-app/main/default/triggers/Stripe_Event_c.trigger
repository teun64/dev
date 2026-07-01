trigger Stripe_Event_c on stripeGC__Stripe_Event__c (after insert) {
    Svc_StripeEventProcessor.process(Trigger.new);
}