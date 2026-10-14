public class Trigger_AccountContactRelation {
	public static void run(){
		if(!Trigger.isExecuting || !Util_FinancialSystem.areTriggerHooksEnabled()){
			return;
		}

		// a removed relation: its Exact contact is retired (see Svc_FinancialSystemContactRemoval)
		if(Trigger.isBefore && Trigger.isDelete){
			Svc_FinancialSystemContactRemoval.handleDeletedRelations((List<AccountContactRelation>) Trigger.old);
		}
	}
}
