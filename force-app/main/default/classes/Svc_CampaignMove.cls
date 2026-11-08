/**
 * Staged campaigns: a parent campaign with one child per Campaign Role (Source, Operational, Offer, Not interested,
 * Not reacted). A member "moves" to the sister campaign with the target role (same parent). A CampaignMember can't
 * change campaign, so a move deletes the member and inserts a new one in the target campaign, carrying every custom
 * field (priority, mail cycle, answer, response token, later hardware flags), so the personal link in mails already
 * sent keeps working. Open call-back Cases follow the member (Campaign__c, CampaignMemberId__c).
 * When the contact is already a member of the target campaign, that member gets the fields instead.
 *
 * Callers: Svc_CampaignResponse (answers), Svc_CampaignOffer (Closed Lost → Source), afl_CampaignMember_Mail_Cycle (not reacted), scr_Case_Create_Opportunity
 * (offer), scr_Campaign_Release_Batch (source → operational).
 * Bulk: one query per object and one DML per kind for all members of a call.
 */
public without sharing class Svc_CampaignMove {

	public static final String ROLE_SOURCE         = 'Source';
	public static final String ROLE_OPERATIONAL    = 'Operational';
	public static final String ROLE_OFFER          = 'Offer';
	public static final String ROLE_NOT_INTERESTED = 'Not interested';
	public static final String ROLE_NOT_REACTED    = 'Not reacted';

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	public class Request {
		@InvocableVariable(label='Campaign Member Id' required=true)
		public String campaignMemberId;
		@InvocableVariable(label='Role' description='Source, Operational, Offer, Not interested or Not reacted' required=true)
		public String role;
		@InvocableVariable(label='Mail Stage' description='Mail Stage of the moved member (empty = Stopped, Completed for Not reacted)')
		public String mailStage;
	}

	public class Result {
		@InvocableVariable(label='Campaign Member Id' description='The member in the target campaign (the same member when nothing moved)')
		public Id campaignMemberId;
		@InvocableVariable(label='Campaign Id' description='The target campaign (the current one when nothing moved)')
		public Id campaignId;
	}

	@InvocableMethod(label='Move Campaign Member' description='Moves campaign members to the sister campaign (same parent) with the given Campaign Role.')
	public static List<Result> run(List<Request> requests) {
		// group by role + stage so one move per group (the scheduled mail cycle hands over many at once)
		Map<String, Set<Id>> idsByKey = new Map<String, Set<Id>>();
		for (Request r : requests) {
			Id cmId = toId(r?.campaignMemberId);
			if (cmId == null || String.isBlank(r.role)) continue;
			String key = r.role + '|' + (r.mailStage == null ? '' : r.mailStage);
			if (!idsByKey.containsKey(key)) idsByKey.put(key, new Set<Id>());
			idsByKey.get(key).add(cmId);
		}
		Map<Id, CampaignMember> moved = new Map<Id, CampaignMember>();
		for (String key : idsByKey.keySet()) {
			String role = key.substringBefore('|');
			String stage = key.substringAfter('|');
			if (String.isBlank(stage)) stage = ROLE_NOT_REACTED.equals(role) ? 'Completed' : 'Stopped';
			moved.putAll(move(idsByKey.get(key), role, new Map<String, Object>{ 'MailStage__c' => stage }));
		}
		List<Result> results = new List<Result>();
		for (Request r : requests) {
			Result res = new Result();
			CampaignMember cm = moved.get(toId(r?.campaignMemberId));
			if (cm != null) {
				res.campaignMemberId = cm.Id;
				res.campaignId = cm.CampaignId;
			}
			results.add(res);
		}
		return results;
	}

	/**
	 * Moves members to the sister campaign with `role` and sets `values` on the moved member.
	 * @return old member Id → member in the target campaign (also for members already there: values applied, not moved;
	 *         members without a parent or without a sister of that role are left out)
	 */
	public static Map<Id, CampaignMember> move(Set<Id> memberIds, String role, Map<String, Object> values) {
		Map<Id, CampaignMember> result = new Map<Id, CampaignMember>();
		if (memberIds == null || memberIds.isEmpty()) return result;
		List<String> fields = carriedFields();
		List<CampaignMember> members = Database.query(
			'SELECT Id, CampaignId, ContactId, LeadId, Campaign.ParentId, Campaign.CampaignRole__c, ' + String.join(fields, ', ')
			+ ' FROM CampaignMember WHERE Id IN :memberIds', RUNNING_MODE);

		Set<Id> parentIds = new Set<Id>();
		for (CampaignMember cm : members) if (cm.Campaign.ParentId != null) parentIds.add(cm.Campaign.ParentId);
		Map<Id, Id> targetByParent = new Map<Id, Id>();
		for (Campaign c : [
			SELECT Id, ParentId FROM Campaign WHERE ParentId IN :parentIds AND CampaignRole__c = :role
			WITH SYSTEM_MODE ORDER BY CreatedDate
		]) {
			if (!targetByParent.containsKey(c.ParentId)) targetByParent.put(c.ParentId, c.Id);
		}

		List<CampaignMember> stay = new List<CampaignMember>();
		List<CampaignMember> toMove = new List<CampaignMember>();
		Set<Id> targetIds = new Set<Id>();
		Set<Id> contactIds = new Set<Id>();
		for (CampaignMember cm : members) {
			Id target = targetByParent.get(cm.Campaign.ParentId);
			if (role.equals(cm.Campaign.CampaignRole__c)) {
				stay.add(cm);
			} else if (target == null) {
				System.debug(LoggingLevel.WARN, 'Svc_CampaignMove: no "' + role + '" campaign next to member ' + cm.Id);
			} else {
				toMove.add(cm);
				targetIds.add(target);
				if (cm.ContactId != null) contactIds.add(cm.ContactId);
			}
		}

		// already in the right campaign: only the values
		List<CampaignMember> updates = new List<CampaignMember>();
		for (CampaignMember cm : stay) {
			CampaignMember upd = new CampaignMember(Id = cm.Id);
			apply(upd, values);
			updates.add(upd);
			result.put(cm.Id, new CampaignMember(Id = cm.Id, CampaignId = cm.CampaignId));
		}

		Map<String, CampaignMember> existing = new Map<String, CampaignMember>();
		for (CampaignMember cm : [
			SELECT Id, CampaignId, ContactId FROM CampaignMember
			WHERE CampaignId IN :targetIds AND ContactId IN :contactIds WITH SYSTEM_MODE
		]) existing.put(cm.CampaignId + '|' + cm.ContactId, cm);

		List<CampaignMember> inserts = new List<CampaignMember>();
		Map<Id, CampaignMember> newByOld = new Map<Id, CampaignMember>();
		Map<Id, Id> targetByOld = new Map<Id, Id>();
		for (CampaignMember cm : toMove) {
			Id target = targetByParent.get(cm.Campaign.ParentId);
			targetByOld.put(cm.Id, target);
			CampaignMember there = cm.ContactId == null ? null : existing.get(target + '|' + cm.ContactId);
			CampaignMember next = there == null
				? new CampaignMember(CampaignId = target, ContactId = cm.ContactId, LeadId = cm.ContactId == null ? cm.LeadId : null)
				: new CampaignMember(Id = there.Id);
			for (String f : fields) next.put(f, cm.get(f));
			apply(next, values);
			if (there == null) inserts.add(next); else updates.add(next);
			newByOld.put(cm.Id, next);
		}

		Savepoint sp = Database.setSavepoint();
		try {
			// delete first: the response token is unique and moves to the new member
			if (!toMove.isEmpty()) Database.delete(toMove, RUNNING_MODE);
			if (!updates.isEmpty()) Database.update(updates, RUNNING_MODE);
			if (!inserts.isEmpty()) Database.insert(inserts, RUNNING_MODE);
			followCases(newByOld, targetByOld);
		} catch (Exception e) {
			Database.rollback(sp);
			throw e;
		}
		for (Id oldId : newByOld.keySet()) {
			result.put(oldId, new CampaignMember(Id = newByOld.get(oldId).Id, CampaignId = targetByOld.get(oldId)));
		}
		return result;
	}

	public static Id siblingId(Id campaignId, String role) {
		Id parentId = [SELECT ParentId FROM Campaign WHERE Id = :campaignId WITH SYSTEM_MODE].ParentId;
		if (parentId == null) return null;
		List<Campaign> c = [
			SELECT Id FROM Campaign WHERE ParentId = :parentId AND CampaignRole__c = :role
			WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 1
		];
		return c.isEmpty() ? null : c[0].Id;
	}

	// ── Helpers ───────────────────────────────────────────────────────────────
	// open call-backs point to the member (back into the mail cycle) and the campaign (Create Opportunity)
	private static void followCases(Map<Id, CampaignMember> newByOld, Map<Id, Id> targetByOld) {
		if (newByOld.isEmpty()) return;
		Map<String, CampaignMember> newByOldText = new Map<String, CampaignMember>();
		for (Id oldId : newByOld.keySet()) newByOldText.put(String.valueOf(oldId), newByOld.get(oldId));
		Set<String> oldIds = newByOldText.keySet();
		List<Case> cases = new List<Case>();
		for (Case c : [
			SELECT Id, CampaignMemberId__c FROM Case
			WHERE CampaignMemberId__c IN :oldIds AND IsClosed = false WITH SYSTEM_MODE
		]) {
			Id oldId = Id.valueOf(c.CampaignMemberId__c);
			cases.add(new Case(Id = c.Id, CampaignMemberId__c = newByOld.get(oldId).Id, Campaign__c = targetByOld.get(oldId)));
		}
		if (!cases.isEmpty()) Database.update(cases, RUNNING_MODE);
	}

	private static void apply(CampaignMember cm, Map<String, Object> values) {
		if (values == null) return;
		for (String f : values.keySet()) cm.put(f, values.get(f));
	}

	// every custom field of the member: new campaign fields move along without code changes. Not by isCreateable(),
	// that follows the running user's field access (the guest response page sees none of them).
	private static List<String> carriedFields() {
		List<String> fields = new List<String>();
		for (Schema.SObjectField f : Schema.SObjectType.CampaignMember.fields.getMap().values()) {
			Schema.DescribeFieldResult d = f.getDescribe(Schema.FieldDescribeOptions.FULL_DESCRIBE);
			if (d.isCustom() && !d.isCalculated() && !d.isAutoNumber()) fields.add(d.getName());
		}
		return fields;
	}

	private static Id toId(String value) {
		if (String.isBlank(value)) return null;
		try {
			return Id.valueOf(value);
		} catch (StringException e) {
			return null;
		}
	}
}
