public class Trigger_Contact {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_Contact.stampPreferenceTokenKey();
		Trigger_Contact.collectPreferencesToDelete();
		Trigger_Contact.deletePreferences();
	}

	// CommunicationPreference__c Ids per Contact, captured before delete: Contact__c is SetNull,
	// so by after delete the link is already cleared and the rows can't be queried by Contact.
	private static Map<Id, Set<Id>> preferenceIdsByContactId = new Map<Id, Set<Id>>();

	private static void collectPreferencesToDelete(){
		if(!(Trigger.isBefore && Trigger.isDelete)){
			return;
		}

		for(CommunicationPreference__c pref : [
			SELECT Id, Contact__c
			FROM CommunicationPreference__c
			WHERE Contact__c IN :Trigger.oldMap.keySet()
			WITH SYSTEM_MODE
		]){
			if(!preferenceIdsByContactId.containsKey(pref.Contact__c)){
				preferenceIdsByContactId.put(pref.Contact__c, new Set<Id>());
			}
			preferenceIdsByContactId.get(pref.Contact__c).add(pref.Id);
		}
	}

	// Deletes the preferences of Contacts that were really deleted. Merge losers
	// (MasterRecordId set) are skipped: their preferences are reparented to the master.
	private static void deletePreferences(){
		if(!(Trigger.isAfter && Trigger.isDelete)){
			return;
		}

		List<CommunicationPreference__c> toDelete = new List<CommunicationPreference__c>();
		for(Contact conOld : (List<Contact>) Trigger.old){
			Set<Id> prefIds = preferenceIdsByContactId.remove(conOld.Id);
			if(prefIds == null || conOld.MasterRecordId != null){
				continue;
			}
			for(Id prefId : prefIds){
				toDelete.add(new CommunicationPreference__c(Id = prefId));
			}
		}
		if(toDelete.isEmpty()) return;

		Database.delete(toDelete, true, AccessLevel.SYSTEM_MODE);
	}

	// Keeps Contact.Preference_Token_Key__c (HMAC of the lowercased Email) in sync so guest
	// Preference Center links can resolve to a Contact without ever carrying its record Id.
	private static void stampPreferenceTokenKey(){
		if(!(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))){
			return;
		}

		List<Contact> candidates = new List<Contact>();
		Set<Id> existingIds = new Set<Id>();
		for(Contact conNew : (List<Contact>) Trigger.new){
			Boolean emailChanged = Trigger.isInsert
				|| conNew.Email != ((Contact) Trigger.oldMap.get(conNew.Id)).Email;

			if(!emailChanged){
				continue;
			}
			candidates.add(conNew);
			if(conNew.Id != null) existingIds.add(conNew.Id);
		}
		if(candidates.isEmpty()) return;

		// New Contacts (before insert, Id == null) have no AccountContactRelation rows yet,
		// so there's nothing to exclude them on — only existing Contacts get checked here.
		Set<Id> excludedContactIds = Util_ContactMarketing.getExcludedContactIds(existingIds);

		for(Contact conNew : candidates){
			if(conNew.Id != null && excludedContactIds.contains(conNew.Id)){
				conNew.Preference_Token_Key__c  = null;
				conNew.Preference_Center_Url__c = null;
				continue;
			}

			String keyHash;
			try {
				keyHash = Util_CommunicationPreferenceToken.hashEmail(conNew.Email);
			} catch(Util_CommunicationPreferenceToken.TokenConfigException e) {
				// Secret not configured yet — leave the key blank rather than blocking Contact
				// DML org-wide. Guest preference-center links simply won't resolve until it is.
				keyHash = null;
			}
			conNew.Preference_Token_Key__c = keyHash;

			try {
				conNew.Preference_Center_Url__c = Util_CommunicationPreferenceToken.buildPreferenceCenterUrl(keyHash);
			} catch(Util_CommunicationPreferenceToken.TokenConfigException e) {
				// Base_Url__c not configured yet — same reasoning as above.
				conNew.Preference_Center_Url__c = null;
			}
		}
	}
}
