/**
 * Created by Gerbrand Spaans (Gen25) on 21/12/2023.
 */

public with sharing class Util_Integration {
    public enum ERROR_HANDLING_TYPES {
        ContinueOnError,
        StopOnError,
        FullRollback
    }
    /**
     * Get Integration Event records and Event Fields that are related to the parent Definition.
     * @param parentDefinition Integration Definition that contains the requested integration events
     *
     * @return Integration Event records and Integration Event Field records. Event records are returned sorted by the
      * Execution Order values.
     */
    public static List<Integration_Event__c> getIntegrationEvents(Integration_Definition__c parentDefinition) {
        return [
            SELECT Id, Name, Type__c, Execution_Order__c, Handler_Name__c, Handler_SObject_Type__c, Integration_Definition__c, Integration_Definition__r.Name, Logging_Type__c, (
                SELECT Id, Name, Data_Type__c, Mapping_Name__c, Type__c, Static_Value__c
                FROM Event_Fields__r
                WHERE Is_Active__c = TRUE
            )
            FROM Integration_Event__c
            WHERE Is_Active__c = TRUE AND Integration_Definition__c = :parentDefinition.Id
            ORDER BY Execution_Order__c ASC
    ];
    }
    public static Map<String, List<Integration_Event__c>> getIntegrationEvents(List<String> definitionNames) {
        Map<String, List<Integration_Event__c>> dataContextByDefinitionName = new Map<String, List<Integration_Event__c>>();
        for(Integration_Event__c event : [
            SELECT Id, Name, Type__c, Execution_Order__c, Handler_Name__c, Handler_SObject_Type__c, Integration_Definition__c, Integration_Definition__r.Name, Logging_Type__c, (
                    SELECT Id, Name, Data_Type__c, Mapping_Name__c, Type__c, Static_Value__c
                    FROM Event_Fields__r
                    WHERE Is_Active__c = TRUE
            )
            FROM Integration_Event__c
            WHERE Is_Active__c = TRUE AND Integration_Definition__r.Name IN :definitionNames
            ORDER BY Execution_Order__c ASC
        ]) {
            if(dataContextByDefinitionName.containsKey(event.Integration_Definition__r.Name)) {
                dataContextByDefinitionName.get(event.Integration_Definition__r.Name).add(event);
            } else {
                dataContextByDefinitionName.put(event.Integration_Definition__r.Name, new List<Integration_Event__c>{event});
            }
        }
        return dataContextByDefinitionName;
    }
    /**
     * Get the Integration Definition record. These records contain context around integrations.
     * @param definitionName The name of the integration definition. This is the value in the Name field
     *
     * @return Integration Definition record with all relevant fields. Does not contain any child records.
     */
    public static Integration_Definition__c getIntegrationDefinitionByName(String definitionName) {
        List<Integration_Definition__c> integrationDefinitions = Util_Integration.getIntegrationDefinitionsByName(new List<String>{definitionName}).values();
        if(integrationDefinitions.isEmpty()) {
            throw new IntegrationDefinitionException('No Integration Definition found with name ' + definitionName);
        }
        return integrationDefinitions[0];
    }

    /**
     * Get multiple integration definitions by the names of the records
     * @param definitionNames List of integration names, as defined in the Name field
     *
     * @return Integration Definition records
     */
    public static Map<String, Integration_Definition__c> getIntegrationDefinitionsByName(List<String> definitionNames) {
        Map<String, Integration_Definition__c> definitionMap = new Map<String, Integration_Definition__c>();

        List<Integration_Definition__c> integrationDefinitions = [
                SELECT Id, Name, Calling_System__c, Receiving_System__c, Named_Credential__c, Time_Out__c, Error_Handling__c
                FROM Integration_Definition__c
                WHERE Name IN :definitionNames
        ];
        for(Integration_Definition__c def : integrationDefinitions) {
            definitionMap.put(def.Name, def);
        }
        return definitionMap;
    }

    /**
     * Start the integration process as defined by the Integration Event records on the Integration Definition. All
     * actions are logged under Event_Log__c records.
     * This method queries the Integration Definition and the Integration Events and is therefore intended for
     * single use only.
     * @param definitionName The name of the Integration Definition that defines the process
     * @param recordId The Id of the record that contains the data
     *
     * @return Guid for the parent Event_Log__c record
     */
    public static String startIntegration(String definitionName, Id recordId) {
        Integration_Definition__c definition = Util_Integration.getIntegrationDefinitionByName(definitionName);
        List<Integration_Event__c> eventContext = Util_Integration.getIntegrationEvents(definition);

        SObject relatedRecord;
        try{
            String sobjectName = recordId.getSobjectType().getDescribe().getName();
            String sobjectFields = String.join(new List<String>(Schema.getGlobalDescribe().get(sobjectName).getDescribe().fields.getMap().keySet()), ',');
            relatedRecord = Database.queryWithBinds('SELECT ' + sobjectFields + ' FROM ' + sobjectName + ' WHERE Id = :recordId', new Map<String, Object>{'recordId' => recordId}, AccessLevel.SYSTEM_MODE);
        } catch (QueryException e) {
            throw new IntegrationDefinitionException('Could not find the specified record');
        }
        return Util_Integration.startIntegration(null, definition, eventContext, relatedRecord);
    }

    /**
     * Start the integration process as defined by the Integration Event records on the Integration Definition. All
     * actions are logged under Event_Log__c records.
     * This method does not retrieve any data, except for anything queried by the handler logic, and is therefore usable
     * in bulkified contexts.
     * See for instance Inv_Integration for an example on how to handle this.
     * @param log Logger object. If null it will be created
     * @param definition The Integration Definition that defines the process
     * @param eventContext The Event Context
     * @param record The  record that contains the data
     *
     * @return Guid for the parent Event_Log__c record
     */
    public static String startIntegration(Logger log, Integration_Definition__c definition, List<Integration_Event__c> eventContext, SObject record) {
        if(log == null) {
            log = Logger.getNewInstance();
        }
        log.setContext(definition, record, null);

        // Prepare the response map. This is shared between handlers and allows sharing and passing back and forth
        // information. The Record SObject is defaulted to 'record'.
        Map<String, Object> variableMap = new Map<String, Object>{'record' => record};

        for(Integration_Event__c event : eventContext) {
            System.debug(event.Name);
            // Prepare and start the logging based on the provided preferences.
            String logGuid = '';
            if(event.Logging_Type__c == Logger.LOGGING_TYPE.Process.name()) {
                logGuid = log.startProcess(event.Name, 'S', record);
            } else if(event.Logging_Type__c == Logger.LOGGING_TYPE.Session.name()) {
                // no info yet, but bootstrap a log anyway.
                logGuid = log.startSession(new HttpRequest(), event.Name, 'S');
            } else {
                throw new IntegrationDefinitionException('Logging type ' + event.Logging_Type__c + ' not supported.');
            }

            try {
                variableMap = Util_Integration.sendToHandler(event, variableMap, logGuid);

                if(event.Logging_Type__c == Logger.LOGGING_TYPE.Process.name()) {
                    log.finalizeProcess(logGuid, JSON.serialize(variableMap));
                } else {
                    // handle integration logs
                }
            } catch (Exception e) {
                System.debug(e);
                System.debug(e.getStackTraceString());
                System.debug(event);
                // log the error
                if(event.Logging_Type__c == Logger.LOGGING_TYPE.Process.name()) {
                    log.finalizeProcess(logGuid, e);
                } else {
                    log.finalizeSession(logGuid, e);
                }
                if(definition.Error_Handling__c == ERROR_HANDLING_TYPES.FullRollback.name()) {
                    // Rollback any items that have already been saved. Then break the loop.
                    log.processFullRollback(logGuid);
                    break;
                } else if(definition.Error_Handling__c == ERROR_HANDLING_TYPES.StopOnError.name()) {
                    // Just break the loop.
                    break;
                } else {
                    // continue with processing as usual.
                }
            }
        }
        log.saveAll();
        return log.getParentGuid();
    }

    /**
     * Send the event context and the data context to the linked handler.
     * @param event Event Context with handler routing information. May also contain child Event Fields for input and output mapping
     * @param variableMap Data context
     * @param logGuid the GUID that identifies the log to use
     *
     * @return The output of the linked handler.
     */
    public static Map<String, Object> sendToHandler(Integration_Event__c event, Map<String, Object> variableMap, String logGuid) {
        Map<String, Object> inputMapping = Util_Integration.getInputMapping(event, variableMap, logGuid);

        Map<String, Object> responseMap = new Map<String, Object>();
        // Flow Handler
        System.debug(JSON.serialize(variableMap));
        System.debug(JSON.serialize(inputMapping));
        if(event.Type__c.toLowerCase() == 'flow') {
            // Flow event - send through the Flow handler.
            responseMap = Util_Integration.sendToFlowHandler(event, inputMapping);
        } else if(event.Type__c.toLowerCase() == 'apex') {
            // Apex Event - send through the Apex handler
            responseMap = Util_Integration.sendToApexHandler(event, inputMapping);
        } else {
            throw new IntegrationDefinitionException('Handler Type ' + event.Type__c + ' not supported');
        }
        System.debug(JSON.serialize(responseMap));
        // Add the returned variables to the variable map. This may also overwrite variables, which is intended (an update)
        variableMap.putAll(responseMap);
        System.debug(JSON.serialize(variableMap));

        return variableMap;
    }

    /**
     * Create the input map. This is used by the handler (Flow Interview or Apex Callable)
     * @param event Event Context with child Event Field Records.
     * @param params Data Context.
     * @param logGuid the GUID that identifies the log to use.
     *
     * @return Input Mapping object, serves as input for the handler.
     */
    private static Map<String, Object> getInputMapping(Integration_Event__c event, Map<String, Object> params, String logGuid) {
        Map<String, Object> inputMapping = new Map<String, Object>{'logId' => logGuid, 'record' => params.get('record')};

        // get and set input variables
        for (Event_Field__c ef : event.Event_Fields__r) {
            if (ef.Type__c.toLowerCase() == 'input') {
                // Only if Type == SObject
                if(String.isNotBlank(ef.Static_Value__c)) {
                    Object value = ef.Static_Value__c;

                    if (ef.Data_Type__c == 'Boolean') {
                        value = ef.Static_Value__c.toLowerCase() == 'true';
                    }
                    inputMapping.put(ef.Mapping_Name__c, value);
                } else {
                    inputMapping.put(ef.Mapping_Name__c, params.get(ef.Name));
                }
            }
        }
        return inputMapping;
    }
    /**
     * Send the event to the Apex Handler. The Apex Class should implement the Callable Interface.
     * @param event The event context with the routing information
     * @param inputMap The inputs for the Apex Class. Will always contain at lease "record" and "logId"
     *
     * @return The output provided by the Apex Class
     */
    private static Map<String, Object> sendToApexHandler(Integration_Event__c event, Map<String, Object> inputMap) {
        Map<String, Object> returnItems = new Map<String, Object>();

        System.debug(event);
        System.debug(event.Handler_Name__c);
        // Check if Apex class is Callable. If not, throw an error.
        Type callableInterfaceType = Callable.class;
        Type callableHandler = Type.forName(event.Handler_Name__c);
        if(!callableInterfaceType.isAssignableFrom(callableHandler)) {
            throw new IntegrationDefinitionException('Handler does not implement the Callable Interface');
        }
        // Instantiate the apexHandler class referenced in the event context.
        // This class must implement the Callable Interface
        Callable apexHandler = (Callable) callableHandler.newInstance();
        Object apexResponse = apexHandler.call(event.Name, inputMap);

        // parse the response to either a map or a single object
        if(apexResponse instanceof Map<String, Object>) {
            // Map is returned, get the defined items from the map and return them
            Map<String, Object> apexResponseMap = (Map<String, Object>)apexResponse;
            for(Event_Field__c ef : event.Event_Fields__r) {
                if(ef.Type__c.toLowerCase() == 'output') {
                    returnItems.put(ef.Mapping_Name__c, apexResponseMap.get(ef.Name));
                }
            }
        } else {
            // Single item is returned, put this in the map and return it.
            for(Event_Field__c ef : event.Event_Fields__r) {
                if(ef.Type__c.toLowerCase() == 'output') {
                    returnItems.put(ef.Mapping_Name__c, apexResponse);
                    return returnItems;
                }
            }
        }

        return returnItems;
    }
    /**
     * Send the event to the Flow Handler. The Flow should be able to be launched from Apex.
     * @param event The event context with the routing information
     * @param inputMap The inputs for the Flow. Will always contain at lease "record" and "logId"
     *
     * @return The output provided by the Flow
     */
    private static Map<String, Object> sendToFlowHandler(Integration_Event__c event, Map<String, Object> inputMap) {
        Flow.Interview handlerFlow = Flow.Interview.createInterview(event.Handler_Name__c, inputMap);
        handlerFlow.start();

        Map<String, Object> outputs = new Map<String, Object>();
        for(Event_Field__c outputField : event.Event_Fields__r) {
            if(outputField.Type__c.toLowerCase() == 'output') {
                outputs.put(outputField.Mapping_Name__c, handlerFlow.getVariableValue(outputField.Name));
            }
        }
        return outputs;
    }
    /**
     * Internal class used to demonstrate the Callable Interface implementation. Also used for test classes.
     */
    public class POC_Callable implements Callable {
        public Object call(String action, Map<String, Object> inputParams) {

            SObject o = (SObject)inputParams.get('record');
            // String logGuid = (String)inputParams.get('logId');
            String s = (String)inputParams.get('staticInput');
            return s + ' ' + o.get('Name');
        }
    }
}