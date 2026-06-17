@isTest
public with sharing class Test_Rest_Contract {

    static testMethod void testRestContract(){
        //ARRANGE - setup request like the external system would....
        RestRequest req = new RestRequest(); 
        RestResponse res = new RestResponse();
        //req.requestURI = 'https://movingintelligence--acc.sandbox.lightning.force.com/services/apexrest/contract?entity=9906915&platform=1';
        req.requestURI = './services/apexrest/contract?entity=9906915&platform=1';
    
        //req.addHeader('Content-Type', 'application/json');
        req.httpMethod = 'GET';
        req.requestBody = Blob.valueof('{}');
    
        RestContext.request = req;
        RestContext.response= res;
        
        //ACT - make the request from inside the test execution context, rather than from the external system
        Test.startTest();
        Util_Rest.AbstractRestResult restResult = Rest_Contract.handleAction();
        //Rest_Contract.CorrectionResponse restResult = Rest_Contract.handleAction();
        Test.stopTest();

        System.assertEquals(true, restResult.success);
        //System.assertEquals(0, restResult.creditAmountNotice);
        //System.assertEquals(0, restResult.creditAmountDirect);   
    }
}