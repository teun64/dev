@isTest
private class Test_Batch_CleanArchivedTasks {
    @isTest
    static void Test_Batch_CleanArchivedTaskssExecute() {
        Test.startTest();
        Batch_CleanArchivedTasks ba= new Batch_CleanArchivedTasks();
        Id jobid= Database.executeBatch(ba,5);
        Test.stopTest();
    }
    @isTest
    static void Test_Batch_CleanArchivedTasksSchedule() {
        Test.startTest();
        Batch_CleanArchivedTasks.setSchedule('0 59 13 * * ? *');
        Test.stopTest();
    }
}