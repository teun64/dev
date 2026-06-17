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
private class Test_Rest_UpsertInstallation {

    private static testMethod void testRestUpsertInstallation(){
        String jsonString = '{"id": "3456","salesforceId": null,"platformId": 1,"accountId": 1,"startDate": 1334658609,"endDate": 1334758609,"remarks": "Stefan Nicodem","driverContactId": "5","licensePlate": "27LBL6","brand": "Seat","model": "Ibiza","chassisNumber": "VSSZZZ6JZAR125529","scmCertificate": null,"hardwareId": "123","hardwareSerial": "Mi00000D","installationDate": 1334656628,"dealerContactId": "2","dealerAccountId": "1","isAlarmContactRequired": true,"lastModificationDate": 1445843865, "hasActiveIncident": true}';
   
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        Util_Rest.RestResult restResult = Rest_UpsertInstallation.handleAction();
        Test.stopTest();

        System.assertEquals(3, [SELECT Count() FROM Asset]); //1 from JSON; 2 from @testsetup
    }

    @testSetup
    private static void testSetup(){
        Account dealerAcc = Test_Data.createAccount('Dealer', '1', 'B2B', false);
        Database.insert(dealerAcc);
        Product2 hwProd = Test_Data.createProduct('Mi50 (43)', '', '43-hw-1', 'Platform', false);
        Database.insert(hwProd);

        Database.insert(new Contact(FirstName = 'test', LastName = 'dealer', AccountId = dealerAcc.Id, Email = 'test1@test1.nl', extId_1__c = '1', Is_Active__c = true));
        Database.insert(new Contact(FirstName = 'test', AccountId = dealerAcc.Id, LastName = 'Driver', Email = 'test@test2.nl', extId_1__c = '2', Is_Active__c = true));
        Database.insert(new Asset(Name = 'testAsset', AccountId = dealerAcc.Id, extID__c = '123-hw-1', Product2Id = hwProd.Id, RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Hardware').getRecordTypeId()));
        Database.insert(new Asset(Name = 'testAssetEntity', AccountId = dealerAcc.Id, extID__c = '7587-in-1', RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Entity').getRecordTypeId()));
    }
}