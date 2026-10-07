// One-off cleanup of duplicate preferences and stale composite keys left by past Contact merges.
// Needs a Subscription25__Schedulable_Class__c record (Name + Unique_Name__c = class name), not scheduled.
// Dry run (counts only, no DML): Database.executeBatch(new Batch_DedupeCommunicationPreferences(true), 200);
// Real run:                      Database.executeBatch(new Batch_DedupeCommunicationPreferences(), 200);
// Totals are written to the debug log of the finish transaction (needs a trace flag on the running user).
global class Batch_DedupeCommunicationPreferences extends Subscription25.Job_AbstractBatch2 implements Database.Stateful {

	private Boolean dryRun = false;
	private Integer deleted = 0;
	private Integer keysRepaired = 0;
	private Integer enabledConflicts = 0;
	private List<String> errors = new List<String>();

	global Batch_DedupeCommunicationPreferences() {
		super('Batch_DedupeCommunicationPreferences');
	}

	global Batch_DedupeCommunicationPreferences(Boolean dryRun) {
		this();
		this.dryRun = dryRun;
	}

	public override Integer getBatchSize() {
		return 200;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc){
		return Database.getQueryLocator(
			'SELECT Id FROM Contact WHERE Id IN (SELECT Contact__c FROM CommunicationPreference__c WHERE Contact__c != null)'
		);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
		Svc_CommunicationPreferenceDedupe.Result res =
			Svc_CommunicationPreferenceDedupe.dedupe(new Map<Id, SObject>(scope).keySet(), dryRun);
		deleted += res.deleted;
		keysRepaired += res.keysRepaired;
		enabledConflicts += res.enabledConflicts;
		if(errors.size() < 100){
			errors.addAll(res.errors);
		}
	}

	public override void finishBatch(Database.BatchableContext bc){
		String summary = (dryRun ? 'DRY RUN - would delete ' : 'Deleted ') + deleted
			+ ', keys ' + (dryRun ? 'to repair ' : 'repaired ') + keysRepaired
			+ ', groups with conflicting IsEnabled ' + enabledConflicts
			+ ', errors ' + errors.size() + ' ' + errors;
		System.debug(LoggingLevel.INFO, 'Batch_DedupeCommunicationPreferences: ' + summary);
	}
}
