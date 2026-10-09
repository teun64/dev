@isTest
private class Test_Rest_UpsertContract {

    private static testMethod void testRestUpsertContract(){
        String jsonString1 = '{"id":"138532","platformId": 1,"accountId":"1","installationId":"7587","productId":"9999392","startDate":"2022-01-10","serviceEndDate":"2027-01-09","salesforceId":null,"quantity":1,"unitPrice":25.0,"contractTerm":36,"renewalTerm":12,"noticeTerm":12,"orderOffsetTerm":-1,"invoicePeriod":12,"firstInvoiceDate":null,"isBaseService":true,"cancellationReason":null,"cancellationRemark":null,"cancellationByEmail":null,"cancellationNewCustomerEmail":null,"cancellationWithLoginAs":null,"prepaid":true,"contractEndDate":"2027-01-09","orderReference":"1-orderReference"}';
        String jsonString2 = '{"id":"138532","platformId": 1,"accountId":"1","installationId":"7587","productId":"9999392","startDate":"2022-01-10","serviceEndDate":"2027-01-09","salesforceId":null,"quantity":1,"unitPrice":25.0,"contractTerm":36,"renewalTerm":12,"noticeTerm":12,"orderOffsetTerm":-1,"invoicePeriod":12,"firstInvoiceDate":null,"isBaseService":true,"cancellationReason":null,"cancellationRemark":null,"cancellationByEmail":null,"cancellationNewCustomerEmail":null,"cancellationWithLoginAs":null,"prepaid":true,"contractEndDate":"2027-01-09","orderReference":"1-orderReference"}';
        String jsonString3 = '{""}';
        //String jsonString = '{"id":"138532","accountId":"1","installationId":"7587","startdate":"2010-12-10","enddate":"2012-01-25","nextProlongationDate":"2012-12-10","periodStartDate":"2010-12-10","salesforceId":null,"priceExclVat":193.2,"periodInMonths":24,"prolongationPeriod":12,"isBaseService":true,"cancellationReason":null,"cancellationRemark":null,"cancellationByEmail":null,"cancellationNewCustomerEmail":null,"cancellationWithLoginAs":null,"isPaid":false,"creditFromDate":null,"articleId":9999392,"promotionCode":null,"promotionCodeDiscountPercentage":null,"resellerId":1,"platformId":1,"priceNet":0.0}';

        
        Product2 pr = Test_Data.createProduct('MiBlack', 'Tst.Black.12', '9999392-sv-1', 'Subscription', false);
        pr.contractTerm__c = 12;
        pr.renewalTerm__c = 12;
        pr.Invoice_Period__c = '0';
        
        Database.insert(pr);
        PricebookEntry pbs = Test_Data.CreatePricebookEntry(pr.id, 8.95, false);
        Database.insert(pbs);
        Pricebook2 pb = new Pricebook2(Name = 'Subscription - Test', Reseller__c = '1', Type__c = 'Subscriptions', IsActive = true);
        Database.insert(pb);        
        PricebookEntry pbe = new PricebookEntry(Product2Id = pr.id, Pricebook2Id = pb.Id, Unitprice = 21, UseStandardPrice = false, Isactive = true);
        Database.insert(pbe);

        //add administration       
        Subscription25__Administration__c adm1 = new Subscription25__Administration__c(
            Name = 'Test Administration 1', 
            Reseller__c = '1', 
            External_ID__c = 1, 
            Subscription25__Default__c = true, 
            Subscription25__Billing_Country__c = 'Netherlands', 
            Subscription25__Invoice_Number_Prefix__c = 'TS1',
            Subscription25__Active__c = true
        );
        Database.insert(adm1);

        Subscription25__Administration__c adm4 = new Subscription25__Administration__c(
            Name = 'Test Administration 0', 
            Reseller__c = '0', 
            External_ID__c = 0, 
            Subscription25__Default__c = true, 
            Subscription25__Billing_Country__c = 'Netherlands', 
            Subscription25__Invoice_Number_Prefix__c = 'TS0',
            Subscription25__Active__c = true
        );
        Database.insert(adm4);
        //add administration       
        Subscription25__VATRate__c vr = new Subscription25__VATRate__c(Name = '0 - Test', Subscription25__Hide_On_Invoice__c = false, Subscription25__Default__c = true, Subscription25__Active__c = true, Subscription25__VAT_Percentage__c = 21.0);
        Database.insert(vr);
 
        Subscription25__VAT_Code__c  vc1 = new Subscription25__VAT_Code__c (Subscription25__Administration__c = adm1.Id, Subscription25__VATRate__c = vr.Id, Subscription25__VAT_Code__c = 'A0' );
        Database.insert(vc1);
        Subscription25__VAT_Code__c  vc4 = new Subscription25__VAT_Code__c (Subscription25__Administration__c = adm4.Id, Subscription25__VATRate__c = vr.Id, Subscription25__VAT_Code__c = 'A0' );
        Database.insert(vc4);
        
        //add administrationproduct
        Subscription25__Administration_Product__c apr1 = new Subscription25__Administration_Product__c(
            Subscription25__Administration__c = adm1.id, 
            Subscription25__Product__c = pr.id, 
            Subscription25__Ledger_Account__c = '13100', 
            Subscription25__Ledger_Account_EU__c = '13200', 
            Subscription25__Ledger_Account_Non_EU__c = '13300', 
            Subscription25__VATRate__c = vr.ID,
            Subscription25__VATRate_EU__c = vr.ID,
            Subscription25__VATRate_Non_EU__c = vr.ID          
        );
        Database.insert(apr1);

        Subscription25__Administration_Product__c apr2 = new Subscription25__Administration_Product__c(
            Subscription25__Administration__c = adm4.id, 
            Subscription25__Product__c = pr.id, 
            Subscription25__Ledger_Account__c = '13100', 
            Subscription25__Ledger_Account_EU__c = '13200', 
            Subscription25__Ledger_Account_Non_EU__c = '13300', 
            Subscription25__VATRate__c = vr.ID,
            Subscription25__VATRate_EU__c = vr.ID,
            Subscription25__VATRate_Non_EU__c = vr.ID          
        );
        Database.insert(apr2);
       
        Test.startTest();
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString1);
        Util_Rest.RestResult restResult1 = Rest_UpsertContract.handleAction();
        // simulate the update situation by running it again
        //Util_Rest.RestResult restResult2 = Rest_UpsertContract.handleAction();
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString2);
        Util_Rest.RestResult restResult3 = Rest_UpsertContract.handleAction();
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString3);
        try {
            Util_Rest.RestResult restResult4 = Rest_UpsertContract.handleAction();
        } catch(Exception e){
            system.debug(e);
        }

        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM Contract]); //1 from JSON
        System.assertEquals(1, [SELECT Count() FROM Subscription25__Contract_Product__c]); //1 from JSON
        //System.assertEquals(1, [SELECT Count() FROM Contractor_Service__c]); //1 from JSON
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