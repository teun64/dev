public class Batch_FinalizeInvoices implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
	public void execute(SchedulableContext sc){
		Database.executeBatch(this, 1);
	}

	public Database.QueryLocator start(Database.BatchableContext bc){
		String query =
			'SELECT Id, Subscription25__Finalized_In_Exact__c ' +
			'FROM Subscription25__Invoice__c ' +
			'WHERE Subscription25__Invoice_Number__c = null AND Subscription25__Exact_Order_Number__c != null LIMIT 30';
		return Database.getQueryLocator(query);
	}

	public void execute(Database.BatchableContext bc, List<SObject> scope){
		Subscription25__Invoice__c curInv = (Subscription25__Invoice__c)scope[0];
		//if the invoice was already printed, just try to get the invoice number again
		if(curInv.Subscription25__Finalized_In_Exact__c){
			Util_Exact.loadInvoiceNumber(scope[0].Id);
		} else {
			Util_Exact.finalizeInvoice(scope[0].Id);
		}
	}

	public void finish(Database.BatchableContext bc){}

	public static void setSchedule(){
		Batch_FinalizeInvoices jobInstance = new Batch_FinalizeInvoices();
		for(Integer i=3; i<60; i+=5){
			String cronString = '0 ' + i + ' * * * ? *';
			String jobName = 'Batch_FinalizeInvoices - ' + cronString;
			System.schedule(jobName, cronString, jobInstance);
		}
	}
}
