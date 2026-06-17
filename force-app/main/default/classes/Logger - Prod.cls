/**
 * Created by Gerbrand Spaans (Gen25) on 15/12/2023.
 * Introduced as a logger helper to help in the Event Based Architecture for MI. The Util_OAuth and Util_Event did this
 * historically, but had some built in artefacts that were not wanted.
 * Creates an Event Log record as a Parent
 * Creates OAuth_Log__c records to log single integration events. These are linked to the parent.
 * Creates Event_Log__c records to log single (internal) events. These are linked to the parent.
 */

 public with sharing class Logger {
    public enum INTEGRATION_STATUS {
        SUBMITTED,
        SUCCESS,
        FAILED,
        RETRY
    }
    public enum LOGGING_TYPE {
        Session,
        Process
    }

    // the instance properties
    private static Logger log;
    private Event_Log__c eventLog;
    private Map<String, OAuth_Log__c> sessionLogs;
    private Map<String, Event_Log__c> processLogs;

    public static Logger getNewInstance() {
        Logger.log = new Logger();
        return Logger.log;
    }
    public static Logger getInstance() {
        if(Logger.log == null) {
            Logger.log = new Logger();
        }
        return Logger.log;
    }
    public static Logger getInstance(String parentEventGuid) {
        if(String.isBlank(parentEventGuid)) {
            return Logger.getInstance();
        }
        Logger l = new Logger();
        Event_Log__c e = [SELECT Id, GUID__c, Stack_Trace__c, Context_Id__c, (SELECT Id, GUID__c, Stack_Trace__c, Context_Id__c FROM Event_Logs__r ORDER BY Execution_Order__c ASC), (SELECT Id, GUID__c, Request_Body__c, Response_Body__c FROM OAuth_Logs__r ORDER BY Execution_Order__c ASC) FROM Event_Log__c WHERE GUID__c = :parentEventGuid];
        return Logger.getInstance(e);
    }
    public static Logger getInstance(Event_Log__c parentLog) {
        if(parentLog == null) {
            return Logger.getInstance();
        }
        Logger l = new Logger();
        l.eventLog = parentLog;
        for(OAuth_Log__c session : parentLog.OAuth_Logs__r) {
            l.sessionLogs.put(session.GUID__c, session);
        }
        for(Event_Log__c childEvent : parentLog.Event_Logs__r) {
            l.processLogs.put(childEvent.GUID__c, childEvent);
        }
        return l;
    }

    private Logger() {
        this.eventLog = new Event_Log__c();
        this.eventLog.GUID__c = Util_System.generateGUID();

        this.sessionLogs = new Map<String, OAuth_Log__c>();
        this.processLogs = new Map<String, Event_Log__c>();
    }
    // Someone decided to abbreviate some picklist api values, but not others. So this sometimes needs to be translated...
    private static final Map<String, String> eventLogSystemMap = new Map<String, String>{
            'Salesforce' => 'S',
            'Exact' => 'E',
            'S' => 'S',
            'E' => 'E'
    };
    public void setContext(String callingSystem, String receivingSystem, String actionName, SObject relatedRecordContext, String asyncJobId) {
        this.eventLog.Type__c = 'INTEGRATION'; // todo set to parent
        this.eventLog.Calling_System__c = Logger.eventLogSystemMap.get(callingSystem);
        this.eventLog.Receiving_System__c = Logger.eventLogSystemMap.get(receivingSystem);
        this.eventLog.Action__c = actionName;
        this.eventLog.Status__c = Util_Event.LogEventStatus.PROCESSING.name();
        this.eventLog.Context_Id__c = relatedRecordContext?.Id;
        this.eventLog.Object__c = relatedRecordContext?.getSObjectType().getDescribe().getName();
        this.eventLog.Context_Name__c = (String)relatedRecordContext?.get('Name');
        this.eventLog.Execution_Order__c = 0; // because this is a parent
        this.eventLog.Async_Job_Id__c = asyncJobId;
    }
    public void setContext(Integration_Definition__c definition, SObject relatedRecord, String asyncJobId) {
        this.setContext(definition.Calling_System__c, definition.Receiving_System__c, definition.Name, relatedRecord, asyncJobId);
    }
    public String getParentGuid() {
        return this.eventLog.GUID__c;
    }
    /**
     * Get OAuth Log record by GUID
     * @param guid GUID for the log
     *
     * @return OAuth Log record
     */
    public OAuth_Log__c getSessionLog(String guid) {
        return this.sessionLogs.get(guid);
    }
    /**
     * Get Event Log record by GUID
     * @param guid GUID for the log
     *
     * @return Event Log record
     */
    public Event_Log__c getProcessLog(String guid) {
        return this.processLogs.get(guid);
    }
    public String addSessionResult(OAuth_Log__c log) {
        // Set a GUID if not yet present
        log.GUID__c = String.isNotBlank(log.GUID__c) ? log.GUID__c : Util_System.generateGUID();
        // Link to the Event Log record
        log.Event_Log__r = this.eventLog;
        // add to the current list
        this.sessionLogs.put(log.GUID__c, log);
        return log.GUID__c;
    }

    /**
     * Save all logs in their current state
     */
    public void saveAll() {
        this.eventLog.Status__c = Util_Event.LogEventStatus.PROCESSED.name();

        // get ContentDocuments for wherever a field is not big enough (and an overflow may be expected)
        Map<String, List<ContentVersion>> contentOverflows = this.getOverflows();

        // Upsert the parent event
        Database.upsert(this.eventLog, Event_Log__c.GUID__c);
        // upsert the integration logs
        Database.upsert(this.sessionLogs.values(), OAuth_Log__c.GUID__c);
        // upsert message logs
        Database.upsert(this.processLogs.values(), Event_Log__c.GUID__c);

        // insert any Content Versions and Document Links where needed.
        if(!contentOverflows.isEmpty()) {
            List<ContentDocumentLink> linksToCreate = this.getContentDocumentLinks(contentOverflows);
            Database.insert(linksToCreate);
        }
    }
    /**
     * Create Content Document Links for the provided Overflow documents and related log records
     * @param contentOverflows Mapped Overflow Documents, mapped by the related log id
     *
     * @return ContentDocumentLink records with Overflow Documents
     */
    private List<ContentDocumentLink> getContentDocumentLinks(Map<String, List<ContentVersion>> contentOverflows) {
        List<ContentVersion> allVersions = new List<ContentVersion>();
        for (List<ContentVersion> cvl : contentOverflows.values()) {
            allVersions.addAll(cvl);
        }
        Database.insert(allVersions);

        Map<Id, ContentVersion> versions = new Map<Id, ContentVersion>([SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :allVersions]);
        List<ContentDocumentLink> linksToCreate = new List<ContentDocumentLink>();
        for (String logGuid : contentOverflows.keySet()) {
            for (ContentVersion file : contentOverflows.get(logGuid)) {
                ContentDocumentLink link = new ContentDocumentLink();
                link.LinkedEntityId = this.sessionLogs.containsKey(logGuid) ? this.getSessionLog(logGuid).Id : this.getProcessLog(logGuid).Id;
                link.ContentDocumentId = versions.get(file.Id).ContentDocumentId;
                link.ShareType = 'I'; //inherit sharing from the linked object
                linksToCreate.add(link);
            }
        }
        return linksToCreate;
    }
    /**
     * Process a full rollback for all process and session logs. Sets all logs to Cancelled State.
     * @param causingProcess The process guid that triggered the rollback. This log is set to Error, all other logs to Cancelled
     */
    public void processFullRollback(String causingProcess) {
        this.eventLog.Status__c = Util_Event.LogEventStatus.CANCELLED.name();

        for(String processGuid : this.processLogs.keySet()) {
            if(processGuid != causingProcess) {
                this.cancelProcess(processGuid);
            }
        }
        for(String sessionGuid : this.sessionLogs.keySet()) {
            if(sessionGuid != causingProcess) {
                this.cancelSession(sessionGuid);
            }
        }
    }
    /**
     * Initialize a process.
     * @param processName Name of the process
     * @param callerSystem The calling System
     * @param relatedRecord The related record
     *
     * @return Event Log Guid. Used to update the status later.
     */
    public String startProcess(String processName, String callerSystem, SObject relatedRecord) {
        return this.startProcess(processName, callerSystem, 'S', relatedRecord);
    }
    private String startProcess(String processName, String callerSystem, String receivingSystem, SObject relatedRecord) {
        Event_Log__c e = new Event_Log__c(
                GUID__c = Util_System.generateGUID(),
                Parent_Event__r = new Event_Log__c(GUID__c = this.eventLog.GUID__c),
                Status__c = Util_Event.LogEventStatus.PROCESSING.name(),
                Action__c = processName,
                Calling_System__c = callerSystem,
                Receiving_System__c = receivingSystem,
                Type__c = 'INTERNAL',
                Related_Record_Id__c = relatedRecord?.Id,
                Object__c = relatedRecord?.getSObjectType().getDescribe().getName(),
                Context_Name__c = (String)relatedRecord?.get('Name'),
                Execution_Order__c = this.getOrder(),
                Context_Id__c = this.eventLog.Context_Id__c,
                Stack_Trace__c = null
        );
        this.processLogs.put(e.GUID__c, e);
        return e.GUID__c;
    }
    /**
     * Finalize a process log with an exception context
     * @param eventGuid The Guid identifier of the log
     * @param e The exception that is thrown
     */
    public void finalizeProcess(String eventGuid, Exception e) {
        this.finalizeProcess(eventGuid, Util_Event.LogResultStatus.ERROR.name(), e.getMessage(), e.getStackTraceString());
    }
    /**
     * Finalize a process log successfully.
     * @param eventGuid The Guid identifier of the log
     * @param successMessage Message to log
     */
    public void finalizeProcess(String eventGuid, String successMessage) {
        this.finalizeProcess(eventGuid, Util_Event.LogResultStatus.COMPLETED.name(), successMessage, null);
    }
    /**
     * Cancel a process.
     * @param eventGuid The Guid identifier of the log
     */
    public void cancelProcess(String eventGuid) {
        this.finalizeProcess(eventGuid, Util_Event.LogResultStatus.ERROR.name(), 'Process cancelled and rolled back due to error in other process', null);
    }
    private void finalizeProcess(String eventGuid, String statusName, String message, String stackTrace) {
        Event_Log__c e = this.getProcessLog(eventGuid);
        e.Status__c = statusName;
        e.Message__c = message;
        e.Stack_Trace__c = stackTrace;
        this.processLogs.put(eventGuid, e);
    }
    /**
     * Start logging for an outgoing session
     * @param httpRequest HttpRequest that is sent
     * @param integrationDefinitionName Name of the Integration
     * @param receivingSystem Code for the system receiving the message
     *
     * @return Log Guid. Use this to update the log after the result is received.
     */
    public String startSession(HttpRequest httpRequest, String integrationDefinitionName, String receivingSystem) {
        return this.startSession(integrationDefinitionName, 'S', receivingSystem, httpRequest.getMethod(), httpRequest.getBody(), httpRequest.getEndpoint());
    }
    /**
     * Start logging for an incoming session
     * @param restRequest RestRequest that is received
     * @param integrationDefinitionName Name of the Integration
     * @param callingSystem Code for the system sending the message
     *
     * @return Log Guid. Use this to update the log after the result is sent back.
     */
    public String startSession(RestRequest restRequest, String integrationDefinitionName, String callingSystem) {
        return this.startSession(integrationDefinitionName, callingSystem, 'S', restRequest.httpMethod, restRequest.requestBody?.toString(), restRequest.requestURI);
    }
    /**
     * Generic method to log any starting integrations
     * @param integrationDefinitionName Name of the Integration
     * @param callingSystem Code for the system sending the message
     * @param receivingSystem Code for the system receiving the message
     * @param requestMethod HttpMethod
     * @param requestBody Request Body
     * @param requestEndpoint Endpoint URL
     *
     * @return Log GUID value
     */
    private String startSession(String integrationDefinitionName, String callingSystem, String receivingSystem, String requestMethod, String requestBody, String requestEndpoint) {
        OAuth_Log__c log = new OAuth_Log__c(
                GUID__c = Util_System.generateGUID(),
                Context__c = integrationDefinitionName,
                Calling_System__c = callingSystem,
                Receiving_System__c = receivingSystem,
                Method__c = requestMethod,
                Request_Body__c = requestBody,
                Endpoint__c = requestEndpoint,
                Status__c = Logger.INTEGRATION_STATUS.SUBMITTED.name(),
                Event_Log__r = new Event_Log__c(GUID__c = this.eventLog.GUID__c),
                Execution_Order__c = this.getOrder()
        );
        this.sessionLogs.put(log.GUID__c, log);
        return log.GUID__c;
    }
    public void setSessionRecordExternalId(String logId, String recordExternalId) {
        OAuth_Log__c log = this.getSessionLog(logId);
        log.Record_External_Id__c = recordExternalId;
    }
    public void setSessionRecord(String logId, Id recordId, String recordName) {
        OAuth_Log__c log = this.getSessionLog(logId);
        log.Record_Id__c = recordId;
        log.Record_Name__c = recordName;
    }
    public void setCallingSystem(String logId, Long platformId) {
        String callingSystem = platformId != null
            ? String.valueOf(platformId)
            : null;
        this.setCallingSystem(logId, callingSystem);
    }
    public void setCallingSystem(String logId, String callingSystem) {
        OAuth_Log__c log = this.getSessionLog(logId);
        log.Calling_System__c = callingSystem;
    }
    public void updateSession(String logId, HttpRequest request, String receivingSystem) {
        OAuth_Log__c log = this.getSessionLog(logId);
        log.Calling_System__c = 'S';
        log.Receiving_System__c = String.isNotBlank(receivingSystem) ? receivingSystem : log.Receiving_System__c;
        log.Method__c = String.isNotBlank(request?.getMethod()) ? request.getMethod() : log.Method__c;
        log.Request_Body__c = String.isNotBlank(request?.getBody()) ? request.getBody() : log.Request_Body__c;
        log.Endpoint__c = String.isNotBlank(request?.getEndpoint()) ? request.getEndpoint() : log.Endpoint__c;
    }
    /**
     * Log the result of an outgoing integration
     * @param sessionGuid The GUID of the log to update
     * @param httpResponse The HttpResponse returned
     */
    public void finalizeSession(String sessionGuid, HttpResponse httpResponse) {
        this.finalizeSession(sessionGuid, httpResponse.getBody(), httpResponse.getStatusCode());
    }
    /**
     * Log the result of an incoming integration
     * @param sessionGuid The GUID of the log to update
     * @param restResponse The HttpResponse returned
     */
    public void finalizeSession(String sessionGuid, RestResponse restResponse) {
        this.finalizeSession(sessionGuid, restResponse?.responseBody?.toString(), restResponse?.statusCode);
    }
    /**
     * Log an Exception on an integration
     * @param sessionGuid Guid of the session
     * @param e Exception
     */
    public void finalizeSession(String sessionGuid, Exception e) {
        this.finalizeSession(sessionGuid, e.getMessage(), 0);
    }
    public void cancelSession(String sessionGuid) {
        this.finalizeSession(sessionGuid, 'Integration cancelled and rolled back due to error in another process', Logger.INTEGRATION_STATUS.FAILED.name(), null);
    }
    /**
     * Generic method to log any finalized integrations
     * @param sessionGuid The GUID of the log to update
     * @param responseBody The response body as string
     * @param statusCode The status code
     */
    public void finalizeSession(String sessionGuid, String responseBody, Integer statusCode) {
        String statusName = statusCode < 300 && statusCode > 199 ? Logger.INTEGRATION_STATUS.SUCCESS.name() : Logger.INTEGRATION_STATUS.FAILED.name();
        this.finalizeSession(sessionGuid, responseBody, statusName, statusCode);
    }
    /**
     * Generic method to log any finalized integrations
     * @param sessionGuid The GUID of the log to update
     * @param responseBody The response body as string
     * @param statusName Status to set on the log record.
     * @param statusCode The status code
     */
    private void finalizeSession(String sessionGuid, String responseBody, String statusName, Integer statusCode) {
        OAuth_Log__c log = this.getSessionLog(sessionGuid);
        log.Response_Body__c = responseBody;
        log.Status_Code__c = statusCode;
        log.Status__c = statusName;

        this.sessionLogs.put(log.GUID__c, log);
    }
    /**
     * If certain fields may have an overflow, store the full value of the log in a Content Document. This method is
     * called once in the saveAll() method.
     * @return List of ContentVersions mapped by the related log record GUID
     */
    @TestVisible
    private Map<String, List<ContentVersion>> getOverflows() {
        Map<String, List<ContentVersion>> overflowDocuments = new Map<String, List<ContentVersion>>();
        for(OAuth_Log__c sessionLog : this.sessionLogs.values()) {
            List<ContentVersion> sessionLogDocs = new List<ContentVersion>();
            // Check for the provided fields if they are too long, and if so truncate the field and create a ContentVersion.
            if(Logger.isFieldOverflowing(sessionLog, 'Request_Body__c')) {
                ContentVersion requestFile = Logger.createOverflowDocument(sessionLog,'Request_Body__c', 'request-txt', 'request.txt');
                Logger.truncateField(sessionLog, 'Request_Body__c');
                sessionLogDocs.add(requestFile);
            }
            if(Logger.isFieldOverflowing(sessionLog, 'Response_Body__c')) {
                ContentVersion responseFile = Logger.createOverflowDocument(sessionLog, 'Response_Body__c', 'response-txt', 'response.txt');
                Logger.truncateField(sessionLog, 'Response_Body__c');
                sessionLogDocs.add(responseFile);
            }
            if(!sessionLogDocs.isEmpty()) {
                overflowDocuments.put(sessionLog.GUID__c, sessionLogDocs);
            }
        }
        for(Event_Log__c processLog : this.processLogs.values()) {
            List<ContentVersion> processLogDocs = new List<ContentVersion>();
            if(Logger.isFieldOverflowing(processLog, 'Stack_Trace__c')) {
                ContentVersion stackTraceFile = Logger.createOverflowDocument(processLog, 'Stack_Trace__c', 'stacktrace-txt', 'stacktrace.txt');
                Logger.truncateField(processLog, 'Stack_Trace__c');
                processLogDocs.add(stackTraceFile);
            }
            if(Logger.isFieldOverflowing(processLog, 'Message__c')) {
                ContentVersion stackTraceFile = Logger.createOverflowDocument(processLog, 'Message__c', 'message-txt', 'message.txt');
                Logger.truncateField(processLog, 'Message__c');
                processLogDocs.add(stackTraceFile);
            }
            if(!processLogDocs.isEmpty()) {
                overflowDocuments.put(processLog.GUID__c, processLogDocs);
            }
        }
        return overflowDocuments;
    }
    /**
     * Create an Overflow Document for the provided record. The Overflow Document contains the full version as set by
     * the Logger class, whenever the information is too long to be contained in the field.
     * @param record The log record that contains the information
     * @param fieldName the field containing the information
     * @param pathName The Path On Client to set on the Content Document
     * @param fileName The File Name to set on the Content Document
     *
     * @return Content Version record
     */
    private static ContentVersion createOverflowDocument(SObject record, String fieldName, String pathName, String fileName) {
        ContentVersion requestFile = new ContentVersion(
                VersionData = Blob.valueOf(String.valueOf(record.get(fieldName))),
                PathOnClient = pathName,
                Title = fileName
        );
        return requestFile;
    }
    /**
     * Safely truncate a field on the provided record to the maximum amount of allowed characters.
     * @param record The record containing the field that needs to be truncated
     * @param fieldName The field that needs to be truncated
     */
    @TestVisible
    private static void truncateField(SObject record, String fieldName) {
        // Get the maximum length allowed for this field
        Integer maxFieldLength = record.getSObjectType().getDescribe().fields.getMap().get(fieldName).getDescribe().length;
        record.put(fieldName, String.valueOf(record.get(fieldName)).left(maxFieldLength));
    }
    /**
     * Check whether the field value on the record is too long to be contained.
     * @param record The record containing the field to check
     * @param fieldName The field to check
     *
     * @return True if the field value is too long
     */
    @TestVisible
    private static Boolean isFieldOverflowing(SObject record, String fieldName) {
        // Get the maximum length allowed for this field
        Integer maxFieldLength = record.getSObjectType().getDescribe().fields.getMap().get(fieldName).getDescribe().length;
        String fieldValue = String.valueOf(record.get(fieldName));
        return String.isNotBlank(String.valueOf(record.get(fieldName))) && maxFieldLength < fieldValue.length();
    }
    /**
     * Get the current execution order for the log. Includes both the amount of process logs as well as session logs.
     * @return The current execution order value.
     */
    private Integer getOrder() {
        return this.sessionLogs.size() + this.processLogs.size() + 1;
    }
}