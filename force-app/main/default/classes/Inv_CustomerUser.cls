/**
 * Flow entry point for the Contact actions Enable/Disable Customer User.
 * Routes on Contact.Customer_User_Type__c, so each portal type gets its own naming/profile rules.
 * Add a new type here (and in the formula field) to support another portal.
 */
public without sharing class Inv_CustomerUser {
	public static final String ACTION_ENABLE  = 'Enable';
	public static final String ACTION_DISABLE = 'Disable';
	public static final String TYPE_DEALER    = 'Dealer Portal';

	public class Request {
		@InvocableVariable(label='Contact Id' required=true)
		public Id contactId;
		@InvocableVariable(label='Action' description='Enable or Disable' required=true)
		public String action;
	}

	public class Response {
		@InvocableVariable(label='Success')
		public Boolean success;
		@InvocableVariable(label='Message')
		public String message;
	}

	@InvocableMethod(label='Enable/Disable Customer User' description='Creates, re-activates or deactivates the customer user of a contact' category='Experience Cloud')
	public static List<Response> run(List<Request> requests) {
		Set<Id> contactIds = new Set<Id>();
		for (Request req : requests) {
			contactIds.add(req.contactId);
		}
		Map<Id, Contact> contacts = new Map<Id, Contact>([
			SELECT Id, Customer_User_Type__c FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE
		]);

		List<Response> responses = new List<Response>();
		for (Request req : requests) {
			Response res = new Response();
			try {
				Contact con = contacts.get(req.contactId);
				if (con == null) throw new Svc_DealerUserSetup.SetupException('Contact not found.');
				res.message = handle(con, req.action);
				res.success = true;
			} catch (Exception e) {
				res.success = false;
				res.message = e.getMessage();
			}
			responses.add(res);
		}
		return responses;
	}

	private static String handle(Contact con, String action) {
		// Disable works whatever the type: an active user must stay switchable off when the
		// account's relation type changes later.
		if (action == ACTION_DISABLE) {
			User u = Svc_DealerUserSetup.disableDealerUser(con.Id);
			return 'Customer user ' + u.Username + ' is deactivated.';
		}
		if (con.Customer_User_Type__c == TYPE_DEALER) {
			if (action == ACTION_ENABLE) {
				User u = Svc_DealerUserSetup.enableDealerUser(con.Id);
				return 'Dealer Portal user ' + u.Username + ' is active.';
			}
			throw new Svc_DealerUserSetup.SetupException('Unknown action: ' + action);
		}
		throw new Svc_DealerUserSetup.SetupException('No customer user type for this contact. ' +
			'Customer users can only be managed for contacts on a B2B account with relation type Dealer or Distributor.');
	}
}
