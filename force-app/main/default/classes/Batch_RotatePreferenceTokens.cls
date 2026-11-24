// Rotates Contact.Preference_Token_Key__c: contacts whose token is older than ROTATE_AFTER_DAYS (or has no date,
// i.e. stamped before rotation existed) get a new key, the old key moves to Preference_Token_Previous__c, and
// Preference_Center_Url__c follows. The guest Preference Center accepts the current key and the previous one
// (with an old-link notice); anything older is shown the expired-link message.
// Oldest tokens first, capped per run (2,500 per day: ~214k legacy contacts rotate over ~86 days, so later cycles stay spread evenly over the 90 days) and so the
// Contact / Data Cloud / Marketing Cloud syncs are not flooded.
// Runs daily as a step of the Day job dispatcher (JobDispatcherStep Day_RotatePreferenceTokens).
// Needs a Subscription25__Schedulable_Class__c record (Name + Unique_Name__c = class name).
// Manual run:  Database.executeBatch(new Batch_RotatePreferenceTokens(), 100);
// Keep the batch size at or below 100: the "rab - Contact" flow faults on a multi-row update of Contacts that
// still have a blank Email_Encrypted__c / Unique_Key__c, so those are updated one at a time (like the backfill).
global class Batch_RotatePreferenceTokens extends Subscription25.Job_AbstractBatch2 implements Database.Stateful, Util_JobDispatcher.Step {

	public static final Integer ROTATE_AFTER_DAYS = 90;
	public static final Integer DEFAULT_DAILY_CAP = 2500;

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	private Integer dailyCap;
	private Integer rotated = 0;
	private Integer failed = 0;
	private List<String> errors = new List<String>();

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_RotatePreferenceTokens() {
		this(DEFAULT_DAILY_CAP);
	}

	global Batch_RotatePreferenceTokens(Integer dailyCap) {
		super('Batch_RotatePreferenceTokens');
		this.dailyCap = dailyCap;
	}

	public override Integer getBatchSize() {
		return 100;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc){
		Date cutoff = Date.today().addDays(-ROTATE_AFTER_DAYS);
		return Database.getQueryLocator(
			'SELECT Id, Email, Email_Encrypted__c, Unique_Key__c, Preference_Token_Key__c FROM Contact ' +
			'WHERE Email != null AND Anonymized__c = false AND Preference_Token_Key__c != null ' +
			'AND (Preference_Token_Date__c = null OR Preference_Token_Date__c < :cutoff) ' +
			'ORDER BY Preference_Token_Date__c ASC NULLS FIRST, Id ' +
			'LIMIT ' + dailyCap
		);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
		List<Contact> toUpdate = new List<Contact>();
		List<Contact> toUpdateSingly = new List<Contact>();
		for(Contact con : (List<Contact>) scope){
			// No try/catch on purpose: a missing secret or base url must stop the run, not silently skip.
			String newKey = Util_CommunicationPreferenceToken.hashEmail(con.Email);
			Contact upd = new Contact(Id = con.Id, Preference_Token_Date__c = Date.today());
			if(newKey != con.Preference_Token_Key__c){
				upd.Preference_Token_Previous__c = con.Preference_Token_Key__c;
				upd.Preference_Token_Key__c = newKey;
				upd.Preference_Center_Url__c = Util_CommunicationPreferenceToken.buildPreferenceCenterUrl(newKey);
			}
			if(String.isBlank(con.Email_Encrypted__c) || String.isBlank(con.Unique_Key__c)){
				toUpdateSingly.add(upd);
			} else {
				toUpdate.add(upd);
			}
		}

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
				rotated++;
				continue;
			}
			failed++;
			if(errors.size() < 100){
				errors.add(updated[i].Id + ': ' + results[i].getErrors()[0].getMessage());
			}
		}
	}

	public override void finishBatch(Database.BatchableContext bc){
		System.debug(LoggingLevel.INFO, 'Batch_RotatePreferenceTokens: rotated ' + rotated + ', failed ' + failed + ' ' + errors);
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_RotatePreferenceTokens');
	}
}
