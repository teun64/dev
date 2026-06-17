public class Batch_ActivateDraftContractProducts implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
    public void execute(SchedulableContext sc){
        Database.executeBatch(this, 1);
    }

    public Database.QueryLocator start(Database.BatchableContext bc){
        String query =
            'SELECT Id, Subscription25__Status__c, Subscription25__Contract__r.AccountId, Subscription25__Contract__r.Account.FinancialDebtorNumber__c, Subscription25__Contract__r.Account.Reseller_Name__c ' +
            'FROM Subscription25__Contract_Product__c ' +
            'WHERE Subscription25__Status__c = \'Draft\' LIMIT 20';
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope){
        Subscription25__Contract_Product__c curContProd = (Subscription25__Contract_Product__c)scope[0];

		try {
			//if the invoice was already printed, just try to get the invoice number again
            if (String.isNotBlank(curContProd.Subscription25__Contract__r.Account.FinancialDebtorNumber__c)) {
                curContProd.Subscription25__Status__c = 'Activated';
                database.update(curContProd);
            } else {
                Util_Exact.syncAccount(curContProd.Subscription25__Contract__r.AccountId);
            }

		} catch(Util_System.FinancialSyncException e) {
			if (e.getMessage().equals(Util_FinancialSystem.EX_LIMITS)) {
				// Limits reached, abort this job and continue next schedule
				System.abortJob(bc.getJobId());
			} else {
				// Unsure what happened, so can't handle it
				throw e;
			}
		}
    }

    public void finish(Database.BatchableContext bc){}

	public static void setSchedule(){
		Batch_ActivateDraftContractProducts jobInstance = new Batch_ActivateDraftContractProducts();
		for(Integer i=2; i<60; i+=5){
			String cronString = '0 ' + i + ' * * * ? *';
			String jobName = 'Batch_ActivateDraftContractProducts - ' + cronString;
			System.schedule(jobName, cronString, jobInstance);
		}
	}
}