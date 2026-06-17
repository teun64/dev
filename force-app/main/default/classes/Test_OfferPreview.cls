@isTest
private class Test_OfferPreview {

    @isTest
    private static void test_Ctrl_OfferPreview(){
        List<Account> accs = Test_Data.generateAccounts(true, 1, 'B2C');
        List<Opportunity> opps = Test_Data.generateOpportunities(true, 1, accs[0].Id, 'Offer' , Date.today().addDays(10));

        Test.startTest();
        Ctrl_OfferPreview.handleSave(opps[0].Id);
        Ctrl_OfferPreview.handleSign(opps[0].Id);
        Test.stopTest();

        System.assertEquals(2, [SELECT Count() FROM ContentDocument]);
        System.assertEquals(2, [SELECT Count() FROM ContentDocumentLink WHERE LinkedEntityId = :opps[0].Id]);
    }
}