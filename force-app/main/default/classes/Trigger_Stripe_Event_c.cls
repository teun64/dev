public class Trigger_Stripe_Event_c {
    public static Boolean isRunning = false;
    private static final Integer MAX_RETRIES = 3;

    public static void run() {
        system.debug('Trigger_Stripe_Event_c.run()' );
        if (!Trigger.isExecuting) {
            system.debug('Trigger_Stripe_Event_c.oeps' );
            throw new IllegalStateException('Must be called from trigger');
        }

        List<stripeGC__Stripe_Event__c> newList = (List<stripeGC__Stripe_Event__c>) Trigger.new;
        Map<Id, stripeGC__Stripe_Event__c> oldMap = (Map<Id, stripeGC__Stripe_Event__c>) Trigger.oldMap;
        List<stripeGC__Stripe_Event__c> oldList = (List<stripeGC__Stripe_Event__c>) Trigger.old;

        if (Trigger.isBefore) {

            if (Trigger.isInsert) {
                system.debug('Trigger_Stripe_Event_c.beforeInsert' );
                Trigger_Stripe_Event_c.beforeInsert(newList);
            }

            if (Trigger.isUpdate) {
                system.debug('Trigger_Stripe_Event_c.beforeUpdate' );
                Trigger_Stripe_Event_c.beforeUpdate(newList, oldMap);
            }

            if (Trigger.isDelete) return;
        }

        if (Trigger.isAfter) {

            if (Trigger.isInsert) {
                system.debug('Trigger_Stripe_Event_c.afterInsert' );
                Trigger_Stripe_Event_c.handleEvents(newList);
            }

            if (Trigger.isUpdate) {
                system.debug('Trigger_Stripe_Event_c.afterUpdate' );
                Trigger_Stripe_Event_c.handleEvents(newList, oldMap);
            }

            if ((Trigger.isDelete) || (Trigger.isUndelete)) return;
        }
    }

    private static void beforeInsert(List<stripeGC__Stripe_Event__c> newList) {

        for (stripeGC__Stripe_Event__c evt : newList) {

            // Default values
            if (evt.processed__c == null) {
                evt.processed__c = false;
            }

            if (evt.retries__c == null) {
                evt.retries__c = 0;
            }
        }
    }

    private static void beforeUpdate(List<stripeGC__Stripe_Event__c> newList, Map<Id, stripeGC__Stripe_Event__c> oldMap) {
        // Prevent manual reset of processed flag
        system.debug('beforeUpdate');

        for (stripeGC__Stripe_Event__c evt : newList) {

            stripeGC__Stripe_Event__c oldEvt = oldMap.get(evt.Id);

            if (oldEvt.processed__c == true &&
                evt.processed__c == false) {
                evt.processed__c = true;
            }
        }
    }


    private static void afterInsert(List<stripeGC__Stripe_Event__c> newList) {
        system.debug('Trigger_Stripe_Event_c.afterInsert');
        if (!newList.isEmpty()) Trigger_Stripe_Event_c.handleEvents(newList);
    }

    private static void afterUpdate(List<stripeGC__Stripe_Event__c> newList, Map<Id, stripeGC__Stripe_Event__c> oldMap) {
        system.debug('Trigger_Stripe_Event_c.afterUpdate');
        if (!newList.isEmpty()) Trigger_Stripe_Event_c.handleEvents(newList, oldMap);
    }

    public static void handleEvents( List<stripeGC__Stripe_Event__c> newList) {
        system.debug('Trigger_Stripe_Event_c.handleEvents(newlist)');
        Trigger_Stripe_Event_c.handleEvents(newList, null);
    }

    public static void handleEvents( List<stripeGC__Stripe_Event__c> newList, Map<Id, stripeGC__Stripe_Event__c> oldMap ) {
        system.debug('Trigger_Stripe_Event_c.handleEvents(newlist,oldMap)');

        // Prevent recursion
        if (isRunning) return;

        isRunning = true;

        system.debug('Trigger_Stripe_Event_c.handleEvents(newlist,oldMap) - isRunning');
        List<stripeGC__Stripe_Event__c> toProcess = new List<stripeGC__Stripe_Event__c>();

        system.debug('Trigger_Stripe_Event_c.handleEvents(newlist,oldMap) - newList - Loop');
        for (stripeGC__Stripe_Event__c evt : newList) {
            system.debug('Trigger_Stripe_Event_c.handleEvents(newlist,oldMap) - newList - event ' + evt);

            stripeGC__Stripe_Event__c oldEvt = null;
            Boolean processEvent = true;

            system.debug('evt.Retries__c = ' + evt.Retries__c);

            if (
                !evt.Processed__c
                && evt.stripeGC__Request_Body__c != null
                && evt.stripeGC__Stripe_Event_Id__c != null
                && ((evt.Retries__c == null ? 0 : evt.Retries__c) <= MAX_RETRIES)
            ) {
                system.debug('Trigger_Stripe_Event_c.handleEvents(newlist,oldMap) - newList - add ' + evt);
                toProcess.add(evt);
            }
        }

        if (!toProcess.isEmpty()) {
            system.debug('Trigger_Stripe_Event_c.handleEvents(newlist,oldMap) - Queue_PaymentProviderEventRetry');
            System.enqueueJob(new Queue_PaymentProviderEventRetry(toProcess));
        }
    }


    private class IllegalStateException extends Exception {}
}