@IsTest(SeeAllData=false)
private class Test_Svc_DealerUserSetup {

    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name                = 'Test Svc Dealer User Setup Account',
            BillingCountryCode  = 'NL',
            RecordTypeId        = Schema.SObjectType.Account
                                    .getRecordTypeInfosByDeveloperName()
                                    .get('B2B')
                                    .getRecordTypeId()
        );
        insert acc;

        Contact linkedCon = new Contact(
            AccountId = acc.Id,
            FirstName = 'Apex',
            LastName  = 'Test Dealer Contact'
        );
        insert linkedCon;

        Contact unlinkedCon = new Contact(
            LastName = 'Test Unlinked Contact'
        );
        insert unlinkedCon;
    }

    @IsTest
    static void testCreateOrUpdateDealerUser_blankEmail_throws() {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'Test Dealer Contact' LIMIT 1];
        try {
            Svc_DealerUserSetup.createOrUpdateDealerUser('', con.Id);
            System.assert(false, 'Expected a SetupException for a blank email');
        } catch (Svc_DealerUserSetup.SetupException e) {
            System.assertEquals('email is required.', e.getMessage());
        }
    }

    @IsTest
    static void testCreateOrUpdateDealerUser_nullContactId_throws() {
        try {
            Svc_DealerUserSetup.createOrUpdateDealerUser('apex.test.svcdealer@mvsc.invalid.test', null);
            System.assert(false, 'Expected a SetupException for a null contactId');
        } catch (Svc_DealerUserSetup.SetupException e) {
            System.assertEquals('contactId is required.', e.getMessage());
        }
    }

    @IsTest
    static void testCreateOrUpdateDealerUser_unlinkedContact_throws() {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'Test Unlinked Contact' LIMIT 1];
        try {
            Svc_DealerUserSetup.createOrUpdateDealerUser('apex.test.svcdealer@mvsc.invalid.test', con.Id);
            System.assert(false, 'Expected a SetupException for a Contact with no Account');
        } catch (Svc_DealerUserSetup.SetupException e) {
            System.assert(e.getMessage().contains('must be linked to an Account'), 'dbg: ' + e.getMessage());
        }
    }

    @IsTest
    static void testCreateOrUpdateDealerUser_createsThenUpdates() {
        Contact con = [SELECT Id, AccountId FROM Contact WHERE LastName = 'Test Dealer Contact' LIMIT 1];
        String email = 'apex.test.svcdealer.create@mvsc.invalid.test';

        Test.startTest();
        Id firstUserId = Svc_DealerUserSetup.createOrUpdateDealerUser(email, con.Id);
        Id secondUserId = Svc_DealerUserSetup.createOrUpdateDealerUser(email, con.Id);
        Test.stopTest();

        System.assertNotEquals(null, firstUserId, 'Should return a new User Id on first call');
        System.assertEquals(firstUserId, secondUserId, 'Second call with the same email should update, not duplicate, the User');

        User u = [SELECT IsActive, Email, Username FROM User WHERE Id = :firstUserId];
        System.assertEquals(true, u.IsActive, 'User should be active');
        System.assertEquals(email, u.Email, 'User Email should match the provided email');
        System.assert(u.Username.startsWith(email), 'dbg: username=' + u.Username);

        Contact reloadedCon = [SELECT Email FROM Contact WHERE Id = :con.Id];
        System.assertEquals(email, reloadedCon.Email, 'Contact Email should be kept in sync with the login email');

        Integer psAssignments = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :firstUserId AND PermissionSet.Name = 'Authenticated_DealerPortal'
        ];
        System.assertEquals(1, psAssignments, 'Should assign Authenticated_DealerPortal exactly once, even across two calls');
    }
}
