@IsTest
private class Test_vr_FinancialEntityChange {

    private static final String VR_MESSAGE = 'You are not allowed to change the Customer Entity';

    private static User createUser(String profileName, String alias) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            LastName = 'vrFinEntity ' + alias,
            Alias = alias,
            Email = alias + '@vrfinentity.test',
            Username = alias + '.' + System.currentTimeMillis() + '@vrfinentity.test',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'nl_NL',
            TimeZoneSidKey = 'Europe/Amsterdam'
        );
        insert u;
        return u;
    }

    private static void assignPermissionSet(User u) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ps_miAllowFinancialEntityChange' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) { // separate setup DML (MIXED_DML)
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    private static Account createOwnedAccount(User owner) {
        Account acc = Test_Data.createAccount('vrFinEntity ' + owner.Alias, '9041', 'B2B', false);
        acc.extID_1__c = null; // no platform id: rbb_Account may derive the reseller from the country
        acc.OwnerId = owner.Id;
        insert acc;
        return [SELECT Id, Reseller_Name__c FROM Account WHERE Id = :acc.Id];
    }

    private static Database.SaveResult updateAs(User u, Account acc) {
        Database.SaveResult sr;
        // System mode like the flows/integrations that set the reseller (profiles have no edit FLS on it);
        // the validation rule still evaluates $User/$Permission of the runAs user.
        System.runAs(u) {
            sr = Database.update(acc, false, AccessLevel.SYSTEM_MODE);
        }
        return sr;
    }

    private static Boolean blockedByRule(Database.SaveResult sr) {
        if (sr.isSuccess()) {
            return false;
        }
        for (Database.Error e : sr.getErrors()) {
            if (e.getMessage().contains(VR_MESSAGE)) {
                return true;
            }
        }
        System.assert(false, 'Update failed for another reason: ' + sr.getErrors());
        return false;
    }

    @IsTest
    static void regularUser_isBlocked() {
        User u = createUser('miSales', 'vrsales');
        Account acc = createOwnedAccount(u);
        System.assertEquals('1', acc.Reseller_Name__c, 'Fixture reseller');

        Database.SaveResult sr = updateAs(u, new Account(Id = acc.Id, Reseller_Name__c = '5'));
        System.assert(blockedByRule(sr), 'A regular user must not change the reseller');
    }

    @IsTest
    static void regularUser_derivedChangeIsBlocked() {
        User u = createUser('miSales', 'vrsalcc');
        Account acc = createOwnedAccount(u);

        // country NL -> DE makes rbb_Account derive reseller 5
        Database.SaveResult sr = updateAs(u, new Account(Id = acc.Id, BillingCountryCode = 'DE'));
        System.assert(blockedByRule(sr), 'A reseller derived by rbb_Account must also be blocked');
    }

    @IsTest
    static void integrationUser_isBlocked() {
        User u = createUser('miAPIIntegration', 'vrapi');
        Account acc = createOwnedAccount(u);

        Database.SaveResult sr = updateAs(u, new Account(Id = acc.Id, Reseller_Name__c = '5'));
        System.assert(blockedByRule(sr), 'Integration users are not exempt');
    }

    @IsTest
    static void permissionSetUser_isAllowed() {
        User u = createUser('miSales', 'vrpsusr');
        assignPermissionSet(u);
        Account acc = createOwnedAccount(u);

        Database.SaveResult sr = updateAs(u, new Account(Id = acc.Id, Reseller_Name__c = '5'));
        System.assert(sr.isSuccess(), 'Permission set user may change the reseller: ' + sr.getErrors());
        System.assertEquals('5', [SELECT Reseller_Name__c FROM Account WHERE Id = :acc.Id].Reseller_Name__c);
    }

    @IsTest
    static void sysAdmin_isAllowed() {
        User u = createUser('System Administrator', 'vradmin');
        Account acc = createOwnedAccount(u);

        Database.SaveResult sr = updateAs(u, new Account(Id = acc.Id, Reseller_Name__c = '5'));
        System.assert(sr.isSuccess(), 'System Administrator may change the reseller: ' + sr.getErrors());
        System.assertEquals('5', [SELECT Reseller_Name__c FROM Account WHERE Id = :acc.Id].Reseller_Name__c);
    }
}
