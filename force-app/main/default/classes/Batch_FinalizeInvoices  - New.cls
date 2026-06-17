public class Batch_FinalizeInvoices implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
	public void execute(SchedulableContext sc){
		Database.executeBatch(this, 1);
	}

	public Database.QueryLocator start(Database.BatchableContext bc){
		String query =
			'SELECT Id, Invoice_Printed_In_Exact__c ' +
			'FROM Subscription25__Invoice__c ' +
			'WHERE Subscription25__Invoice_Number__c = null AND Subscription25__Exact_Order_Number__c != null';
		return Database.getQueryLocator(query);
	}

	public void execute(Database.BatchableContext bc, List<SObject> scope){
		Subscription25__Invoice__c curInv = (Subscription25__Invoice__c)scope[0];
		Map<Id, Subscription25__Invoice__c> invoiceMap = new Map<Id, Subscription25__Invoice__c>((List<Subscription25__Invoice__c>) scope);

		String SYNC_NAME = 'FinancialSystem - Finalize Invoice';

		// Remove records with pending requests
		List<Event_Log__c> pendingLogs = [
			SELECT Id
			FROM Event_Log__c
			WHERE Related_Record_Id__c = :invoiceMap.keySet()
				AND Action__c = :SYNC_NAME
				AND Status__c NOT IN :Util_Event.FINISHED_EVENT_STATUS
		];
		for (Event_Log__c log : pendingLogs) {
			invoiceMap.remove(log.Related_Record_Id__c);
		}

		// Call for remaining invoices (if any)
		for (Subscription25__Invoice__c invoice : invoiceMap.values()) {
			Inv_Integration.Request req = new Inv_Integration.Request();
			req.integrationDefinitionName = SYNC_NAME;
			req.relatedRecordId = invoice.Id;
			List<Inv_Integration.Request> requests = new List<Inv_Integration.Request> { req };
			List<Inv_Integration.Result> responses = Inv_Integration.execute(requests);

			for (Inv_Integration.Result res : responses) {
				if (res.message?.contains(Util_FinancialSystem.EX_LIMITS)) {
					// Limits reached, abort this job and continue next schedule
					System.abortJob(bc.getJobId());
				}
			}
		}

		// DEPRECATED
		// try {
		// 	//if the invoice was already printed, just try to get the invoice number again
		// 	if(curInv.Invoice_Printed_In_Exact__c) {
		// 		Util_FinancialSystem.loadInvoiceNumber(scope[0].Id);
		// 	} else {
		// 		Util_FinancialSystem.finalizeInvoice(scope[0].Id);
		// 	}
		// } catch(Util_System.ExactSyncException e) {
		// 	if (e.getMessage().equals(Util_FinancialSystem.EX_LIMITS)) {
		// 		// Limits reached, abort this job and continue next schedule
		// 		System.abortJob(bc.getJobId());
		// 	} else {
		// 		// Unsure what happened, so can't handle it
		// 		throw e;
		// 	}
		// }
	}

	public void finish(Database.BatchableContext bc) {}

	public static void setSchedule() {
		Batch_FinalizeInvoices jobInstance = new Batch_FinalizeInvoices();
		for(Integer i=3; i<60; i+=5){
			String cronString = '0 ' + i + ' * * * ? *';
			String jobName = 'Batch_FinalizeInvoices - ' + cronString;
			System.schedule(jobName, cronString, jobInstance);
		}
	}
}