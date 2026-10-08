/**
 * Financial system (Exact) hooks on Contact, kept apart from Trigger_Contact so the legacy Exact
 * integration (Util_Exact) can be retired without touching the existing Contact trigger.
 */
public class Trigger_ContactFinancialSystem {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_ContactFinancialSystem.handleFinancialSystemContacts();
	}

	// Exact contacts of the deleted / merged contact's relations: captured before delete (the relations
	// are gone by after delete), then retired or taken over by the merge master.
	private static void handleFinancialSystemContacts(){
		if(!Trigger.isDelete){
			return;
		}
		if(Trigger.isBefore){
			Svc_FinancialSystemContactRemoval.captureForContacts(Trigger.oldMap.keySet());
		} else {
			Svc_FinancialSystemContactRemoval.handleDeletedContacts((List<Contact>) Trigger.old);
		}
	}
}
