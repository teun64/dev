public class Trigger_Contact {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_Contact.stampPreferenceTokenKey();
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
