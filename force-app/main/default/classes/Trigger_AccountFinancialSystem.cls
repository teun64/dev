/**
 * Financial system (Exact) hooks on Account, kept apart from Trigger_Account so the legacy Exact
 * integration (Util_Exact) can be retired without touching the existing Account trigger.
 */
public class Trigger_AccountFinancialSystem {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_AccountFinancialSystem.upsertDebtorNumbers();
	}

	//a set / changed FinancialDebtorNumber__c is stored on the Subscription25 debtor number record (account + administration)
	private static void upsertDebtorNumbers(){
		if(!(Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate))){
			return;
		}
		Util_FinancialSystemAccount.upsertDebtorNumbers((List<Account>)Trigger.new, (Map<Id, Account>)Trigger.oldMap);
	}
}
