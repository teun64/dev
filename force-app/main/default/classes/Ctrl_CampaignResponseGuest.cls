/**
 * Customer Hub response page (/response?token=&a=) for campaign mails: the customer confirms the answer behind the
 * button they clicked. Guest, token-only: the token is the member's random ResponseToken__c, no record Id is exposed.
 * Loading only reads (a mail scanner opening the link changes nothing); the answer is written on the confirm click.
 * Own class because guest Apex access is granted per class (see Ctrl_PreferenceCenterGuest).
 */
public without sharing class Ctrl_CampaignResponseGuest {

	// answer codes in the mail links → Response__c values
	public static final Map<String, String> ANSWER_BY_CODE = new Map<String, String>{
		'callme'        => Svc_CampaignResponse.ANSWER_CALL_ME,
		'offer'         => Svc_CampaignResponse.ANSWER_OFFER,
		'notnow'        => Svc_CampaignResponse.ANSWER_NOT_NOW,
		'notinterested' => Svc_CampaignResponse.ANSWER_NOT_INTERESTED
	};

	public class PageData {
		@AuraEnabled public Boolean valid = false;
		@AuraEnabled public String firstName;
		@AuraEnabled public String accountName;
		@AuraEnabled public String campaignLabel;
		@AuraEnabled public String currentAnswer;   // code of the answer already given, if any
		@AuraEnabled public String recontactFrom;   // yyyy-MM-dd, Not now
		@AuraEnabled public List<String> quarters = new List<String>();   // yyyy-MM-dd quarter starts for Not now
	}

	@AuraEnabled(cacheable=true)
	public static PageData getResponse(String token) {
		PageData data = new PageData();
		CampaignMember cm = Svc_CampaignResponse.memberByToken(token);
		if (cm == null || !cm.Campaign.IsActive) return data;
		data.valid = true;
		data.firstName = cm.Contact?.FirstName;
		data.accountName = cm.Contact?.Account?.Name;
		data.campaignLabel = String.isNotBlank(cm.Campaign.CallbackLabel__c) ? cm.Campaign.CallbackLabel__c : cm.Campaign.Name;
		data.currentAnswer = codeOf(cm.Response__c);
		data.recontactFrom = cm.RecontactFrom__c == null ? null : String.valueOf(cm.RecontactFrom__c);
		for (Date d : quarterOptions()) data.quarters.add(String.valueOf(d));
		return data;
	}

	/** @return applied, unchanged or invalid */
	@AuraEnabled
	public static String submit(String token, String answerCode, String recontactFrom) {
		CampaignMember cm = Svc_CampaignResponse.memberByToken(token);
		String answer = ANSWER_BY_CODE.get(answerCode);
		if (cm == null || !cm.Campaign.IsActive || answer == null) return Svc_CampaignResponse.OUTCOME_INVALID;

		Svc_CampaignResponse.Request r = new Svc_CampaignResponse.Request();
		r.campaignMemberId = cm.Id;
		r.answer = answer;
		r.source = 'Campaign mail';
		if (Svc_CampaignResponse.ANSWER_NOT_NOW.equals(answer)) {
			// only a quarter the page offered
			Date chosen;
			try {
				chosen = String.isBlank(recontactFrom) ? null : Date.valueOf(recontactFrom);
			} catch (Exception e) {
				return Svc_CampaignResponse.OUTCOME_INVALID;
			}
			if (chosen != null && !quarterOptions().contains(chosen)) return Svc_CampaignResponse.OUTCOME_INVALID;
			r.recontactFrom = chosen;
		}
		try {
			return Svc_CampaignResponse.apply(r).outcome;
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'Ctrl_CampaignResponseGuest.submit: ' + e.getMessage());
			throw new AuraHandledException('Your answer could not be saved. Please try again later.');
		}
	}

	private static List<Date> quarterOptions() {
		return Svc_CampaignResponse.quarterStarts(Date.today(), 4);
	}

	private static String codeOf(String answer) {
		for (String code : ANSWER_BY_CODE.keySet()) {
			if (ANSWER_BY_CODE.get(code).equals(answer)) return code;
		}
		return null;
	}
}
