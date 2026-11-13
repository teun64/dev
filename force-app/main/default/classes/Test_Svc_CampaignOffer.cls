/**
 * Tests Svc_CampaignOffer: the Opportunity of an "Offer" answer with a line per migration product. The 2G count per
 * product comes from quantityOverride (contracts on hardware need the subscription package).
 */
@IsTest
private class Test_Svc_CampaignOffer {

	@TestSetup
	static void setup() {
		Account acct = Test_Data.createAccount('Offer Account', (String) null, 'B2B', true);
		Test_Data.createContact(acct.Id, 'Main', null, 'main@offer.test', true);
		Database.insert(new Campaign(Name = 'Offer Campaign', IsActive = true, CallbackLabel__c = '2G/4G conversion'), AccessLevel.SYSTEM_MODE);

		// rbc_Opportunity picks the Pricebook on Relation Type (End User) + Reseller (1)
		String currencyCode = [SELECT IsoCode FROM CurrencyType WHERE IsCorporate = true].IsoCode;
		Pricebook2 pricebook = new Pricebook2(Name = 'Test - NL - Direct Sales', IsActive = true, Type__c = 'Consumer & Business Users', Reseller__c = '1');
		Database.insert(pricebook, AccessLevel.SYSTEM_MODE);
		List<Product2> products = new List<Product2>{
			Test_Data.createProduct('Mi50.M', 'T-MI50M', 't-mi50m', 'Hardware', false),
			Test_Data.createProduct('Mi01.M', 'T-MI01M', 't-mi01m', 'Hardware', false)
		};
		Database.insert(products, AccessLevel.SYSTEM_MODE);
		List<PricebookEntry> entries = new List<PricebookEntry>();
		for (Product2 prod : products) {
			entries.add(new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prod.Id, UnitPrice = 165, IsActive = true, CurrencyIsoCode = currencyCode));
		}
		Database.insert(entries, AccessLevel.SYSTEM_MODE);
		// only Mi50.M has a price in the Opportunity price book
		Database.insert(new PricebookEntry(Pricebook2Id = pricebook.Id, Product2Id = products[0].Id, UnitPrice = 165, IsActive = true,
			CurrencyIsoCode = currencyCode), AccessLevel.SYSTEM_MODE);
	}

	static Id productId(String name) {
		return [SELECT Id FROM Product2 WHERE Name = :name WITH SYSTEM_MODE].Id;
	}

	static Id offer() {
		Id contactId = [SELECT Id FROM Contact WHERE Email = 'main@offer.test' WITH SYSTEM_MODE].Id;
		Id campaignId = [SELECT Id FROM Campaign WHERE Name = 'Offer Campaign' WITH SYSTEM_MODE].Id;
		return Svc_CampaignOffer.createOffer(contactId, campaignId, 'Campaign mail');
	}

	@IsTest
	static void offer_linesPerMigrationProduct() {
		Svc_CampaignOffer.quantityOverride = new Map<Id, Integer>{ productId('Mi50.M') => 3 };
		Test.startTest();
		Id oppId = offer();
		Test.stopTest();
		Opportunity opp = [
			SELECT Name, CampaignId, Campaign.Name, LeadSource, ContactId,
			       (SELECT Quantity, UnitPrice, Product2.Name FROM OpportunityLineItems)
			FROM Opportunity WHERE Id = :oppId WITH SYSTEM_MODE
		];
		System.assertEquals('Offer Campaign', opp.Campaign.Name);
		System.assertEquals('2G/4G conversion - Offer Account', opp.Name);
		System.assertEquals('E-mail', opp.LeadSource);
		System.assertNotEquals(null, opp.ContactId);
		System.assertEquals(1, opp.OpportunityLineItems.size());
		System.assertEquals('Mi50.M', opp.OpportunityLineItems[0].Product2.Name);
		System.assertEquals(3, opp.OpportunityLineItems[0].Quantity);
		System.assertEquals(165, opp.OpportunityLineItems[0].UnitPrice);
	}

	@IsTest
	static void offer_productWithoutPrice_inDescription() {
		Svc_CampaignOffer.quantityOverride = new Map<Id, Integer>{ productId('Mi50.M') => 1, productId('Mi01.M') => 2 };
		Test.startTest();
		Id oppId = offer();
		Test.stopTest();
		Opportunity opp = [SELECT Description, (SELECT Id FROM OpportunityLineItems) FROM Opportunity WHERE Id = :oppId WITH SYSTEM_MODE];
		System.assertEquals(1, opp.OpportunityLineItems.size());
		System.assert(opp.Description.contains('2x Mi01.M'), opp.Description);
	}

	@IsTest
	static void offer_twice_sameOpportunity() {
		Svc_CampaignOffer.quantityOverride = new Map<Id, Integer>{ productId('Mi50.M') => 1 };
		Id first = offer();
		Test.startTest();
		Id second = offer();
		Test.stopTest();
		System.assertEquals(first, second);
		System.assertEquals(1, [SELECT COUNT() FROM Opportunity WITH SYSTEM_MODE]);
	}

	@IsTest
	static void offer_fromCall_ownerIsAgent() {
		Svc_CampaignOffer.quantityOverride = new Map<Id, Integer>();
		Id contactId = [SELECT Id FROM Contact WHERE Email = 'main@offer.test' WITH SYSTEM_MODE].Id;
		Id campaignId = [SELECT Id FROM Campaign WHERE Name = 'Offer Campaign' WITH SYSTEM_MODE].Id;
		Test.startTest();
		Id oppId = Svc_CampaignOffer.createOffer(contactId, campaignId, Svc_CampaignOffer.SOURCE_CALL);
		Test.stopTest();
		Opportunity opp = [SELECT OwnerId, LeadSource FROM Opportunity WHERE Id = :oppId WITH SYSTEM_MODE];
		System.assertEquals(UserInfo.getUserId(), opp.OwnerId);
		System.assertEquals('Telephone', opp.LeadSource);
	}

	@IsTest
	static void offer_fromPage_ownerIsAccountOwner() {
		Svc_CampaignOffer.quantityOverride = new Map<Id, Integer>();
		User other = [SELECT Id FROM User WHERE IsActive = true AND UserType = 'Standard' AND Id != :UserInfo.getUserId() LIMIT 1];
		Account acct = [SELECT Id FROM Account WHERE Name = 'Offer Account' WITH SYSTEM_MODE];
		acct.OwnerId = other.Id;
		Database.update(acct, AccessLevel.SYSTEM_MODE);
		Test.startTest();
		Id oppId = offer();
		Test.stopTest();
		System.assertEquals(other.Id, [SELECT OwnerId FROM Opportunity WHERE Id = :oppId WITH SYSTEM_MODE].OwnerId);
	}

	@IsTest
	static void quantities_noHardware_empty() {
		Id accountId = [SELECT Id FROM Account WHERE Name = 'Offer Account' WITH SYSTEM_MODE].Id;
		System.assert(Svc_CampaignOffer.quantities(accountId, [SELECT Id FROM Campaign WHERE Name = 'Offer Campaign' WITH SYSTEM_MODE].Id).qtyByProduct.isEmpty());
	}

	// ── CampaignOfferProduct__c mapping ──────────────────────────────────────
	static Asset hw(Id productId, String accessories) {
		return new Asset(Name = 'hw', Product2Id = productId, Accessories__c = accessories);
	}

	static CampaignOfferProduct__c row(Id hardware, Id offer, Id alt, String field, String value, Integer priority) {
		return new CampaignOfferProduct__c(Hardware__c = hardware, OfferProduct__c = offer, AlternativeProduct__c = alt,
			FilterField__c = field, FilterValue__c = value, Priority__c = priority);
	}

	@IsTest
	static void resolve_filterTrueOffer_falseAlternative_noFilterAlways() {
		Id mi50 = productId('Mi50.M'), mi01 = productId('Mi01.M');
		Product2 hwProduct = Test_Data.createProduct('HW Mi50', 'T-HW50', 't-hw50', 'Hardware', true);
		List<CampaignOfferProduct__c> rows = new List<CampaignOfferProduct__c>{
			row(hwProduct.Id, mi50, mi01, 'Accessories__c', 'Klasse 5 module (intern)', 1)
		};
		Svc_CampaignOffer.Plan plan = new Svc_CampaignOffer.Plan();
		Svc_CampaignOffer.resolve(new List<Asset>{
			hw(hwProduct.Id, 'Miblock;Klasse 5 module (intern)'), hw(hwProduct.Id, 'Klasse 5 module (intern)'), hw(hwProduct.Id, 'Miblock'), hw(hwProduct.Id, null)
		}, rows, plan);
		System.assertEquals(2, plan.qtyByProduct.get(mi50));
		System.assertEquals(2, plan.qtyByProduct.get(mi01));
		System.assert(plan.notes.isEmpty());
		// no filter: always the offer product
		plan = new Svc_CampaignOffer.Plan();
		Svc_CampaignOffer.resolve(new List<Asset>{ hw(hwProduct.Id, null) }, new List<CampaignOfferProduct__c>{ row(hwProduct.Id, mi01, null, null, null, 1) }, plan);
		System.assertEquals(1, plan.qtyByProduct.get(mi01));
	}

	@IsTest
	static void resolve_noRowOrNoAlternative_note() {
		Id mi50 = productId('Mi50.M');
		Product2 hwProduct = Test_Data.createProduct('HW Other', 'T-HWO', 't-hwo', 'Hardware', true);
		Svc_CampaignOffer.Plan plan = new Svc_CampaignOffer.Plan();
		// filter false without alternative → unmapped; hardware without any row → unmapped
		Svc_CampaignOffer.resolve(new List<Asset>{ hw(hwProduct.Id, 'Miblock'), hw(productId('Mi01.M'), null) },
			new List<CampaignOfferProduct__c>{ row(hwProduct.Id, mi50, null, 'Accessories__c', 'Klasse 5 module (intern)', 1) }, plan);
		System.assert(plan.qtyByProduct.isEmpty());
		System.assertEquals(1, plan.notes.size());
		System.assert(plan.notes[0].contains('1x HW Other') && plan.notes[0].contains('1x Mi01.M'), plan.notes[0]);
	}

	@IsTest
	static void resolve_priority_firstRowThatGivesProductWins() {
		Id mi50 = productId('Mi50.M'), mi01 = productId('Mi01.M');
		Product2 hwProduct = Test_Data.createProduct('HW Prio', 'T-HWP', 't-hwp', 'Hardware', true);
		// row 1 only has an offer product for Klasse 5, row 2 (no filter) catches the rest
		Svc_CampaignOffer.Plan plan = new Svc_CampaignOffer.Plan();
		Svc_CampaignOffer.resolve(new List<Asset>{ hw(hwProduct.Id, 'Klasse 5 module (intern)'), hw(hwProduct.Id, null) },
			new List<CampaignOfferProduct__c>{
				row(hwProduct.Id, mi50, null, 'Accessories__c', 'Klasse 5 module (intern)', 1),
				row(hwProduct.Id, mi01, null, null, null, 2)
			}, plan);
		System.assertEquals(1, plan.qtyByProduct.get(mi50));
		System.assertEquals(1, plan.qtyByProduct.get(mi01));
	}

	@IsTest
	static void offer_noRowsConfigured_hardwareNoteOnly() {
		// quantityOverride unset: the contract query runs (no contracts here) → no lines, no note, Opportunity still made
		Id oppId = offer();
		System.assertNotEquals(null, oppId);
		System.assertEquals(0, [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :oppId WITH SYSTEM_MODE]);
	}

	@IsTest
	static void loadRows_campaignScopeAndInvalidField() {
		Id campaignId = [SELECT Id FROM Campaign WHERE Name = 'Offer Campaign' WITH SYSTEM_MODE].Id;
		Campaign other = new Campaign(Name = 'Other Main', IsActive = true);
		Database.insert(other, AccessLevel.SYSTEM_MODE);
		Product2 hwProduct = Test_Data.createProduct('HW Scope', 'T-HWS', 't-hws', 'Hardware', true);
		Id offerProduct = productId('Mi50.M');
		CampaignOfferProduct__c second = row(hwProduct.Id, offerProduct, null, null, null, 2);
		second.Campaign__c = campaignId;
		CampaignOfferProduct__c first = row(hwProduct.Id, offerProduct, null, null, null, 1);
		first.Campaign__c = campaignId;
		CampaignOfferProduct__c foreign = row(hwProduct.Id, offerProduct, null, null, null, 1);
		foreign.Campaign__c = other.Id;
		CampaignOfferProduct__c bad = row(hwProduct.Id, offerProduct, offerProduct, 'Nope__c', 'x', 3);
		bad.Campaign__c = campaignId;
		Database.insert(new List<CampaignOfferProduct__c>{ second, first, foreign, bad }, AccessLevel.SYSTEM_MODE);
		Test.startTest();
		List<String> notes = new List<String>();
		List<CampaignOfferProduct__c> rows = Svc_CampaignOffer.loadRows(campaignId, notes);
		Test.stopTest();
		System.assertEquals(2, rows.size());
		System.assertEquals(first.Id, rows[0].Id, 'by priority');
		System.assertEquals(second.Id, rows[1].Id);
		System.assertEquals(1, notes.size());
	}

	@IsTest
	static void validation_requiredProductsAndFilterPair() {
		Id campaignId = [SELECT Id FROM Campaign WHERE Name = 'Offer Campaign' WITH SYSTEM_MODE].Id;
		Product2 hwProduct = Test_Data.createProduct('HW Val', 'T-HWV', 't-hwv', 'Hardware', true);
		Id mi50 = productId('Mi50.M');
		List<CampaignOfferProduct__c> bad = new List<CampaignOfferProduct__c>{
			row(hwProduct.Id, null, null, null, null, 1),                                            // no offer product
			row(null, mi50, null, null, null, 1),                                                    // no hardware
			row(hwProduct.Id, mi50, null, 'Accessories__c', 'x', 1),                                 // filter without alternative
			row(hwProduct.Id, mi50, mi50, 'Accessories__c', null, 1),                                // field without value
			row(hwProduct.Id, mi50, mi50, null, 'x', 1)                                              // value without field
		};
		for (CampaignOfferProduct__c r : bad) {
			r.Campaign__c = campaignId;
			Database.SaveResult sr = Database.insert(r, false);
			System.assert(!sr.isSuccess(), 'should be refused: ' + r);
		}
		CampaignOfferProduct__c ok = row(hwProduct.Id, mi50, mi50, 'Accessories__c', 'x', 1);
		ok.Campaign__c = campaignId;
		System.assert(Database.insert(ok, false).isSuccess());
	}
}
