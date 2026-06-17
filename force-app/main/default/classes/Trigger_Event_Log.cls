/**
 * Created by Gerbrand Spaans (Gen25) on 04/01/2024.
 */

public with sharing class Trigger_Event_Log {
    public static final String EVENT_JOB_NAME = 'Queue_EventIntegration';
    public static void run() {
        if(!Trigger.isExecuting) {
            return;
        }
        if(!Automation_Hierarchy__c.getInstance().Trigger_Event_Log__c) {
            return;
        }
        if(Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
            Trigger_Event_Log.runEventBatch();
        }
    }

    private static void runEventBatch() {
        List<Event_Log__c> eventLogs = (List<Event_Log__c>) Trigger.new;
        Trigger_Event_Log.runEventBatch(eventLogs);
    }
    public static void runEventBatch(List<Event_Log__c> eventLogs) {
        // Get Processable Events in Trigger Context
        List<Event_Log__c> newProcesses = new List<Event_Log__c>();
        for(Event_Log__c el : eventLogs) {
            // Should be Parent Event and status should be Resubmit or Submitted
            if(String.isBlank(el.Parent_Event__c) && (el.Status__c?.toUpperCase() == Util_Event.LogEventStatus.SUBMITTED.name() || el.Status__c?.toUpperCase() == Util_Event.LogEventStatus.RESUBMIT.name())) {
                newProcesses.add(el);
            }
        }
        if(newProcesses.isEmpty()) {
            return;
        }
        // Check if the process is already running. If so, the process will requeue itself and will run when it runs.
        List<AsyncApexJob> currentJobs = [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME AND Status IN ('Preparing','Processing','Queued')];
        if(currentJobs.isEmpty()) {
            // no current running jobs, start a new process
            Queue_EventIntegration integrationJob = new Queue_EventIntegration();
            System.enqueueJob(integrationJob);
        }
    }
}