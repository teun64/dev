/**
 * Keeps the Source campaign of a staged campaign (Svc_CampaignMove) filled with its selection (Campaign.SourceSelection__c).
 * Run daily by Batch_CampaignSource: phase 1 adds and updates members per account, phase 2 removes members whose account
 * left the selection.
 *
 * Selection "2G migration": End User accounts with an active (Activated + Active__c) platform 1 contract on hardware that
 * has a Migration Product (Product2.MigrationProduct__c; so Source and the offer lines always agree) with a 2G modem
 * (Modem__c '1' or empty). Optional billing country filter (Campaign.SourceCountryCodes__c).
 * One member per account under the parent: the Main contact (active ACR with role Main, the oldest when there are more).
 *  - new account                       → member in Source: Account__c, UnitCount__c (2G units), Priority__c
 *  - already in Source                 → Priority__c + UnitCount__c updated, RecontactFrom__c ("Not now") kept
 *  - already in Operational            → UnitCount__c updated
 *  - in Offer / Not interested / Not reacted → left alone (never back into Source)
 *  - account without 2G units any more → removed from Source; in Operational only counted (user decision pending)
 * Priority = Migration Priority of the account's best 2G hardware (Product2.MigrationPriority__c, empty = 9) × 10
 * + segment: 1 B2B with 3+ units, 2 B2B with 1-2, 3 B2C (units = all active contracts on mapped hardware, as in the matrix).
 */
public without sharing class Svc_CampaignSource {

	public static final String SELECTION_2G = '2G migration';

	public static final Integer SEGMENT_B2B_LARGE = 1;
	public static final Integer SEGMENT_B2B_SMALL = 2;
	public static final Integer SEGMENT_B2C = 3;
	public static final Integer LARGE_FROM_UNITS = 3;
	public static final Integer RANK_UNKNOWN = 9;

	private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

	// the contract selection; the batch start query uses it as a semi-join, the counts per account as an aggregate
	public static final String CONTRACT_SCOPE = 'Status = \'Activated\' AND Active__c = true AND System_Platform__c = \'1\''
		+ ' AND Account.Relation_type__c = \'End User\' AND Hardware__r.Product2.MigrationProduct__c != null';
	public static final String MODEM_2G = '(Hardware__r.Modem__c = \'1\' OR Hardware__r.Modem__c = null)';

	public class Result {
		public Integer added = 0;
		public Integer updated = 0;
		public Integer elsewhere = 0;
		public Integer noMainContact = 0;
		public Integer removed = 0;
		public Integer operationalOutOfScope = 0;

		public void add(Result other) {
			added += other.added;
			updated += other.updated;
			elsewhere += other.elsewhere;
			noMainContact += other.noMainContact;
			removed += other.removed;
			operationalOutOfScope += other.operationalOutOfScope;
		}

		public override String toString() {
			return 'added ' + added + ', updated ' + updated + ', already in another stage ' + elsewhere
				+ ', no Main contact ' + noMainContact + ', removed ' + removed
				+ ', Operational without 2G (not removed) ' + operationalOutOfScope;
		}
	}

	public class Scope {
		public Integer units2G = 0;
		public Integer unitsAll = 0;
		public Integer rank = RANK_UNKNOWN;
	}

	/** The active Source campaigns that have a selection, with their parent. */
	public static List<Campaign> sources() {
		return [
			SELECT Id, ParentId, SourceSelection__c, SourceCountryCodes__c FROM Campaign
			WHERE CampaignRole__c = :Svc_CampaignMove.ROLE_SOURCE AND SourceSelection__c = :SELECTION_2G
			  AND IsActive = true AND ParentId != null
			WITH SYSTEM_MODE
		];
	}

	/** Batch start: accounts with at least one 2G unit in the selection. */
	public static String accountQuery() {
		return 'SELECT Id, BillingCountryCode, RecordType.DeveloperName FROM Account WHERE Relation_type__c = \'End User\''
			+ ' AND Id IN (SELECT AccountId FROM Contract WHERE ' + CONTRACT_SCOPE + ' AND ' + MODEM_2G + ')';
	}

	// ── Phase 1: add / update ─────────────────────────────────────────────────
	public static Result sync(List<Account> accounts, List<Campaign> sourceCampaigns, Boolean dryRun) {
		Result res = new Result();
		if (accounts.isEmpty() || sourceCampaigns.isEmpty()) return res;
		Map<Id, Account> accountById = new Map<Id, Account>(accounts);
		Map<Id, Scope> scopeByAccount = scopes(accountById.keySet());
		Map<Id, Id> mainByAccount = mainContacts(scopeByAccount.keySet());

		Map<Id, Campaign> sourceByParent = new Map<Id, Campaign>();
		for (Campaign c : sourceCampaigns) sourceByParent.put(c.ParentId, c);
		Map<String, CampaignMember> existing = existingMembers(sourceByParent.keySet(), scopeByAccount.keySet(),
			new Set<Id>(mainByAccount.values()));

		List<CampaignMember> inserts = new List<CampaignMember>();
		List<CampaignMember> updates = new List<CampaignMember>();
		// a contact can be the Main contact of several accounts: one member per contact per campaign
		Set<String> insertedKeys = new Set<String>();
		for (Campaign source : sourceCampaigns) {
			Set<String> countries = countryCodes(source.SourceCountryCodes__c);
			for (Id accountId : scopeByAccount.keySet()) {
				Scope s = scopeByAccount.get(accountId);
				Account acct = accountById.get(accountId);
				if (s.units2G == 0) continue;
				if (!countries.isEmpty() && !countries.contains(acct.BillingCountryCode)) continue;
				Id contactId = mainByAccount.get(accountId);
				CampaignMember cm = existing.get(source.ParentId + '|' + accountId);
				if (cm == null && contactId != null) cm = existing.get(source.ParentId + '|' + contactId);
				Decimal priority = priority(s, acct);
				if (cm == null) {
					if (contactId == null) {
						res.noMainContact++;
						continue;
					}
					if (!insertedKeys.add(source.Id + '|' + contactId)) {
						res.elsewhere++;
						continue;
					}
					inserts.add(new CampaignMember(CampaignId = source.Id, ContactId = contactId, Account__c = accountId,
						UnitCount__c = s.units2G, Priority__c = priority));
					res.added++;
				} else if (cm.CampaignId == source.Id) {
					if (cm.Priority__c != priority || cm.UnitCount__c != s.units2G || cm.Account__c != accountId) {
						updates.add(new CampaignMember(Id = cm.Id, Priority__c = priority, UnitCount__c = s.units2G, Account__c = accountId));
						res.updated++;
					}
				} else if (cm.Campaign.CampaignRole__c == Svc_CampaignMove.ROLE_OPERATIONAL) {
					if (cm.UnitCount__c != s.units2G || cm.Account__c != accountId) {
						updates.add(new CampaignMember(Id = cm.Id, UnitCount__c = s.units2G, Account__c = accountId));
						res.updated++;
					}
				} else {
					res.elsewhere++;
				}
			}
		}
		if (!dryRun) {
			if (!inserts.isEmpty()) Database.insert(inserts, RUNNING_MODE);
			if (!updates.isEmpty()) Database.update(updates, RUNNING_MODE);
		}
		return res;
	}

	// ── Phase 2: remove ───────────────────────────────────────────────────────
	/** Batch start of phase 2: the members of the Source and Operational campaigns. */
	public static String memberQuery() {
		return 'SELECT Id, CampaignId, Campaign.CampaignRole__c, Account__c, Contact.AccountId FROM CampaignMember'
			+ ' WHERE Campaign.ParentId IN :parentIds AND Campaign.CampaignRole__c IN (\'' + Svc_CampaignMove.ROLE_SOURCE
			+ '\', \'' + Svc_CampaignMove.ROLE_OPERATIONAL + '\')';
	}

	public static Result prune(List<CampaignMember> members, Boolean dryRun) {
		Result res = new Result();
		Set<Id> accountIds = new Set<Id>();
		for (CampaignMember cm : members) accountIds.add(accountOf(cm));
		accountIds.remove(null);
		Map<Id, Scope> scopeByAccount = scopes(accountIds);
		List<CampaignMember> deletes = new List<CampaignMember>();
		for (CampaignMember cm : members) {
			Scope s = scopeByAccount.get(accountOf(cm));
			if (s != null && s.units2G > 0) continue;
			if (cm.Campaign.CampaignRole__c == Svc_CampaignMove.ROLE_SOURCE) {
				deletes.add(new CampaignMember(Id = cm.Id));
				res.removed++;
			} else {
				res.operationalOutOfScope++;
			}
		}
		if (!dryRun && !deletes.isEmpty()) Database.delete(deletes, RUNNING_MODE);
		return res;
	}

	// ── Helpers ───────────────────────────────────────────────────────────────
	@TestVisible
	private static Map<Id, Scope> scopeOverride;

	// per account: 2G units, all units on mapped hardware and the best (lowest) Migration Priority of its 2G hardware
	public static Map<Id, Scope> scopes(Set<Id> accountIds) {
		if (scopeOverride != null) return scopeOverride;
		Map<Id, Scope> scopeByAccount = new Map<Id, Scope>();
		// a Number field can't be grouped: group by hardware product, its Migration Priority comes after
		List<AggregateResult> rows = Database.query(
			'SELECT AccountId acct, Hardware__r.Modem__c modem, Hardware__r.Product2Id product, COUNT(Id) n'
			+ ' FROM Contract WHERE AccountId IN :accountIds AND ' + CONTRACT_SCOPE
			+ ' GROUP BY AccountId, Hardware__r.Modem__c, Hardware__r.Product2Id', RUNNING_MODE);
		Set<Id> productIds = new Set<Id>();
		for (AggregateResult ar : rows) productIds.add((Id) ar.get('product'));
		Map<Id, Product2> products = new Map<Id, Product2>([SELECT Id, MigrationPriority__c FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE]);
		for (AggregateResult ar : rows) {
			Id accountId = (Id) ar.get('acct');
			if (!scopeByAccount.containsKey(accountId)) scopeByAccount.put(accountId, new Scope());
			Scope s = scopeByAccount.get(accountId);
			Integer n = (Integer) ar.get('n');
			String modem = (String) ar.get('modem');
			s.unitsAll += n;
			if (modem == null || modem == '1') {
				s.units2G += n;
				Decimal rank = products.get((Id) ar.get('product'))?.MigrationPriority__c;
				if (rank != null && rank.intValue() < s.rank) s.rank = rank.intValue();
			}
		}
		return scopeByAccount;
	}

	@TestVisible
	private static Decimal priority(Scope s, Account acct) {
		Integer segment = acct.RecordType?.DeveloperName == 'B2C' ? SEGMENT_B2C
			: (s.unitsAll >= LARGE_FROM_UNITS ? SEGMENT_B2B_LARGE : SEGMENT_B2B_SMALL);
		return s.rank * 10 + segment;
	}

	private static Map<Id, Id> mainContacts(Set<Id> accountIds) {
		Map<Id, Id> mainByAccount = new Map<Id, Id>();
		for (AccountContactRelation acr : [
			SELECT AccountId, ContactId FROM AccountContactRelation
			WHERE AccountId IN :accountIds AND IsActive = true AND Roles INCLUDES ('Main')
			WITH SYSTEM_MODE ORDER BY CreatedDate
		]) {
			if (!mainByAccount.containsKey(acr.AccountId)) mainByAccount.put(acr.AccountId, acr.ContactId);
		}
		return mainByAccount;
	}

	// parent|account and parent|contact → the member anywhere under the parent (all 5 stages)
	private static Map<String, CampaignMember> existingMembers(Set<Id> parentIds, Set<Id> accountIds, Set<Id> contactIds) {
		Map<String, CampaignMember> byKey = new Map<String, CampaignMember>();
		for (CampaignMember cm : [
			SELECT Id, CampaignId, Campaign.ParentId, Campaign.CampaignRole__c, ContactId, Contact.AccountId, Account__c,
			       Priority__c, UnitCount__c
			FROM CampaignMember
			WHERE Campaign.ParentId IN :parentIds AND (Account__c IN :accountIds OR ContactId IN :contactIds)
			WITH SYSTEM_MODE
		]) {
			if (cm.Account__c != null) byKey.put(cm.Campaign.ParentId + '|' + cm.Account__c, cm);
			byKey.put(cm.Campaign.ParentId + '|' + cm.ContactId, cm);
		}
		return byKey;
	}

	private static Id accountOf(CampaignMember cm) {
		return cm.Account__c != null ? cm.Account__c : cm.Contact?.AccountId;
	}

	private static Set<String> countryCodes(String codes) {
		Set<String> result = new Set<String>();
		if (String.isBlank(codes)) return result;
		for (String c : codes.split(',')) if (String.isNotBlank(c)) result.add(c.trim().toUpperCase());
		return result;
	}
}
