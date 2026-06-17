@isTest
private class Test_Batch_CleanOauthLogs {

    @isTest
    static void Test_Batch_CleanOauthLogsExecute() {
        OAuth_Log__c ol = new OAuth_Log__c();
        ol.CreatedDate = System.now().addDays(-10);
        ol.GUID__c = '85BBD920-42A0-1069-0ZE4-08002B30309D';
        Database.insert(ol);
        
        Test.startTest();
        Batch_CleanOauthLogs ba= new Batch_CleanOauthLogs();
        Id jobid= Database.executeBatch(ba,5);
        Test.stopTest();
    }
    @isTest
    static void Test_Batch_CleanOauthLogsSchedule() {
        Test.startTest();
        Batch_CleanOauthLogs.setSchedule('0 59 13 * * ? *');
        Test.stopTest();
    }
}