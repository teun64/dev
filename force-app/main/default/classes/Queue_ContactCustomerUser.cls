/**
 * Sets Contact.Customer_User_Active__c from the contact's portal user (active User with this ContactId).
 * Enqueued by Trigger_User; run(contactIds) is also usable for a backfill.
 * One contact per DML: rab - Contact faults on bulk Contact updates.
 */
public without sharing class Queue_ContactCustomerUser implements Queueable {
	private Set<Id> contactIds;

	public Queue_ContactCustomerUser(Set<Id> contactIds) {
		this.contactIds = contactIds;
	}

	public void execute(QueueableContext context) {
		run(this.contactIds);
	}

	public static void run(Set<Id> contactIds) {
		if (contactIds == null || contactIds.isEmpty()) return;

		Set<Id> activeContactIds = new Set<Id>();
		for (User u : [
			SELECT ContactId FROM User
			WHERE ContactId IN :contactIds AND IsActive = true
			WITH SYSTEM_MODE
		]) {
			activeContactIds.add(u.ContactId);
		}

		for (Contact con : [
			SELECT Id, Customer_User_Active__c FROM Contact
			WHERE Id IN :contactIds
			WITH SYSTEM_MODE
		]) {
			Boolean active = activeContactIds.contains(con.Id);
			if (con.Customer_User_Active__c == active) continue;
			Database.update(new Contact(Id = con.Id, Customer_User_Active__c = active), false, AccessLevel.SYSTEM_MODE);
		}
	}
}
