/**
 * Runs the steps of a job dispatcher (JobDispatcherStep__mdt) one after another, lowest Order__c first.
 * Batch_JobDispatcher starts the first active step; every step starts the next one from its finishBatch.
 * A batch can only start another batch from finish, so the hand-over always happens there.
 * A failed step ends the round; the next dispatcher run starts again at the first step.
 */
public with sharing class Util_JobDispatcher {
	/** Implemented by every step class: the dispatcher name travels with the batch instance to its finishBatch. */
	public interface Step {
		void setDispatcher(String dispatcher);
	}

	public class DispatcherException extends Exception {}

	private static final Set<String> OPEN_STATUSES = new Set<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' };

	@TestVisible
	private static List<JobDispatcherStep__mdt> testSteps;

	/**
	 * Active steps of the dispatcher, lowest Order__c first. A class configured twice only runs at its first position:
	 * startNext finds the current step by class name, so a repeated class would restart the round endlessly.
	 */
	public static List<JobDispatcherStep__mdt> getSteps(String dispatcher) {
		List<JobDispatcherStep__mdt> source = testSteps != null ? testSteps : JobDispatcherStep__mdt.getAll().values();
		Map<Decimal, List<JobDispatcherStep__mdt>> byOrder = new Map<Decimal, List<JobDispatcherStep__mdt>>();
		for (JobDispatcherStep__mdt s : source) {
			if (s.IsActive__c && s.Dispatcher__c == dispatcher) {
				if (!byOrder.containsKey(s.Order__c)) {
					byOrder.put(s.Order__c, new List<JobDispatcherStep__mdt>());
				}
				byOrder.get(s.Order__c).add(s);
			}
		}
		List<Decimal> orders = new List<Decimal>(byOrder.keySet());
		orders.sort();
		List<JobDispatcherStep__mdt> result = new List<JobDispatcherStep__mdt>();
		Set<String> classNames = new Set<String>();
		for (Decimal o : orders) {
			for (JobDispatcherStep__mdt s : byOrder.get(o)) {
				if (classNames.add(s.ApexClass__c)) {
					result.add(s);
				}
			}
		}
		return result;
	}

	/**
	 * Starts the first step of a new round, unless a step of the previous round is still running.
	 * Returns the started batch job id, or null when skipped or when there are no active steps.
	 */
	public static Id startRound(String dispatcher) {
		List<JobDispatcherStep__mdt> steps = getSteps(dispatcher);
		if (steps.isEmpty() || isRunning(steps)) {
			return null;
		}
		return startStep(steps[0], dispatcher);
	}

	/**
	 * Starts the step after the given class. Call from the step's finishBatch.
	 * No-op when the batch was not started by a dispatcher (dispatcher == null) or when it was the last step.
	 */
	public static Id startNext(String dispatcher, String currentClass) {
		if (String.isBlank(dispatcher)) {
			return null;
		}
		List<JobDispatcherStep__mdt> steps = getSteps(dispatcher);
		for (Integer i = 0; i < steps.size() - 1; i++) {
			if (steps[i].ApexClass__c == currentClass) {
				return startStep(steps[i + 1], dispatcher);
			}
		}
		return null;
	}

	private static Boolean isRunning(List<JobDispatcherStep__mdt> steps) {
		Set<String> classNames = new Set<String>();
		for (JobDispatcherStep__mdt s : steps) {
			classNames.add(s.ApexClass__c);
		}
		return ![
			SELECT Id FROM AsyncApexJob
			WHERE JobType = 'BatchApex' AND ApexClass.Name IN :classNames AND Status IN :OPEN_STATUSES
			LIMIT 1
		].isEmpty();
	}

	private static Id startStep(JobDispatcherStep__mdt step, String dispatcher) {
		Type t = Type.forName(step.ApexClass__c);
		Object instance = t == null ? null : t.newInstance();
		if (!(instance instanceof Subscription25.Job_AbstractBatch2) || !(instance instanceof Step)) {
			throw new DispatcherException(
				'Dispatcher ' + dispatcher + ': ' + step.ApexClass__c + ' is not a Subscription25.Job_AbstractBatch2 implementing Util_JobDispatcher.Step'
			);
		}
		((Step) instance).setDispatcher(dispatcher);
		return Database.executeBatch((Database.Batchable<SObject>) instance, batchSize(step, (Subscription25.Job_AbstractBatch2) instance));
	}

	private static Integer batchSize(JobDispatcherStep__mdt step, Subscription25.Job_AbstractBatch2 instance) {
		if (step.BatchSize__c != null && step.BatchSize__c > 0) {
			return step.BatchSize__c.intValue();
		}
		List<Subscription25__Schedulable_Class__c> config = [
			SELECT Subscription25__Batch_Size__c FROM Subscription25__Schedulable_Class__c
			WHERE Name = :step.ApexClass__c
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (!config.isEmpty() && config[0].Subscription25__Batch_Size__c != null && config[0].Subscription25__Batch_Size__c > 0) {
			return config[0].Subscription25__Batch_Size__c.intValue();
		}
		return instance.getBatchSize();
	}
}
