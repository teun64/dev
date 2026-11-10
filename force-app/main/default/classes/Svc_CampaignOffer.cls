/**
 * The "Offer" answer of a migration campaign (Svc_CampaignResponse): an Opportunity for the member's account with one
 * line per migration product. Each hardware product the customer has points to the product offered in its place
 * (Product2.MigrationProduct__c, e.g. Mi50 → Mi50.M, MiTracer (Mi01) → Mi01.M); the quantity = the account's active
 * contracts on that hardware with a 2G modem (Modem__c '1' or empty), so the offer replaces every 2G unit.
 *
 * The Opportunity is linked to the campaign the member is in when it is made (the Offer campaign: the member moves
 * first). Record type Standard_Opportunity; rbc_Opportunity sets the price book and stage; the owner is the agent when the answer comes
 * from a call, otherwise the account owner (the page runs as the site guest). Lines use that price book; products without an active price there are listed in the Description
 * instead, so sales can add them. An open Opportunity for the same account and campaign is reused, not duplicated.
 *
 * Closed Lost (Trigger_Opportunity): the account's member of the Offer campaign moves back to the Source campaign
 * (answer and mail cycle cleared), so the Source job keeps it up to date and a later release mails it again. A large
 * account (LargeAccount__c) goes back to the Large account campaign instead (phone only).
 * Not when another open Opportunity of the same account is still on that campaign.
 */
public without sharing class Svc_CampaignOffer {

	// Opportunity.LeadSource per answer source (Svc_CampaignResponse.Request.source); the rest = E-mail (the mail page)
	public static final String SOURCE_CALL = 'Call';
	public static final Map<String, String> LEAD_SOURCE_BY_SOURCE = new Map<String, String>{ SOURCE_CALL => 'Telephone' };
	public static final String LEAD_SOURCE_DEFAULT = 'E-mail';
	public static final Integer CLOSE_DAYS = 30;
	// only this stage sends the member back to Source (not Closed Unqualified / Closed Swapped)
	public static final String STAGE_LOST = 'Closed Lost';

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	// tests: contracts on hardware need the subscription package; the query itself is checked live in dev
	@TestVisible
	private static Map<Id, Integer> quantityOverride;

	/**
	 * @return the Opportunity Id (null when the contact has no account)
	 */
	public static Id createOffer(Id contactId, Id campaignId, String source) {
		Contact con = [
			SELECT Id, AccountId, Account.Name, Account.OwnerId, Account.Owner.IsActive, Account.Owner.UserType
			FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE
		];
		if (con.AccountId == null) return null;

		List<Opportunity> open = [
			SELECT Id FROM Opportunity
			WHERE AccountId = :con.AccountId AND CampaignId = :campaignId AND IsClosed = false
			WITH SYSTEM_MODE ORDER BY CreatedDate DESC LIMIT 1
		];
		if (!open.isEmpty()) return open[0].Id;

		Campaign camp = [SELECT Id, Name, CallbackLabel__c, Parent.CallbackLabel__c FROM Campaign WHERE Id = :campaignId WITH SYSTEM_MODE];
		String label = String.isNotBlank(camp.CallbackLabel__c) ? camp.CallbackLabel__c
			: (String.isNotBlank(camp.Parent?.CallbackLabel__c) ? camp.Parent.CallbackLabel__c : camp.Name);
		Opportunity opp = new Opportunity(
			// explicit: the site guest (response page) has no default Opportunity record type
			RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Standard_Opportunity').getRecordTypeId(),
			Name = (label + ' - ' + con.Account.Name).left(120),
			AccountId = con.AccountId,
			ContactId = con.Id,
			CampaignId = campaignId,
			CloseDate = Date.today().addDays(CLOSE_DAYS),
			LeadSource = LEAD_SOURCE_BY_SOURCE.containsKey(source) ? LEAD_SOURCE_BY_SOURCE.get(source) : LEAD_SOURCE_DEFAULT,
			Option_Require_Signature__c = true
		);
		// owner: the agent on a call, otherwise the account owner (the page runs as the site guest)
		if (SOURCE_CALL.equals(source) && UserInfo.getUserType() == 'Standard') opp.OwnerId = UserInfo.getUserId();
		else if (con.Account.Owner.IsActive && con.Account.Owner.UserType == 'Standard') opp.OwnerId = con.Account.OwnerId;
		Database.insert(opp, RUNNING_MODE);
		addLines(opp.Id, quantities(con.AccountId));
		return opp.Id;
	}

	// ── Closed Lost → back to Source ─────────────────────────────────────────
	public static void afterUpdate(List<Opportunity> news, Map<Id, Opportunity> olds) {
		Map<Id, Opportunity> lost = new Map<Id, Opportunity>();
		for (Opportunity o : news) {
			Opportunity old = olds.get(o.Id);
			if (o.CampaignId != null && o.AccountId != null && STAGE_LOST.equals(o.StageName) && !STAGE_LOST.equals(old.StageName)) lost.put(o.Id, o);
		}
		if (lost.isEmpty()) return;
		// a failure must not block closing the Opportunity: the member can be moved by hand
		try {
			backToSource(lost.values());
		} catch (Exception e) {
			System.debug(LoggingLevel.ERROR, 'Svc_CampaignOffer.backToSource: ' + e.getMessage() + '\n' + e.getStackTraceString());
		}
	}

	@TestVisible
	private static void backToSource(List<Opportunity> lost) {
		Set<Id> campaignIds = new Set<Id>();
		Set<Id> accountIds = new Set<Id>();
		Set<Id> lostIds = new Set<Id>();
		for (Opportunity o : lost) {
			campaignIds.add(o.CampaignId);
			accountIds.add(o.AccountId);
			lostIds.add(o.Id);
		}
		// only Offer campaigns of a staged campaign
		Set<Id> offerIds = new Map<Id, Campaign>([
			SELECT Id FROM Campaign
			WHERE Id IN :campaignIds AND CampaignRole__c = :Svc_CampaignMove.ROLE_OFFER AND ParentId != null WITH SYSTEM_MODE
		]).keySet();
		if (offerIds.isEmpty()) return;
		Set<String> stillOpen = new Set<String>();
		for (Opportunity o : [
			SELECT CampaignId, AccountId FROM Opportunity
			WHERE CampaignId IN :offerIds AND AccountId IN :accountIds AND IsClosed = false AND Id NOT IN :lostIds WITH SYSTEM_MODE
		]) stillOpen.add(o.CampaignId + '|' + o.AccountId);
		Set<String> keys = new Set<String>();
		for (Opportunity o : lost) {
			String key = o.CampaignId + '|' + o.AccountId;
			if (offerIds.contains(o.CampaignId) && !stillOpen.contains(key)) keys.add(key);
		}
		if (keys.isEmpty()) return;
		Set<Id> memberIds = new Set<Id>();
		Set<Id> largeIds = new Set<Id>();
		for (CampaignMember cm : [
			SELECT Id, CampaignId, Account__c, Contact.AccountId, LargeAccount__c FROM CampaignMember
			WHERE CampaignId IN :offerIds AND (Account__c IN :accountIds OR Contact.AccountId IN :accountIds) WITH SYSTEM_MODE
		]) {
			Id accountId = cm.Account__c != null ? cm.Account__c : cm.Contact.AccountId;
			if (keys.contains(cm.CampaignId + '|' + accountId)) (cm.LargeAccount__c ? largeIds : memberIds).add(cm.Id);
		}
		// answer cleared: the old mail links work again, and the release starts a fresh mail cycle
		Map<String, Object> cleared = new Map<String, Object>{
			'Response__c' => null, 'MailStage__c' => null, 'MailNumber__c' => null, 'MailDueOn__c' => null, 'RecontactFrom__c' => null
		};
		Svc_CampaignMove.move(memberIds, Svc_CampaignMove.ROLE_SOURCE, cleared);
		// large accounts are phone only: back to the Large account campaign, never into the mail cycle
		Svc_CampaignMove.move(largeIds, Svc_CampaignMove.ROLE_LARGE_ACCOUNT, cleared);
	}

	// migration product → number of the account's active 2G contracts on hardware with that migration product
	@TestVisible
	private static Map<Id, Integer> quantities(Id accountId) {
		Map<Id, Integer> qtyByProduct = new Map<Id, Integer>();
		if (quantityOverride != null) return quantityOverride;
		for (AggregateResult ar : [
			SELECT Hardware__r.Product2.MigrationProduct__c product, COUNT(Id) n
			FROM Contract
			WHERE AccountId = :accountId AND Status = 'Activated' AND Active__c = true
			  AND Hardware__r.Product2.MigrationProduct__c != null
			  AND (Hardware__r.Modem__c = '1' OR Hardware__r.Modem__c = null)
			WITH SYSTEM_MODE
			GROUP BY Hardware__r.Product2.MigrationProduct__c
		]) {
			qtyByProduct.put((Id) ar.get('product'), (Integer) ar.get('n'));
		}
		return qtyByProduct;
	}

	private static void addLines(Id oppId, Map<Id, Integer> qtyByProduct) {
		if (qtyByProduct.isEmpty()) return;
		// re-query: rbc_Opportunity chose the price book
		Opportunity opp = [SELECT Id, Pricebook2Id, CurrencyIsoCode, Description FROM Opportunity WHERE Id = :oppId WITH SYSTEM_MODE];
		Set<Id> productIds = qtyByProduct.keySet();
		Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
		if (opp.Pricebook2Id != null) {
			for (PricebookEntry e : [
				SELECT Id, Product2Id, UnitPrice FROM PricebookEntry
				WHERE Pricebook2Id = :opp.Pricebook2Id AND CurrencyIsoCode = :opp.CurrencyIsoCode
				  AND IsActive = true AND Product2.IsActive = true AND Product2Id IN :productIds
				WITH SYSTEM_MODE ORDER BY CreatedDate
			]) {
				if (!entryByProduct.containsKey(e.Product2Id)) entryByProduct.put(e.Product2Id, e);
			}
		}
		List<OpportunityLineItem> lines = new List<OpportunityLineItem>();
		List<String> missing = new List<String>();
		Map<Id, Product2> products = new Map<Id, Product2>([SELECT Id, Name FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE]);
		for (Id productId : productIds) {
			PricebookEntry e = entryByProduct.get(productId);
			if (e == null) {
				missing.add(qtyByProduct.get(productId) + 'x ' + products.get(productId).Name);
				continue;
			}
			lines.add(new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = e.Id,
				Quantity = qtyByProduct.get(productId), UnitPrice = e.UnitPrice));
		}
		if (!lines.isEmpty()) Database.insert(lines, RUNNING_MODE);
		if (!missing.isEmpty()) {
			String note = 'No active price in the price book for: ' + String.join(missing, ', ') + '. Add these lines by hand.';
			Database.update(new Opportunity(Id = opp.Id,
				Description = String.isBlank(opp.Description) ? note : opp.Description + '\n' + note), RUNNING_MODE);
		}
	}
}
