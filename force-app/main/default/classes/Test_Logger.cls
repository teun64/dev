/**
 * Created by Gerbrand Spaans (Gen25) on 25/01/2024.
 */
@IsTest
private class Test_Logger {
    @IsTest
    private static void testInstanceFromNullString() {
        String nullString = null;
        Logger log = Logger.getInstance(nullString);

        Assert.isNotNull(log.getParentGuid());
    }
    @IsTest
    private static void testInstanceFromNullEvent() {
        IntegrationTransaction__c nullEvent = null;
        Logger log = Logger.getInstance(nullEvent);

        Assert.isNotNull(log.getParentGuid());
    }
    @IsTest
    private static void testInstanceFromExistingLog() {
        IntegrationTransaction__c testParentLog = new IntegrationTransaction__c(
                GUID__c = 'testacb',
                Status__c = Util_Event.LogEventStatus.PROCESSED.name()
        );
        insert testParentLog;
        IntegrationTransaction__c testChildProcess = new IntegrationTransaction__c(
                Parent__c = testParentLog.Id,
                GUID__c = 'testProcess1',
                Status__c = Util_Event.LogEventStatus.PROCESSED.name()
        );
        insert testChildProcess;
        IntegrationAttempt__c testChildSession = new IntegrationAttempt__c(
                IntegrationTransaction__c = testParentLog.Id,
                GUID__c = 'testSession1'
        );
        insert testChildSession;

        Logger testLog = Logger.getInstance(testParentLog.GUID__c);

        Assert.areEqual(testParentLog.GUID__c, testLog.getParentGuid());
        Assert.isNotNull(testLog.getSessionLog(testChildSession.GUID__c));
        Assert.isNotNull(testLog.getProcessLog(testChildProcess.GUID__c));
    }
    @IsTest
    private static void testSessionLogic() {
        Logger log = Logger.getInstance();

        RestRequest testRestRequest = new RestRequest();
        testRestRequest.httpMethod = 'POST';
        testRestRequest.requestBody = Blob.valueOf('test body content');
        testRestRequest.requestURI = 'https://www.movingintelligence.nl';
        String sessionLogGuid = log.startSession(testRestRequest, 'Test Integration', 'S');
        Assert.isNotNull(sessionLogGuid);

        IntegrationAttempt__c newSessionLog = log.getSessionLog(sessionLogGuid);
        Assert.areEqual(1, newSessionLog.Execution_Order__c);
        Assert.areEqual('S', newSessionLog.Receiving_System__c);

        log.updateSession(sessionLogGuid, new HttpRequest(), 'E');
        IntegrationAttempt__c updatedLog = log.getSessionLog(sessionLogGuid);
        Assert.areEqual('S', updatedLog.Calling_System__c);
        Assert.areEqual('E', updatedLog.Receiving_System__c);

        log.cancelSession(sessionLogGuid);
        IntegrationAttempt__c cancelledSession = log.getSessionLog(sessionLogGuid);
        Assert.areEqual(Logger.INTEGRATION_STATUS.FAILED.name(), cancelledSession.Status__c);

        String logGuid = log.addSessionResult(new IntegrationAttempt__c());
        Assert.isNotNull(logGuid);

        HttpRequest testHttpRequest = new HttpRequest();
        testHttpRequest.setBody('POST');
        testHttpRequest.setMethod('POST');
        testHttpRequest.setEndpoint('https://www.movingintelligence.nl');
        Assert.isNotNull(log.startSession(testHttpRequest, 'Test Process', 'E'));
    }
    @IsTest
    private static void testFieldOverflows() {
        // create a base string that will be used to create longer, overflowing strings.
        String baseString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

        Logger log = Logger.getInstance();

        // Prepare a session log
        IntegrationAttempt__c sessionLog = new IntegrationAttempt__c(Request_Body__c = baseString, Response_Body__c = baseString);
        while(sessionLog.Request_Body__c.length() < IntegrationAttempt__c.Request_Body__c.getDescribe().length) {
            sessionLog.Request_Body__c += baseString;
        }
        while(sessionLog.Response_Body__c.length() < IntegrationAttempt__c.Response_Body__c.getDescribe().length) {
            sessionLog.Response_Body__c += baseString;
        }
        String sessionLogGuid = log.addSessionResult(sessionLog);

        String processLogGuid = log.startProcess('Test Process', 'S', new Account());
        String overFlowMessage = baseString;
        while(overFlowMessage.length() < IntegrationTransaction__c.Message__c.getDescribe().length) {
            overFlowMessage += baseString;
        }
        log.finalizeProcess(processLogGuid, overFlowMessage);

        Test.startTest();
        Map<String, List<ContentVersion>> overflowDocs = log.getOverflows();
        Test.stopTest();

        Assert.areEqual(2, overflowDocs.size(), 'Expected 2 ContentVersion lists');
        Assert.areEqual(1, overflowDocs.get(processLogGuid).size(), 'Expected that the process log would generate 1 log');
        Assert.areEqual(2, overflowDocs.get(sessionLogGuid).size(), 'Expected that the session log would generate 2 logs');
    }
    @IsTest
    private static void testFieldOverflowsDuringSave() {
        // create a base string that will be used to create longer, overflowing strings.
        String baseString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

        Logger log = Logger.getInstance();

        // Prepare a session log
        IntegrationAttempt__c sessionLog = new IntegrationAttempt__c(Request_Body__c = baseString, Response_Body__c = baseString);
        while(sessionLog.Request_Body__c.length() < IntegrationAttempt__c.Request_Body__c.getDescribe().length) {
            sessionLog.Request_Body__c += baseString;
        }
        while(sessionLog.Response_Body__c.length() < IntegrationAttempt__c.Response_Body__c.getDescribe().length) {
            sessionLog.Response_Body__c += baseString;
        }
        String sessionLogGuid = log.addSessionResult(sessionLog);

        String processLogGuid = log.startProcess('Test Process', 'S', new Account());
        String overFlowMessage = baseString;
        while(overFlowMessage.length() < IntegrationTransaction__c.Message__c.getDescribe().length) {
            overFlowMessage += baseString;
        }
        log.finalizeProcess(processLogGuid, overFlowMessage);

        Test.startTest();
        log.saveAll();
        Test.stopTest();

        Assert.areEqual(3, [SELECT Id FROM ContentDocument].size());
    }
}