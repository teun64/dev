public class Batch_FinalizeInvoicesLimited implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
	private String query;
	private String reseller;
	private String baseQuery = 'SELECT Id, Subscription25__Finalized_In_Exact__c, Subscription25__Administration__r.Reseller__c FROM Subscription25__Invoice__c' +
								' WHERE Subscription25__Invoice_Number__c = null' + 
								' AND Subscription25__Administration__r.Reseller__c = {0}' + 
								' AND Subscription25__Exact_Order_Number__c != null' + 
								' ORDER BY Subscription25__Administration__r.Reseller__c' + 
								' LIMIT 30';
	
    public Batch_FinalizeInvoicesLimited(String reseller) {
        this.reseller = reseller;
    }

	public Batch_FinalizeInvoicesLimited() {
		this.reseller = '1';
    }

	public void execute(SchedulableContext sc){
		Database.executeBatch(this, 1);
	}

	public Database.QueryLocator start(Database.BatchableContext bc){
		query = String.format(this.baseQuery, new List<String> { ('\'' + this.reseller + '\'')});
		//System.debug('start - baseQuery = ' + baseQuery);
		//System.debug('start - reseller = ' + this.reseller);
		//System.debug('start - query  = ' + query);
		//System.debug(Database.query(query));
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
		/*
		for(sObject s : scope){
			curInv = (Subscription25__Invoice__c)s;
			//if the invoice was already printed, just try to get the invoice number again
			if (curInv.Subscription25__Finalized_In_Exact__c) ){
				Util_Exact.loadInvoiceNumber(curInv.Id);
			} else {
				Util_Exact.finalizeInvoice(curInv.Id);
			}
			//System.debug('execute = ' + curInv.Id);
		}
		*/	
	}

	public void finish(Database.BatchableContext bc){
		String nextReseller;

		for (AggregateResult reseller : [SELECT 
											Subscription25__Administration__r.Reseller__c 
										FROM 
											Subscription25__Invoice__c 
										WHERE 
											Subscription25__Invoice_Number__c = null 
											AND Subscription25__Exact_Order_Number__c != null 
											AND Subscription25__Administration__r.Reseller__c != :this.reseller 
										GROUP BY
											Subscription25__Administration__r.Reseller__c]) {
			nextReseller = (String)reseller.get('Reseller__c');

			//System.debug('finish - running Reseller ' + nextReseller);

			if ((String.isNotBlank(nextReseller)) && (Integer.valueOf(nextReseller) > Integer.valueOf(this.reseller))) {
				Database.executeBatch(new Batch_FinalizeInvoicesLimited(nextReseller), 1);
				break;
			}

		}

	}

	public static void setSchedule(){
		Batch_FinalizeInvoicesLimited jobInstance = new Batch_FinalizeInvoicesLimited();
		//for(Integer i=3; i<60; i+=5){
			String cronString = '0 /6 1-3,5-23 * * ?';
			//String cronString = '0 ' + i + ' * * * ? *';
			String jobName = 'Batch_FinalizeInvoicesLimited - ' + cronString;
			System.schedule(jobName, cronString, jobInstance);
		//}
	}
}
