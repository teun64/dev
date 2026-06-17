/**
 * Created by Gerbrand Spaans (Gen25) on 28/11/2023.
 */
@IsTest
private with sharing class Test_Queue_FinancialSystemAccountSync {
    @IsTest
    private static void testBatch() {
        insert new Subscription25__Schedulable_Class__c(Name = 'Batch_FinancialSystemAccountSync');

        Batch_FinancialSystemAccountSync b = new Batch_FinancialSystemAccountSync();
        Assert.areEqual(1, b.getBatchSize(), 'Batch size should be set to 1');

        Test.startTest();
        Database.executeBatch(b);
        Test.stopTest();

        List<Event_Log__c> batchLogs = [SELECT Id FROM Event_Log__c];
        Assert.areEqual(1, batchLogs.size());
    }
    @IsTest
    private static void testBatch_ExecuteBatch() {
        Subscription25__Administration__c admin = new Subscription25__Administration__c(
                Subscription25__Named_Credential__c = 'Exact_NL',
                Subscription25__Twinfield_Company_Code__c = '123',
                Subscription25__Active__c = true
        );

        Logger2 l = Logger2.getInstance();
        l.saveAll();

        Batch_FinancialSystemAccountSync b = new Batch_FinancialSystemAccountSync();

        Test.startTest();
        b.executeBatch(null, new List<SObject>{admin}, l.getParentGuid());
        Test.stopTest();

        List<Event_Log__c> logFiles = [SELECT Id, (SELECT Id FROM OAuth_Logs__r) FROM Event_Log__c];
        Assert.areEqual(1, logFiles.size(), 'No Event Log Created');
    }
    @IsTest
    private static void testAccountSync() {
        List<NamedCredential> ncs = [SELECT Id, DeveloperName FROM NamedCredential LIMIT 1];
        Assert.areEqual(1, ncs.size(), 'No Named Credentials found');

        Subscription25__Administration__c admin = new Subscription25__Administration__c(
                Subscription25__Twinfield_Company_Code__c = '00',
                Subscription25__Named_Credential__c = ncs[0].DeveloperName
        );

        Event_Log__c eventLog = Util_Event.getLog(null, 'S', 'E', 'Account', 'Test Context', null, 'Batch_FinancialSystemAccountSync', admin.Subscription25__Twinfield_Company_Code__c);
        Database.insert(eventLog);

        Account testAccount = Test_Data.createAccount('Test', 'ABC123', 'B2B', false);
        testAccount.FinancialIdAccount__c = 'TEST1';
        insert testAccount;

        String responseString = '{"d": {"results": [{"__metadata": {"type": "Exact.Web.Api.Models.Sync.CRM.AccountSync", "uri": "https://start.exactonline.nl/api/v1/2362180/sync/crm/Accounts(314159L)"}, "Blocked": true, "ID": "TEST1", "Timestamp": "314159"}, {"__metadata": {"type": "Exact.Web.Api.Models.Sync.CRM.AccountSync", "uri": "https://start.exactonline.nl/api/v1/2362180/sync/crm/Accounts(314160L)"}, "Blocked": false, "ID": "6e85ff20-e2c5-44e6-ad4c-3360b00d06b1", "Timestamp": "314160"}]}}';
        Test_Mocks mock = new Test_Mocks(responseString, 200);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Queue_FinancialSystemAccountSync q = new Queue_FinancialSystemAccountSync(admin, null, eventLog.GUID__c);
        q.execute(null);
        Test.stopTest();

        Map<Id, Account> validateAccounts = new Map<Id, Account>([SELECT Id, Is_Blocked__c FROM Account]);
        Assert.areEqual(1, validateAccounts.size(), 'Only one account should be returned.');
        // test account was returned by query
        Assert.isTrue(validateAccounts.containsKey(testAccount.Id), 'Test Account should still present in Salesforce');
        Assert.isTrue((Boolean)validateAccounts.get(testAccount.Id).get('Is_Blocked__c'), 'Test Account not set to Blocked');

        List<Event_Log__c> logs = [SELECT Id, (SELECT Id FROM OAuth_Logs__r) FROM Event_Log__c ORDER BY Parent_Event__c NULLS FIRST];
        Assert.areEqual(2, logs.size(), 'Expected one parent log and one update log');
        Assert.areEqual(1, logs[0].OAuth_Logs__r.size(), 'Expected on integration log');
    }
    @IsTest
    private static void testRequeueLogic() {
        List<NamedCredential> ncs = [SELECT Id, DeveloperName FROM NamedCredential LIMIT 1];
        Assert.areEqual(1, ncs.size(), 'No Named Credentials found');

        Subscription25__Administration__c admin = new Subscription25__Administration__c(
                Subscription25__Twinfield_Company_Code__c = '00',
                Subscription25__Named_Credential__c = ncs[0].DeveloperName
        );

        Event_Log__c eventLog = Util_Event.getLog(null, 'S', 'E', 'Account', 'Test Context', null, 'Batch_FinancialSystemAccountSync', admin.Subscription25__Twinfield_Company_Code__c);
        Database.insert(eventLog);

        Test_Mocks mock = new Test_Mocks('{"d":{"results":[]}}', 200);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Queue_FinancialSystemAccountSync q = new Queue_FinancialSystemAccountSync(admin, null, eventLog.GUID__c);
        q.reschedule(new Map<String, Object>{'__next' => 'https://thisurl.com/api/this/resource?is=needed'});
        Test.stopTest();
    }
    @IsTest
    private static void testMapToSalesforceAccounts() {
        // create 2 accounts in Salesforce. These should be returned.
        List<Account> testAccounts = new List<Account>{
                Test_Data.createAccount('Test1', 'ABC123', 'B2B', false),
                Test_Data.createAccount('Test2', 'DEF456', 'B2B', false)
        };
        testAccounts[0].FinancialIdAccount__c = 'ABC123';
        testAccounts[1].FinancialIdAccount__c = 'DEF456';
        insert testAccounts;

        // add a dummy account. This account is not committed to the database and should not be returned by the tested method.
        Account dummyAccount = Test_Data.createAccount('Dummy1', 'dummy','B2B',false);
        dummyAccount.FinancialIdAccount__c = 'DUMMY';
        testAccounts.add(dummyAccount);

        // Create the input Map
        Map<String, Account> testAccountsMap = new Map<String, Account>();
        for(Account a : testAccounts) {
            testAccountsMap.put(a.FinancialIdAccount__c, a);
        }

        Test.startTest();
        Queue_FinancialSystemAccountSync.mapToSalesforceAccountsAndRemoveUnknowns(testAccountsMap);
        Test.stopTest();

        Assert.areEqual(2, testAccountsMap.size(), 'Not all accounts found and returned');

        Assert.areNotEqual('DUMMY', testAccountsMap.values()[0].FinancialIdAccount__c, 'Should never return the dummy method');
        Assert.isNotNull(testAccountsMap.values()[0].Id, 'Should never return an account without an Id');

        Assert.areNotEqual('DUMMY', testAccountsMap.values()[1].FinancialIdAccount__c, 'Should never return the dummy method');
        Assert.isNotNull(testAccountsMap.values()[1].Id, 'Should never return an account without an Id');
    }
    @IsTest
    private static void testAccountMapping() {
        Map<String, String> fieldMapping = new Map<String, String>{
                'ID' => 'Id',
                'name' => 'Name',
                'street' => 'BillingStreet'
        };

        // List of example responses
        List<Object> sourceObjects = (List<Object>)JSON.deserializeUntyped('[{"ID":"001000000000000001","name":"Test Account 1","street":"Streetstreet"},{"ID":"001000000000000002","name":"Test Account 2","street":"Gustav Mahlerlaan"},{"ID":"001000000000000003","name":"Test Account 3","street":"Hogeweg"}]');

        Test.startTest();
        Map<String, Account> testAccounts = Queue_FinancialSystemAccountSync.getAccountUpdates(sourceObjects, fieldMapping);
        Test.stopTest();

        Assert.areEqual('001000000000000001', testAccounts.values()[0].Id);
        Assert.areEqual('Test Account 1', testAccounts.values()[0].Name);
        Assert.areEqual('Streetstreet', testAccounts.values()[0].BillingStreet);

        Assert.areEqual('001000000000000002', testAccounts.values()[1].Id);
        Assert.areEqual('Test Account 2', testAccounts.values()[1].Name);
        Assert.areEqual('Gustav Mahlerlaan', testAccounts.values()[1].BillingStreet);

        Assert.areEqual('001000000000000003', testAccounts.values()[2].Id);
        Assert.areEqual('Test Account 3', testAccounts.values()[2].Name);
        Assert.areEqual('Hogeweg', testAccounts.values()[2].BillingStreet);
    }
    @IsTest
    private static void testCustomSettingLogic() {
        Subscription25__Administration__c testAdmin = new Subscription25__Administration__c(
                Subscription25__Twinfield_Company_Code__c = 'TEST'
        );

        // Assert that at the start there are no settings present
        List<Exact_Settings__c> currentSettings = [SELECT Id FROM Exact_Settings__c];
        Assert.areEqual(0, currentSettings.size(), 'Settings should not be present in test context at start of test');

        Queue_FinancialSystemAccountSync.saveAccountSyncTimestamp(testAdmin, '42');

        Integer savedTimestamp = Queue_FinancialSystemAccountSync.getAccountSyncTimestamp(testAdmin);
        Assert.areEqual(42, savedTimestamp, 'Setting not created correctly');

        Queue_FinancialSystemAccountSync.saveAccountSyncTimestamp(testAdmin, '314');
        Integer updatedTimestamp = Queue_FinancialSystemAccountSync.getAccountSyncTimestamp(testAdmin);
        Assert.areEqual(314, updatedTimestamp, 'Setting not updated correctly');

        Assert.areEqual(1, [SELECT Id FROM Exact_Settings__c].size(), 'Setting should have been created once and updated.');
    }
    @IsTest
    private static void testLimits() {
        Subscription25__Administration__c testAdmin = new Subscription25__Administration__c(
                Subscription25__Twinfield_Company_Code__c = 'TEST'
        );
        Util_FinancialSystem.Limits l = Util_FinancialSystem.getLimits(testAdmin);
        Assert.isFalse(l.limitReached(), 'Limit cannot be reached yet');

        HttpResponse response = new HttpResponse();
        // No more daily  requests left
        response.setHeader('X-RateLimit-Remaining', String.valueOf(-1));
        Util_FinancialSystem.logLimits(response, testAdmin);

        l = Util_FinancialSystem.getLimits(testAdmin);
        System.debug('Hours asserted');
        Assert.isTrue(l.limitReached(), 'Hourly limits should be reached');

        // no more minutely requests left
        response.setHeader('X-RateLimit-Remaining', String.valueOf(100)); //reset
        response.setHeader('X-RateLimit-Minutely-Remaining', String.valueOf(-1));
        response.setHeader('X-RateLimit-Reset', String.valueOf(System.now().getTime() + 1000));
        Util_FinancialSystem.logLimits(response, testAdmin);

        l = Util_FinancialSystem.getLimits(testAdmin);
        System.debug('Minutes asserted');
        Assert.isTrue(l.limitReached(), 'Minutely limits should be reached');

        // multiple consecutive errors
        response.setHeader('X-RateLimit-Minutely-Remaining', String.valueOf(100)); // reset
        response.setHeader('X-RateLimit-Reset', String.valueOf(System.now().getTime() - 1000)); // reset
        response.setStatusCode(0);
        // Log 2 errors
        Util_FinancialSystem.logLimits(response, testAdmin);
        Util_FinancialSystem.logLimits(response, testAdmin);

        l = Util_FinancialSystem.getLimits(testAdmin);
        System.debug('Errors asserted');
        Assert.isTrue(l.limitReached(), 'Consecutive errors should be reached');
    }
}