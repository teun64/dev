/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class Test_OfferPDF {

    @IsTest
    private static void test_Ctrl_OfferPDF(){
        List<Account> accs = Test_Data.generateAccounts(true, 1, 'B2C');
        List<Opportunity> opps = Test_Data.generateOpportunities(true, 1, accs[0].Id, 'Offer' , Date.today().addDays(10));
        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, accs[0].Id, true);
        PageReference pageRef = new PageReference('/apex/OfferPDF?renderType=PDF&amp;id=' + opps[0].Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('id', opps[0].Id);
        ApexPages.StandardController sc = new ApexPages.StandardController(opps[0]);
        Ctrl_OfferPDF contr = new Ctrl_OfferPDF(sc);

        test.startTest();
        contr.getOfferSubscriptions();
        contr.getLanguage();
        contr.getOfferSections();
        contr.getOfferTerms();
        contr.getTest();
        test.stopTest();
    }
}