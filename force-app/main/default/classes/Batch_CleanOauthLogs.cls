public class  Batch_CleanOauthLogs implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public void execute(SchedulableContext sc){
        Database.executeBatch(this, 2000);
    }

    public Iterable<Sobject> start(Database.BatchableContext bc){
        //String query =  'SELECT Id FROM Event_Log__c WHERE CreatedDate < LAST_N_DAYS:7';
        //String query =  'SELECT Id FROM OAuth_Log__c WHERE CreatedDate < :System.now().addDays(-8)';
        return (Iterable<Sobject>)Database.getQueryLocator([SELECT Id FROM OAuth_Log__c WHERE CreatedDate < :System.now().addDays(-8)]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope){
        // Delete records in bulk
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext bc) {}

    public static void setSchedule() {
        Batch_CleanOauthLogs.setSchedule('0 1 19 * * ? *');
    }

    public static void setSchedule(String cronString) {
        Batch_CleanOauthLogs jobInstance = new Batch_CleanOauthLogs();
        String jobName = 'Batch_CleanOauthLog - ' + cronString;
        System.schedule(jobName, cronString, jobInstance);
    }
}