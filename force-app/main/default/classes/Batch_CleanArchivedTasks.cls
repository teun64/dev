public class Batch_CleanArchivedTasks implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public void execute(SchedulableContext sc){
        Database.executeBatch(this, 2000);
    }

    public Iterable<Sobject> start(Database.BatchableContext bc){
        String query =  'SELECT Id FROM Task WHERE IsArchived = true and IsDeleted = false ALL ROWS';
        return (Iterable<Sobject>)Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope){
        // Delete records in bulk
        Database.delete(scope, false);
    }

    public void finish(Database.BatchableContext bc) {}

    public static void setSchedule() {
        Batch_CleanArchivedTasks.setSchedule('0 0 6 * * ? *');
    }

    public static void setSchedule(String cronString) {
        Batch_CleanArchivedTasks jobInstance = new Batch_CleanArchivedTasks();
        String jobName = 'Batch_CleanArchivedTasks - ' + cronString;
        System.schedule(jobName, cronString, jobInstance);
    }
}