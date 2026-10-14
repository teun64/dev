/**
 * Repairs draft Opportunity orders not yet in Exact: sets the warehouse API name on the order and splits
 * orders with products of more than one warehouse (Exact allows one warehouse per sales order), see
 * Util_FinancialSystemWarehouse.splitOrders.
 * Default (dispatcher step before Batch_FinancialSystemOrderSync): only orders flagged for the sync, so an order is not
 * split while someone is still working on it. Repair (once, after the warehouse data is set):
 * Database.executeBatch(new Batch_FinancialSystemOrderWarehouse(true), 20) - all draft orders.
 */
global class Batch_FinancialSystemOrderWarehouse extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {
	// per order: 1 update + insert / delete / insert when split
	private static final Integer BATCH_SIZE = 20;

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	// true: all draft Opportunity orders (repair); false: only the ones flagged for the sync
	private Boolean allDrafts = false;

	global Batch_FinancialSystemOrderWarehouse() {
		super('Batch_FinancialSystemOrderWarehouse');
	}

	public Batch_FinancialSystemOrderWarehouse(Boolean allDrafts) {
		this();
		this.allDrafts = allDrafts == true;
	}

	public override Integer getBatchSize() {
		return BATCH_SIZE;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		// no bind variables: the Subscription25 job framework runs the locator outside this method's scope
		return Database.getQueryLocator(
			'SELECT Id FROM Order WHERE Status = \'Draft\' AND Exact_Id__c = null'
			+ ' AND Type IN (\'' + String.join(new List<String>(Util_FinancialSystemWarehouse.SPLIT_ORDER_TYPES), '\',\'') + '\')'
			+ (this.allDrafts ? '' : ' AND SyncToFinancialSystem__c = true')
			+ ' ORDER BY CreatedDate ASC', AccessLevel.SYSTEM_MODE);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Map<Id, String> results = Util_FinancialSystemWarehouse.splitOrders(new Map<Id, SObject>(scope).keySet());
		for (Id ordId : results.keySet()) {
			if (results.get(ordId).startsWith('Failed')) {
				System.debug(LoggingLevel.ERROR, 'Order ' + ordId + ': ' + results.get(ordId));
			}
		}
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemOrderWarehouse');
	}
}
