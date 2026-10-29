public class Trigger_Opportunity {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		//Trigger_Opportunity.syncAccountToExact();

		// Webshop order confirmation: stamp Order_Processed_At__c and send it on Closed Won (Util_OrderConfirmation)
		if(Trigger.isUpdate && Trigger.isBefore){
			Util_OrderConfirmation.beforeUpdate((List<Opportunity>)Trigger.new, Trigger.oldMap);
		}
		if(Trigger.isUpdate && Trigger.isAfter){
			Util_OrderConfirmation.afterUpdate((List<Opportunity>)Trigger.new, Trigger.oldMap);
		}
	}

	//when an opportunity gets closed won, sync it to exact (if it wasn't already)
	// private static void syncAccountToExact(){
	// 	if(!(Trigger.isAfter && Trigger.isUpdate)){
	// 		return;
	// 	}

	// 	List<Opportunity> iterList = Trigger.new;
	// 	Set<Id> acctIdsToDo = new Set<Id>();
	// 	for(Opportunity oppNew : iterList){
	// 		Opportunity oppOld = (Opportunity)Trigger.oldMap.get(oppNew.Id);

	// 		if(!oppOld.IsWon && oppNew.IsWon){
	// 			acctIdsToDo.add(oppNew.AccountId);
	// 		}
	// 	}

	// 	Integer cnt = 0;
	// 	for(Id acctId : acctIdsToDo) {
	// 		Util_Exact.syncAccountAsync(acctId);
	// 		if(++cnt == 20){
	// 			break; //to prevent limits, probably opportunities will not be closed won in bulk, so should be no problem
	// 		}
	// 	}
	// }
}