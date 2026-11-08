/**
 * Release a batch of a staged campaign (Svc_CampaignMove): moves the next N members from the Source campaign to the
 * Operational campaign, highest priority first (Priority__c ascending, empty last), skipping members with a Recontact
 * From in the future ("Not now"). The moved members start the mail cycle today: Mail Stage Due, mail 1, Released On
 * today (day 0 of the Mail Schedule), next batch number. Called by scr_Campaign_Release_Batch (Campaign button).
 */
public without sharing class Svc_CampaignRelease {

	public static final Integer MAX_SIZE = 2000;

	public class Request {
		@InvocableVariable(label='Campaign Id' description='Any campaign of the staged campaign: the parent or one of its children' required=true)
		public Id campaignId;
		@InvocableVariable(label='Batch Size' required=true)
		public Integer size;
	}

	public class Result {
		@InvocableVariable(label='Released' description='Number of members moved to the Operational campaign')
		public Integer released = 0;
		@InvocableVariable(label='Batch Number')
		public Integer batchNumber;
		@InvocableVariable(label='Message' description='Why nothing was released')
		public String message;
	}

	@InvocableMethod(label='Release Campaign Batch' description='Moves the next members (by priority) from the Source to the Operational campaign and starts their mail cycle.')
	public static List<Result> run(List<Request> requests) {
		List<Result> results = new List<Result>();
		for (Request r : requests) results.add(release(r.campaignId, r.size));
		return results;
	}

	public static Result release(Id campaignId, Integer size) {
		Result res = new Result();
		Campaign c = [SELECT Id, ParentId, CampaignRole__c FROM Campaign WHERE Id = :campaignId WITH SYSTEM_MODE];
		Id parentId = c.CampaignRole__c == null ? c.Id : c.ParentId;
		Id sourceId = childId(parentId, Svc_CampaignMove.ROLE_SOURCE);
		Id operationalId = childId(parentId, Svc_CampaignMove.ROLE_OPERATIONAL);
		if (sourceId == null || operationalId == null) {
			res.message = 'The parent campaign needs a child campaign with role Source and one with role Operational.';
			return res;
		}
		if (size == null || size < 1) {
			res.message = 'Batch size must be at least 1.';
			return res;
		}
		Date today = Date.today();
		Map<Id, CampaignMember> members = new Map<Id, CampaignMember>([
			SELECT Id FROM CampaignMember
			WHERE CampaignId = :sourceId AND (RecontactFrom__c = null OR RecontactFrom__c <= :today)
			WITH SYSTEM_MODE
			ORDER BY Priority__c ASC NULLS LAST, CreatedDate ASC
			LIMIT :Math.min(size, MAX_SIZE)
		]);
		if (members.isEmpty()) {
			res.message = 'No members to release in the Source campaign.';
			return res;
		}
		AggregateResult last = [
			SELECT MAX(MailBatch__c) maxBatch FROM CampaignMember WHERE Campaign.ParentId = :parentId WITH SYSTEM_MODE
		];
		Decimal maxBatch = (Decimal) last.get('maxBatch');
		res.batchNumber = maxBatch == null ? 1 : maxBatch.intValue() + 1;
		Map<Id, CampaignMember> moved = Svc_CampaignMove.move(members.keySet(), Svc_CampaignMove.ROLE_OPERATIONAL, new Map<String, Object>{
			'MailStage__c'           => 'Due',
			'MailNumber__c'          => 1,
			'MailDueOn__c'           => today,
			'MailBatchReleasedOn__c' => today,
			'MailBatch__c'           => res.batchNumber,
			'Response__c'            => null,
			'ResponseOn__c'          => null,
			'RecontactFrom__c'       => null
		});
		res.released = moved.size();
		return res;
	}

	private static Id childId(Id parentId, String role) {
		if (parentId == null) return null;
		List<Campaign> c = [
			SELECT Id FROM Campaign WHERE ParentId = :parentId AND CampaignRole__c = :role WITH SYSTEM_MODE ORDER BY CreatedDate LIMIT 1
		];
		return c.isEmpty() ? null : c[0].Id;
	}
}
