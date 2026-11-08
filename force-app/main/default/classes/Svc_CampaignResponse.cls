/**
 * The customer's answer to a campaign ("apply answer"): one entry for every channel, so the result is always the same.
 * Used by the Customer Hub response page (Ctrl_CampaignResponseGuest, guest) and the call-back Case button
 * (scr_Case_Callback_Reached). Generic: works for any campaign; the campaign supplies the context.
 *
 * Every answer: Response__c + ResponseOn__c, MailStage__c Stopped (the mail cycle stops), and the member Status from
 * STATUS_BY_ANSWER when the campaign has that member status (campaigns without it keep their Status).
 * In a staged campaign (Campaign Role set, Svc_CampaignMove) the member then moves to the sister campaign:
 *  - Call me        → Operational (stays there; back from Source / Not interested / Not reacted) + a sales call-back
 *  - Offer          → Offer (finished), then an Opportunity linked to the Offer campaign with a line per migration
 *                     product (Svc_CampaignOffer: Mi50 → Mi50.M, quantity = the customer's 2G units). No call-back: the
 *                     Opportunity (account owner) is the follow-up. On a call-back Case the Case gets the Opportunity
 *                     and closes as reached.
 *  - Not now        → Source, RecontactFrom__c = the chosen quarter start (default: the next quarter); the next batch
 *                     release skips the member until that date
 *  - Not interested → Not interested
 * A campaign without a role keeps the member where it is (only the fields and the call-back).
 * The same answer twice (a second click, a mail scanner) changes nothing. A different answer replaces the first; an open
 * call-back gets a note so the rep sees it. "Not interested" on the page closes an open call-back (no call needed; user
 * decision 2026-11-07).
 *
 * Also stamps the response token + link on new members (Trigger CampaignMember).
 */
public without sharing class Svc_CampaignResponse {

	public static final String ANSWER_CALL_ME        = 'Call me';
	public static final String ANSWER_OFFER          = 'Offer';
	public static final String ANSWER_NOT_NOW        = 'Not now';
	public static final String ANSWER_NOT_INTERESTED = 'Not interested';

	public static final String OUTCOME_APPLIED   = 'applied';
	public static final String OUTCOME_UNCHANGED = 'unchanged';
	public static final String OUTCOME_INVALID   = 'invalid';

	public static final String CASE_STATUS_REACHED = 'Succesfull';

	// member Status per answer, only set when the campaign has that status
	public static final Map<String, String> STATUS_BY_ANSWER = new Map<String, String>{
		ANSWER_CALL_ME        => 'Call requested',
		ANSWER_OFFER          => 'Offer requested',
		ANSWER_NOT_NOW        => 'Postponed',
		ANSWER_NOT_INTERESTED => 'Declined'
	};

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	public class Request {
		@InvocableVariable(label='Campaign Member Id' description='The member who answered (empty for a call-back without campaign)')
		public String campaignMemberId;
		@InvocableVariable(label='Answer' description='Call me, Offer, Not now or Not interested' required=true)
		public String answer;
		@InvocableVariable(label='Recontact From' description='Not now: first day of the chosen quarter (default: next quarter)')
		public Date recontactFrom;
		@InvocableVariable(label='Source' description='Campaign mail, Call, Website or Marketing')
		public String source;
		@InvocableVariable(label='Note' description='Text added to the call-back Case')
		public String note;
		@InvocableVariable(label='Case Id' description='Call: the call-back Case the rep is on (reached the customer)')
		public Id caseId;
	}

	public class Result {
		@InvocableVariable(label='Outcome' description='applied, unchanged or invalid')
		public String outcome;
		@InvocableVariable(label='Case Id' description='The call-back Case (Call me / Offer)')
		public Id caseId;
		@InvocableVariable(label='Opportunity Id' description='Offer: the Opportunity made')
		public Id opportunityId;
	}

	@InvocableMethod(label='Apply Campaign Answer' description='Applies a customer answer (Call me, Offer, Not now, Not interested) to a campaign member.')
	public static List<Result> run(List<Request> requests) {
		List<Result> results = new List<Result>();
		for (Request r : requests) results.add(apply(r));
		return results;
	}

	public static Result apply(Request r) {
		Result res = new Result();
		res.outcome = OUTCOME_INVALID;
		if (r == null || !STATUS_BY_ANSWER.containsKey(r.answer)) return res;

		CampaignMember cm = member(r.campaignMemberId);
		if (cm == null) {
			// a call-back without campaign (website, marketing): only the Case
			if (r.caseId == null) return res;
			closeCallback(r.caseId, r.answer, r.note, true);
			res.outcome = OUTCOME_APPLIED;
			res.caseId = r.caseId;
			return res;
		}

		Date recontactFrom = ANSWER_NOT_NOW.equals(r.answer)
			? (r.recontactFrom == null ? quarterStarts(Date.today(), 1)[0] : r.recontactFrom)
			: null;
		if (r.answer.equals(cm.Response__c) && recontactFrom == cm.RecontactFrom__c) {
			res.outcome = OUTCOME_UNCHANGED;
			res.caseId = openCallbackId(cm.ContactId, cm.CampaignId);
			return res;
		}

		Database.update(new CampaignMember(
			Id = cm.Id,
			Response__c = r.answer,
			ResponseOn__c = Datetime.now(),
			MailStage__c = 'Stopped',
			RecontactFrom__c = recontactFrom
		), RUNNING_MODE);

		// staged campaign: the member moves to the sister campaign of the answer (the fields above move along)
		Id memberId = cm.Id;
		Id campaignId = cm.CampaignId;
		String role = targetRole(cm.Campaign.CampaignRole__c, r.answer);
		if (role != null && !role.equals(cm.Campaign.CampaignRole__c)) {
			Map<String, Object> values = ANSWER_NOT_NOW.equals(r.answer)
				? new Map<String, Object>{ 'MailStage__c' => null, 'MailNumber__c' => null, 'MailDueOn__c' => null }
				: new Map<String, Object>{ 'MailStage__c' => 'Stopped' };
			CampaignMember moved = Svc_CampaignMove.move(new Set<Id>{ cm.Id }, role, values).get(cm.Id);
			if (moved != null) {
				memberId = moved.Id;
				campaignId = moved.CampaignId;
			}
		}
		String status = STATUS_BY_ANSWER.get(r.answer);
		if (hasStatus(campaignId, status)) Database.update(new CampaignMember(Id = memberId, Status = status), RUNNING_MODE);

		if (ANSWER_OFFER.equals(r.answer)) {
			// in the Offer campaign now (staged): the Opportunity is linked to it
			res.opportunityId = Svc_CampaignOffer.createOffer(cm.ContactId, campaignId, r.source);
			Id caseId = r.caseId != null ? r.caseId : openCallbackId(cm.ContactId, campaignId);
			if (caseId != null) {
				Database.update(new Case(Id = caseId, Opportunity__c = res.opportunityId), RUNNING_MODE);
				// the Opportunity is the follow-up now: the call-back closes (also when the customer answered on the page)
				closeCallback(caseId, r.answer, r.note, r.caseId != null);
				res.caseId = caseId;
			}
		} else if (ANSWER_CALL_ME.equals(r.answer)) {
			if (r.caseId != null) {
				// the rep is on the call-back already
				noteOnCase(r.caseId, r.answer, r.note);
				res.caseId = r.caseId;
			} else {
				Svc_SalesCallback.Request cb = new Svc_SalesCallback.Request();
				cb.step = Svc_SalesCallback.STEP_REQUEST;
				cb.contactId = cm.ContactId;
				cb.campaignId = campaignId;
				cb.campaignMemberId = memberId;
				cb.source = r.source;
				cb.note = noteText(r.answer, r.note);
				res.caseId = Svc_SalesCallback.request(cb);
			}
		} else if (r.caseId != null) {
			closeCallback(r.caseId, r.answer, r.note, true);
			res.caseId = r.caseId;
		} else {
			// answered on the page while a call-back is open: Not interested closes it, otherwise tell the rep before they call
			Id openId = openCallbackId(cm.ContactId, campaignId);
			if (openId != null && ANSWER_NOT_INTERESTED.equals(r.answer)) closeCallback(openId, r.answer, r.note, false);
			else if (openId != null) noteOnCase(openId, r.answer, r.note);
		}
		res.outcome = OUTCOME_APPLIED;
		return res;
	}

	// ── Response token ────────────────────────────────────────────────────────
	// before insert / before update: a token for every member without one (bulk, no queries)
	public static void stampTokens(List<CampaignMember> members) {
		String baseUrl = PreferenceTokenConfig__c.getOrgDefaults()?.Base_Url__c;
		for (CampaignMember cm : members) {
			if (String.isNotBlank(cm.ResponseToken__c)) continue;
			cm.ResponseToken__c = EncodingUtil.convertToHex(Crypto.generateAesKey(256));
			cm.ResponseUrl__c = String.isBlank(baseUrl) ? null : baseUrl.removeEnd('/') + '/response?token=' + cm.ResponseToken__c;
		}
	}

	public static CampaignMember memberByToken(String token) {
		if (String.isBlank(token) || !Pattern.matches('[0-9a-f]{64}', token)) return null;
		List<CampaignMember> found = [
			SELECT Id, CampaignId, ContactId, Response__c, RecontactFrom__c, Contact.FirstName, Contact.Account.Name,
			       Campaign.Name, Campaign.CallbackLabel__c, Campaign.IsActive, Campaign.CampaignRole__c
			FROM CampaignMember WHERE ResponseToken__c = :token WITH SYSTEM_MODE LIMIT 1
		];
		return found.isEmpty() ? null : found[0];
	}

	// ── Quarters ──────────────────────────────────────────────────────────────
	// the first day of the next `count` quarters after the one `today` is in
	public static List<Date> quarterStarts(Date today, Integer count) {
		Integer month = ((today.month() - 1) / 3) * 3 + 1;
		Date start = Date.newInstance(today.year(), month, 1);
		List<Date> starts = new List<Date>();
		for (Integer i = 1; i <= count; i++) starts.add(start.addMonths(3 * i));
		return starts;
	}

	// ── Helpers ───────────────────────────────────────────────────────────────
	private static CampaignMember member(String memberId) {
		if (String.isBlank(memberId)) return null;
		Id cmId;
		try {
			cmId = Id.valueOf(memberId);
		} catch (StringException e) {
			return null;
		}
		List<CampaignMember> found = [
			SELECT Id, CampaignId, ContactId, Response__c, RecontactFrom__c, Campaign.CampaignRole__c
			FROM CampaignMember WHERE Id = :cmId WITH SYSTEM_MODE
		];
		return found.isEmpty() ? null : found[0];
	}

	private static Boolean hasStatus(Id campaignId, String status) {
		return [SELECT COUNT() FROM CampaignMemberStatus WHERE CampaignId = :campaignId AND Label = :status WITH SYSTEM_MODE] > 0;
	}

	// Campaign Role to move to for an answer; null = stay (no staged campaign, or already right)
	@TestVisible
	private static String targetRole(String currentRole, String answer) {
		if (String.isBlank(currentRole)) return null;
		if (ANSWER_NOT_NOW.equals(answer)) return Svc_CampaignMove.ROLE_SOURCE;
		if (ANSWER_NOT_INTERESTED.equals(answer)) return Svc_CampaignMove.ROLE_NOT_INTERESTED;
		if (ANSWER_OFFER.equals(answer)) return Svc_CampaignMove.ROLE_OFFER;
		// Call me: back into the operational campaign, unless the offer is already made (Offer = finished)
		if (Svc_CampaignMove.ROLE_OFFER.equals(currentRole)) return null;
		return Svc_CampaignMove.ROLE_OPERATIONAL;
	}

	private static Id openCallbackId(Id contactId, Id campaignId) {
		List<Case> open = [
			SELECT Id FROM Case
			WHERE ContactId = :contactId AND Campaign__c = :campaignId AND Origin = :Svc_SalesCallback.ORIGIN
			  AND CallbackSource__c != null AND IsClosed = false
			WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1
		];
		return open.isEmpty() ? null : open[0].Id;
	}

	private static void noteOnCase(Id caseId, String answer, String note) {
		Case c = [SELECT Id, Description FROM Case WHERE Id = :caseId WITH SYSTEM_MODE];
		Database.update(new Case(Id = c.Id, Description = Svc_SalesCallback.addNote(c.Description, noteText(answer, note))), RUNNING_MODE);
	}

	// the answer needs no further call: close the Case as successful (byAgent: reached on the call-back; otherwise the
	// customer answered on the page)
	private static void closeCallback(Id caseId, String answer, String note, Boolean byAgent) {
		Case c = [SELECT Id, Description, IsClosed FROM Case WHERE Id = :caseId WITH SYSTEM_MODE];
		if (c.IsClosed) return;
		Case upd = new Case(
			Id = c.Id,
			Status = CASE_STATUS_REACHED,
			Description = Svc_SalesCallback.addNote(c.Description, noteText(answer, note) + (byAgent ? '' : ' (answered on the page, closed)'))
		);
		if (byAgent) upd.CallbackLastAgent__c = UserInfo.getUserId();
		Database.update(upd, RUNNING_MODE);
	}

	private static String noteText(String answer, String note) {
		String text = 'Answer: ' + answer + (ANSWER_OFFER.equals(answer) ? ' (Opportunity created)' : '');
		return String.isBlank(note) ? text : text + ' - ' + note;
	}
}
