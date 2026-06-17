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
private class Test_Inv_getPaymentProviderConstant {

    @isTest
    static void TestGetPaymentProviderConstant() {
        Inv_getPaymentProviderConstant.ppConstantRequest inp1 = new Inv_getPaymentProviderConstant.ppConstantRequest();
        inp1.ppConstantKey = 'AccountIdKey';
        list<Inv_getPaymentProviderConstant.ppConstantRequest> inpList1 = new list<Inv_getPaymentProviderConstant.ppConstantRequest>();
        inpList1.add(inp1);
        Inv_getPaymentProviderConstant.ppConstantRequest inp2 = new Inv_getPaymentProviderConstant.ppConstantRequest();
        inp2.ppConstantKey = 'AccountIdKey';
        list<Inv_getPaymentProviderConstant.ppConstantRequest> inpList2 = new list<Inv_getPaymentProviderConstant.ppConstantRequest>();
        inpList2.add(inp2);
        Inv_getPaymentProviderConstant.ppConstantRequest inp3 = new Inv_getPaymentProviderConstant.ppConstantRequest();
        inp3.ppConstantKey = 'NoneIdKey';
        list<Inv_getPaymentProviderConstant.ppConstantRequest> inpList3 = new list<Inv_getPaymentProviderConstant.ppConstantRequest>();
        inpList3.add(inp3);

        Test.startTest();
        // error sign no document / not ready
        List<Inv_getPaymentProviderConstant.ppConstantResult> resList1 = Inv_getPaymentProviderConstant.getPaymentProviderConstant(inpList1);
        list<Inv_getPaymentProviderConstant.ppConstantResult> resList2 = Inv_getPaymentProviderConstant.getPaymentProviderConstant(inpList2);
        list<Inv_getPaymentProviderConstant.ppConstantResult> resList3 = Inv_getPaymentProviderConstant.getPaymentProviderConstant(inpList3);
        Test.stopTest();

        System.assertEquals(resList1[0].ppConstantValue, resList2[0].ppConstantValue);  
        System.assertEquals(null, resList3[0].ppConstantValue);  
    }
}