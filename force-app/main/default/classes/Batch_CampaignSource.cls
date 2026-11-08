// Keeps the Source campaigns of staged campaigns filled with their selection (Svc_CampaignSource). Chained as a step of
// the Day job dispatcher (Util_JobDispatcher, JobDispatcherStep__mdt Day_CampaignSourceSync).
// Phase 1 (accounts in the selection): add / update members. Phase 2 (Source + Operational members): remove the ones
// whose account has no 2G units left. Phase 1 starts phase 2 from its finish; phase 2 starts the next dispatcher step.
// Needs a Subscription25__Schedulable_Class__c record (Name + Unique_Name__c = class name).
// Dry run (counts only, no DML): Database.executeBatch(new Batch_CampaignSource(true), 200);
// Manual real run:                Database.executeBatch(new Batch_CampaignSource(), 200);
// Totals are written to the debug log of the finish transaction of phase 2 (needs a trace flag on the running user).
global class Batch_CampaignSource extends Subscription25.Job_AbstractBatch2 implements Database.Stateful, Util_JobDispatcher.Step {

	private Boolean dryRun = false;
	private Boolean prunePhase = false;
	private Svc_CampaignSource.Result total = new Svc_CampaignSource.Result();
	private List<String> errors = new List<String>();

	// set when started by Batch_JobDispatcher: the finish of phase 2 then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_CampaignSource() {
		super('Batch_CampaignSource');
	}

	global Batch_CampaignSource(Boolean dryRun) {
		this();
		this.dryRun = dryRun;
	}

	public override Integer getBatchSize() {
		return 200;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		Set<Id> parentIds = new Set<Id>();
		for (Campaign c : Svc_CampaignSource.sources()) parentIds.add(c.ParentId);
		// no Source campaign with a selection: nothing to scan
		if (parentIds.isEmpty()) return Database.getQueryLocator('SELECT Id FROM Account LIMIT 0', AccessLevel.SYSTEM_MODE);
		if (!prunePhase) return Database.getQueryLocator(Svc_CampaignSource.accountQuery(), AccessLevel.SYSTEM_MODE);
		return Database.getQueryLocatorWithBinds(Svc_CampaignSource.memberQuery(),
			new Map<String, Object>{ 'parentIds' => parentIds }, AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		try {
			total.add(prunePhase
				? Svc_CampaignSource.prune((List<CampaignMember>) scope, dryRun)
				: Svc_CampaignSource.sync((List<Account>) scope, Svc_CampaignSource.sources(), dryRun));
		} catch (Exception e) {
			if (errors.size() < 100) errors.add(e.getMessage());
		}
	}

	public override void finishBatch(Database.BatchableContext bc) {
		if (!prunePhase) {
			Batch_CampaignSource next = new Batch_CampaignSource(dryRun);
			next.prunePhase = true;
			next.total = total;
			next.errors = errors;
			next.dispatcher = dispatcher;
			Database.executeBatch(next, getBatchSize());
			return;
		}
		String summary = (dryRun ? 'DRY RUN - ' : '') + total + ', errors ' + errors.size() + ' ' + errors;
		System.debug(LoggingLevel.INFO, 'Batch_CampaignSource: ' + summary);
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_CampaignSource');
	}
}
