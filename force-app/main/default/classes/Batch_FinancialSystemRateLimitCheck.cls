/**
 * Daily check of the financial system (Exact Online) API rate limit per administration.
 * One cheap call (GET current/Me) per administration returns the X-RateLimit-* headers; the daily limit,
 * remaining calls and reset moment are stored on the administration (Daily_Limit__c,
 * FinancialRateLimitRemaining__c, ...ResetOn__c, ...CheckedOn__c). The sync batches use these with
 * FinancialRateLimitMaxPercentage__c to stay within their share of the daily limit.
 * Logs a WARNING Event_Log__c when the previous usage already exceeded that share.
 * Scheduled as a Subscription25 job (Subscription25__Schedulable_Class__c, Name = Unique Name = class name).
 */
global class Batch_FinancialSystemRateLimitCheck extends Subscription25.Job_AbstractBatch2 implements Database.AllowsCallouts, Util_JobDispatcher.Step {
	@TestVisible
	private static final String ME_ENDPOINT = 'api/v1/current/Me';

	// set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
	private String dispatcher;

	public void setDispatcher(String dispatcher) {
		this.dispatcher = dispatcher;
	}

	global Batch_FinancialSystemRateLimitCheck() {
		super('Batch_FinancialSystemRateLimitCheck');
	}

	public override Integer getBatchSize() {
		return 10;
	}

	public override Database.QueryLocator startBatch(Database.BatchableContext bc) {
		return Database.getQueryLocator([
			SELECT Id
			FROM Subscription25__Administration__c
			WHERE Subscription25__Active__c = true
				AND Subscription25__Synchronisation__c = :Util_FinancialSystem.SYNC_EXACT
				AND Subscription25__Named_Credential__c != null
			WITH SYSTEM_MODE
		]);
	}

	public override void executeBatch(Database.BatchableContext bc, List<SObject> scope) {
		Batch_FinancialSystemRateLimitCheck.check(new Map<Id, SObject>(scope).keySet());
	}

	/**
	 * Reads and stores the rate limit of the given administrations. Callouts first, DML after.
	 */
	public static void check(Set<Id> adminIds) {
		List<Subscription25__Administration__c> admins = [
			SELECT Id, Name, Subscription25__Active__c, Subscription25__Synchronisation__c, Subscription25__Named_Credential__c, Subscription25__Twinfield_Company_Code__c,
				Acceptance_Environment_Available__c, Daily_Limit__c, FinancialRateLimitMaxPercentage__c,
				FinancialRateLimitRemaining__c, FinancialRateLimitResetOn__c, FinancialRateLimitCheckedOn__c
			FROM Subscription25__Administration__c
			WHERE Id IN :adminIds
			WITH SYSTEM_MODE
		];

		List<Event_Log__c> logs = new List<Event_Log__c>();
		Set<String> namedCredentials = new Set<String>();
		for (Subscription25__Administration__c admin : admins) {
			if (!Util_FinancialSystem.isSyncEnabled(admin)) {
				continue;
			}
			// usage of the previous period, before this check refreshes the values
			Util_FinancialSystem.Limits before = new Util_FinancialSystem.Limits(admin);
			Event_Log__c log = Util_Event.createLog('S', 'E', 'Subscription25__Administration__c', 'RateLimitCheck', admin.Id, admin.Name, null);
			log.Result_Status__c = Util_Event.LogResultStatus.COMPLETED.name();
			log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
			log.Message__c = '';
			namedCredentials.add(admin.Subscription25__Named_Credential__c);
			try {
				Util_FinancialSystem.doRequest(admin, ME_ENDPOINT, new Map<String, String>{ '$select' => 'CurrentDivision' }, 'GET', null, log.GUID__c);
				Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(admin);
				log.Message__c = 'Daily limit ' + lim.dailyLimit + ', remaining ' + lim.dailyRemaining
					+ ' (' + lim.usedPercentage() + '% used), batch maximum ' + lim.maxPercentage + '%.';
				Decimal prevUsed = before.usedPercentage();
				if (prevUsed != null && prevUsed > before.maxPercentage) {
					log.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
					log.Message__c += ' Previous check: ' + prevUsed + '% used, above the maximum.';
				}
			} catch (Exception e) {
				log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
				log.Message__c = e.getTypeName() + ': ' + e.getMessage();
			}
			logs.add(log);
		}
		Util_FinancialSystem.saveLimits();
		Util_FinancialSystem.saveLogs(logs, namedCredentials, null);
	}

	public override void finishBatch(Database.BatchableContext bc) {
		Util_JobDispatcher.startNext(this.dispatcher, 'Batch_FinancialSystemRateLimitCheck');
	}
}
