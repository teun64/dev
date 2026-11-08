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
		System.assert(Svc_CampaignOffer.quantities(accountId).isEmpty());
	}
}
