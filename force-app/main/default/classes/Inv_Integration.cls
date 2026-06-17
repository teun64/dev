/**
 * Created by Gerbrand Spaans (Gen25) on 22/12/2023.
 * Invocable that allows flows to run the event process directly. Process is Bulkified.
 * For asynchronous execution, see the Queue_IntegrationEvent.
 */

public with sharing class Inv_Integration {
    /**
     * Request Container. Internal private properties are set during the execute() phase.
     */
    public class Request {
        @InvocableVariable(Label='Integration Definition Name' Description='The name of the Integration Definition that contains the Events' Required=true)
        public String integrationDefinitionName;
        @InvocableVariable(Label='Related Record Id' Description='The Id of the record that is the basis of the integration' Required=true)
        public Id relatedRecordId;

        public Logger2 parentLog;

        private SObject relatedRecord;
        private Integration_Definition__c definition;
        private List<Integration_Event__c> eventContext;
    }
    /**
     * Result container. Contains the result of the specified action, and the Parent Event Guid.
     */
    public class Result {
        @InvocableVariable(Label='Result Was Success' Description='True if the process has run successfully')
        public Boolean isSuccess;
        @InvocableVariable(Label='Result Message' Description='The message returned by the main process handler')
        public String message;
        @InvocableVariable(Label='Log Guid' Description='The GUID of the Main Event Log record')
        public String eventGuid;
    }

    /**
     * Invocable method to start an integration or process defined in an Integration Definition object
     * @param requests Inv_Integration Request, contains the context of the integration to start.
     *
     * @return Result object.
     */
    @InvocableMethod(Description='Start a Process' Label='Start a Process')
    public static List<Inv_Integration.Result> execute(List<Inv_Integration.Request> requests) {
        List<Inv_Integration.Result> results = new List<Inv_Integration.Result>();

        Inv_Integration.setRequestContext(requests);

        System.debug('inv ' + requests.size());
        for(Inv_Integration.Request integrationRequest : requests) {

            System.debug(integrationRequest);
            Inv_Integration.Result result = new Inv_Integration.Result();
            try {
                String eventLogGuid = Util_Integration.startIntegration(integrationRequest.parentLog, integrationRequest.definition, integrationRequest.eventContext, integrationRequest.relatedRecord);
                result.isSuccess = true;
                result.message = 'Process ran successfully';
                result.eventGuid = eventLogGuid;
            } catch (Util_System.IntegrationDefinitionException e) {
                result.isSuccess = false;
                result.message = e.getMessage();
            } catch(Exception e) {
                System.debug(e.getStackTraceString());
                result.isSuccess = false;
                result.message = 'An unexpected error occurred: ' + e.getMessage();
            }
            System.debug(result);
            results.add(result);
        }
        return results;
    }

    /**
     * To make sure that these requests are bulkified, the relatedRecord SObject and the Integration Definition are proactively queried and set in the request.
     * @param requests Inv_Integration request objects.
     */
    private static void setRequestContext(List<Inv_Integration.Request> requests) {
        Set<String> definitionNames = new Set<String>();
        Set<Id> relatedRecordIds = new Set<Id>();
        Set<String> recordObjects = new Set<String>();
        for(Inv_Integration.Request r : requests) {
            definitionNames.add(r.integrationDefinitionName);
            relatedRecordIds.add(r.relatedRecordId);
            recordObjects.add(r.relatedRecordId.getSobjectType().getDescribe().getName());
        }

        // query all integration definitions
        Map<String, Integration_Definition__c> definitionsByName = Util_Integration.getIntegrationDefinitionsByName(new List<String>(definitionNames));
        // query all integration events
        Map<String, List<Integration_Event__c>> eventsByDefinition = Util_Integration.getIntegrationEvents(new List<String>(definitionNames));
        // query all records and set them in a record map
        Map<Id, SObject> recordMap = new Map<Id, SObject>();
        for(String sobjectName : recordObjects) {
            String sobjectFields = String.join(new List<String>(Schema.getGlobalDescribe().get(sobjectName).getDescribe().fields.getMap().keySet()), ',');
            for(SObject relatedRecord : Database.queryWithBinds('SELECT ' + sobjectFields + ' FROM ' + sobjectName + ' WHERE Id IN :recordIds', new Map<String, Object>{'recordIds' => relatedRecordIds}, AccessLevel.SYSTEM_MODE)) {
                recordMap.put(relatedRecord.Id, relatedRecord);
            }
        }

        // set the sobject and integration definition
        for(Inv_Integration.Request r : requests) {
            r.relatedRecord = recordMap.get(r.relatedRecordId);
            r.definition = definitionsByName.get(r.integrationDefinitionName);
            r.eventContext = eventsByDefinition.get(r.integrationDefinitionName);
        }
    }
}