public class Trigger_AccountContactRelation {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		// one owner per role per account + account lookups from the roles (replaces afl_AccountContactRelation_Roles)
		if(Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)){
			Svc_AccountContactRelationRoles.apply((List<AccountContactRelation>) Trigger.new, (Map<Id, AccountContactRelation>) Trigger.oldMap);
		}

		// a removed relation: its Exact contact is retired (see Svc_FinancialSystemContactRemoval)
		if(Trigger.isBefore && Trigger.isDelete && Util_FinancialSystem.areTriggerHooksEnabled()){
			Svc_FinancialSystemContactRemoval.handleDeletedRelations((List<AccountContactRelation>) Trigger.old);
		}
	}
}
