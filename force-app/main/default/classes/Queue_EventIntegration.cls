/**
 * Created by Gerbrand Spaans (Gen25) on 04/01/2024.
 * Gets any Event Logs that are ready for processing. Send these through the handlers.
 * This Queueable is usually started by the Trigger_Event_Log.cls.
 */

public with sharing class Queue_EventIntegration implements Queueable {
    private static final Integer MAX_NUMBER_OF_EVENTS = (Integer)Automation_Hierarchy__c.getInstance().Max_Event_Log_Queue_Size__c;

    public void execute(QueueableContext context) {
        List<Inv_Integration.Request> integrationRequests = new List<Inv_Integration.Request>();
        // Get event logs that can be synced. Send these to their handlers.
        List<Event_Log__c> eventLogs = Queue_EventIntegration.getSubmittedLogsForQueue();
        if(eventLogs.isEmpty()) {
            return;
        }

        for(Event_Log__c log : eventLogs) {
            Inv_Integration.Request r = new Inv_Integration.Request();
            r.integrationDefinitionName = log.Action__c;
            r.relatedRecordId = log.Related_Record_Id__c;
            r.parentLog = Logger2.getInstance(log);
            integrationRequests.add(r);
        }

        // Run the logs to the handler.
        Inv_Integration.execute(integrationRequests);

        // Restart the process for any items that are still or newly queued.
        System.enqueueJob(new Queue_EventIntegration());
    }

    private static List<Event_Log__c> getSubmittedLogsForQueue() {
        return [
                SELECT Id, Related_Record_Id__c, Action__c, GUID__c, CreatedBy.Name,
                    (SELECT Id, GUID__c FROM Event_Logs__r),
                    (SELECT Id, GUID__c FROM OAuth_Logs__r)
                FROM Event_Log__c
                WHERE Status__c IN (:Util_Event.LogEventStatus.SUBMITTED.name(), :Util_Event.LogEventStatus.RESUBMIT.name())
                AND Parent_Event__c = NULL
                ORDER BY CreatedDate ASC
                LIMIT :Queue_EventIntegration.MAX_NUMBER_OF_EVENTS
        ];
    }
}