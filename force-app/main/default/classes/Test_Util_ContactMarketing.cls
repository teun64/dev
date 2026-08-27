@IsTest
private class Test_Util_ContactMarketing {

    @TestSetup
    static void makeData() {
        Account acc = Test_Data.createAccount('ACME ContactMarketing BV', '9024', 'B2B', false);
        insert acc;

        Contact marketable = new Contact(
            AccountId = acc.Id, FirstName = 'Marketable', LastName = 'ContactMarketingTester',
            Email = 'marketable@example.com'
        );
        Contact excluded = new Contact(
            AccountId = acc.Id, FirstName = 'Excluded', LastName = 'ContactMarketingTester'
            // No Email/Phone/MobilePhone - Marketing__c formula is false without any contact info
        );
        Contact noRelation = new Contact(
            FirstName = 'NoRelation', LastName = 'ContactMarketingTester', Email = 'norelation@example.com'
            // No AccountId - never gets an AccountContactRelation at all
        );
        // Inserted one at a time - the "rab - Contact" flow faults on a bulk multi-row
        // Contact insert/update in this org (unhandled fault, CANNOT_EXECUTE_FLOW_TRIGGER).
        insert marketable;
        insert excluded;
        insert noRelation;

        AccountContactRelation acr = [
            SELECT Id, Roles FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :marketable.Id LIMIT 1
        ];
        acr.Roles = 'Main'; // not billing-only, plus an email above -> Marketing__c = true
        update acr;
    }

    @IsTest
    static void testGetExcludedContactIds_nullOrEmptySetReturnsEmpty() {
        System.assertEquals(0, Util_ContactMarketing.getExcludedContactIds(null).size());
        System.assertEquals(0, Util_ContactMarketing.getExcludedContactIds(new Set<Id>()).size());
    }

    @IsTest
    static void testGetExcludedContactIds_mixedRelations() {
        Contact marketable = [SELECT Id FROM Contact WHERE Email = 'marketable@example.com' LIMIT 1];
        Contact excluded   = [SELECT Id FROM Contact WHERE FirstName = 'Excluded' LIMIT 1];
        Contact noRelation = [SELECT Id FROM Contact WHERE FirstName = 'NoRelation' LIMIT 1];

        Test.startTest();
        Set<Id> result = Util_ContactMarketing.getExcludedContactIds(
            new Set<Id>{ marketable.Id, excluded.Id, noRelation.Id }
        );
        Test.stopTest();

        System.assert(!result.contains(marketable.Id), 'Contact with a marketable relation is not excluded');
        System.assert(result.contains(excluded.Id), 'Contact with only non-marketable relations is excluded');
        System.assert(!result.contains(noRelation.Id), 'Contact with no relations at all is not excluded');
    }
}
