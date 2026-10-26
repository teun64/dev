@IsTest(SeeAllData=false)
public class Test_Svc_DealerUserSetup {

    @TestSetup
    static void makeData() {
        createDealerFixture();
    }

    // Shared with Test_Inv_CustomerUser.
    // Account owner with a role (required for a contact-linked portal user), a B2B Dealer
    // account with a contact, a contact without account and a dealer account with a role-less owner.
    public static void createDealerFixture() {
        // A permission set group must be (re)calculated in a test before it can be assigned.
        for (PermissionSetGroup psg : [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :Svc_DealerUserSetup.PSG_NAME]) {
            Test.calculatePermissionSetGroup(psg.Id);
        }
        User roleOwner;
        User noRoleOwner;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole role = new UserRole(Name = 'Test Dealer Owner Role');
            insert role;
            Id adminProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
            roleOwner   = newInternalUser('apex.test.dealerowner', adminProfileId, role.Id);
            noRoleOwner = newInternalUser('apex.test.dealernorole', adminProfileId, null);
            insert new List<User>{ roleOwner, noRoleOwner };
        }

        Id b2bRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId();
        Account acc = new Account(
            Name               = 'Test Svc Dealer User Setup Account',
            BillingCountryCode = 'NL',
            RecordTypeId       = b2bRtId,
            Relation_type__c   = 'Dealer',
            OwnerId            = roleOwner.Id
        );
        Account noRoleAcc = new Account(
            Name               = 'Test Svc Dealer No Role Account',
            BillingCountryCode = 'NL',
            RecordTypeId       = b2bRtId,
            Relation_type__c   = 'Dealer',
            OwnerId            = noRoleOwner.Id
        );
        Account endUserAcc = new Account(
            Name               = 'Test Svc Dealer End User Account',
            BillingCountryCode = 'NL',
            RecordTypeId       = b2bRtId,
            Relation_type__c   = 'End User',
            OwnerId            = roleOwner.Id
        );
        insert new List<Account>{ acc, noRoleAcc, endUserAcc };

        // One per DML: rab - Contact faults on more than one Contact.Email in a single insert.
        List<Contact> contacts = new List<Contact>{
            new Contact(AccountId = acc.Id, FirstName = 'Apex', LastName = 'Test Dealer Contact',
                Email = 'apex.test.svcdealer.contact@mvsc.invalid.test'),
            new Contact(AccountId = noRoleAcc.Id, FirstName = 'Apex', LastName = 'Test No Role Contact',
                Email = 'apex.test.svcdealer.norole@mvsc.invalid.test'),
            new Contact(AccountId = endUserAcc.Id, FirstName = 'Apex', LastName = 'Test End User Contact',
                Email = 'apex.test.svcdealer.enduser@mvsc.invalid.test'),
            new Contact(LastName = 'Test Unlinked Contact')
        };
        for (Contact con : contacts) {
            insert con;
        }
    }

    // dev has only one Customer Community Plus seat. Deactivating the active holders here is
    // rolled back with the test, but frees a seat for the user this test creates.
    public static void freeCommunitySeat() {
        UserLicense lic = [SELECT TotalLicenses, UsedLicenses FROM UserLicense WHERE Name = 'Customer Community Plus' LIMIT 1];
        if (lic.TotalLicenses - lic.UsedLicenses > 0) return;
        List<User> holders = [
            SELECT Id FROM User
            WHERE IsActive = true AND Profile.UserLicense.Name = 'Customer Community Plus'
        ];
        for (User u : holders) {
            u.IsActive = false;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update holders;
        }
    }

    private static User newInternalUser(String prefix, Id profileId, Id roleId) {
        return new User(
            ProfileId         = profileId,
            UserRoleId        = roleId,
            Username          = prefix + '@mvsc.invalid.test',
            Email             = prefix + '@mvsc.invalid.test',
            LastName          = prefix,
            Alias             = prefix.right(8),
            LocaleSidKey      = 'nl_NL',
            LanguageLocaleKey = 'nl_NL',
            TimeZoneSidKey    = 'Europe/Amsterdam',
            EmailEncodingKey  = 'UTF-8'
        );
    }

    private static Contact getContact(String lastName) {
        return [SELECT Id, AccountId, Email FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    @IsTest
    static void testCreateOrUpdateDealerUser_blankEmail_throws() {
        Contact con = getContact('Test Dealer Contact');
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
        Contact con = getContact('Test Unlinked Contact');
        try {
            Svc_DealerUserSetup.createOrUpdateDealerUser('apex.test.svcdealer@mvsc.invalid.test', con.Id);
            System.assert(false, 'Expected a SetupException for a Contact with no Account');
        } catch (Svc_DealerUserSetup.SetupException e) {
            System.assert(e.getMessage().contains('must be linked to an Account'), 'dbg: ' + e.getMessage());
        }
    }

    @IsTest
    static void testEnableDealerUser_ownerWithoutRole_throws() {
        Contact con = getContact('Test No Role Contact');
        try {
            Svc_DealerUserSetup.enableDealerUser(con.Id);
            System.assert(false, 'Expected a SetupException for an account owner without role');
        } catch (Svc_DealerUserSetup.SetupException e) {
            System.assert(e.getMessage().contains('has no role'), 'dbg: ' + e.getMessage());
        }
    }

    @IsTest
    static void testEnableDealerUser_noAccess_throws() {
        Contact con = getContact('Test Dealer Contact');
        Id stdProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        User plain = newInternalUser('apex.test.dealernoaccess', stdProfileId, null);
        insert plain;

        System.runAs(plain) {
            try {
                Svc_DealerUserSetup.enableDealerUser(con.Id);
                System.assert(false, 'Expected a SetupException for a user without the custom permission');
            } catch (Svc_DealerUserSetup.SetupException e) {
                System.assert(e.getMessage().contains('not allowed'), 'dbg: ' + e.getMessage());
            }
        }
    }

    // Non-sysadmin holder of ps_miExperienceCloudCustomer_Admin: system-mode DML must still work.
    @IsTest
    static void testEnableDealerUser_permissionSetHolder_succeeds() {
        Contact con = getContact('Test Dealer Contact');
        Id stdProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
        User holder = newInternalUser('apex.test.dealerpsholder', stdProfileId, null);
        insert holder;
        insert new PermissionSetAssignment(
            AssigneeId      = holder.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'ps_miExperienceCloudCustomer_Admin' LIMIT 1].Id
        );
        freeCommunitySeat();

        User enabled;
        Test.startTest();
        System.runAs(holder) {
            enabled = Svc_DealerUserSetup.enableDealerUser(con.Id);
        }
        Test.stopTest();

        System.assertEquals(true, enabled.IsActive, 'User should be enabled by the permission set holder');
    }

    @IsTest
    static void testCreateOrUpdateDealerUser_createsThenUpdates() {
        Contact con = getContact('Test Dealer Contact');
        String email = 'apex.test.svcdealer.create@mvsc.invalid.test';
        freeCommunitySeat();

        Test.startTest();
        Id firstUserId = Svc_DealerUserSetup.createOrUpdateDealerUser(email, con.Id);
        Id secondUserId = Svc_DealerUserSetup.createOrUpdateDealerUser(email, con.Id);
        Test.stopTest();

        System.assertNotEquals(null, firstUserId, 'Should return a new User Id on first call');
        System.assertEquals(firstUserId, secondUserId, 'Second call for the same contact should update, not duplicate, the User');

        User u = [SELECT IsActive, Email, Username, ContactId, Profile.Name FROM User WHERE Id = :firstUserId];
        System.assertEquals(true, u.IsActive, 'User should be active');
        System.assertEquals(email, u.Email, 'User Email should match the provided email');
        System.assertEquals(con.Id, u.ContactId, 'User should be linked to the contact');
        System.assertEquals(Svc_DealerUserSetup.PROFILE_NAME, u.Profile.Name, 'User should get the dealer profile');
        System.assert(u.Username.startsWith(email + '.midealer'), 'dbg: username=' + u.Username);

        Contact reloadedCon = [SELECT Email FROM Contact WHERE Id = :con.Id];
        System.assertEquals(email, reloadedCon.Email, 'Contact Email should be kept in sync with the login email');

        Integer psgAssignments = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :firstUserId AND PermissionSetGroup.DeveloperName = :Svc_DealerUserSetup.PSG_NAME
        ];
        System.assertEquals(1, psgAssignments, 'Should assign pg_miDealerPortal exactly once, even across two calls');

        Integer memberPsAssignments = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :firstUserId AND PermissionSet.Name = :Svc_DealerUserSetup.MEMBER_PS_NAME AND PermissionSetGroupId = null
        ];
        System.assertEquals(1, memberPsAssignments, 'Should assign the site member set directly, exactly once');
    }

    @IsTest
    static void testEnableDisableEnable_reusesUser() {
        Contact con = getContact('Test Dealer Contact');
        freeCommunitySeat();

        Test.startTest();
        User enabled  = Svc_DealerUserSetup.enableDealerUser(con.Id);
        User disabled = Svc_DealerUserSetup.disableDealerUser(con.Id);
        User again    = Svc_DealerUserSetup.enableDealerUser(con.Id);
        Test.stopTest();

        System.assertEquals(enabled.Id, disabled.Id, 'Disable should hit the enabled user');
        System.assertEquals(enabled.Id, again.Id, 'Re-enable should re-activate the same user');
        System.assertEquals(true, [SELECT IsActive FROM User WHERE Id = :again.Id].IsActive, 'User should be active again');
        System.assert(again.Username.startsWith(con.Email + '.midealer'), 'dbg: username=' + again.Username);
    }

    @IsTest
    static void testBuildUsername_stripsPlusTag() {
        String username = Svc_DealerUserSetup.buildUsername('teun.rietman+accdealer@outlook.com');
        System.assert(username.startsWith('teun.rietman@outlook.com.miDealer'), 'dbg: username=' + username);
        System.assert(!username.contains('+'), 'dbg: username=' + username);
    }

    @IsTest
    static void testDisableDealerUser_noUser_throws() {
        Contact con = getContact('Test Dealer Contact');
        try {
            Svc_DealerUserSetup.disableDealerUser(con.Id);
            System.assert(false, 'Expected a SetupException for a contact without user');
        } catch (Svc_DealerUserSetup.SetupException e) {
            System.assert(e.getMessage().contains('no active customer user'), 'dbg: ' + e.getMessage());
        }
    }
}
