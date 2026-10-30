/**
 * Publishes Order_Process__e for Util_OrderConfirmation (2026-10-30).
 *
 * Deliberately on API 66.0: from 67.0 Apex runs in user mode by default and EventBus.publish then needs Create on
 * Order_Process__e for the running user (Sales closing an order, a portal user placing one). Without it the
 * publish fails silently ("Access to entity 'Order_Process__e' denied") and no confirmation is sent.
 * EventBus.publish has no AccessLevel parameter, so keep this class below 67.0.
 */
public without sharing class Util_OrderProcessPublisher {
    public static List<Database.SaveResult> publish(List<Order_Process__e> events) {
        if (events == null || events.isEmpty()) return new List<Database.SaveResult>();
        List<Database.SaveResult> results = EventBus.publish(events);
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) System.debug(LoggingLevel.ERROR, 'Order_Process__e not published: ' + result.getErrors());
        }
        return results;
    }
}
