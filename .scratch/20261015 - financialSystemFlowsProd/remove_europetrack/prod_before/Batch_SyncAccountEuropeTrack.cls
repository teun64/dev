public class Batch_SyncAccountEuropeTrack implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public void execute(SchedulableContext sc){
        Database.executeBatch(this, 1);
    }

    public Database.QueryLocator start(Database.BatchableContext bc){
        String query =
            'SELECT Id, FinancialBatchDone__c ' +
            'FROM Account ' +
            'WHERE extId_5__c != null AND extId_5__c != \'0\' AND FinancialDebtorNumber__c = null AND FinancialBatchDone__c = false LIMIT 10';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope){
        Account curAcc = (Account)scope[0];
        //if the invoice was already printed, just try to get the invoice number again
        Util_Exact.syncAccount(curAcc.Id);
        curAcc.FinancialBatchDone__c = true;
        database.update(curAcc);
    }

    public void finish(Database.BatchableContext bc){}

    public static void setSchedule(){
        Batch_SyncAccountEuropeTrack jobInstance = new Batch_SyncAccountEuropeTrack();

        for(Integer i=0; i<60; i+=1){
            //String cronString = '0 ' + i + ' * * * ? *';
            String cronString = '0 ' + i + ' 6 * * ? *';
            String jobName = 'Batch_SyncAccountEuropeTrack - ' + cronString;
            System.schedule(jobName, cronString, jobInstance);
        }
    }
}