@IsTest
private class Test_Batch_ActivateDraftContractProducts {

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
        Product2 prod = Test_Data.createProduct('Test Product', 'test-prod-1', '1-sv-1', 'Subscription', true);
        Test_Data.createPricebookEntry(prod.Id, 100, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('21%', 21, true, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vatRate.Id, true);

        Account withDebtor = Test_Data.createAccount('Activate With Debtor BV', '9051', 'B2B', true);
        withDebtor.FinancialDebtorNumber__c = '12345';
        update withDebtor;

        Account withoutDebtor = Test_Data.createAccount('Activate Without Debtor BV', '9052', 'B2B', true);

        Contract contWithDebtor = Test_Data.createContract(withDebtor.Id, admin.Id, true);
        Subscription25__Contract_Product__c cpWithDebtor = Test_Data.createContractProduct(contWithDebtor.Id, prod.Id, false);
        cpWithDebtor.Subscription25__Status__c = 'Draft';
        insert cpWithDebtor;

        Contract contWithoutDebtor = Test_Data.createContract(withoutDebtor.Id, admin.Id, true);
        Subscription25__Contract_Product__c cpWithoutDebtor = Test_Data.createContractProduct(contWithoutDebtor.Id, prod.Id, false);
        cpWithoutDebtor.Subscription25__Status__c = 'Draft';
        insert cpWithoutDebtor;

        Database.insert(new Subscription25__Schedulable_Class__c(
            Name = 'Batch_ActivateDraftContractProducts',
            Subscription25__Unique_Name__c = 'Batch_ActivateDraftContractProducts'
        ), AccessLevel.SYSTEM_MODE);
    }

    // ── a Draft Contract Product on an Account with a debtor number gets Activated ──
    @IsTest
    static void testActivatesWhenDebtorNumberPresent() {
        Subscription25__Contract_Product__c before = [
            SELECT Id FROM Subscription25__Contract_Product__c
            WHERE Subscription25__Contract__r.Account.FinancialDebtorNumber__c = '12345'
        ];

        Test.startTest();
        Database.executeBatch(new Batch_ActivateDraftContractProducts());
        Test.stopTest();

        Subscription25__Contract_Product__c updated = [SELECT Subscription25__Status__c FROM Subscription25__Contract_Product__c WHERE Id = :before.Id];
        System.assertEquals('Activated', updated.Subscription25__Status__c, 'Activated once its Account has a debtor number');
    }

    // ── a Draft Contract Product on an Account without a debtor number is left alone, not logged ──
    @IsTest
    static void testSkipsWhenNoDebtorNumber() {
        Subscription25__Contract_Product__c before = [
            SELECT Id FROM Subscription25__Contract_Product__c
            WHERE Subscription25__Contract__r.Account.Name = 'Activate Without Debtor BV'
        ];

        Test.startTest();
        Database.executeBatch(new Batch_ActivateDraftContractProducts());
        Test.stopTest();

        Subscription25__Contract_Product__c updated = [SELECT Subscription25__Status__c FROM Subscription25__Contract_Product__c WHERE Id = :before.Id];
        System.assertEquals('Draft', updated.Subscription25__Status__c, 'Left Draft - no debtor number yet, recurs every run until the Account has one');
        System.assertEquals(0, [SELECT COUNT() FROM Event_Log__c], 'Deliberately not logged - would flood Event_Log__c every run for the same backlog');
    }

    // ── finishBatch hands off to the dispatcher via Util_JobDispatcher.startNext, and is a
    // harmless no-op as the last (or only) step of a round ──
    @IsTest
    static void testFinishBatchIsNoOpAsLastDispatcherStep() {
        Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{
            new JobDispatcherStep__mdt(Dispatcher__c = 'TestDispatcher', ApexClass__c = 'Batch_ActivateDraftContractProducts', Order__c = 20, IsActive__c = true)
        };

        Batch_ActivateDraftContractProducts batch = new Batch_ActivateDraftContractProducts();
        batch.setDispatcher('TestDispatcher');

        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'Batch_ActivateDraftContractProducts'],
            'Only the one run - last step of the dispatcher chain starts nothing further');
    }
}
