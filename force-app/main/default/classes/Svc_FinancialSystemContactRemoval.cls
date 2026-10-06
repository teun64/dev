/**
 * Keeps Exact contacts in line when their AccountContactRelation disappears: a deleted contact, a contact merge
 * (Salesforce deletes every relation of the losing contact and repoints the account's contact lookups to the
 * master) or a removed relation. The data is captured before the delete:
 *  - deleted contact / removed relation: the Exact contact is queued on its account
 *    (Account.FinancialContactsToRetire__c, account flagged); the account sync marks it DO NOT USE, clears the
 *    email, excludes it from mailings and ends it
 *  - merge, master related to the same account: the master's relation takes over the loser's Exact contact and
 *    platform ids (extId_1..6__c) where its own are empty, and its roles when it has none; a loser Exact contact
 *    that is not taken over is retired
 *  - merge, master not related to that account: a relation master - account is created with the loser's roles,
 *    Exact contact and platform ids
 * A relation that takes over an Exact contact is flagged, so the contact update sends the master's name and email.
 */
public without sharing class Svc_FinancialSystemContactRemoval {
	@TestVisible
	private static final List<String> PLATFORM_ID_FIELDS = new List<String>{
		'extId_1__c', 'extId_2__c', 'extId_3__c', 'extId_4__c', 'extId_5__c', 'extId_6__c'
	};

	// relations of contacts being deleted, captured in Contact before delete (gone by after delete)
	private static Map<Id, AccountContactRelation> captured = new Map<Id, AccountContactRelation>();
	// contacts being deleted in this transaction: their relations are handled by the contact trigger, not the relation trigger
	private static Set<Id> deletingContactIds = new Set<Id>();

	public class RetireEntry {
		public String id;
		public String firstName;
		public String middleName;
		public String lastName;
	}

	/** Contact before delete. */
	public static void captureForContacts(Set<Id> contactIds) {
		deletingContactIds.addAll(contactIds);
		String fields = String.join(PLATFORM_ID_FIELDS, ', ');
		for (AccountContactRelation acr : (List<AccountContactRelation>) Database.queryWithBinds(
				'SELECT Id, AccountId, ContactId, Roles, FinancialIdContact__c, ' + fields
				+ ', Contact.FirstName, Contact.MiddleName, Contact.LastName'
				+ ' FROM AccountContactRelation WHERE ContactId IN :contactIds',
				new Map<String, Object>{ 'contactIds' => contactIds }, AccessLevel.SYSTEM_MODE)) {
			captured.put(acr.Id, acr);
		}
	}

	/** Contact after delete: retire for real deletes, take over for merge losers (MasterRecordId set). */
	public static void handleDeletedContacts(List<Contact> oldContacts) {
		Map<Id, Id> masterByLoser = new Map<Id, Id>();
		Set<Id> contactIds = new Set<Id>();
		for (Contact c : oldContacts) {
			contactIds.add(c.Id);
			if (c.MasterRecordId != null) {
				masterByLoser.put(c.Id, c.MasterRecordId);
			}
		}
		List<AccountContactRelation> loserRelations = new List<AccountContactRelation>();
		List<AccountContactRelation> toRetire = new List<AccountContactRelation>();
		for (AccountContactRelation acr : captured.values()) {
			if (!contactIds.contains(acr.ContactId)) {
				continue;
			}
			captured.remove(acr.Id);
			if (masterByLoser.containsKey(acr.ContactId)) {
				loserRelations.add(acr);
			} else if (String.isNotBlank(acr.FinancialIdContact__c)) {
				toRetire.add(acr);
			}
		}
		if (!loserRelations.isEmpty()) {
			Svc_FinancialSystemContactRemoval.takeOver(loserRelations, masterByLoser, toRetire);
		}
		Svc_FinancialSystemContactRemoval.queueRetirements(toRetire, new Map<Id, Contact>());
	}

	/** AccountContactRelation before delete: a removed relation (relations of deleted contacts are skipped). */
	public static void handleDeletedRelations(List<AccountContactRelation> oldRelations) {
		List<AccountContactRelation> toRetire = new List<AccountContactRelation>();
		Set<Id> contactIds = new Set<Id>();
		for (AccountContactRelation acr : oldRelations) {
			if (String.isNotBlank(acr.FinancialIdContact__c) && !deletingContactIds.contains(acr.ContactId)) {
				toRetire.add(acr);
				contactIds.add(acr.ContactId);
			}
		}
		if (toRetire.isEmpty()) {
			return;
		}
		Map<Id, Contact> contacts = new Map<Id, Contact>([
			SELECT Id, FirstName, MiddleName, LastName FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE
		]);
		Svc_FinancialSystemContactRemoval.queueRetirements(toRetire, contacts);
	}

	/**
	 * Merge: the master's relation per account (existing, else a new one) takes over what it does not have yet.
	 * An Exact contact that cannot be taken over (the master has its own, or saving fails) is retired.
	 */
	private static void takeOver(List<AccountContactRelation> loserRelations, Map<Id, Id> masterByLoser, List<AccountContactRelation> toRetire) {
		Set<Id> accountIds = new Set<Id>();
		for (AccountContactRelation acr : loserRelations) {
			accountIds.add(acr.AccountId);
		}
		Set<Id> masterIds = new Set<Id>(masterByLoser.values());
		Map<String, AccountContactRelation> targetByKey = new Map<String, AccountContactRelation>();
		for (AccountContactRelation acr : (List<AccountContactRelation>) Database.queryWithBinds(
				'SELECT Id, AccountId, ContactId, Roles, FinancialIdContact__c, ' + String.join(PLATFORM_ID_FIELDS, ', ')
				+ ' FROM AccountContactRelation WHERE ContactId IN :masterIds AND AccountId IN :accountIds',
				new Map<String, Object>{ 'masterIds' => masterIds, 'accountIds' => accountIds }, AccessLevel.SYSTEM_MODE)) {
			targetByKey.put('' + acr.AccountId + acr.ContactId, acr);
		}

		Map<String, AccountContactRelation> changed = new Map<String, AccountContactRelation>();
		// loser relation whose Exact contact a target took over: retired when saving the target fails
		Map<String, AccountContactRelation> exactDonorByKey = new Map<String, AccountContactRelation>();
		for (AccountContactRelation loser : loserRelations) {
			Id masterId = masterByLoser.get(loser.ContactId);
			String key = '' + loser.AccountId + masterId;
			AccountContactRelation target = targetByKey.get(key);
			if (target == null) {
				target = new AccountContactRelation(AccountId = loser.AccountId, ContactId = masterId);
				targetByKey.put(key, target);
			}
			Boolean isChanged = false;
			if (String.isNotBlank(loser.FinancialIdContact__c)) {
				if (String.isBlank(target.FinancialIdContact__c)) {
					target.FinancialIdContact__c = loser.FinancialIdContact__c;
					target.Sync_To_Financial_System__c = true;
					exactDonorByKey.put(key, loser);
					isChanged = true;
				} else {
					toRetire.add(loser);
				}
			}
			for (String f : PLATFORM_ID_FIELDS) {
				if (String.isBlank((String) target.get(f)) && String.isNotBlank((String) loser.get(f))) {
					target.put(f, loser.get(f));
					isChanged = true;
				}
			}
			if (String.isBlank(target.Roles) && String.isNotBlank(loser.Roles)) {
				target.Roles = loser.Roles;
				isChanged = true;
			}
			if (isChanged || target.Id == null) {
				changed.put(key, target);
			}
		}
		if (changed.isEmpty()) {
			return;
		}

		List<String> keys = new List<String>(changed.keySet());
		List<AccountContactRelation> toSave = new List<AccountContactRelation>();
		for (String key : keys) {
			toSave.add(changed.get(key));
		}
		List<Database.UpsertResult> results = Database.upsert(toSave, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < results.size(); i++) {
			if (!results[i].isSuccess() && exactDonorByKey.containsKey(keys[i])) {
				toRetire.add(exactDonorByKey.get(keys[i]));
			}
		}
	}

	/** Queues the Exact contacts on their accounts and flags the accounts for the account sync. */
	private static void queueRetirements(List<AccountContactRelation> relations, Map<Id, Contact> contacts) {
		if (relations.isEmpty()) {
			return;
		}
		Map<Id, List<RetireEntry>> byAccount = new Map<Id, List<RetireEntry>>();
		for (AccountContactRelation acr : relations) {
			Contact con = contacts.containsKey(acr.ContactId) ? contacts.get(acr.ContactId) : acr.Contact;
			RetireEntry entry = new RetireEntry();
			entry.id = acr.FinancialIdContact__c;
			entry.firstName = con?.FirstName;
			entry.middleName = con?.MiddleName;
			entry.lastName = con?.LastName;
			if (!byAccount.containsKey(acr.AccountId)) {
				byAccount.put(acr.AccountId, new List<RetireEntry>());
			}
			byAccount.get(acr.AccountId).add(entry);
		}
		List<Account> accounts = new List<Account>();
		for (Account acct : [
				SELECT Id, FinancialContactsToRetire__c FROM Account WHERE Id IN :byAccount.keySet() WITH SYSTEM_MODE]) {
			List<RetireEntry> entries = Svc_FinancialSystemContactRemoval.readEntries(acct.FinancialContactsToRetire__c);
			Set<String> known = new Set<String>();
			for (RetireEntry e : entries) {
				known.add(e.id);
			}
			for (RetireEntry e : byAccount.get(acct.Id)) {
				if (known.add(e.id)) {
					entries.add(e);
				}
			}
			accounts.add(new Account(Id = acct.Id, FinancialContactsToRetire__c = JSON.serialize(entries),
				SyncToFinancialSystem__c = true, FinancialSyncAttempts__c = 0, FinancialSyncNextAttempt__c = null));
		}
		Database.update(accounts, false, AccessLevel.SYSTEM_MODE);
	}

	public static List<RetireEntry> readEntries(String raw) {
		if (String.isBlank(raw)) {
			return new List<RetireEntry>();
		}
		try {
			return (List<RetireEntry>) JSON.deserialize(raw, List<RetireEntry>.class);
		} catch (Exception e) {
			return new List<RetireEntry>();
		}
	}
}
