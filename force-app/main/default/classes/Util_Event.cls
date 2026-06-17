public without sharing class Util_Event {
    public enum LogResultStatus {
		COMPLETED,
		WARNING,
		ERROR,
		UNHANDLED_EXCEPTION
	}

	public enum LogEventStatus {
		SUBMITTED,
		PROCESSING,
		PENDING,
		RESUBMIT,
		PROCESSED,
		CANCELLED
	}
	public final static Set<String> FINISHED_EVENT_STATUS = new Set<String> {
		Util_Event.LogEventStatus.PROCESSED.name(),
		Util_Event.LogEventStatus.CANCELLED.name()
	};

	public static Event_Log__c getLog(String guid, String callingSystem, String receivingSystem,  String objectName, String action, Id contextId, String contextName, String externalId){
		Event_Log__c log;

		if (String.isBlank(guid)) {
			log = Util_Event.createLog(callingSystem, receivingSystem, objectName, action, contextId, contextName, externalId);
		} else {
			log = [
					SELECT Id, Type__c, Calling_System__c, Receiving_System__c, Object__c, Action__c, Context_Id__c, Context_Name__c, extId__c, GUID__c, Result_Status__c, Message__c, Integration_Status__c
					FROM Event_Log__c
					WHERE GUID__c = :guid
			];
		}

		log.Result_Status__c = Util_Event.LogResultStatus.COMPLETED.name();
		log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSING.name();
		log.Message__c = '';

		return log;
	}

	public static Event_Log__c createLog(String callingSystem, String receivingSystem, String objectName, String action, Id contextId, String contextName, String externalId){
		Event_Log__c log = new Event_Log__c();
		log.Type__c = 'INTEGRATION';
		log.Calling_System__c = callingSystem;
		log.Receiving_System__c = receivingSystem;
		log.Object__c = objectName;
		log.Action__c = action;
		log.Context_Id__c = contextId;
		log.Context_Name__c = contextName;
		log.extId__c = externalId;
		log.GUID__c = Util_System.generateGUID();
		return log;
	}
}