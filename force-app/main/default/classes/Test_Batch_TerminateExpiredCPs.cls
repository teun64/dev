@IsTest
private class Test_Batch_TerminateExpiredCPs {

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
        Product2 prod = Test_Data.createProduct('Partner code', 'test-prod-1', '1-sv-1', 'Handling', false);
        prod.Is_Partner_Code__c = true;
        insert prod;
        Product2 otherProd = Test_Data.createProduct('Activation Fee', 'test-prod-2', '2-sv-1', 'Handling', true);
        Test_Data.createPricebookEntry(prod.Id, 100, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('21%', 21, true, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vatRate.Id, true);
        Test_Data.createPricebookEntry(otherProd.Id, 100, true);
        Test_Data.createAdministrationProduct(admin.Id, otherProd.Id, vatRate.Id, true);

        Account acct = Test_Data.createAccount('Terminate Expired BV', '9061', 'B2B', true);
        // contract products on an active contract require the account to be known in the administration
        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);
        Contract contr = Test_Data.createContract(acct.Id, admin.Id, false);
        contr.StartDate = Date.today().addYears(-1);
        Database.insert(contr, AccessLevel.SYSTEM_MODE);
        contr.Status = 'Activated';
        Database.update(contr, AccessLevel.SYSTEM_MODE);

        Subscription25__Contract_Product__c expired = Test_Data.createContractProduct(contr.Id, prod.Id, false);
        expired.Subscription25__Start_Date__c = contr.StartDate;
        expired.Subscription25__Description__c = 'expired';

        Subscription25__Contract_Product__c endsTomorrow = Test_Data.createContractProduct(contr.Id, prod.Id, false);
        endsTomorrow.Subscription25__Start_Date__c = contr.StartDate;
        endsTomorrow.Subscription25__Description__c = 'endsTomorrow';
        Subscription25__Contract_Product__c otherExpired = Test_Data.createContractProduct(contr.Id, otherProd.Id, false);
        otherExpired.Subscription25__Start_Date__c = contr.StartDate;
        otherExpired.Subscription25__Description__c = 'otherExpired';
        Database.insert(new List<Subscription25__Contract_Product__c>{ expired, endsTomorrow, otherExpired }, AccessLevel.SYSTEM_MODE);

        // Closed with a termination date, as the platform/Rest_UpsertContract leaves them. Subscription25 terminates a contract
        // product saved Closed with a date in the past right away, so 'expired' ends today and the batch runs as of tomorrow
        expired.Subscription25__Status__c = 'Closed';
        expired.Subscription25__Termination_Date__c = Date.today();
        endsTomorrow.Subscription25__Status__c = 'Closed';
        endsTomorrow.Subscription25__Termination_Date__c = Date.today().addDays(1);
        otherExpired.Subscription25__Status__c = 'Closed';
        otherExpired.Subscription25__Termination_Date__c = Date.today();
        Database.update(new List<Subscription25__Contract_Product__c>{ expired, endsTomorrow, otherExpired }, AccessLevel.SYSTEM_MODE);

        Database.insert(new Subscription25__Schedulable_Class__c(
            Name = 'Batch_TerminateExpiredContractProducts',
            Subscription25__Unique_Name__c = 'Batch_TerminateExpiredContractProducts'
        ), AccessLevel.SYSTEM_MODE);
    }

    private static Subscription25__Contract_Product__c cp(Date terminationDate, String contractStatus, Date contractTerminationDate) {
        return new Subscription25__Contract_Product__c(
            Subscription25__Termination_Date__c = terminationDate,
            Subscription25__Contract__r = new Contract(Status = contractStatus, Subscription25__Termination_Date__c = contractTerminationDate));
    }

    // ── which Closed contract products count as expired ──
    @IsTest
    static void testIsExpired() {
        Date today = Date.today();
        Date yesterday = today.addDays(-1);
        System.assert(Batch_TerminateExpiredContractProducts.isExpired(cp(yesterday, 'Activated', null), today), 'A: Activated contract without termination date');
        System.assert(!Batch_TerminateExpiredContractProducts.isExpired(cp(yesterday, 'Activated', today.addDays(30)), today), 'Activated contract with a termination date: left alone');
        System.assert(Batch_TerminateExpiredContractProducts.isExpired(cp(yesterday, 'Closed', today.addDays(30)), today), 'B: Closed contract ending later');
        System.assert(!Batch_TerminateExpiredContractProducts.isExpired(cp(yesterday, 'Closed', yesterday), today), 'Closed contract ending the same day: left to the package');
        System.assert(!Batch_TerminateExpiredContractProducts.isExpired(cp(yesterday, 'Closed', yesterday.addDays(-1)), today), 'Closed contract ending earlier: left to the package');
        System.assert(!Batch_TerminateExpiredContractProducts.isExpired(cp(yesterday, 'Terminated', yesterday), today), 'Terminated contract: left to the package');
        System.assert(!Batch_TerminateExpiredContractProducts.isExpired(cp(today, 'Activated', null), today), 'Ends today: still running');
        System.assert(!Batch_TerminateExpiredContractProducts.isExpired(cp(null, 'Activated', null), today), 'No termination date');
    }

    // ── the batch terminates the expired Partner code line, leaves the one still running and other products ──
    @IsTest
    static void testTerminatesExpired() {
        System.assertEquals(3, [SELECT COUNT() FROM Subscription25__Contract_Product__c WHERE Subscription25__Status__c = 'Closed'], 'All Closed before the run');

        Batch_TerminateExpiredContractProducts batch = new Batch_TerminateExpiredContractProducts();
        batch.referenceDate = Date.today().addDays(1);

        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        Map<String, String> statusByDescription = new Map<String, String>();
        for (Subscription25__Contract_Product__c c : [SELECT Subscription25__Description__c, Subscription25__Status__c FROM Subscription25__Contract_Product__c]) {
            statusByDescription.put(c.Subscription25__Description__c, c.Subscription25__Status__c);
        }
        System.assertEquals('Terminated', statusByDescription.get('expired'), 'Termination date passed on an Activated contract');
        System.assertEquals('Closed', statusByDescription.get('endsTomorrow'), 'Termination date not passed yet: still running');
        System.assertEquals('Closed', statusByDescription.get('otherExpired'), 'Not a Partner code product: left to the package');
        System.assertEquals(0, [SELECT COUNT() FROM Event_Log__c], 'Nothing failed');
    }

    @IsTest
    static void testGetBatchSize() {
        System.assertEquals(100, new Batch_TerminateExpiredContractProducts().getBatchSize());
    }

    // ── a DML failure is logged, not silently dropped ──
    @IsTest
    static void testLogsFailure() {
        Subscription25__Contract_Product__c existing = [SELECT Id FROM Subscription25__Contract_Product__c WHERE Subscription25__Description__c = 'expired'];
        Id deletedId = existing.Id;
        delete existing;

        // a stale scope row (as if queried before the delete) - the update on it now fails
        Subscription25__Contract_Product__c staleRow = cp(Date.today().addDays(-1), 'Activated', null);
        staleRow.Id = deletedId;

        Test.startTest();
        new Batch_TerminateExpiredContractProducts().executeBatch(null, new List<SObject>{ staleRow });
        Test.stopTest();

        List<Event_Log__c> logs = [SELECT Message__c, Result_Status__c FROM Event_Log__c];
        System.assertEquals(1, logs.size(), 'Failure to terminate is logged');
        System.assertEquals(Util_Event.LogResultStatus.ERROR.name(), logs[0].Result_Status__c);
        System.assert(logs[0].Message__c.contains(String.valueOf(deletedId)), 'Log names the failed Contract Product');
    }

    // ── finishBatch hands off to the dispatcher, a no-op as the last step of a round ──
    @IsTest
    static void testFinishBatchIsNoOpAsLastDispatcherStep() {
        Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{
            new JobDispatcherStep__mdt(Dispatcher__c = 'TestDispatcher', ApexClass__c = 'Batch_TerminateExpiredContractProducts', Order__c = 40, IsActive__c = true)
        };

        Batch_TerminateExpiredContractProducts batch = new Batch_TerminateExpiredContractProducts();
        batch.setDispatcher('TestDispatcher');

        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'Batch_TerminateExpiredContractProducts'],
            'Only the one run - last step of the dispatcher chain starts nothing further');
    }
}
