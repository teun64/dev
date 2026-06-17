@isTest
private class Test_Rest_UpsertHardware {

    private static testMethod void testRestUpsertHardware(){
        String jsonString = '{"id": "3456","salesforceId": "02i3W000002S9M8QAK","serial": "Mi064394","scmLabel": "RS0007916","accessories": null,"currentFirmwareVersion": "1757","simState": "active/live","simCoverage": "2019_0.75MB_EU_90128","hardwareTypeId": "43","pcb": "MK3","bluetooth": false,"modem": "1","hardwareStatus": "Uitlevering","hardwareStatusId": "8","dealerAccountId": "1","activationCode": null,"activationCodeUsedDate": null,"activationCodeCustomerEmail": null,"sentForDeliveryDate": 1630401612,"installationDate": null,"licensePlate": null,"chassisNumber": null,"sentForDeliveryAccountId": "1","firstInstallationDate": null,"firstInstallationAccountId": null,"sentForDeliveryType": "Sales","firstDeliveryDate": 1630401612,"firstDeliveryAccountId": "1","firstDeliveryType": "Sales","lastDealerTaskWithLoginAs": false,"platformId": 1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        Util_Rest.RestResult restResult = Rest_UpsertHardware.handleAction();
        Test.stopTest();

        System.assertEquals(3, [SELECT Count() FROM Asset]); //1 from JSON; 2 from @testSetup
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