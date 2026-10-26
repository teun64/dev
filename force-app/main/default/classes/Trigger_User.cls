public class Trigger_User {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_User.syncContactCustomerUser();
	}

	// Contact.Customer_User_Active__c follows the portal user's IsActive. Contact DML can't run in the
	// same transaction as User DML (MIXED_DML_OPERATION), so the update goes through a queueable.
	private static void syncContactCustomerUser(){
		if(!(Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate))){
			return;
		}

		Set<Id> contactIds = new Set<Id>();
		for(User usrNew : (List<User>) Trigger.new){
			User usrOld = Trigger.isUpdate ? (User) Trigger.oldMap.get(usrNew.Id) : null;
			if(usrOld == null){
				if(usrNew.ContactId != null){
					contactIds.add(usrNew.ContactId);
				}
				continue;
			}
			if(usrNew.IsActive != usrOld.IsActive || usrNew.ContactId != usrOld.ContactId){
				if(usrNew.ContactId != null) contactIds.add(usrNew.ContactId);
				if(usrOld.ContactId != null) contactIds.add(usrOld.ContactId);
			}
		}

		if(contactIds.isEmpty() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()){
			return;
		}
		System.enqueueJob(new Queue_ContactCustomerUser(contactIds));
	}
}
