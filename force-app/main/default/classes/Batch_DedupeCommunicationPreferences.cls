// One-off cleanup of duplicate preferences and stale composite keys left by past Contact merges.
// Dry run (counts only, no DML): Database.executeBatch(new Batch_DedupeCommunicationPreferences(true), 200);
// Real run:                      Database.executeBatch(new Batch_DedupeCommunicationPreferences(false), 200);
// Totals are written to the debug log of the finish transaction (needs a trace flag on the running user).
public without sharing class Batch_DedupeCommunicationPreferences implements Database.Batchable<SObject>, Database.Stateful {

	private Boolean dryRun;
	private Integer deleted = 0;
	private Integer keysRepaired = 0;
	private Integer enabledConflicts = 0;
	private List<String> errors = new List<String>();

	public Batch_DedupeCommunicationPreferences(Boolean dryRun){
		this.dryRun = dryRun;
	}

	public Database.QueryLocator start(Database.BatchableContext bc){
		return Database.getQueryLocator(
			'SELECT Id FROM Contact WHERE Id IN (SELECT Contact__c FROM CommunicationPreference__c WHERE Contact__c != null)'
		);
	}

	public void execute(Database.BatchableContext bc, List<Contact> scope){
		Svc_CommunicationPreferenceDedupe.Result res =
			Svc_CommunicationPreferenceDedupe.dedupe(new Map<Id, Contact>(scope).keySet(), dryRun);
		deleted += res.deleted;
		keysRepaired += res.keysRepaired;
		enabledConflicts += res.enabledConflicts;
		if(errors.size() < 100){
			errors.addAll(res.errors);
		}
	}

	public void finish(Database.BatchableContext bc){
		String summary = (dryRun ? 'DRY RUN - would delete ' : 'Deleted ') + deleted
			+ ', keys ' + (dryRun ? 'to repair ' : 'repaired ') + keysRepaired
			+ ', groups with conflicting IsEnabled ' + enabledConflicts
			+ ', errors ' + errors.size() + ' ' + errors;
		System.debug(LoggingLevel.INFO, 'Batch_DedupeCommunicationPreferences: ' + summary);
	}
}
