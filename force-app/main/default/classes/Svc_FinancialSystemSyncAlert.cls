/**
 * Blocking + alerting for the account and order sync to the financial system (Exact Online).
 *
 * Every failure / warning gets a category where it is raised (see categorize):
 *  - DATA      : hard - a person must fix it (Web Services validation, missing establishment address, duplicate Exact
 *                link, Exact 400 validation message; orders: no products, products of several warehouses, no Exact
 *                warehouse id, items not in Exact). DATA warnings count as well (account in Exact, a contact refused).
 *  - TECHNICAL : soft - connection / authorisation / Exact-side problem (401/403/404/5xx, callout failure, unreadable
 *                response, unhandled exception) and bank account / mandate problems. Retried with back-off, never blocks.
 *  - SILENT    : by design not synced (reseller without Exact, sandbox without acceptance environment).
 *
 * HARD_FAILURE_LIMIT hard failures in a row (FinancialSyncHardFailures__c) -> FinancialSyncBlocked__c: the batches skip
 * the record and the ONLY alert is sent (user decision 2026-10-13):
 *  - owner is an active person            -> bell notification (CustomNotificationType FinancialSystemSyncFailed)
 *  - owner is an integration profile, inactive, not a standard user or a queue
 *                                         -> Case owned by queue gqCaseAdministration<reseller> (2 GR / 3 BE -> 1 NL)
 * User.Integration_User__c is not used: it also counts System Administrators.
 * Unblocked by a successful sync, the "Sync to Exact (new)" button / action, or (account) a data change that makes
 * rbb_Account re-flag the account (FinancialSyncAttempts__c reset to 0).
 * TODO: route the gqCaseAdministration queues via Omni-channel.
 */
public without sharing class Svc_FinancialSystemSyncAlert {
	public static final String NOTIFICATION_TYPE = 'FinancialSystemSyncFailed';
	public static final Integer HARD_FAILURE_LIMIT = 3;
	public static final String QUEUE_PREFIX = 'gqCaseAdministration';
	// resellers without their own administration queue
	private static final Map<String, String> QUEUE_RESELLER = new Map<String, String>{ '2' => '1', '3' => '1' };

	public enum Category { DATA, TECHNICAL, SILENT }

	/** The data must be fixed by a person: thrown where the sync knows the cause is data. */
	public class DataException extends Exception {}

	public class Issue {
		public Category category;
		public String message;
		public Issue(Category category, String message) {
			this.category = category;
			this.message = message;
		}
	}

	public class Alert {
		public Id recordId;
		public Id accountId;
		public Id ownerId;
		public String reseller;
		public String title;
		public String body;
	}

	@TestVisible
	private static List<Alert> notified = new List<Alert>();
	@TestVisible
	private static List<Case> casesCreated = new List<Case>();

	// ---------------------------------------------------------------- classification

	public static Category categorize(Exception e) {
		if (e instanceof DataException) {
			return Category.DATA;
		}
		if (e instanceof Util_System.CustomException) {
			return Category.SILENT;
		}
		if (e instanceof Util_System.FinancialSyncException) {
			// Exact answers 400 with a readable validation message (e.g. invalid postcode / VAT number)
			return Util_FinancialSystem.lastErrorStatus == 400 ? Category.DATA : Category.TECHNICAL;
		}
		return Category.TECHNICAL;
	}

	/** First hard (DATA) message of a run, or null when the run had no hard failure. */
	public static String hardFailure(List<Issue> issues) {
		for (Issue i : issues) {
			if (i.category == Category.DATA) {
				return i.message;
			}
		}
		return null;
	}

	/**
	 * Alert for a record that just got blocked.
	 */
	public static Alert blocked(Id recordId, Id accountId, Id ownerId, String reseller, String label, String message, String restart) {
		Alert a = new Alert();
		a.recordId = recordId;
		a.accountId = accountId;
		a.ownerId = ownerId;
		a.reseller = reseller;
		a.title = ('Exact sync stopped: ' + label).left(250);
		a.body = ('Stopped after ' + HARD_FAILURE_LIMIT + ' failed attempts: ' + message + '\n' + restart).left(750);
		return a;
	}

	@TestVisible
	private static Boolean isIntegrationProfile(String profileName) {
		return profileName != null && (profileName.containsIgnoreCase('Integration') || profileName == 'miSync' || profileName == 'PT1');
	}

	@TestVisible
	private static String queueName(String reseller) {
		String code = String.isBlank(reseller) ? '1' : reseller;
		return QUEUE_PREFIX + (QUEUE_RESELLER.containsKey(code) ? QUEUE_RESELLER.get(code) : code);
	}

	// ---------------------------------------------------------------- delivery

	/**
	 * Notifies the owner or creates a case. Never throws: the outcome per record goes into the sync log.
	 */
	public static Map<Id, String> send(List<Alert> alerts) {
		Map<Id, String> outcome = new Map<Id, String>();
		if (alerts.isEmpty()) {
			return outcome;
		}
		try {
			Set<Id> ownerIds = new Set<Id>();
			for (Alert a : alerts) {
				ownerIds.add(a.ownerId);
			}
			Map<Id, User> owners = new Map<Id, User>([
				SELECT Id, IsActive, UserType, Profile.Name FROM User WHERE Id IN :ownerIds WITH SYSTEM_MODE
			]);
			List<Alert> toNotify = new List<Alert>();
			List<Alert> toCase = new List<Alert>();
			for (Alert a : alerts) {
				User u = owners.get(a.ownerId);
				Boolean person = u != null && u.IsActive && u.UserType == 'Standard' && !Svc_FinancialSystemSyncAlert.isIntegrationProfile(u.Profile?.Name);
				if (person) {
					toNotify.add(a);
				} else {
					toCase.add(a);
				}
			}
			Svc_FinancialSystemSyncAlert.notifyOwners(toNotify, outcome);
			Svc_FinancialSystemSyncAlert.createCases(toCase, outcome);
		} catch (Exception e) {
			for (Alert a : alerts) {
				if (!outcome.containsKey(a.recordId)) {
					outcome.put(a.recordId, 'Alert not sent: ' + e.getMessage());
				}
			}
		}
		return outcome;
	}

	private static void notifyOwners(List<Alert> alerts, Map<Id, String> outcome) {
		if (alerts.isEmpty()) {
			return;
		}
		List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE WITH SYSTEM_MODE LIMIT 1];
		for (Alert a : alerts) {
			if (types.isEmpty()) {
				outcome.put(a.recordId, 'Alert not sent: notification type ' + NOTIFICATION_TYPE + ' missing.');
				continue;
			}
			try {
				Messaging.CustomNotification n = new Messaging.CustomNotification();
				n.setNotificationTypeId(types[0].Id);
				n.setTitle(a.title);
				n.setBody(a.body);
				n.setTargetId(a.recordId);
				n.send(new Set<String>{ a.ownerId });
				notified.add(a);
				outcome.put(a.recordId, 'Sync stopped; owner notified.');
			} catch (Exception e) {
				outcome.put(a.recordId, 'Sync stopped; owner notification failed: ' + e.getMessage());
			}
		}
	}

	/**
	 * Owner is not a person who reads a bell notification (webshop / platform integration, inactive, automated process,
	 * queue): a case for the administration queue of the reseller. No second case while one with the same subject is open.
	 */
	private static void createCases(List<Alert> alerts, Map<Id, String> outcome) {
		if (alerts.isEmpty()) {
			return;
		}
		Set<String> queueNames = new Set<String>();
		Set<Id> accountIds = new Set<Id>();
		Set<String> subjects = new Set<String>();
		for (Alert a : alerts) {
			queueNames.add(Svc_FinancialSystemSyncAlert.queueName(a.reseller));
			accountIds.add(a.accountId);
			subjects.add(a.title);
		}
		Map<String, Id> queues = new Map<String, Id>();
		for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' AND DeveloperName IN :queueNames WITH SYSTEM_MODE]) {
			queues.put(g.DeveloperName, g.Id);
		}
		Set<String> open = new Set<String>();
		for (Case c : [SELECT AccountId, Subject FROM Case WHERE AccountId IN :accountIds AND Subject IN :subjects AND IsClosed = false WITH SYSTEM_MODE]) {
			open.add(c.AccountId + '|' + c.Subject);
		}
		Id recordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Default')?.getRecordTypeId();

		List<Case> cases = new List<Case>();
		List<Alert> caseAlerts = new List<Alert>();
		for (Alert a : alerts) {
			String queue = Svc_FinancialSystemSyncAlert.queueName(a.reseller);
			if (!queues.containsKey(queue)) {
				outcome.put(a.recordId, 'Sync stopped; no case created: queue ' + queue + ' missing.');
			} else if (open.contains(a.accountId + '|' + a.title)) {
				outcome.put(a.recordId, 'Sync stopped; an open case already exists.');
			} else {
				cases.add(new Case(
					RecordTypeId = recordTypeId,
					OwnerId = queues.get(queue),
					AccountId = a.accountId,
					Origin = 'Automated',
					Subject = a.title,
					Description = a.body + '\n' + Url.getOrgDomainUrl().toExternalForm() + '/' + a.recordId
				));
				caseAlerts.add(a);
			}
		}
		if (cases.isEmpty()) {
			return;
		}
		List<Database.SaveResult> srs = Database.insert(cases, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < srs.size(); i++) {
			if (srs[i].isSuccess()) {
				casesCreated.add(cases[i]);
				outcome.put(caseAlerts[i].recordId, 'Sync stopped; case created for ' + Svc_FinancialSystemSyncAlert.queueName(caseAlerts[i].reseller) + '.');
			} else {
				outcome.put(caseAlerts[i].recordId, 'Sync stopped; case not created: ' + srs[i].getErrors()[0].getMessage());
			}
		}
	}
}
