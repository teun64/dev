// One-off backfill of Contact.Preference_Token_Key__c / Preference_Center_Url__c. Trigger_Contact only stamps
// these on insert or when Email changes, so Contacts that existed before the Preference Center went live never
// got a link (prod 2026-10-09: 3,053 of 228,613 Contacts). Same rules as the trigger: no Email -> no link,
// invoice/digital-only Contacts (Util_ContactMarketing) -> no link. Anonymized Contacts are skipped.
// Contacts that "rab - Contact" picks up (blank Email_Encrypted__c / Unique_Key__c) are updated one at a time: that
// flow faults on a multi-row Contact update. Keep the batch size at or below 100 (one DML per such Contact).
// Dry run (counts only, no DML): Database.executeBatch(new Batch_BackfillPreferenceCenterUrl(true), 100);
// Real run:                      Database.executeBatch(new Batch_BackfillPreferenceCenterUrl(), 100);
// Totals are written to the debug log of the finish transaction (needs a trace flag on the running user).
public class Batch_BackfillPreferenceCenterUrl implements Database.Batchable<SObject>, Database.Stateful {

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	private Boolean dryRun = false;
	private Integer stamped = 0;
	private Integer excluded = 0;
	private Integer failed = 0;
	private List<String> errors = new List<String>();

	public Batch_BackfillPreferenceCenterUrl() {}

	public Batch_BackfillPreferenceCenterUrl(Boolean dryRun) {
		this.dryRun = dryRun;
	}

	public Database.QueryLocator start(Database.BatchableContext bc){
		return Database.getQueryLocator(
			'SELECT Id, Email, Email_Encrypted__c, Unique_Key__c FROM Contact ' +
			'WHERE Email != null AND Anonymized__c = false ' +
			'AND (Preference_Center_Url__c = null OR Preference_Token_Key__c = null)'
		);
	}

	public void execute(Database.BatchableContext bc, List<SObject> scope){
		List<Contact> contacts = (List<Contact>) scope;
		Set<Id> excludedIds = Util_ContactMarketing.getExcludedContactIds(new Map<Id, Contact>(contacts).keySet());

		List<Contact> toUpdate = new List<Contact>();
		List<Contact> toUpdateSingly = new List<Contact>();
		for(Contact con : contacts){
			if(excludedIds.contains(con.Id)){
				excluded++;
				continue;
			}
			// No try/catch on purpose: a missing PreferenceTokenConfig__c secret or base url must stop the
			// backfill instead of silently stamping nothing.
			String keyHash = Util_CommunicationPreferenceToken.hashEmail(con.Email);
			Contact upd = new Contact(
				Id = con.Id,
				Preference_Token_Key__c = keyHash,
				Preference_Center_Url__c = Util_CommunicationPreferenceToken.buildPreferenceCenterUrl(keyHash)
			);
			if(String.isBlank(con.Email_Encrypted__c) || String.isBlank(con.Unique_Key__c)){
				toUpdateSingly.add(upd);
			} else {
				toUpdate.add(upd);
			}
		}

		if(dryRun){
			stamped += toUpdate.size() + toUpdateSingly.size();
			return;
		}

		// partial success: one Contact failing validation must not roll back the rest of the chunk
		if(!toUpdate.isEmpty()){
			collect(toUpdate, Database.update(toUpdate, false, RUNNING_MODE));
		}
		for(Contact upd : toUpdateSingly){
			collect(new List<Contact>{ upd }, Database.update(new List<Contact>{ upd }, false, RUNNING_MODE));
		}
	}

	private void collect(List<Contact> updated, List<Database.SaveResult> results){
		for(Integer i = 0; i < results.size(); i++){
			if(results[i].isSuccess()){
				stamped++;
				continue;
			}
			failed++;
			if(errors.size() < 100){
				errors.add(updated[i].Id + ': ' + results[i].getErrors()[0].getMessage());
			}
		}
	}

	public void finish(Database.BatchableContext bc){
		String summary = (dryRun ? 'DRY RUN - would stamp ' : 'Stamped ') + stamped
			+ ', excluded (invoice/digital only) ' + excluded
			+ ', failed ' + failed + ' ' + errors;
		System.debug(LoggingLevel.INFO, 'Batch_BackfillPreferenceCenterUrl: ' + summary);
	}
}
