/**
 * Generic sales call-back: a Case (Origin Callback) in gqCaseSalesCallback1, which Omni-Channel routes to sales through
 * rcCaseSalesCallback1 (priority 3). Not tied to one campaign: the Campaign gives the context (Callback Label in the
 * subject, Campaign on the Case), so a campaign mail, a call outcome or later the website all use the same entry.
 *
 * Steps (one invocable, like Svc_PaymentActionRequired):
 *  - request     → one open call-back per Contact + Campaign: a new Case, or the note added to the open one
 *  - not reached → the agent tried and didn't reach the customer: try + 1, back to the queue (Omni routes it again);
 *                  at MAX_ATTEMPTS the Case closes as not reached
 *  - expire      → CallbackDueOn__c passed on an open Case (rab_Case_Callback_Due): closes as not reached
 * Not reached = Status Unsuccesfull, Reason Customer Unavailable, a mail to the manager of the last agent (fallback:
 * label SalesCallback_FallbackManagerEmail) and the campaign member back into the mail cycle (afl_CampaignMember_Mail_Cycle).
 *
 * not reached / expire are bulk: every call-back requested on one day has the same due moment, so the scheduled path
 * hands them over together (one query per object, one update per object, one sendEmail).
 * Runs in system mode: the request step is also called for guests (response page) and agents can't edit CampaignMember.
 */
public without sharing class Svc_SalesCallback {

	public static final String STEP_REQUEST     = 'request';
	public static final String STEP_NOT_REACHED = 'not reached';
	public static final String STEP_EXPIRE      = 'expire';

	public static final String QUEUE            = 'gqCaseSalesCallback1';
	public static final String BUSINESS_HOURS   = 'Sales (NL)';
	public static final String TIME_ZONE        = 'Europe/Amsterdam';
	public static final String SENDER           = 'noreply@movingintelligence.com';
	public static final String ORIGIN           = 'Callback';
	public static final String STATUS_RETRY     = 'Call Back';
	public static final String STATUS_CLOSED    = 'Unsuccesfull';
	public static final String REASON_CLOSED    = 'Customer Unavailable';
	public static final Integer MAX_ATTEMPTS     = 2;
	public static final Integer DUE_WORKING_DAYS = 2;

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	public class Request {
		@InvocableVariable(label='Step' description='request, not reached or expire' required=true)
		public String step;
		@InvocableVariable(label='Case Id' description='not reached / expire: the call-back Case')
		public Id caseId;
		@InvocableVariable(label='Contact Id' description='request: the customer to call back')
		public Id contactId;
		@InvocableVariable(label='Campaign Id' description='request: campaign the request comes from (optional)')
		public Id campaignId;
		@InvocableVariable(label='Campaign Member Id' description='request: member to put back into the mail cycle when not reached (optional)')
		public String campaignMemberId;
		@InvocableVariable(label='Source' description='request: Campaign mail, Call, Website or Marketing')
		public String source;
		@InvocableVariable(label='Note' description='Text added to the Case description')
		public String note;
	}

	public class Result {
		@InvocableVariable(label='Case Id')
		public Id caseId;
	}

	@InvocableMethod(label='Sales Callback' description='Creates a sales call-back Case, logs a try that did not reach the customer, or expires an open call-back.')
	public static List<Result> run(List<Request> requests) {
		List<Result> results = new List<Result>();
		Map<Id, String> notReachedNotes = new Map<Id, String>();
		Set<Id> expireIds = new Set<Id>();
		for (Request r : requests) {
			Result res = new Result();
			if (r != null) {
				if (STEP_REQUEST.equals(r.step)) {
					res.caseId = request(r);
				} else if (STEP_NOT_REACHED.equals(r.step) && r.caseId != null) {
					notReachedNotes.put(r.caseId, r.note);
					res.caseId = r.caseId;
				} else if (STEP_EXPIRE.equals(r.step) && r.caseId != null) {
					expireIds.add(r.caseId);
					res.caseId = r.caseId;
				}
			}
			results.add(res);
		}
		if (!notReachedNotes.isEmpty()) notReached(notReachedNotes);
		if (!expireIds.isEmpty()) expire(expireIds);
		return results;
	}

	// ── Request ───────────────────────────────────────────────────────────────
	public static Id request(Request r) {
		if (r.contactId == null) return null;
		List<Case> open = [
			SELECT Id, Description FROM Case
			WHERE ContactId = :r.contactId AND Campaign__c = :r.campaignId AND Origin = :ORIGIN
			  AND CallbackSource__c != null AND IsClosed = false
			WITH SYSTEM_MODE
			ORDER BY CreatedDate DESC LIMIT 1
		];
		if (!open.isEmpty()) {
			// a second click, a mail scanner or a request from another channel: no second Case
			Case c = open[0];
			if (String.isNotBlank(r.note)) {
				Database.update(new Case(Id = c.Id, Description = addNote(c.Description, r.note)), RUNNING_MODE);
			}
			return c.Id;
		}

		Contact con = [SELECT Id, AccountId, Account.Name, Name FROM Contact WHERE Id = :r.contactId WITH SYSTEM_MODE];
		String label = 'Sales';
		if (r.campaignId != null) {
			Campaign camp = [SELECT Name, CallbackLabel__c FROM Campaign WHERE Id = :r.campaignId WITH SYSTEM_MODE];
			label = String.isNotBlank(camp.CallbackLabel__c) ? camp.CallbackLabel__c : camp.Name;
		}
		Case c = new Case(
			OwnerId = queueId(),
			Origin = ORIGIN,
			Priority = 'High',
			Status = 'New',
			ContactId = con.Id,
			AccountId = con.AccountId,
			Subject = ('Callback - ' + label + ' - ' + (con.AccountId != null ? con.Account.Name : con.Name)).left(255),
			Description = addNote(null, r.note),
			Campaign__c = r.campaignId,
			CampaignMemberId__c = r.campaignMemberId,
			CallbackSource__c = r.source,
			CallbackAttempts__c = 0,
			CallbackDueOn__c = dueOn(Datetime.now())
		);
		Database.insert(c, RUNNING_MODE);
		return c.Id;
	}

	/**
	 * Bulk request: one result Id per request, same rules as request() (one open call-back per Contact + Campaign: a new
	 * Case or the note added to the open one; also between requests of the same call). One query per object, one insert and
	 * one update for all. Requests without Contact give null; requests without Campaign are handled one by one.
	 */
	public static List<Id> requestBulk(List<Request> requests) {
		List<Id> ids = new List<Id>();
		Set<Id> contactIds = new Set<Id>();
		Set<Id> campaignIds = new Set<Id>();
		for (Request r : requests) {
			ids.add(null);
			if (r.contactId != null && r.campaignId != null) {
				contactIds.add(r.contactId);
				campaignIds.add(r.campaignId);
			}
		}
		Map<String, Case> openByKey = new Map<String, Case>();
		if (!contactIds.isEmpty()) {
			for (Case c : [
				SELECT Id, Description, ContactId, Campaign__c FROM Case
				WHERE ContactId IN :contactIds AND Campaign__c IN :campaignIds AND Origin = :ORIGIN
				  AND CallbackSource__c != null AND IsClosed = false
				WITH SYSTEM_MODE ORDER BY CreatedDate DESC
			]) if (!openByKey.containsKey(c.ContactId + '|' + c.Campaign__c)) openByKey.put(c.ContactId + '|' + c.Campaign__c, c);
		}
		Map<Id, Contact> contacts = new Map<Id, Contact>([
			SELECT Id, AccountId, Account.Name, Name FROM Contact WHERE Id IN :contactIds WITH SYSTEM_MODE
		]);
		Map<Id, Campaign> campaigns = new Map<Id, Campaign>([
			SELECT Id, Name, CallbackLabel__c FROM Campaign WHERE Id IN :campaignIds WITH SYSTEM_MODE
		]);
		Id queue = contactIds.isEmpty() ? null : queueId();
		Datetime due = contactIds.isEmpty() ? null : dueOn(Datetime.now());
		Map<String, Case> newByKey = new Map<String, Case>();
		Map<Id, Case> noteUpdates = new Map<Id, Case>();
		for (Integer i = 0; i < requests.size(); i++) {
			Request r = requests[i];
			if (r.contactId == null) continue;
			if (r.campaignId == null) {
				ids[i] = request(r);
				continue;
			}
			String key = r.contactId + '|' + r.campaignId;
			Case open = openByKey.get(key);
			if (open != null) {
				if (String.isNotBlank(r.note)) {
					Case upd = noteUpdates.containsKey(open.Id) ? noteUpdates.get(open.Id) : new Case(Id = open.Id, Description = open.Description);
					upd.Description = addNote(upd.Description, r.note);
					noteUpdates.put(open.Id, upd);
				}
				ids[i] = open.Id;
				continue;
			}
			Case created = newByKey.get(key);
			if (created == null) {
				Contact con = contacts.get(r.contactId);
				Campaign camp = campaigns.get(r.campaignId);
				String label = String.isNotBlank(camp.CallbackLabel__c) ? camp.CallbackLabel__c : camp.Name;
				created = new Case(
					OwnerId = queue, Origin = ORIGIN, Priority = 'High', Status = 'New', ContactId = con.Id, AccountId = con.AccountId,
					Subject = ('Callback - ' + label + ' - ' + (con.AccountId != null ? con.Account.Name : con.Name)).left(255),
					Description = addNote(null, r.note), Campaign__c = r.campaignId, CampaignMemberId__c = r.campaignMemberId,
					CallbackSource__c = r.source, CallbackAttempts__c = 0, CallbackDueOn__c = due
				);
				newByKey.put(key, created);
			} else if (String.isNotBlank(r.note)) {
				created.Description = addNote(created.Description, r.note);
			}
		}
		if (!newByKey.isEmpty()) Database.insert(newByKey.values(), RUNNING_MODE);
		if (!noteUpdates.isEmpty()) Database.update(noteUpdates.values(), RUNNING_MODE);
		for (Integer i = 0; i < requests.size(); i++) {
			Request r = requests[i];
			if (ids[i] != null || r.contactId == null || r.campaignId == null) continue;
			ids[i] = newByKey.get(r.contactId + '|' + r.campaignId).Id;
		}
		return ids;
	}

	// ── Not reached ───────────────────────────────────────────────────────────
	public static void notReached(Id caseId, String note) {
		notReached(new Map<Id, String>{ caseId => note });
	}

	public static void notReached(Map<Id, String> notesByCase) {
		Id agentId = UserInfo.getUserId();
		Id queue = queueId();
		List<Case> retry = new List<Case>();
		List<Case> closeCases = new List<Case>();
		List<Case> closeUpdates = new List<Case>();
		for (Case c : openCallbacks(notesByCase.keySet())) {
			Integer attempts = (c.CallbackAttempts__c == null ? 0 : c.CallbackAttempts__c.intValue()) + 1;
			String note = notesByCase.get(c.Id);
			Case upd = new Case(
				Id = c.Id,
				CallbackAttempts__c = attempts,
				CallbackLastAgent__c = agentId,
				Description = addNote(c.Description, 'Try ' + attempts + ' not reached' + (String.isBlank(note) ? '' : ': ' + note))
			);
			if (attempts < MAX_ATTEMPTS) {
				// back to the queue: Omni-Channel offers it again
				upd.OwnerId = queue;
				upd.Status = STATUS_RETRY;
				retry.add(upd);
			} else {
				c.CallbackLastAgent__c = agentId;
				closeCases.add(c);
				closeUpdates.add(upd);
			}
		}
		if (!retry.isEmpty()) Database.update(retry, RUNNING_MODE);
		close(closeCases, closeUpdates);
	}

	// ── Expire ────────────────────────────────────────────────────────────────
	public static void expire(Set<Id> caseIds) {
		List<Case> closeCases = new List<Case>();
		List<Case> closeUpdates = new List<Case>();
		for (Case c : openCallbacks(caseIds)) {
			if (c.CallbackLastAgent__c == null && c.OwnerId.getSObjectType() == User.SObjectType) c.CallbackLastAgent__c = c.OwnerId;
			closeCases.add(c);
			closeUpdates.add(new Case(Id = c.Id,
				Description = addNote(c.Description, 'Not called back within ' + DUE_WORKING_DAYS + ' working days')));
		}
		close(closeCases, closeUpdates);
	}

	// ── Close as not reached ──────────────────────────────────────────────────
	// cases = the Case as read (CallbackLastAgent__c = agent for the mail), updates = what is written
	private static void close(List<Case> cases, List<Case> updates) {
		if (cases.isEmpty()) return;
		for (Case upd : updates) {
			upd.Status = STATUS_CLOSED;
			upd.Reason = REASON_CLOSED;
		}
		Database.update(updates, RUNNING_MODE);
		backToMailCycle(cases);
		mailManagers(cases);
	}

	// The member stopped the mail cycle with "Call me" (opens a call-back, Svc_CampaignResponse); not reached = the
	// cycle continues where it was. "Offer" has an Opportunity: no mails again.
	private static void backToMailCycle(List<Case> cases) {
		Set<Id> memberIds = new Set<Id>();
		for (Case c : cases) {
			if (String.isBlank(c.CampaignMemberId__c)) continue;
			try {
				memberIds.add(Id.valueOf(c.CampaignMemberId__c));
			} catch (StringException e) {
				System.debug(LoggingLevel.WARN, 'Svc_SalesCallback: invalid member Id on Case ' + c.CaseNumber);
			}
		}
		if (memberIds.isEmpty()) return;
		List<CampaignMember> updates = new List<CampaignMember>();
		for (CampaignMember cm : [
			SELECT Id, MailNumber__c FROM CampaignMember WHERE Id IN :memberIds AND Response__c = 'Call me' WITH SYSTEM_MODE
		]) {
			updates.add(new CampaignMember(
				Id = cm.Id,
				Response__c = null,
				ResponseOn__c = null,
				MailStage__c = cm.MailNumber__c == null ? 'Waiting' : 'Due'
			));
		}
		if (!updates.isEmpty()) Database.update(updates, RUNNING_MODE);
	}

	private static void mailManagers(List<Case> cases) {
		Set<Id> agentIds = new Set<Id>();
		for (Case c : cases) if (c.CallbackLastAgent__c != null) agentIds.add(c.CallbackLastAgent__c);
		Map<Id, User> agents = new Map<Id, User>([
			SELECT Id, Name, ManagerId, Manager.IsActive FROM User WHERE Id IN :agentIds WITH SYSTEM_MODE
		]);
		Id fallback = fallbackManager();
		List<OrgWideEmailAddress> sender = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :SENDER WITH SYSTEM_MODE LIMIT 1];

		List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
		for (Case c : cases) {
			User agent = agents.get(c.CallbackLastAgent__c);
			Id managerId = (agent != null && agent.ManagerId != null && agent.Manager.IsActive) ? agent.ManagerId : fallback;
			if (managerId == null) {
				System.debug(LoggingLevel.WARN, 'Svc_SalesCallback: no manager to mail for Case ' + c.CaseNumber);
				continue;
			}
			Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
			m.setTargetObjectId(managerId);
			m.setSaveAsActivity(false);
			// the scheduled path runs as the Automated Process user, which needs an org-wide sender
			if (!sender.isEmpty()) m.setOrgWideEmailAddressId(sender[0].Id);
			m.setSubject('Call-back not reached: ' + c.Subject);
			m.setPlainTextBody(
				'The customer of Case ' + c.CaseNumber + ' was not reached and the call-back is closed.\n\n'
				+ 'Account: ' + (c.Account?.Name == null ? '-' : c.Account.Name) + '\n'
				+ 'Contact: ' + (c.Contact?.Name == null ? '-' : c.Contact.Name) + '\n'
				+ 'Campaign: ' + (c.Campaign__r?.Name == null ? '-' : c.Campaign__r.Name) + '\n'
				+ 'Agent: ' + (agent == null ? 'nobody picked it up' : agent.Name) + '\n\n'
				+ Url.getOrgDomainUrl().toExternalForm() + '/' + c.Id
			);
			mails.add(m);
		}
		if (mails.isEmpty()) return;
		try {
			Messaging.sendEmail(mails, false);
		} catch (Exception e) {
			// Log but do not surface: a mail problem must not reopen or block the call-back
			System.debug(LoggingLevel.WARN, 'Svc_SalesCallback mail failed: ' + e.getMessage());
		}
	}

	@TestVisible
	private static Id managerOf(Id agentId) {
		if (agentId != null) {
			User agent = [SELECT ManagerId, Manager.IsActive FROM User WHERE Id = :agentId WITH SYSTEM_MODE];
			if (agent.ManagerId != null && agent.Manager.IsActive) return agent.ManagerId;
		}
		return fallbackManager();
	}

	private static Id fallbackManager() {
		// sandboxes add .invalid to user emails
		String email = System.Label.SalesCallback_FallbackManagerEmail + '%';
		List<User> fallback = [SELECT Id FROM User WHERE Email LIKE :email AND IsActive = true WITH SYSTEM_MODE LIMIT 1];
		return fallback.isEmpty() ? null : fallback[0].Id;
	}

	// ── Helpers ───────────────────────────────────────────────────────────────
	private static List<Case> openCallbacks(Set<Id> caseIds) {
		return [
			SELECT Id, CaseNumber, Subject, Description, OwnerId, CallbackAttempts__c, CallbackLastAgent__c,
			       CampaignMemberId__c, Account.Name, Contact.Name, Campaign__r.Name
			FROM Case
			WHERE Id IN :caseIds AND IsClosed = false AND CallbackSource__c != null
			WITH SYSTEM_MODE
		];
	}

	private static Id queueId() {
		return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = :QUEUE WITH SYSTEM_MODE].Id;
	}

	// DUE_WORKING_DAYS full working days after the request day (Sales (NL) business hours, so weekends and holidays are
	// skipped): due at the start of the next working day after those, e.g. Friday request → Wednesday opening time.
	// Days are walked one by one because opening hours differ per weekday; days are taken in Amsterdam time, so a
	// guest or a user in another time zone gets the same due moment.
	@TestVisible
	private static Datetime dueOn(Datetime fromMoment) {
		List<BusinessHours> bh = [
			SELECT Id FROM BusinessHours WHERE Name = :BUSINESS_HOURS AND IsActive = true WITH SYSTEM_MODE LIMIT 1
		];
		if (bh.isEmpty()) return fromMoment.addDays(DUE_WORKING_DAYS + 1);
		Timezone tz = Timezone.getTimeZone(TIME_ZONE);
		Datetime due = fromMoment;
		for (Integer i = 0; i <= DUE_WORKING_DAYS; i++) {
			Date nextDay = Date.valueOf(due.format('yyyy-MM-dd', TIME_ZONE)).addDays(1);
			// midnight Amsterdam = midnight GMT minus the Amsterdam offset on that day
			Datetime midnightGmt = Datetime.newInstanceGmt(nextDay, Time.newInstance(0, 0, 0, 0));
			Datetime midnight = midnightGmt.addSeconds(-tz.getOffset(midnightGmt) / 1000);
			due = BusinessHours.nextStartDate(bh[0].Id, midnight);
		}
		return due;
	}

	public static String addNote(String description, String note) {
		if (String.isBlank(note)) return description;
		String line = Datetime.now().format('yyyy-MM-dd HH:mm', TIME_ZONE) + ' ' + note;
		return (String.isBlank(description) ? line : description + '\n' + line).left(32000);
	}
}
