/**
 * Admin overview on the parent of a staged campaign (Svc_CampaignMove), LWC stagedCampaignOverview on rp_Campaign:
 *  1. Status: members per role campaign, mail progress, reactions (per batch and per hardware), call-backs.
 *  2. Release: the next N members from Source to Operational (Svc_CampaignRelease), which starts mail 1.
 *  3. Revenue: the Opportunities linked to the role campaigns (open / won / lost).
 * All member figures come from ONE query: Apex counts every member row read, and a big campaign (2G Migratie:
 * ~26,000 members) would pass the 50,000-row limit with several queries.
 * Reactions are the current state of the members: an Offer that goes Closed Lost sends the member back to Source with
 * the answer cleared, so offers are counted from the Opportunities, not from the members.
 */
public with sharing class Ctrl_StagedCampaignOverview {

	public static final List<String> ROLES = new List<String>{
		Svc_CampaignMove.ROLE_SOURCE, Svc_CampaignMove.ROLE_OPERATIONAL, Svc_CampaignMove.ROLE_OFFER,
		Svc_CampaignMove.ROLE_NOT_INTERESTED, Svc_CampaignMove.ROLE_NOT_REACTED, Svc_CampaignMove.ROLE_DEALER,
		Svc_CampaignMove.ROLE_LARGE_ACCOUNT
	};
	public static final List<String> ANSWERS = new List<String>{
		Svc_CampaignResponse.ANSWER_CALL_ME, Svc_CampaignResponse.ANSWER_OFFER, Svc_CampaignResponse.ANSWER_NOT_NOW,
		Svc_CampaignResponse.ANSWER_NOT_INTERESTED, Svc_CampaignResponse.ANSWER_DEALER
	};
	// Priority__c = MigrationPriority__c of the best 2G hardware (9 = not mapped) x 10 + segment (Svc_CampaignSource)
	public static final Map<Integer, String> SEGMENTS = new Map<Integer, String>{ 1 => 'B2B 3+ units', 2 => 'B2B 1-2 units', 3 => 'B2C' };

	public class Overview {
		@AuraEnabled public Boolean staged = false;
		@AuraEnabled public Id parentId;
		@AuraEnabled public String parentName;
		@AuraEnabled public Boolean canRelease = false;
		@AuraEnabled public List<Box> campaigns = new List<Box>();
		@AuraEnabled public Integer released = 0;
		@AuraEnabled public Integer reacted = 0;
		@AuraEnabled public List<Box> reactions = new List<Box>();
		@AuraEnabled public List<Box> mails = new List<Box>();
		@AuraEnabled public List<Box> notNow = new List<Box>();
		@AuraEnabled public List<Row> batches = new List<Row>();
		@AuraEnabled public List<Row> hardware = new List<Row>();
		@AuraEnabled public List<Box> callbacks = new List<Box>();
		@AuraEnabled public Integer sourceReady = 0;
		@AuraEnabled public Integer sourceParked = 0;
		@AuraEnabled public List<Box> sourceByPriority = new List<Box>();
		@AuraEnabled public List<Box> revenue = new List<Box>();
	}

	public class Box {
		@AuraEnabled public String label;
		@AuraEnabled public Integer count = 0;
		@AuraEnabled public Decimal amount;
		@AuraEnabled public Id recordId;
		Box(String label) { this.label = label; }
	}

	public class Row {
		@AuraEnabled public String label;
		@AuraEnabled public Date releasedOn;
		@AuraEnabled public Integer members = 0;
		@AuraEnabled public Integer inCycle = 0;
		@AuraEnabled public Integer reacted = 0;
		@AuraEnabled public Integer callMe = 0;
		@AuraEnabled public Integer offer = 0;
		@AuraEnabled public Integer notNow = 0;
		@AuraEnabled public Integer notInterested = 0;
		@AuraEnabled public Integer dealer = 0;
		@AuraEnabled public Integer notReacted = 0;
		Row(String label) { this.label = label; }
	}

	public class ReleaseResult {
		@AuraEnabled public Integer released = 0;
		@AuraEnabled public Integer batchNumber;
		@AuraEnabled public String message;
	}

	@AuraEnabled(cacheable=false)
	public static Overview getOverview(Id campaignId) {
		Overview o = new Overview();
		Campaign c = [SELECT Id, Name, ParentId, CampaignRole__c FROM Campaign WHERE Id = :campaignId WITH USER_MODE];
		if (c.CampaignRole__c != null) return o;   // only on the parent
		Map<Id, Campaign> children = new Map<Id, Campaign>([
			SELECT Id, Name, CampaignRole__c FROM Campaign
			WHERE ParentId = :c.Id AND CampaignRole__c IN :ROLES WITH SYSTEM_MODE ORDER BY CreatedDate
		]);
		if (children.isEmpty()) return o;
		o.staged = true;
		o.parentId = c.Id;
		o.parentName = c.Name;
		o.canRelease = canRelease();

		Map<String, Box> byRole = new Map<String, Box>();
		Map<Id, String> roleOf = new Map<Id, String>();
		for (String role : ROLES) byRole.put(role, new Box(role));
		for (Campaign child : children.values()) {
			roleOf.put(child.Id, child.CampaignRole__c);
			if (byRole.get(child.CampaignRole__c).recordId == null) byRole.get(child.CampaignRole__c).recordId = child.Id;
		}
		o.campaigns = byRole.values();
		Map<String, Box> reactions = boxes(ANSWERS);
		Map<String, Box> mails = boxes(new List<String>{ 'Mail 1', 'Mail 2', 'Mail 3' });
		Map<String, Box> notNow = new Map<String, Box>();
		Map<Integer, Row> batches = new Map<Integer, Row>();
		Map<Integer, Row> hardware = new Map<Integer, Row>();
		Map<Decimal, Box> sourceByPriority = new Map<Decimal, Box>();
		Map<Integer, String> hardwareNames = hardwareNames();
		Date today = Date.today();

		// a query loop (number fields can't be grouped): every member is read once, in chunks of 200
		for (CampaignMember cm : [
			SELECT CampaignId, MailStage__c, MailNumber__c, Response__c, MailBatch__c, Priority__c, RecontactFrom__c,
				MailBatchReleasedOn__c
			FROM CampaignMember WHERE CampaignId IN :children.keySet() WITH SYSTEM_MODE
		]) {
			Integer n = 1;
			String role = roleOf.get(cm.CampaignId);
			String stage = cm.MailStage__c;
			String answer = cm.Response__c;
			Decimal mail = cm.MailNumber__c;
			Decimal batch = cm.MailBatch__c;
			Decimal priority = cm.Priority__c;
			Date recontact = cm.RecontactFrom__c;
			byRole.get(role).count += n;

			if (role == Svc_CampaignMove.ROLE_SOURCE) {
				if (recontact != null && recontact > today) o.sourceParked += n;
				else {
					o.sourceReady += n;
					Box p = sourceByPriority.get(priority);
					if (p == null) sourceByPriority.put(priority, p = new Box(priorityLabel(priority, hardwareNames)));
					p.count += n;
				}
			}
			if (answer != null) {
				reactions.get(answer).count += n;
				o.reacted += n;
			}
			if (answer == Svc_CampaignResponse.ANSWER_NOT_NOW && recontact != null) {
				String q = 'Q' + ((recontact.month() - 1) / 3 + 1) + ' ' + recontact.year();
				if (!notNow.containsKey(q)) notNow.put(q, new Box(q));
				notNow.get(q).count += n;
			}
			if (role == Svc_CampaignMove.ROLE_OPERATIONAL && stage == 'Due' && mail != null && mails.containsKey('Mail ' + mail.intValue())) {
				mails.get('Mail ' + mail.intValue()).count += n;
			}
			// released = has a batch number (a "Not now" back in Source keeps its batch, a Closed Lost offer too)
			if (batch == null) continue;
			o.released += n;
			Row b = batches.get(batch.intValue());
			if (b == null) batches.put(batch.intValue(), b = new Row('Batch ' + batch.intValue()));
			Date releasedOn = cm.MailBatchReleasedOn__c;
			if (releasedOn != null && (b.releasedOn == null || releasedOn < b.releasedOn)) b.releasedOn = releasedOn;
			Integer hw = priority == null ? 9 : priority.intValue() / 10;
			Row h = hardware.get(hw);
			if (h == null) hardware.put(hw, h = new Row(hardwareNames.containsKey(hw) ? hardwareNames.get(hw) : 'Not mapped'));
			for (Row r : new List<Row>{ b, h }) count(r, n, role, stage, answer);
		}

		o.reactions = reactions.values();
		o.mails = mails.values();
		List<String> quarters = new List<String>(notNow.keySet());
		quarters.sort();
		for (String q : quarters) o.notNow.add(notNow.get(q));
		List<Integer> keys = new List<Integer>(batches.keySet());
		keys.sort();
		for (Integer k : keys) o.batches.add(batches.get(k));
		keys = new List<Integer>(hardware.keySet());
		keys.sort();
		for (Integer k : keys) o.hardware.add(hardware.get(k));
		List<Decimal> priorities = new List<Decimal>(sourceByPriority.keySet());
		priorities.sort();
		for (Decimal p : priorities) o.sourceByPriority.add(sourceByPriority.get(p));
		if (sourceByPriority.containsKey(null)) o.sourceByPriority.add(sourceByPriority.get(null));

		o.callbacks = callbacks(children.keySet());
		o.revenue = revenue(children.keySet());
		return o;
	}

	@AuraEnabled
	public static ReleaseResult release(Id campaignId, Integer size) {
		if (!canRelease()) throw new AuraHandledException('You don\'t have access to release campaign members.');
		ReleaseResult r = new ReleaseResult();
		try {
			Svc_CampaignRelease.Result res = Svc_CampaignRelease.release(campaignId, size);
			r.released = res.released;
			r.batchNumber = res.batchNumber;
			r.message = res.message;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
		return r;
	}

	// releasing deletes and inserts members (Svc_CampaignMove runs without sharing), so it needs full member access
	@TestVisible
	private static Boolean canRelease() {
		Schema.DescribeSObjectResult d = CampaignMember.SObjectType.getDescribe();
		return d.isCreateable() && d.isUpdateable() && d.isDeletable();
	}

	private static void count(Row r, Integer n, String role, String stage, String answer) {
		r.members += n;
		if (answer != null) r.reacted += n;
		if (answer == Svc_CampaignResponse.ANSWER_CALL_ME) r.callMe += n;
		else if (answer == Svc_CampaignResponse.ANSWER_OFFER) r.offer += n;
		else if (answer == Svc_CampaignResponse.ANSWER_NOT_NOW) r.notNow += n;
		else if (answer == Svc_CampaignResponse.ANSWER_NOT_INTERESTED) r.notInterested += n;
		else if (answer == Svc_CampaignResponse.ANSWER_DEALER) r.dealer += n;
		else if (role == Svc_CampaignMove.ROLE_NOT_REACTED) r.notReacted += n;
		else if (role == Svc_CampaignMove.ROLE_OPERATIONAL && stage == 'Due') r.inCycle += n;
	}

	private static List<Box> callbacks(Set<Id> campaignIds) {
		Map<String, Box> byStatus = new Map<String, Box>();
		for (AggregateResult ar : [
			SELECT Status status, COUNT(Id) n FROM Case
			WHERE Campaign__c IN :campaignIds AND CallbackSource__c != null WITH SYSTEM_MODE GROUP BY Status
		]) {
			Box b = new Box((String) ar.get('status'));
			b.count = (Integer) ar.get('n');
			byStatus.put(b.label, b);
		}
		return byStatus.values();
	}

	// revenue = Opportunity amounts only; costs wait for the definition of the margin (user, 2026-11-09)
	private static List<Box> revenue(Set<Id> campaignIds) {
		Map<String, Box> groups = boxes(new List<String>{ 'Open', 'Won', 'Lost' });
		for (AggregateResult ar : [
			SELECT IsClosed closed, IsWon won, COUNT(Id) n, SUM(Amount) amount FROM Opportunity
			WHERE CampaignId IN :campaignIds WITH SYSTEM_MODE GROUP BY IsClosed, IsWon
		]) {
			Box b = groups.get((Boolean) ar.get('won') ? 'Won' : (Boolean) ar.get('closed') ? 'Lost' : 'Open');
			b.count += (Integer) ar.get('n');
			Decimal amount = (Decimal) ar.get('amount');
			b.amount = (b.amount == null ? 0 : b.amount) + (amount == null ? 0 : amount);
		}
		for (Box b : groups.values()) if (b.amount == null) b.amount = 0;
		return groups.values();
	}

	private static Map<Integer, String> hardwareNames() {
		Map<Integer, List<String>> names = new Map<Integer, List<String>>();
		for (Product2 p : [
			SELECT Name, MigrationPriority__c FROM Product2 WHERE MigrationPriority__c != null WITH SYSTEM_MODE ORDER BY Name
		]) {
			Integer k = p.MigrationPriority__c.intValue();
			if (!names.containsKey(k)) names.put(k, new List<String>());
			names.get(k).add(p.Name);
		}
		Map<Integer, String> result = new Map<Integer, String>();
		for (Integer k : names.keySet()) result.put(k, String.join(names.get(k), ' / '));
		return result;
	}

	private static String priorityLabel(Decimal priority, Map<Integer, String> hardwareNames) {
		if (priority == null) return 'No priority';
		Integer hw = priority.intValue() / 10;
		Integer segment = Math.mod(priority.intValue(), 10);
		String name = hardwareNames.containsKey(hw) ? hardwareNames.get(hw) : 'Not mapped';
		return priority.intValue() + ' · ' + name + (SEGMENTS.containsKey(segment) ? ' · ' + SEGMENTS.get(segment) : '');
	}

	private static Map<String, Box> boxes(List<String> labels) {
		Map<String, Box> m = new Map<String, Box>();
		for (String l : labels) m.put(l, new Box(l));
		return m;
	}
}
