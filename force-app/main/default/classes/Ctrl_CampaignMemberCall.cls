/**
 * Calling from the campaign member (2026-11-10): the large-account person works the Large account campaign from the
 * member record page, no Omni-Channel. LWC campaignMemberCall (member page: account, contact, answer buttons) and
 * campaignCallList (Large account campaign page: who to call next).
 * Answers go through Svc_CampaignResponse with source Call (Opportunity owner = the person who clicks); a move gives
 * the member a new Id, which the page then opens.
 */
public with sharing class Ctrl_CampaignMemberCall {

	public static final Set<String> ANSWERS = new Set<String>{
		Svc_CampaignResponse.ANSWER_OFFER, Svc_CampaignResponse.ANSWER_NOT_NOW, Svc_CampaignResponse.ANSWER_NOT_INTERESTED
	};
	public static final Integer CALL_LIST_SIZE = 200;

	public class Member {
		@AuraEnabled public Id memberId;
		@AuraEnabled public Id campaignId;
		@AuraEnabled public String campaignName;
		@AuraEnabled public String campaignRole;
		@AuraEnabled public String status;
		@AuraEnabled public String response;
		@AuraEnabled public Date recontactFrom;
		@AuraEnabled public Decimal unitCount;
		@AuraEnabled public Decimal priority;
		@AuraEnabled public Boolean largeAccount;
		@AuraEnabled public Id accountId;
		@AuraEnabled public String accountName;
		@AuraEnabled public String accountPhone;
		@AuraEnabled public String accountOwner;
		@AuraEnabled public String accountCity;
		@AuraEnabled public Decimal activeSubscriptions;
		@AuraEnabled public Id contactId;
		@AuraEnabled public String contactName;
		@AuraEnabled public String contactPhone;
		@AuraEnabled public String contactMobile;
		@AuraEnabled public String contactEmail;
		@AuraEnabled public Boolean canAnswer;
		@AuraEnabled public List<Option> quarters = new List<Option>();
	}

	public class Option {
		@AuraEnabled public String label;
		@AuraEnabled public String value;
		Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	public class AnswerResult {
		@AuraEnabled public String outcome;
		@AuraEnabled public Id campaignMemberId;
		@AuraEnabled public Id opportunityId;
	}

	public class CallRow {
		@AuraEnabled public Id memberId;
		@AuraEnabled public String contactName;
		@AuraEnabled public String accountName;
		@AuraEnabled public String phone;
		@AuraEnabled public Decimal unitCount;
		@AuraEnabled public Decimal priority;
		@AuraEnabled public String response;
		@AuraEnabled public Date recontactFrom;
	}

	public class CallList {
		@AuraEnabled public List<CallRow> rows = new List<CallRow>();
		@AuraEnabled public Integer toCall = 0;
		@AuraEnabled public Integer waiting = 0;
	}

	/** The member with its account and contact; null when it no longer exists (moved: it has a new Id). */
	@AuraEnabled
	public static Member getMember(Id memberId) {
		List<CampaignMember> found = [
			SELECT Id, CampaignId, Campaign.Name, Campaign.CampaignRole__c, Status, Response__c, RecontactFrom__c, UnitCount__c,
			       Priority__c, LargeAccount__c, Account__c, ContactId, Contact.Name, Contact.Phone, Contact.MobilePhone,
			       Contact.Email, Contact.AccountId
			FROM CampaignMember WHERE Id = :memberId WITH SYSTEM_MODE
		];
		if (found.isEmpty()) return null;
		CampaignMember cm = found[0];
		Member m = new Member();
		m.memberId = cm.Id;
		m.campaignId = cm.CampaignId;
		m.campaignName = cm.Campaign.Name;
		m.campaignRole = cm.Campaign.CampaignRole__c;
		m.status = cm.Status;
		m.response = cm.Response__c;
		m.recontactFrom = cm.RecontactFrom__c;
		m.unitCount = cm.UnitCount__c;
		m.priority = cm.Priority__c;
		m.largeAccount = cm.LargeAccount__c;
		m.contactId = cm.ContactId;
		m.contactName = cm.Contact?.Name;
		m.contactPhone = cm.Contact?.Phone;
		m.contactMobile = cm.Contact?.MobilePhone;
		m.contactEmail = cm.Contact?.Email;
		m.accountId = cm.Account__c != null ? cm.Account__c : cm.Contact?.AccountId;
		if (m.accountId != null) {
			Account a = [
				SELECT Name, Phone, Owner.Name, BillingCity, Subscriptions_Activated__c FROM Account WHERE Id = :m.accountId WITH SYSTEM_MODE
			];
			m.accountName = a.Name;
			m.accountPhone = a.Phone;
			m.accountOwner = a.Owner?.Name;
			m.accountCity = a.BillingCity;
			m.activeSubscriptions = a.Subscriptions_Activated__c;
		}
		m.canAnswer = String.isNotBlank(m.campaignRole) && canAnswer();
		for (Date d : Svc_CampaignResponse.quarterStarts(Date.today(), 4)) {
			m.quarters.add(new Option('Q' + (((d.month() - 1) / 3) + 1) + ' ' + d.year(), String.valueOf(d)));
		}
		return m;
	}

	/** Offer, Not now (recontactFrom = a quarter start) or Not interested, recorded as a call. */
	@AuraEnabled
	public static AnswerResult answer(Id memberId, String answer, String recontactFrom) {
		if (!canAnswer()) throw new AuraHandledException('You have no access to change campaign members.');
		if (!ANSWERS.contains(answer)) throw new AuraHandledException('Unknown answer: ' + answer);
		Svc_CampaignResponse.Request r = new Svc_CampaignResponse.Request();
		r.campaignMemberId = memberId;
		r.answer = answer;
		r.source = Svc_CampaignOffer.SOURCE_CALL;
		if (Svc_CampaignResponse.ANSWER_NOT_NOW.equals(answer) && String.isNotBlank(recontactFrom)) r.recontactFrom = Date.valueOf(recontactFrom);
		Svc_CampaignResponse.Result res;
		try {
			res = Svc_CampaignResponse.apply(r);
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
		AnswerResult out = new AnswerResult();
		out.outcome = res.outcome;
		out.campaignMemberId = res.campaignMemberId != null ? res.campaignMemberId : memberId;
		out.opportunityId = res.opportunityId;
		return out;
	}

	/** Large account campaign: who to call (no answer yet, or Not now and the date has come), by priority. */
	@AuraEnabled
	public static CallList getCallList(Id campaignId) {
		CallList cl = new CallList();
		Date today = Date.today();
		cl.waiting = [SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaignId AND RecontactFrom__c > :today WITH SYSTEM_MODE];
		cl.toCall = [
			SELECT COUNT() FROM CampaignMember WHERE CampaignId = :campaignId AND (RecontactFrom__c = null OR RecontactFrom__c <= :today) WITH SYSTEM_MODE
		];
		for (CampaignMember cm : [
			SELECT Id, Contact.Name, Contact.Phone, Contact.MobilePhone, Account__r.Name, Account__r.Phone, Contact.Account.Name,
			       UnitCount__c, Priority__c, Response__c, RecontactFrom__c
			FROM CampaignMember
			WHERE CampaignId = :campaignId AND (RecontactFrom__c = null OR RecontactFrom__c <= :today)
			WITH SYSTEM_MODE
			ORDER BY Priority__c ASC NULLS LAST, UnitCount__c DESC NULLS LAST, CreatedDate ASC
			LIMIT :CALL_LIST_SIZE
		]) {
			CallRow row = new CallRow();
			row.memberId = cm.Id;
			row.contactName = cm.Contact?.Name;
			row.accountName = cm.Account__r?.Name != null ? cm.Account__r.Name : cm.Contact?.Account?.Name;
			row.phone = firstNonBlank(new List<String>{ cm.Contact?.Phone, cm.Contact?.MobilePhone, cm.Account__r?.Phone });
			row.unitCount = cm.UnitCount__c;
			row.priority = cm.Priority__c;
			row.response = cm.Response__c;
			row.recontactFrom = cm.RecontactFrom__c;
			cl.rows.add(row);
		}
		return cl;
	}

	// answering moves the member (delete + insert)
	private static Boolean canAnswer() {
		Schema.DescribeSObjectResult d = Schema.SObjectType.CampaignMember;
		return d.isCreateable() && d.isUpdateable() && d.isDeletable();
	}

	private static String firstNonBlank(List<String> values) {
		for (String v : values) if (String.isNotBlank(v)) return v;
		return null;
	}
}
