/**
 * Created by Gerbrand Spaans (Gen25) on 11/01/2024.
 */
@IsTest
public class Test_Util_Integration {
    private static final String DEFINITION_NAME = 'Test Definition';

    // Class is made public to allow access to the provided test handlers.
    @TestSetup
    private static void testSetup() {
        // create integration definitions
        List<Integration_Definition__c> definitions = new List<Integration_Definition__c>{
                new Integration_Definition__c(Name = Test_Util_Integration.DEFINITION_NAME)
        };
        insert definitions;

        // create integration events. One is inactive
        List<Integration_Event__c> events = new List<Integration_Event__c>{
                new Integration_Event__c(
                        Integration_Definition__c = definitions[0].Id,
                        Type__c = 'Apex',
                        Is_Active__c = true,
                        Execution_Order__c = 10,
                        Name = 'Test Event 1',
                        Handler_Name__c = 'Test_Util_Integration.Handler1',
                        Logging_Type__c = Logger2.LOGGING_TYPE.Process.name()
                ),
                new Integration_Event__c(
                        Integration_Definition__c = definitions[0].Id,
                        Type__c = 'Apex',
                        Is_Active__c = true,
                        Execution_Order__c = 20,
                        Name = 'Test Event 2',
                        Handler_Name__c = 'Test_Util_Integration.Handler2',
                        Logging_Type__c = Logger2.LOGGING_TYPE.Process.name()
                ),
                new Integration_Event__c(
                        Integration_Definition__c = definitions[0].Id,
                        Type__c = 'Apex',
                        Is_Active__c = false,
                        Execution_Order__c = 30,
                        Name = 'Inactive Test Event 3',
                        Handler_Name__c = 'Test_Util_Integration.Handler3',
                        Logging_Type__c = Logger2.LOGGING_TYPE.Session.name()
                )
        };
        insert events;

        // Insert Event Fields
        List<Event_Field__c> eventFields = new List<Event_Field__c>{
                new Event_Field__c(
                        Name = 'handlerInput1',
                        Mapping_Name__c = 'handlerInput1',
                        Integration_Event__c = events[0].Id,
                        Type__c = 'Input',
                        Is_Active__c = true,
                        Data_Type__c = 'SObject'
                ),
                new Event_Field__c(
                        Name = 'handlerStaticInput1',
                        Mapping_Name__c = 'handlerStaticInput1',
                        Integration_Event__c = events[0].Id,
                        Type__c = 'Input',
                        Is_Active__c = true,
                        Static_Value__c = 'Hello'
                ),
                new Event_Field__c(
                        Name = 'handlerOutput1',
                        Mapping_Name__c = 'handlerOutput1',
                        Integration_Event__c = events[0].Id,
                        Type__c = 'Output',
                        Is_Active__c = true,
                        Data_Type__c = 'SObject'
                ),
                // set the output of the first handler as input for the second
                new Event_Field__c(
                        Name = 'handlerOutput1',
                        Mapping_Name__c = 'handlerInput2',
                        Integration_Event__c = events[1].Id,
                        Type__c = 'Input',
                        Is_Active__c = true,
                        Data_Type__c = 'SObject'
                ),
                new Event_Field__c(
                        Name = 'handlerOutput2',
                        Mapping_Name__c = 'handlerOutput2',
                        Integration_Event__c = events[1].Id,
                        Type__c = 'Output',
                        Is_Active__c = true,
                        Data_Type__c = 'SObject'
                ),
                new Event_Field__c(
                        Name = 'handlerInput3',
                        Mapping_Name__c = 'handlerInput3',
                        Integration_Event__c = events[2].Id,
                        Type__c = 'Input',
                        Is_Active__c = false,
                        Data_Type__c = 'SObject'
                ),
                new Event_Field__c(
                        Name = 'handlerOutput3',
                        Mapping_Name__c = 'handlerOutput3',
                        Integration_Event__c = events[2].Id,
                        Type__c = 'Output',
                        Is_Active__c = false,
                        Data_Type__c = 'SObject'
                )
        };
        insert eventFields;

        // insert record data
        Test_Data.createAccount('TestAccount', 'abc123', 'B2B', true);

        // insert settings
        Automation_Hierarchy__c settingsRecord = Automation_Hierarchy__c.getInstance();
        settingsRecord.Trigger_Event_Log__c = true;
        settingsRecord.Max_Event_Log_Queue_Size__c = 5;
        insert settingsRecord;
    }

    // Test Apex Handlers provided in the test class
    public class Handler1 implements Callable {
        public Map<String, Object> call(String action, Map<String, Object> inputs) {
            System.debug('handler 1 inputs');
            System.debug(inputs);
            // manipulate the string as part of the function. returns 'Hello There'
            String theInput = String.valueOf(inputs.get('handlerStaticInput1'));
            return new Map<String, Object>{'handlerOutput1' => theInput + ' There'};
        }
    }
    public class Handler2 implements Callable {
        public Object call(String action, Map<String, Object> inputs) {
            System.debug('handler 2 inputs');
            System.debug(inputs);
            // manipulate the string as part of the function. returns 'Hello There Tester'
            return String.valueOf(inputs.get('handlerInput2') + ' Tester');
        }
    }
    public class HandlerWithError implements Callable {
        public Object call(String action, Map<String, Object> inputs) {
            throw new Util_System.CustomException('Test Handler Exception');
        }
    }

    // test classes
    @IsTest
    private static void testIntegration() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        String logId = Util_Integration.startIntegration(Test_Util_Integration.DEFINITION_NAME, testAccount.Id);
        Test.stopTest();

        Assert.isNotNull(logId);

        Event_Log__c parentLog = [SELECT Id, Status__c, (SELECT Id, Status__c, Message__c FROM Event_Logs__r) FROM Event_Log__c WHERE GUID__c = :logId];
        Assert.areEqual(Util_Event.LogEventStatus.PROCESSED.name(), parentLog.Status__c, 'Parent Log does not have expected final status');
        Assert.areEqual(2, parentLog.Event_Logs__r.size(), 'Expected two child event logs');
        Assert.areEqual(Util_Event.LogResultStatus.COMPLETED.name(), parentLog.Event_Logs__r[0].Status__c, 'Child log does not have expected final status');
        Assert.areEqual(Util_Event.LogResultStatus.COMPLETED.name(), parentLog.Event_Logs__r[1].Status__c, 'Child log does not have expected final status');

        Assert.isTrue(parentLog.Event_Logs__r[0].Message__c.contains('"handlerOutput1":"Hello There"'), 'HandlerOutput1 value is not enriched');
        Assert.isTrue(parentLog.Event_Logs__r[1].Message__c.contains('"handlerOutput2":"Hello There Tester"'), 'HandlerOutput2 value is not enriched');
    }
    @IsTest
    private static void testExceptions() {
        try {
            Util_Integration.startIntegration('Does Not Exist', null);
            Assert.fail('Expected the method to fail with an exception');
        } catch (Util_System.IntegrationDefinitionException e) {
            Assert.isTrue(e.getMessage().contains('No Integration Definition found with name'));
        }

        try {
            Util_Integration.startIntegration(Test_Util_Integration.DEFINITION_NAME, '001000000000001');
            Assert.fail('Expected the method to fail with an exception');
        } catch (Util_System.IntegrationDefinitionException e) {
            Assert.isTrue(e.getMessage().contains('Could not find the specified record'));
        }

        Integration_Event__c incorrectEvent = new Integration_Event__c(Type__c = 'Python Script');
        try {
            Util_Integration.sendToHandler(incorrectEvent, new Map<String, Object>(), 'logGUID');
            Assert.fail('Non-existent type should throw an error');
        } catch (Util_System.IntegrationDefinitionException e) {
            Assert.isTrue(e.getMessage().contains('Handler Type Python Script not supported'));
        }

        incorrectEvent.Type__c = 'Apex';
        incorrectEvent.Handler_Name__c = 'Test_Util_Integration';
        try {
            Util_Integration.sendToHandler(incorrectEvent, new Map<String, Object>(), 'logGUID');
            Assert.fail('Class that does not implement Callable should throw an error');
        } catch (Util_System.IntegrationDefinitionException e) {
            Assert.isTrue(e.getMessage().contains('Handler does not implement the Callable Interface'));
        }
    }
    @IsTest
    private static void testErrorHandling() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];

        Integration_Definition__c definition = [SELECT Id, Error_Handling__c FROM Integration_Definition__c WHERE Name = :Test_Util_Integration.DEFINITION_NAME];

        Integration_Event__c event = new Integration_Event__c(
                Integration_Definition__c = definition.Id,
                Type__c = 'Apex',
                Handler_Name__c = 'Test_Util_Integration.HandlerWithError',
                Execution_Order__c = 15,
                Is_Active__c = true,
                Logging_Type__c = Logger2.LOGGING_TYPE.Process.name()
        );
        insert event;

        // Test Continue on Error
        definition.Error_Handling__c = Util_Integration.ERROR_HANDLING_TYPES.ContinueOnError.name();
        update definition;
        String logGuid = Util_Integration.startIntegration(Test_Util_Integration.DEFINITION_NAME, testAccount.Id);

        Event_Log__c continuedLog = [SELECT Id, Status__c, (SELECT Id, Status__c FROM Event_Logs__r ORDER BY Execution_Order__c ASC) FROM Event_Log__c WHERE GUID__c = :logGuid];
        Assert.isNotNull(continuedLog, 'Expected to find one parent log');
        Assert.areEqual(Util_Event.LogEventStatus.PROCESSED.name(), continuedLog.Status__c, 'Expected the parent log to have status processed.');
        Assert.areEqual(3, continuedLog.Event_Logs__r.size(), 'Expected three child logs');
        Assert.areEqual('COMPLETED', continuedLog.Event_Logs__r[0].Status__c);
        Assert.areEqual('ERROR', continuedLog.Event_Logs__r[1].Status__c);
        Assert.areEqual('COMPLETED', continuedLog.Event_Logs__r[2].Status__c);

        // Test Stop on Error
        definition.Error_Handling__c = Util_Integration.ERROR_HANDLING_TYPES.StopOnError.name();
        update definition;

        Test.startTest();
        logGuid = Util_Integration.startIntegration(Test_Util_Integration.DEFINITION_NAME, testAccount.Id);
        Test.stopTest();

        Event_Log__c stoppedLog = [SELECT Id, Status__c, (SELECT Id, Status__c FROM Event_Logs__r ORDER BY Execution_Order__c ASC) FROM Event_Log__c WHERE GUID__c = :logGuid];
        Assert.isNotNull(stoppedLog, 'Expected to find one parent log');
        Assert.areEqual(Util_Event.LogEventStatus.PROCESSED.name(), stoppedLog.Status__c, 'Expected the parent log to have status processed.');
        Assert.areEqual(2, stoppedLog.Event_Logs__r.size(), 'Expected three child logs');
        Assert.areEqual('COMPLETED', stoppedLog.Event_Logs__r[0].Status__c);
        Assert.areEqual('ERROR', stoppedLog.Event_Logs__r[1].Status__c);

        // Test Rollback on Error
        definition.Error_Handling__c = Util_Integration.ERROR_HANDLING_TYPES.FullRollback.name();
        update definition;

        logGuid = Util_Integration.startIntegration(Test_Util_Integration.DEFINITION_NAME, testAccount.Id);

        Event_Log__c rollbackedLog = [SELECT Id, Status__c, (SELECT Id, Status__c FROM Event_Logs__r ORDER BY Execution_Order__c ASC) FROM Event_Log__c WHERE GUID__c = :logGuid];
        Assert.isNotNull(rollbackedLog, 'Expected to find one parent log');
        Assert.areEqual(Util_Event.LogEventStatus.PROCESSED.name(), rollbackedLog.Status__c, 'Expected the parent log to have status processed.');
        Assert.areEqual(2, rollbackedLog.Event_Logs__r.size(), 'Expected three child logs');
        Assert.areEqual('ERROR', rollbackedLog.Event_Logs__r[0].Status__c);
        Assert.areEqual('ERROR', rollbackedLog.Event_Logs__r[1].Status__c);
    }
    @IsTest
    private static void testInvocable() {
        Inv_Integration.Request request = new Inv_Integration.Request();
        request.integrationDefinitionName = Test_Util_Integration.DEFINITION_NAME;
        request.relatedRecordId = [SELECT Id FROM Account LIMIT 1].Id;

        Test.startTest();
        List<Inv_Integration.Result> results = Inv_Integration.execute(new List<Inv_Integration.Request>{request});
        Test.stopTest();

        // result message validation
        Assert.areEqual(1, results.size(), 'Expected one result');
        Assert.areEqual(true, results[0].isSuccess, 'Expected result to be success');
        Assert.isNotNull(results[0].eventGuid, 'Event GUID not returned');
        Assert.isNotNull(results[0].message, 'No result message provided');
        Assert.areEqual('Process ran successfully', results[0].message, 'Expected different message in result');

        // Log validation
        Event_Log__c parentLog = [SELECT Id, Status__c, (SELECT Id, Status__c, Message__c FROM Event_Logs__r) FROM Event_Log__c WHERE GUID__c = :results[0].eventGuid];
        Assert.areEqual(Util_Event.LogEventStatus.PROCESSED.name(), parentLog.Status__c, 'Parent Log does not have expected final status');
        Assert.areEqual(2, parentLog.Event_Logs__r.size(), 'Expected two child event logs');
        Assert.areEqual(Util_Event.LogResultStatus.COMPLETED.name(), parentLog.Event_Logs__r[0].Status__c, 'Child log does not have expected final status');
        Assert.areEqual(Util_Event.LogResultStatus.COMPLETED.name(), parentLog.Event_Logs__r[1].Status__c, 'Child log does not have expected final status');
    }
    @IsTest
    private static void testInvocableExceptions() {
        Inv_Integration.Request request = new Inv_Integration.Request();
        request.integrationDefinitionName = 'Does not exist';
        request.relatedRecordId = [SELECT Id FROM Account LIMIT 1].Id;

        Test.startTest();
        List<Inv_Integration.Result> results = Inv_Integration.execute(new List<Inv_Integration.Request>{request});
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Expected one result');
        Assert.isFalse(results[0].isSuccess, 'Expected an error');
    }
    @IsTest
    private static void testTriggerLogic_NoStartConditions() {
        List<AsyncApexJob> historicJobs = [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME];

        // each condition should not trigger the job to be executed.
        // Inserting a completed parent
        Event_Log__c testParentEvent = new Event_Log__c(
                GUID__c = 'testevent',
                Status__c = Util_Event.LogEventStatus.PROCESSED.name()
        );
        insert testParentEvent;
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME AND Id NOT IN :historicJobs].size(), 'Job should not be started on processed parent event creation');

        // inserting a child record only
        Event_Log__c testChildSession = new Event_Log__c(
                GUID__c = 'testsession',
                Status__c = Util_Event.LogEventStatus.SUBMITTED.name(),
                Parent_Event__c = testParentEvent.Id
        );
        insert testChildSession;
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME AND Id NOT IN :historicJobs].size(), 'Job should not start on child event creation');

        // Simply executing the logic
        Trigger_Event_Log.run();
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME AND Id NOT IN :historicJobs].size(), 'Job should not be started when not in Trigger mode');

        // inserting correct record but settings turned off
        Automation_Hierarchy__c triggerSetting = Automation_Hierarchy__c.getInstance();
        triggerSetting.Trigger_Event_Log__c = false;
        upsert triggerSetting;

        testParentEvent.Status__c = Util_Event.LogEventStatus.SUBMITTED.name();
        update testParentEvent;
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME AND Id NOT IN :historicJobs].size(), 'Job should not be started when Trigger is turned off in settings');

        // Deleting Event
        triggerSetting = Automation_Hierarchy__c.getInstance();
        triggerSetting.Trigger_Event_Log__c = true;
        upsert triggerSetting;
        delete testParentEvent;
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME AND Id NOT IN :historicJobs].size(), 'Job should not be started when context is Delete');
    }
    @IsTest
    private static void testTriggerLogic_runEventBatch() {
        List<AsyncApexJob> historicJobs = [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME];

        Event_Log__c testLog = new Event_Log__c();
        List<Event_Log__c> eventLogs = new List<Event_Log__c>{testLog};

        Trigger_Event_Log.runEventBatch(eventLogs);
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME].size(), 'Job should not be started on parent event without status');

        testLog.Status__c = Util_Event.LogEventStatus.PROCESSED.name();

        Trigger_Event_Log.runEventBatch(eventLogs);
        Assert.areEqual(0, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME].size(), 'Job should not be started on parent event with processed status');

        testLog.Status__c = Util_Event.LogEventStatus.SUBMITTED.name();

        Test.startTest();
        Trigger_Event_Log.runEventBatch(eventLogs);
        Test.stopTest();

        Assert.areEqual(1, [SELECT Id FROM AsyncApexJob WHERE ApexClass.Name = :Trigger_Event_Log.EVENT_JOB_NAME].size(), 'Job should have been started by submitted parent event');
    }
}