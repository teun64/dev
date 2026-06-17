@isTest
private class Test_Batch_CleanEventLogs {

    @isTest
    static void Test_Batch_CleanEventLogsExecute() {
        Event_Log__c el = new Event_Log__c();
        el.CreatedDate = System.now().addDays(-10);
        el.GUID__c = '85BBD920-42A0-1069-0ZE4-08002B30309D';
        Database.insert(el);

        Test.startTest();
        Batch_CleanEventLogs ba= new Batch_CleanEventLogs();
        Id jobid= Database.executeBatch(ba,5);
        Test.stopTest();
    }
    @isTest
    static void Test_Batch_CleanEventLogsSchedule() {
        Test.startTest();
        Batch_CleanEventLogs.setSchedule('0 59 13 * * ? *');
        Test.stopTest();
    }
}