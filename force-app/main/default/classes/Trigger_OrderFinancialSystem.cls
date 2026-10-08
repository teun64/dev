/**
 * Financial system (Exact) hooks on Order, kept apart from Trigger_Order so the legacy Exact
 * integration (Util_Exact) can be retired without touching the existing Order trigger.
 */
public class Trigger_OrderFinancialSystem {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_OrderFinancialSystem.queueAccountFinancialSync();
	}

	//a new draft hardware / opportunity order needs the account in the financial system (debtor number) before
	//the order can be synced: queue the account for Batch_FinancialSystemAccountSync; the order sync waits for it
	private static void queueAccountFinancialSync(){
		if(!(Trigger.isAfter && Trigger.isInsert)){
			return;
		}
		List<Order> iterList = Trigger.new;
		Set<Id> acctIds = new Set<Id>();
		for(Order ord : iterList){
			if(ord.AccountId != null && ord.Status == 'Draft' && (ord.Type == 'Hardware' || ord.Type == 'Opportunity')){
				acctIds.add(ord.AccountId);
			}
		}
		if(acctIds.isEmpty()){
			return;
		}
		Set<Id> toFlag = new Set<Id>();
		for(Account acct : [SELECT Id FROM Account WHERE Id IN :acctIds AND FinancialDebtorNumber__c = null AND SyncToFinancialSystem__c = false WITH SYSTEM_MODE]){
			toFlag.add(acct.Id);
		}
		if(!toFlag.isEmpty()){
			Util_FinancialSystemAccount.flagAccounts(toFlag);
		}
	}
}
