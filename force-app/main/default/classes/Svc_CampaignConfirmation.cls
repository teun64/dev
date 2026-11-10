/**
 * Confirmation mail of a campaign answer (2026-11-10), sent by the CampaignConfirmation__e subscriber as the Automated
 * Process user (Svc_CampaignResponse publishes it after commit; the guest on the response page never sends mail itself).
 *  - Call me  → campaignConfirmCallMe_NL: we call you within 3 working days (not when the rep is on the call already)
 *  - Offer    → campaignConfirmOffer_NL: you get the offer within 4 working days
 *  - Not now  → campaignConfirmNotNow_NL: we contact you again in the chosen quarter (#PERIODE#, from RecontactFrom__c)
 * The templates merge on the Contact (Recipient); the quarter is not a Contact field, so it replaces #PERIODE# after
 * rendering. Only staged campaigns (Campaign Role set): the templates are written for the 2G migration.
 * Sender: sales@movingintelligence.nl, otherwise noreply@movingintelligence.com (sandboxes). Logged as an activity.
 */
public without sharing class Svc_CampaignConfirmation {

	public static final Map<String, String> TEMPLATE_BY_ANSWER = new Map<String, String>{
		Svc_CampaignResponse.ANSWER_CALL_ME => 'campaignConfirmCallMe_NL',
		Svc_CampaignResponse.ANSWER_OFFER   => 'campaignConfirmOffer_NL',
		Svc_CampaignResponse.ANSWER_NOT_NOW => 'campaignConfirmNotNow_NL'
	};
	public static final List<String> SENDERS = new List<String>{ 'sales@movingintelligence.nl', 'noreply@movingintelligence.com' };
	public static final String PERIOD_PLACEHOLDER = '#PERIODE#';

	private static final List<String> QUARTER_NL = new List<String>{ 'het eerste', 'het tweede', 'het derde', 'het vierde' };
	private static final List<String> MONTHS_NL = new List<String>{ 'januari', 'februari', 'maart', 'april', 'mei', 'juni',
		'juli', 'augustus', 'september', 'oktober', 'november', 'december' };

	@TestVisible
	private static Integer sentCount = 0;

	// whether apply() confirms this answer: staged campaigns only, and "Call me" not when the rep is on the call
	public static Boolean confirms(String answer, String campaignRole, Id caseId) {
		if (String.isBlank(campaignRole) || !TEMPLATE_BY_ANSWER.containsKey(answer)) return false;
		return !(Svc_CampaignResponse.ANSWER_CALL_ME.equals(answer) && caseId != null);
	}

	public static CampaignConfirmation__e event(Id memberId, String answer) {
		return new CampaignConfirmation__e(CampaignMemberId__c = memberId, Answer__c = answer);
	}

	public static void send(List<CampaignConfirmation__e> events) {
		Map<Id, String> answerByMember = new Map<Id, String>();
		for (CampaignConfirmation__e e : events) {
			if (TEMPLATE_BY_ANSWER.containsKey(e.Answer__c)) answerByMember.put(Id.valueOf(e.CampaignMemberId__c), e.Answer__c);
		}
		if (answerByMember.isEmpty()) return;

		Map<String, Id> templateIds = new Map<String, Id>();
		for (EmailTemplate t : [SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN :TEMPLATE_BY_ANSWER.values() WITH SYSTEM_MODE]) {
			templateIds.put(t.DeveloperName, t.Id);
		}
		Id senderId = senderId();
		List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
		for (CampaignMember cm : [
			SELECT Id, ContactId, Contact.Email, RecontactFrom__c, Response__c
			FROM CampaignMember WHERE Id IN :answerByMember.keySet() WITH SYSTEM_MODE
		]) {
			String answer = answerByMember.get(cm.Id);
			Id templateId = templateIds.get(TEMPLATE_BY_ANSWER.get(answer));
			// the member answered something else in the meantime, or has no address: no confirmation
			if (templateId == null || !answer.equals(cm.Response__c) || String.isBlank(cm.Contact.Email)) continue;
			Messaging.SingleEmailMessage m = Messaging.renderStoredEmailTemplate(templateId, cm.ContactId, null);
			String period = periodLabel(cm.RecontactFrom__c);
			m.setSubject(m.getSubject().replace(PERIOD_PLACEHOLDER, period));
			m.setHtmlBody(m.getHtmlBody().replace(PERIOD_PLACEHOLDER, period));
			if (m.getPlainTextBody() != null) m.setPlainTextBody(m.getPlainTextBody().replace(PERIOD_PLACEHOLDER, period));
			m.setTargetObjectId(cm.ContactId);
			m.setSaveAsActivity(true);
			if (senderId != null) m.setOrgWideEmailAddressId(senderId);
			mails.add(m);
		}
		if (mails.isEmpty()) return;
		for (Messaging.SendEmailResult r : Messaging.sendEmail(mails, false)) {
			if (r.isSuccess()) sentCount++;
			else System.debug(LoggingLevel.ERROR, 'Campaign confirmation not sent: ' + r.getErrors());
		}
	}

	// "het tweede kwartaal van 2027 (april tot en met juni)"; empty date → empty (not a Not now answer)
	@TestVisible
	private static String periodLabel(Date startDate) {
		if (startDate == null) return '';
		Integer q = (startDate.month() - 1) / 3;
		return QUARTER_NL[q] + ' kwartaal van ' + startDate.year()
			+ ' (' + MONTHS_NL[q * 3] + ' tot en met ' + MONTHS_NL[q * 3 + 2] + ')';
	}

	private static Id senderId() {
		Map<String, Id> byAddress = new Map<String, Id>();
		for (OrgWideEmailAddress o : [
			SELECT Id, Address FROM OrgWideEmailAddress WHERE Address IN :SENDERS AND IsVerified = true AND IsAllowAllProfiles = true WITH SYSTEM_MODE
		]) byAddress.put(o.Address.toLowerCase(), o.Id);
		for (String a : SENDERS) if (byAddress.containsKey(a)) return byAddress.get(a);
		return null;
	}
}
