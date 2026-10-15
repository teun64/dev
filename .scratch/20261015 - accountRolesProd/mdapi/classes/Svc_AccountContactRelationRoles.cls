/**
 * One owner per role per account, account lookups from the roles, roles removed from a contact without an email
 * address. Replaces the record-triggered flows rab_ / afl_AccountContactRelation_Roles (2026-10-15): the flow ran
 * once per changed relation, async, and parallel runs rewrote the account's other relations from the same snapshot,
 * so one removal could be lost (two Payment contacts after a REST call that moved Main and Invoice at once).
 * Here every account is handled once per save: decide the owner of each role, then one update for the relations
 * and one for the accounts.
 *
 * Per changed relation (inserted, or Roles changed):
 *  - contact without an email address: Main, Invoice, Digital, Reminder and Payment are removed (Shipping stays),
 *    RoleRemovalAlert__c says which
 *  - owner of a unique role (Main, Invoice, Shipping, Reminder, Digital, Payment) = the changed relation that
 *    gained it in this save (the last one when several did), else a changed relation that still holds it;
 *    the role is removed from every other relation of the account
 *  - account lookups follow the owners: Main -> Contact_person__c, Invoice -> Contact_Billing__c +
 *    Subscription25__Billing_Attendant_To__c, Shipping -> Contact_Shipping__c, Digital ->
 *    Subscription25__UBL_Billing_Attendant_To__c, Reminder -> Subscription25__Reminder_Contact__c (Payment has
 *    none); a lookup is never cleared when its role disappears
 * Failures do not block the save that started it: they are written to Event_Log__c (action RolesSync).
 */
public without sharing class Svc_AccountContactRelationRoles {
	public static final List<String> UNIQUE_ROLES = new List<String>{ 'Main', 'Invoice', 'Shipping', 'Reminder', 'Digital', 'Payment' };
	private static final Set<String> EMAIL_ROLES = new Set<String>{ 'Main', 'Invoice', 'Digital', 'Reminder', 'Payment' };

	// the relations this class updates itself are not handled again
	private static Boolean running = false;

	public static void apply(List<AccountContactRelation> relations, Map<Id, AccountContactRelation> oldMap) {
		if (Svc_AccountContactRelationRoles.running) {
			return;
		}
		List<AccountContactRelation> changed = new List<AccountContactRelation>();
		Set<Id> accountIds = new Set<Id>();
		for (AccountContactRelation acr : relations) {
			AccountContactRelation old = (oldMap == null) ? null : oldMap.get(acr.Id);
			if ((old == null) ? String.isNotBlank(acr.Roles) : (acr.Roles != old.Roles)) {
				changed.add(acr);
				accountIds.add(acr.AccountId);
			}
		}
		if (changed.isEmpty()) {
			return;
		}

		Map<Id, AccountContactRelation> current = new Map<Id, AccountContactRelation>([
			SELECT Id, AccountId, ContactId, Roles, Contact.Name, Contact.Email
			FROM AccountContactRelation WHERE AccountId IN :accountIds WITH SYSTEM_MODE
		]);
		Map<Id, Account> accounts = new Map<Id, Account>([
			SELECT Id, Contact_person__c, Contact_Billing__c, Contact_Shipping__c, Subscription25__Billing_Attendant_To__c,
				Subscription25__UBL_Billing_Attendant_To__c, Subscription25__Reminder_Contact__c
			FROM Account WHERE Id IN :accountIds WITH SYSTEM_MODE
		]);

		Map<Id, List<String>> rolesById = new Map<Id, List<String>>();
		for (AccountContactRelation acr : current.values()) {
			rolesById.put(acr.Id, Svc_AccountContactRelationRoles.split(acr.Roles));
		}
		Map<Id, AccountContactRelation> toUpdate = new Map<Id, AccountContactRelation>();

		// 1. no email address: roles that need one are removed from the changed relation
		for (AccountContactRelation acr : changed) {
			AccountContactRelation cur = current.get(acr.Id);
			if (cur == null || String.isNotBlank(cur.Contact.Email)) {
				continue;
			}
			List<String> roles = rolesById.get(acr.Id);
			List<String> removed = new List<String>();
			for (String role : new List<String>(roles)) {
				if (EMAIL_ROLES.contains(role)) {
					roles.remove(roles.indexOf(role));
					removed.add(role);
				}
			}
			if (!removed.isEmpty()) {
				toUpdate.put(acr.Id, new AccountContactRelation(Id = acr.Id, RoleRemovalAlert__c = 'ALERT: role(s) removed because '
					+ cur.Contact.Name + ' has no email address: ' + String.join(removed, ', ') + '.'));
			}
		}

		// 2. owner per account and role: the changed relation that gained it (last one wins), else one that holds it
		Map<String, Id> ownerByKey = new Map<String, Id>();
		Set<String> gainedKeys = new Set<String>();
		for (AccountContactRelation acr : changed) {
			AccountContactRelation old = (oldMap == null) ? null : oldMap.get(acr.Id);
			Set<String> oldRoles = new Set<String>(Svc_AccountContactRelationRoles.split(old?.Roles));
			for (String role : rolesById.get(acr.Id)) {
				if (!UNIQUE_ROLES.contains(role)) {
					continue;
				}
				String key = acr.AccountId + '|' + role;
				Boolean gained = !oldRoles.contains(role);
				if (gained) {
					ownerByKey.put(key, acr.Id);
					gainedKeys.add(key);
				} else if (!gainedKeys.contains(key)) {
					ownerByKey.put(key, acr.Id);
				}
			}
		}

		// 3. the other relations of the account lose the roles that have an owner
		for (AccountContactRelation acr : current.values()) {
			List<String> roles = rolesById.get(acr.Id);
			Boolean dirty = false;
			for (String role : new List<String>(roles)) {
				Id owner = ownerByKey.get(acr.AccountId + '|' + role);
				if (owner != null && owner != acr.Id) {
					roles.remove(roles.indexOf(role));
					dirty = true;
				}
			}
			if (dirty || toUpdate.containsKey(acr.Id)) {
				AccountContactRelation upd = toUpdate.containsKey(acr.Id) ? toUpdate.get(acr.Id) : new AccountContactRelation(Id = acr.Id);
				upd.Roles = roles.isEmpty() ? null : String.join(roles, ';');
				toUpdate.put(acr.Id, upd);
			}
		}

		// 4. account lookups follow the owners
		Map<Id, Account> accountUpdates = new Map<Id, Account>();
		for (String key : ownerByKey.keySet()) {
			Id accountId = (Id) key.substringBefore('|');
			String role = key.substringAfter('|');
			Id contactId = current.get(ownerByKey.get(key)).ContactId;
			Account acc = accounts.get(accountId);
			if (acc == null) {
				continue;
			}
			Account upd = accountUpdates.containsKey(accountId) ? accountUpdates.get(accountId) : new Account(Id = accountId);
			Boolean dirty = false;
			if (role == 'Main' && acc.Contact_person__c != contactId) {
				upd.Contact_person__c = contactId;
				dirty = true;
			} else if (role == 'Invoice' && (acc.Contact_Billing__c != contactId || acc.Subscription25__Billing_Attendant_To__c != contactId)) {
				upd.Contact_Billing__c = contactId;
				upd.Subscription25__Billing_Attendant_To__c = contactId;
				dirty = true;
			} else if (role == 'Shipping' && acc.Contact_Shipping__c != contactId) {
				upd.Contact_Shipping__c = contactId;
				dirty = true;
			} else if (role == 'Digital' && acc.Subscription25__UBL_Billing_Attendant_To__c != contactId) {
				upd.Subscription25__UBL_Billing_Attendant_To__c = contactId;
				dirty = true;
			} else if (role == 'Reminder' && acc.Subscription25__Reminder_Contact__c != contactId) {
				upd.Subscription25__Reminder_Contact__c = contactId;
				dirty = true;
			}
			if (dirty) {
				accountUpdates.put(accountId, upd);
			}
		}

		Svc_AccountContactRelationRoles.running = true;
		try {
			List<Event_Log__c> logs = new List<Event_Log__c>();
			if (!toUpdate.isEmpty()) {
				List<AccountContactRelation> rows = toUpdate.values();
				List<Database.SaveResult> results = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
				for (Integer i = 0; i < results.size(); i++) {
					if (!results[i].isSuccess()) {
						logs.add(Svc_AccountContactRelationRoles.errorLog(rows[i].Id, results[i].getErrors()));
					}
				}
			}
			if (!accountUpdates.isEmpty()) {
				List<Account> rows = accountUpdates.values();
				List<Database.SaveResult> results = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
				for (Integer i = 0; i < results.size(); i++) {
					if (!results[i].isSuccess()) {
						logs.add(Svc_AccountContactRelationRoles.errorLog(rows[i].Id, results[i].getErrors()));
					}
				}
			}
			if (!logs.isEmpty()) {
				Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
			}
		} finally {
			Svc_AccountContactRelationRoles.running = false;
		}
	}

	private static List<String> split(String roles) {
		List<String> out = new List<String>();
		if (String.isNotBlank(roles)) {
			for (String role : roles.split(';')) {
				if (String.isNotBlank(role) && !out.contains(role.trim())) {
					out.add(role.trim());
				}
			}
		}
		return out;
	}

	private static Event_Log__c errorLog(Id recordId, List<Database.Error> errors) {
		Event_Log__c log = Util_Event.createLog('S', 'S', String.valueOf(recordId.getSObjectType()), 'RolesSync', recordId, null, null);
		log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
		List<String> messages = new List<String>();
		for (Database.Error e : errors) {
			messages.add(e.getMessage());
		}
		log.Message__c = String.join(messages, ' | ').left(131072);
		return log;
	}
}
