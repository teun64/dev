/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_Subscription25_InvoiceTest
{
    @IsTest
    private static void testTrigger()
    {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Subscription25__Invoice__c inv = Test_data.createInvoice(admin.Id, acct.Id, 'Draft', true);

        // Force the dlrs_Subscription25_InvoiceTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(inv);
    }
}