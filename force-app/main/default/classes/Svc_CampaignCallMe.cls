/**
 * "Call me" without the response page: a member put straight into an Operational campaign (import, list edit, API) with
 * Response__c = 'Call me' gets the same call-back Case as a customer who clicked "Call me" in the mail:
 *  - before save: ResponseOn__c = now and MailStage__c = Stopped when empty (no mail goes to someone who is phoned),
 *  - after save: one call-back Case per member (Svc_SalesCallback.requestBulk: one open call-back per Contact + Campaign,
 *    Case carries Campaign__c + CampaignMemberId__c so Callback Reached can move the member), source Marketing.
 * Fires on insert, or when Response__c changes to 'Call me', and only in a campaign with Campaign Role Operational of a
 * staged campaign. No confirmation mail (that is sent by the response page only). Svc_CampaignResponse.apply sets
 * `suppress` while it runs (it makes its own call-back, with the real source and note).
 * A not-reached call-back puts the member back into the mail cycle (Svc_SalesCallback.backToMailCycle) as with the mail answer.
 * Keep import batches small (about 20): every member is one Case with its flows.
 */
public without sharing class Svc_CampaignCallMe {

	public static Boolean suppress = false;

	public static final String SOURCE = 'Marketing';
	private static final String ANSWER = 'Call me';

	public static void beforeSave(List<CampaignMember> news, Map<Id, CampaignMember> olds) {
		for (CampaignMember cm : candidates(news, olds)) {
			if (cm.ResponseOn__c == null) cm.ResponseOn__c = Datetime.now();
			if (String.isBlank(cm.MailStage__c)) cm.MailStage__c = 'Stopped';
		}
	}

	public static void afterSave(List<CampaignMember> news, Map<Id, CampaignMember> olds) {
		List<Svc_SalesCallback.Request> requests = new List<Svc_SalesCallback.Request>();
		for (CampaignMember cm : candidates(news, olds)) {
			if (cm.ContactId == null) continue;
			Svc_SalesCallback.Request r = new Svc_SalesCallback.Request();
			r.step = Svc_SalesCallback.STEP_REQUEST;
			r.contactId = cm.ContactId;
			r.campaignId = cm.CampaignId;
			r.campaignMemberId = cm.Id;
			r.source = SOURCE;
			r.note = 'Answer: Call me - member added to the campaign directly (no customer answer)';
			requests.add(r);
		}
		if (!requests.isEmpty()) Svc_SalesCallback.requestBulk(requests);
	}

	// Response changed to 'Call me' (or inserted with it), in an Operational campaign of a staged campaign
	private static List<CampaignMember> candidates(List<CampaignMember> news, Map<Id, CampaignMember> olds) {
		List<CampaignMember> result = new List<CampaignMember>();
		if (suppress) return result;
		Set<Id> campaignIds = new Set<Id>();
		List<CampaignMember> changed = new List<CampaignMember>();
		for (CampaignMember cm : news) {
			if (!ANSWER.equals(cm.Response__c)) continue;
			if (olds != null && olds.containsKey(cm.Id) && ANSWER.equals(olds.get(cm.Id).Response__c)) continue;
			changed.add(cm);
			campaignIds.add(cm.CampaignId);
		}
		if (changed.isEmpty()) return result;
		Set<Id> operational = new Map<Id, Campaign>([
			SELECT Id FROM Campaign
			WHERE Id IN :campaignIds AND CampaignRole__c = :Svc_CampaignMove.ROLE_OPERATIONAL AND ParentId != null WITH SYSTEM_MODE
		]).keySet();
		for (CampaignMember cm : changed) if (operational.contains(cm.CampaignId)) result.add(cm);
		return result;
	}
}
