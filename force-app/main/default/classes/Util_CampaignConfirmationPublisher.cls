/**
 * Publishes CampaignConfirmation__e for Svc_CampaignConfirmation (2026-11-10).
 *
 * Deliberately on API 66.0, like Util_OrderProcessPublisher: from 67.0 Apex runs in user mode by default and
 * EventBus.publish then needs Create on the event for the running user (the Customer Hub guest on the response page).
 * Without it the publish fails silently and no confirmation is sent. EventBus.publish has no AccessLevel parameter.
 */
public without sharing class Util_CampaignConfirmationPublisher {
	public static List<Database.SaveResult> publish(List<CampaignConfirmation__e> events) {
		if (events == null || events.isEmpty()) return new List<Database.SaveResult>();
		List<Database.SaveResult> results = EventBus.publish(events);
		for (Database.SaveResult result : results) {
			if (!result.isSuccess()) System.debug(LoggingLevel.ERROR, 'CampaignConfirmation__e not published: ' + result.getErrors());
		}
		return results;
	}
}
