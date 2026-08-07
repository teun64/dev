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
    
    private static testMethod void testFirstOrderNegativeAdvanceScenario(){
        //real payload captured from prod for account 14779 (DE.Professional / hardware 165810), second hardware
        //unit for the same account/contract-setup as the reported invoice-date bug.
        //NOTE: FirstInvoiceDate changed from the real "2026-07-01" (before Startdate) to "2026-07-16" (after Startdate) -
        //dev runs Subscription25 package v2.67.0.1 (prod is on v2.66.0.1), which added a validation rejecting a
        //First_Invoice_Date before the contract StartDate; that's exactly the malformed combination that caused this
        //bug in the first place; the underlying invoice-date math this test exercises is unaffected by that field
        String jsonString = '{"PlatformId":2,"AccountId":"14779","InstallationId":null,"HardwareId":"165810","ContractId":null,"Startdate":"2026-07-15","Enddate":null,"ServiceEndDate":null,"NextProlongationDate":null,"PeriodStartDate":null,"PriceExclVat":null,"UnitPrice":9.500,"PriceNet":null,"PeriodInMonths":12,"ContractTerm":12,"ProlongationPeriod":12,"RenewalTerm":12,"NoticeTerm":null,"ArticleNumber":"DE.Professional","IsBaseService":true,"CancellationReason":null,"CancellationRemark":null,"CancellationByEmail":null,"CancellationNewCustomerEmail":null,"CancellationWithLoginAs":false,"IsPaid":false,"CreditFromDate":null,"ContractEndDate":null,"ArticleId":"200","ProductId":"200","PromotionCode":null,"PartnerCode":null,"PromotionCodeDiscountPercentage":0,"PartnerCodeDiscountPercentage":0,"ResellerId":5,"SalesChannelId":1,"OrderReference":null,"PaymentProviderReference":null,"PaymentProviderAmountPaid":0.0,"PaymentMethod":null,"Imported":false,"PurchaseOrigin":null,"Prepaid":false,"Quantity":1,"InvoicePeriod":1,"InvoiceTerm":1,"InvoiceProductName":null,"FirstInvoiceDate":"2026-07-16","Id":"h_14779_165810_daf20774","SalesforceId":null}';

        Account acct = Test_Data.createAccount('Warme-mit-Konzept GmbH', '14779', 'B2B', false);
        acct.extId_2__c = '14779';
        acct.Reseller_Name__c = '5';
        acct.Market__c = 'Fleet';
        acct.Sales_Channel__c = 'Moving Intelligence';
        acct.FinancialDebtorNumber__c = 'TEST-14779';
        Database.insert(acct);
        //rbb_Account's before-insert defaults block would otherwise overwrite these with this org's own reseller-5
        //defaults; force them to match the real account's configuration via a follow-up update
        acct.Invoice_Frequency__c = 'First of the month';
        acct.Payment_Method_Contracts__c = 'I8';
        acct.OrderOffsetTerm__c = -1;
        Database.update(acct);

        Product2 prod = Test_Data.createProduct('Professional', 'DE.Professional', '200-sv-2', 'Subscription', false);
        prod.isBaseService__c = true;
        prod.Contract_settings_from_Account__c = true;
        prod.OrderOffsetTerm__c = 0;
        Database.insert(prod);
        Test_Data.createPricebookEntry(prod.Id, 9.5, true);

        Pricebook2 pb = new Pricebook2(Name = 'Subscription - Reseller 5', Reseller__c = '5', Type__c = 'Subscriptions', IsActive = true);
        Database.insert(pb);
        Database.insert(new PricebookEntry(Product2Id = prod.Id, Pricebook2Id = pb.Id, UnitPrice = 9.5, UseStandardPrice = false, IsActive = true));

        Subscription25__Administration__c admin = new Subscription25__Administration__c(
            Name = 'Test Administration 5',
            Reseller__c = '5',
            External_ID__c = 5,
            Subscription25__Default__c = true,
            Subscription25__Billing_Country__c = 'Germany',
            Subscription25__Invoice_Number_Prefix__c = 'TS5',
            Subscription25__Active__c = true
        );
        Database.insert(admin);

        Subscription25__VATRate__c vr = new Subscription25__VATRate__c(Name = '19 - Test', Subscription25__Hide_On_Invoice__c = false, Subscription25__Default__c = true, Subscription25__Active__c = true, Subscription25__VAT_Percentage__c = 19.0);
        Database.insert(vr);
        Database.insert(new Subscription25__VAT_Code__c(Subscription25__Administration__c = admin.Id, Subscription25__VATRate__c = vr.Id, Subscription25__VAT_Code__c = 'A0'));
        Database.insert(new Subscription25__Administration_Product__c(
            Subscription25__Administration__c = admin.id,
            Subscription25__Product__c = prod.id,
            Subscription25__Ledger_Account__c = '13100',
            Subscription25__Ledger_Account_EU__c = '13200',
            Subscription25__Ledger_Account_Non_EU__c = '13300',
            Subscription25__VATRate__c = vr.ID,
            Subscription25__VATRate_EU__c = vr.ID,
            Subscription25__VATRate_Non_EU__c = vr.ID
        ));

        Test.startTest();
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);
        Util_Rest.RestResult result = Rest_UpsertContract.handleAction();
        Test.stopTest();

        System.assertEquals(true, result.success, String.join(result.messages, '; '));

        Contract cont = [SELECT Id, StartDate, Subscription25__Months_In_Advance__c, Subscription25__First_Invoice_Date__c, Is_Imported__c FROM Contract WHERE extId__c = 'h_14779_165810_daf20774-2'];
        System.assertEquals(Date.newInstance(2026, 7, 15), cont.StartDate);
        System.assertEquals(-1, cont.Subscription25__Months_In_Advance__c);
        System.assertEquals(Date.newInstance(2026, 7, 16), cont.Subscription25__First_Invoice_Date__c);

        Subscription25__Contract_Product__c contProd = [SELECT Id, Subscription25__Start_Date__c FROM Subscription25__Contract_Product__c WHERE extId__c = 'h_14779_165810_daf20774-2'];

        //the recurring order + 1st order are normally created by the Subscription25 package's own batch off the
        //contract/contract product this payload just produced; simulate that step to exercise the (fixed) Trigger_Order
        Subscription25__Recurring_Order__c recOrder = new Subscription25__Recurring_Order__c(
            Subscription25__Account__c = acct.Id,
            Subscription25__Administration__c = admin.Id,
            Subscription25__Contract_Product__c = contProd.Id,
            Subscription25__Period__c = 1,
            Subscription25__Start_Date__c = contProd.Subscription25__Start_Date__c,
            Subscription25__Months_In_Advance__c = cont.Subscription25__Months_In_Advance__c
        );
        Database.insert(recOrder);

        Order firstOrd = Test_Data.createOrder(acct.Id, admin.Id, contProd.Subscription25__Start_Date__c, false);
        firstOrd.Type = 'Contract';
        firstOrd.EndDate = Date.newInstance(2026, 7, 31);
        firstOrd.Subscription25__Recurring_Order__c = recOrder.Id;
        //mirrors what the package itself sets before Trigger_Order runs, confirmed against real prod data for this account
        firstOrd.Subscription25__Invoice_Date__c = Date.newInstance(2026, 8, 15);
        Database.insert(firstOrd);

        firstOrd = [SELECT Subscription25__Invoice_Date__c FROM Order WHERE Id = :firstOrd.Id];
        System.assertEquals(Date.newInstance(2026, 8, 1), firstOrd.Subscription25__Invoice_Date__c);
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