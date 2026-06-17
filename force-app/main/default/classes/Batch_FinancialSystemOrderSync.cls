global with sharing class Batch_FinancialSystemOrderSync extends Subscription25.Job_AbstractBatch2 implements Callable {
	private static final Integer DEFAULT_BATCH_SIZE = 1;
	private static final String CONTEXT_NAME = 'Sync Draft Opportunity Orders to FinancialSystem';

	private String mainLogGuid;

	global Batch_FinancialSystemOrderSync() {
		super('Batch_FinancialSystemOrderSync');
	}

	public override Integer getBatchSize() {
		return DEFAULT_BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext context) {
		Logger2 log = Logger2.getInstance();
		log.setContext('S', 'E', Batch_FinancialSystemOrderSync.CONTEXT_NAME, new Order(), context.getJobId());
		log.saveAll();
		this.mainLogGuid = log.getParentGuid();

		return Database.getQueryLocator([
			SELECT Id
			FROM Order
			WHERE Type = 'Opportunity'
				AND Status = 'Draft'
				AND CreatedDate = LAST_N_DAYS:30
		]);
	}

	@TestVisible
	private void executeBatch(Database.BatchableContext context, List<SObject> scope, String logGuid) {
		this.mainLogGuid = logGuid;
		this.executeBatch(context, scope);
	}

	public override void executeBatch(Database.BatchableContext context, List<SObject> scope) {
		Queue_FinancialSystemOrderSync financialSystemQueue = new Queue_FinancialSystemOrderSync((Order)scope[0], this.mainLogGuid);
		System.enqueueJob(financialSystemQueue);
	}

	public override void finishBatch(Database.BatchableContext context) {
	}

	public Object call(String action, Map<String, Object> args) {
		if (String.isBlank(action) || action.equalsIgnoreCase('run')) {
			return run();
		}

		throw new Util_System.CustomException('Unsupported action: ' + action);
	}

	@InvocableMethod(label='Sync Draft Opportunity Orders to FinancialSystem' description='Syncs Draft Opportunity Orders created in the last 30 days to FinancialSystem and activates successfully synced Orders.')
	public static List<BatchResult> runFromFlow(List<BatchRequest> requests) {
		List<BatchResult> results = new List<BatchResult>();
		results.add(new BatchResult(run()));
		return results;
	}

	public static Id run() {
		return Database.executeBatch(new Batch_FinancialSystemOrderSync(), DEFAULT_BATCH_SIZE);
	}

	public class BatchRequest {
		@InvocableVariable(label='Batch size')
		public Integer batchSize;
	}

	public class BatchResult {
		@InvocableVariable(label='Batch job ID')
		public Id jobId;

		public BatchResult() {
		}

		public BatchResult(Id jobId) {
			this.jobId = jobId;
		}
	}
}