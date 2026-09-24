// Collapses duplicate CommunicationPreference__c rows per Contact + Config + BusinessLine (the
// CompositeKey__c parts) and repairs stale composite keys. Duplicates and stale keys come from
// Contact merges: the loser's preferences are reparented to the master without firing
// rbb_CommunicationPreference, so the key still holds the loser's Id.
//
// Survivor per group: latest EffectiveDate__c; on a tie the opt-out (IsEnabled__c = false) wins,
// so a tie never turns into an opt-in; then latest LastModifiedDate.
public without sharing class Svc_CommunicationPreferenceDedupe {

	public class Result {
		public Integer deleted = 0;
		public Integer keysRepaired = 0;
		public Integer enabledConflicts = 0;
		public List<String> errors = new List<String>();
	}

	public static Result dedupe(Set<Id> contactIds){
		return dedupe(contactIds, false);
	}

	// dryRun: count what would be deleted/repaired without any DML.
	public static Result dedupe(Set<Id> contactIds, Boolean dryRun){
		Result res = new Result();
		if(contactIds == null || contactIds.isEmpty()){
			return res;
		}

		Map<String, CommunicationPreference__c> keptByKey = new Map<String, CommunicationPreference__c>();
		Set<String> conflictKeys = new Set<String>();
		List<CommunicationPreference__c> toDelete = new List<CommunicationPreference__c>();
		for(CommunicationPreference__c pref : [
			SELECT Id, Contact__c, Config__c, BusinessLine__c, IsEnabled__c, EffectiveDate__c, LastModifiedDate, CompositeKey__c
			FROM CommunicationPreference__c
			WHERE Contact__c IN :contactIds
			WITH SYSTEM_MODE
		]){
			String key = compositeKey(pref);
			CommunicationPreference__c kept = keptByKey.get(key);
			if(kept == null){
				keptByKey.put(key, pref);
				continue;
			}
			if(kept.IsEnabled__c != pref.IsEnabled__c){
				conflictKeys.add(key);
			}
			if(wins(pref, kept)){
				toDelete.add(kept);
				keptByKey.put(key, pref);
			} else {
				toDelete.add(pref);
			}
		}
		res.enabledConflicts = conflictKeys.size();

		List<CommunicationPreference__c> toUpdate = new List<CommunicationPreference__c>();
		for(String key : keptByKey.keySet()){
			CommunicationPreference__c kept = keptByKey.get(key);
			if(kept.CompositeKey__c != key){
				toUpdate.add(new CommunicationPreference__c(Id = kept.Id, CompositeKey__c = key));
			}
		}

		if(dryRun){
			res.deleted = toDelete.size();
			res.keysRepaired = toUpdate.size();
			return res;
		}

		// Delete before update: CompositeKey__c is unique, so a survivor can only take over the
		// correct key once the duplicate holding it is gone. Partial success so one bad row never
		// rolls back a merge or a whole batch chunk.
		if(!toDelete.isEmpty()){
			List<Database.DeleteResult> delResults = Database.delete(toDelete, false, AccessLevel.SYSTEM_MODE);
			for(Integer i = 0; i < delResults.size(); i++){
				if(delResults[i].isSuccess()){
					res.deleted++;
				} else {
					res.errors.add('Delete ' + toDelete[i].Id + ': ' + delResults[i].getErrors()[0].getMessage());
				}
			}
		}
		if(!toUpdate.isEmpty()){
			List<Database.SaveResult> updResults = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
			for(Integer i = 0; i < updResults.size(); i++){
				if(updResults[i].isSuccess()){
					res.keysRepaired++;
				} else {
					res.errors.add('Update ' + toUpdate[i].Id + ': ' + updResults[i].getErrors()[0].getMessage());
				}
			}
		}
		return res;
	}

	// Mirrors fCompositeKey in rbb_CommunicationPreference, which recomputes it on update.
	private static String compositeKey(CommunicationPreference__c pref){
		return pref.Contact__c + '|'
			+ (pref.Config__c == null ? 'NONE' : String.valueOf(pref.Config__c)) + '|'
			+ (String.isBlank(pref.BusinessLine__c) ? 'NONE' : pref.BusinessLine__c);
	}

	private static Boolean wins(CommunicationPreference__c candidate, CommunicationPreference__c current){
		Datetime candidateDate = candidate.EffectiveDate__c;
		Datetime currentDate = current.EffectiveDate__c;
		if(candidateDate != currentDate){
			if(candidateDate == null) return false;
			if(currentDate == null) return true;
			return candidateDate > currentDate;
		}
		if(candidate.IsEnabled__c != current.IsEnabled__c){
			return !candidate.IsEnabled__c;
		}
		return candidate.LastModifiedDate > current.LastModifiedDate;
	}
}
