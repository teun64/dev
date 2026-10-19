@IsTest
private class Test_Batch_TerminateExcludedContracts {

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
        Database.update(new Subscription25__Administration__c(Id = admin.Id, Subscription25__Exclude_From_Jobs__c = true), AccessLevel.SYSTEM_MODE);
        Product2 prod = Test_Data.createProduct('Test Product', 'test-prod-1', '1-sv-1', 'Subscription', true);
        Test_Data.createPricebookEntry(prod.Id, 100, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('21%', 21, true, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vatRate.Id, true);

        Account acct = Test_Data.createAccount('Terminate Excluded BV', '9071', 'B2B', true);
        // contract products on an active contract require the account to be known in the administration
        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

        List<Contract> contracts = new List<Contract>();
        for (String name : new List<String>{ 'expired', 'endsInAWeek' }) {
            Contract contr = Test_Data.createContract(acct.Id, admin.Id, false);
            contr.StartDate = Date.today().addYears(-1);
            contr.Name = name;
            contracts.add(contr);
        }
        Database.insert(contracts, AccessLevel.SYSTEM_MODE);
        for (Contract contr : contracts) {
            contr.Status = 'Activated';
        }
        Database.update(contracts, AccessLevel.SYSTEM_MODE);

        List<Subscription25__Contract_Product__c> cps = new List<Subscription25__Contract_Product__c>();
        for (Contract contr : contracts) {
            Subscription25__Contract_Product__c cp = Test_Data.createContractProduct(contr.Id, prod.Id, false);
            cp.Subscription25__Start_Date__c = contr.StartDate;
            cps.add(cp);
        }
        Database.insert(cps, AccessLevel.SYSTEM_MODE);
        for (Subscription25__Contract_Product__c cp : cps) {
            cp.Subscription25__Status__c = 'Activated';
        }
        Database.update(cps, AccessLevel.SYSTEM_MODE);

        // Closed with a termination date, as a platform termination with a future date leaves them. Subscription25 terminates
        // a contract (and its contract products) right away on any save with a termination date in the past - yesterday,
        // today - 7, or first a future date and then moving it back alike - so the dates are in the future and the batch
        // checks 7 days ahead in a test run: 'expired' (in 6 days) counts as expired, 'endsInAWeek' (in 7 days) does not
        contracts[0].Status = 'Closed';
        contracts[0].Subscription25__Termination_Date__c = Date.today().addDays(6);
        contracts[1].Status = 'Closed';
        contracts[1].Subscription25__Termination_Date__c = Date.today().addDays(7);
        Database.update(contracts, AccessLevel.SYSTEM_MODE);

        Database.insert(new Subscription25__Schedulable_Class__c(
            Name = 'Batch_TerminateExcludedAdminContracts',
            Subscription25__Unique_Name__c = 'Batch_TerminateExcludedAdminContracts'
        ), AccessLevel.SYSTEM_MODE);
    }

    private static Map<String, String> statusByName() {
        Map<String, String> result = new Map<String, String>();
        for (Contract contr : [SELECT Name, Status FROM Contract]) {
            result.put(contr.Name, contr.Status);
        }
        return result;
    }

    // ── an expired Closed contract in an excluded administration is terminated ──
    @IsTest
    static void testTerminatesExpiredInExcludedAdministration() {
        System.assertEquals(2, [SELECT COUNT() FROM Contract WHERE Status = 'Closed'], 'Both Closed before the run');

        Test.startTest();
        Database.executeBatch(new Batch_TerminateExcludedAdminContracts());
        Test.stopTest();

        Map<String, String> status = statusByName();
        System.assertEquals('Terminated', status.get('expired'), 'Termination date passed');
        System.assertEquals('Closed', status.get('endsInAWeek'), 'Termination date not passed yet: still running');
        // Subscription25 terminates the contract products with the contract only once their (real) termination date has passed,
        // which a test can't reach - the contract-level update is what the batch is responsible for
        System.assertEquals(0, [SELECT COUNT() FROM Event_Log__c], 'Nothing failed');
    }

    // ── administrations the package jobs do process are left to Job_ContractManagement ──
    @IsTest
    static void testSkipsAdministrationNotExcluded() {
        Subscription25__Administration__c admin = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Database.update(new Subscription25__Administration__c(Id = admin.Id, Subscription25__Exclude_From_Jobs__c = false), AccessLevel.SYSTEM_MODE);

        Test.startTest();
        Database.executeBatch(new Batch_TerminateExcludedAdminContracts());
        Test.stopTest();

        System.assertEquals('Closed', statusByName().get('expired'), 'Not excluded from the jobs: left to the package');
    }

    @IsTest
    static void testGetBatchSize() {
        System.assertEquals(50, new Batch_TerminateExcludedAdminContracts().getBatchSize());
    }

    // ── a DML failure is logged, not silently dropped ──
    @IsTest
    static void testLogsFailure() {
        Contract existing = [SELECT Id FROM Contract WHERE Name = 'expired'];
        Id deletedId = existing.Id;
        delete [SELECT Id FROM Subscription25__Contract_Product__c WHERE Subscription25__Contract__c = :deletedId];
        Database.delete(existing, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        new Batch_TerminateExcludedAdminContracts().executeBatch(null, new List<SObject>{ new Contract(Id = deletedId) });
        Test.stopTest();

        List<Event_Log__c> logs = [SELECT Message__c, Result_Status__c FROM Event_Log__c];
        System.assertEquals(1, logs.size(), 'Failure to terminate is logged');
        System.assertEquals(Util_Event.LogResultStatus.ERROR.name(), logs[0].Result_Status__c);
        System.assert(logs[0].Message__c.contains(String.valueOf(deletedId)), 'Log names the failed Contract');
    }

    // ── finishBatch hands off to the dispatcher, a no-op as the last step of a round ──
    @IsTest
    static void testFinishBatchIsNoOpAsLastDispatcherStep() {
        Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{
            new JobDispatcherStep__mdt(Dispatcher__c = 'TestDispatcher', ApexClass__c = 'Batch_TerminateExcludedAdminContracts', Order__c = 50, IsActive__c = true)
        };

        Batch_TerminateExcludedAdminContracts batch = new Batch_TerminateExcludedAdminContracts();
        batch.setDispatcher('TestDispatcher');

        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'Batch_TerminateExcludedAdminContracts'],
            'Only the one run - last step of the dispatcher chain starts nothing further');
    }
}
