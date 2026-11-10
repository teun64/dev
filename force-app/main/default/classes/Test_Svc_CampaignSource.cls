/**
 * Tests Svc_CampaignSource + Batch_CampaignSource: filling and pruning the Source campaign of a staged campaign.
 * The 2G units per account come from scopeOverride (contracts on hardware need the subscription package).
 */
@IsTest
private class Test_Svc_CampaignSource {

	@TestSetup
	static void setup() {
		insert new Subscription25__Schedulable_Class__c(Name = 'Batch_CampaignSource', Subscription25__Unique_Name__c = 'Batch_CampaignSource');
		Campaign parent = new Campaign(Name = 'Source Test', IsActive = true);
		Database.insert(parent, AccessLevel.SYSTEM_MODE);
		List<Campaign> children = new List<Campaign>();
		for (String role : new List<String>{ 'Source', 'Operational', 'Offer', 'Not interested', 'Not reacted' }) {
			children.add(new Campaign(Name = 'Source Test - ' + role, ParentId = parent.Id, IsActive = true, CampaignRole__c = role,
				SourceSelection__c = role == 'Source' ? Svc_CampaignSource.SELECTION_2G : null));
		}
		Database.insert(children, AccessLevel.SYSTEM_MODE);
		List<Account> accts = new List<Account>{
			Test_Data.createAccount('Source B2B', (String) null, 'B2B', false),
			Test_Data.createAccount('Source B2C', (String) null, 'B2C', false),
			Test_Data.createAccount('Source NoMain', (String) null, 'B2B', false)
		};
		accts[0].BillingCountryCode = 'NL';
		accts[1].BillingCountryCode = 'BE';
		Database.insert(accts, AccessLevel.SYSTEM_MODE);
		Test_Data.createContact(accts[0].Id, 'MainB2B', null, 'main@b2b.test', true);
		Test_Data.createContact(accts[1].Id, 'MainB2C', null, 'main@b2c.test', true);
		Contact noMain = Test_Data.createContact(accts[2].Id, 'NotMain', null, 'other@nomain.test', true);
		List<AccountContactRelation> acrs = [SELECT Id, ContactId FROM AccountContactRelation WITH SYSTEM_MODE];
		for (AccountContactRelation acr : acrs) acr.Roles = acr.ContactId == noMain.Id ? 'Invoice' : 'Main';
		Database.update(acrs, AccessLevel.SYSTEM_MODE);
	}

	static Map<String, Account> accounts() {
		Map<String, Account> byName = new Map<String, Account>();
		for (Account a : [SELECT Id, Name, BillingCountryCode, RecordType.DeveloperName FROM Account WHERE Name LIKE 'Source %' WITH SYSTEM_MODE]) {
			byName.put(a.Name, a);
		}
		return byName;
	}

	static Svc_CampaignSource.Scope scope(Integer units2G, Integer unitsAll, Integer rank) {
		Svc_CampaignSource.Scope s = new Svc_CampaignSource.Scope();
		s.units2G = units2G;
		s.unitsAll = unitsAll;
		s.rank = rank;
		return s;
	}

	static void useScopes(Integer b2bUnits) {
		Map<String, Account> a = accounts();
		Svc_CampaignSource.scopeOverride = new Map<Id, Svc_CampaignSource.Scope>{
			a.get('Source B2B').Id => scope(b2bUnits, b2bUnits, 1),
			a.get('Source B2C').Id => scope(1, 1, 3),
			a.get('Source NoMain').Id => scope(1, 1, 1)
		};
	}

	static Svc_CampaignSource.Result sync() {
		return Svc_CampaignSource.sync(accounts().values(), Svc_CampaignSource.sources(), false);
	}

	static List<CampaignMember> members(String role) {
		return [SELECT Id, ContactId, Account__c, Account__r.Name, Priority__c, UnitCount__c, RecontactFrom__c FROM CampaignMember
			WHERE Campaign.Name = :('Source Test - ' + role) WITH SYSTEM_MODE ORDER BY Account__r.Name];
	}

	@IsTest
	static void sync_addsMainContactsWithPriority() {
		useScopes(4);
		Test.startTest();
		Svc_CampaignSource.Result res = sync();
		Test.stopTest();
		List<CampaignMember> source = members('Source');
		System.assertEquals(2, res.added);
		System.assertEquals(1, res.noMainContact);
		System.assertEquals(2, source.size());
		System.assertEquals('Source B2B', source[0].Account__r.Name);
		System.assertEquals(11, source[0].Priority__c, 'Mi50 (1) B2B 3+ (1)');
		System.assertEquals(4, source[0].UnitCount__c);
		System.assertEquals(33, source[1].Priority__c, 'rank 3, B2C');
	}

	@IsTest
	static void sync_twice_updatesKeepsRecontact() {
		useScopes(4);
		sync();
		CampaignMember b2b = members('Source')[0];
		Database.update(new CampaignMember(Id = b2b.Id, RecontactFrom__c = Date.newInstance(2027, 4, 1)), AccessLevel.SYSTEM_MODE);
		useScopes(2);
		Test.startTest();
		Svc_CampaignSource.Result res = sync();
		Test.stopTest();
		CampaignMember after = members('Source')[0];
		System.assertEquals(0, res.added);
		System.assertEquals(1, res.updated);
		System.assertEquals(12, after.Priority__c, 'B2B 1-2 now');
		System.assertEquals(2, after.UnitCount__c);
		System.assertEquals(Date.newInstance(2027, 4, 1), after.RecontactFrom__c, 'Not now kept');
	}

	static void addLargeAccountCampaign() {
		Campaign parent = [SELECT Id FROM Campaign WHERE Name = 'Source Test' WITH SYSTEM_MODE];
		Database.insert(new Campaign(Name = 'Source Test - Large account', ParentId = parent.Id, IsActive = true,
			CampaignRole__c = Svc_CampaignMove.ROLE_LARGE_ACCOUNT), AccessLevel.SYSTEM_MODE);
		Svc_CampaignSource.largeOverride = new Set<Id>{ accounts().get('Source B2B').Id };
	}

	@IsTest
	static void sync_largeAccount_inLargeAccountCampaign() {
		useScopes(4);
		addLargeAccountCampaign();
		Test.startTest();
		sync();
		Test.stopTest();
		List<CampaignMember> large = [SELECT Account__r.Name, LargeAccount__c FROM CampaignMember
			WHERE Campaign.Name = 'Source Test - Large account' WITH SYSTEM_MODE];
		System.assertEquals(1, large.size());
		System.assertEquals('Source B2B', large[0].Account__r.Name);
		System.assert(large[0].LargeAccount__c, 'phone only');
		System.assertEquals(1, members('Source').size(), 'only the B2C member');
	}

	@IsTest
	static void sync_grownIntoLargeAccount_movesFromSource() {
		useScopes(4);
		sync();
		addLargeAccountCampaign();
		Test.startTest();
		Svc_CampaignSource.Result res = sync();
		Test.stopTest();
		System.assertEquals(1, res.movedToLarge);
		System.assertEquals(1, [SELECT COUNT() FROM CampaignMember WHERE Campaign.Name = 'Source Test - Large account' AND LargeAccount__c = true WITH SYSTEM_MODE]);
		System.assertEquals(1, members('Source').size());
	}

	@IsTest
	static void sync_memberInOtherStage_notBackIntoSource() {
		useScopes(4);
		sync();
		CampaignMember b2b = members('Source')[0];
		Svc_CampaignMove.move(new Set<Id>{ b2b.Id }, Svc_CampaignMove.ROLE_NOT_INTERESTED, null);
		Test.startTest();
		Svc_CampaignSource.Result res = sync();
		Test.stopTest();
		System.assertEquals(1, res.elsewhere);
		System.assertEquals(1, members('Source').size(), 'only the B2C member');
		System.assertEquals(1, members('Not interested').size());
	}

	@IsTest
	static void sync_countryFilter() {
		Campaign source = [SELECT Id FROM Campaign WHERE Name = 'Source Test - Source' WITH SYSTEM_MODE];
		Database.update(new Campaign(Id = source.Id, SourceCountryCodes__c = 'nl, de'), AccessLevel.SYSTEM_MODE);
		useScopes(1);
		Test.startTest();
		sync();
		Test.stopTest();
		List<CampaignMember> m = members('Source');
		System.assertEquals(1, m.size());
		System.assertEquals('Source B2B', m[0].Account__r.Name);
	}

	@IsTest
	static void prune_removesFromSourceCountsOperational() {
		useScopes(1);
		sync();
		CampaignMember b2c = members('Source')[1];
		Svc_CampaignMove.move(new Set<Id>{ b2c.Id }, Svc_CampaignMove.ROLE_OPERATIONAL, null);
		// both accounts lost their 2G units
		Svc_CampaignSource.scopeOverride = new Map<Id, Svc_CampaignSource.Scope>();
		List<CampaignMember> scopeMembers = [
			SELECT Id, CampaignId, Campaign.CampaignRole__c, Account__c, Contact.AccountId FROM CampaignMember
			WHERE Campaign.Parent.Name = 'Source Test' WITH SYSTEM_MODE
		];
		Test.startTest();
		Svc_CampaignSource.Result res = Svc_CampaignSource.prune(scopeMembers, false);
		Test.stopTest();
		System.assertEquals(1, res.removed);
		System.assertEquals(1, res.operationalOutOfScope);
		System.assertEquals(0, members('Source').size());
		System.assertEquals(1, members('Operational').size(), 'Operational is not removed (pending decision)');
	}

	@IsTest
	static void dryRun_noDml() {
		useScopes(1);
		Test.startTest();
		Svc_CampaignSource.Result res = Svc_CampaignSource.sync(accounts().values(), Svc_CampaignSource.sources(), true);
		Test.stopTest();
		System.assertEquals(2, res.added);
		System.assertEquals(0, members('Source').size());
	}

	@IsTest
	static void batch_runsWithoutContracts() {
		Test.startTest();
		Database.executeBatch(new Batch_CampaignSource(true), 200);
		Test.stopTest();
		System.assertEquals(0, members('Source').size(), 'no contracts in the selection');
		System.assert(Svc_CampaignSource.accountQuery().contains('MigrationProduct__c'));
	}
}
