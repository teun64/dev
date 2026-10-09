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

    // ---- generic tests: keep identical in Test_Rest_UpsertContract and Test_Rest_UpsertContractV2 ----

    private static testMethod void testValidationErrors(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        Map<String, Object> noId = Test_Rest_UpsertContract.basePayload('900590', 1);
        noId.put('id', null);
        Map<String, Object> noPlatform = Test_Rest_UpsertContract.basePayload('900591', 1);
        noPlatform.put('platformId', null);
        Map<String, Object> noAccount = Test_Rest_UpsertContract.basePayload('900592', 1);
        noAccount.put('accountId', null);
        Map<String, Object> unknownAccount = Test_Rest_UpsertContract.basePayload('900593', 1);
        unknownAccount.put('accountId', '999999');
        Map<String, Object> unknownProduct = Test_Rest_UpsertContract.basePayload('900594', 1);
        unknownProduct.put('productId', '0000000');

        Test.startTest();
        for (Map<String, Object> payload : new List<Map<String, Object>>{noId, noPlatform, noAccount, unknownAccount, unknownProduct}) {
            Util_Rest.RestResult result = Test_Rest_UpsertContract.callRest(payload);
            System.assertEquals(false, result.success, String.join(result.messages, '; '));
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT Count() FROM Contract]);
    }

    private static testMethod void testTerminationIdNoCredit(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminate('900601', '1', '2026-06-30');
        System.assertEquals('No Credit', contr.Termination_Method__c);
        //terminated at the end of the current contract period
        System.assertEquals(Date.newInstance(2027, 1, 9), contr.Subscription25__Termination_Date__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Service_End_Date__c);
    }

    private static testMethod void testTerminationIdFullCredit(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminate('900602', '2', '2026-06-30');
        System.assertEquals('Full Credit', contr.Termination_Method__c);
        //first contract term: terminated the day before the start date, everything is credited
        System.assertEquals(Date.newInstance(2026, 1, 9), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationIdPartialCreditImmediate(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminate('900603', '3', '2026-06-30');
        System.assertEquals('Partial Credit Immediate', contr.Termination_Method__c);
        //terminated on the service end date
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Subscription25__Termination_Date__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Service_End_Date__c);
    }

    private static testMethod void testTerminationIdPartialCreditWithCancellationTerm(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminate('900604', '4', '2026-06-30');
        System.assertEquals('Partial Credit with Cancellation Term', contr.Termination_Method__c);
        //renewal term 12 -> service end date + 1 month cancellation term
        System.assertEquals(Date.newInstance(2026, 7, 30), contr.Subscription25__Termination_Date__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Service_End_Date__c);
    }

    private static testMethod void testTerminationIdAutoRenewalOff(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminate('900605', '5', null);
        System.assertEquals('Auto renewal off', contr.Termination_Method__c);
        //service and termination both end at the end of the current contract period
        System.assertEquals(Date.newInstance(2027, 1, 9), contr.Subscription25__Termination_Date__c);
        System.assertEquals(Date.newInstance(2027, 1, 9), contr.Service_End_Date__c);
    }

    private static testMethod void testTerminationIdReverted(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        //a revert only works while the termination date is still in the future: once it has passed the contract is
        //Terminated and the call stops early, so these dates are relative to today
        Map<String, Object> create = Test_Rest_UpsertContract.basePayload('900606', 1);
        create.put('startDate', String.valueOf(Date.today().addMonths(-1)));
        Map<String, Object> terminate = Test_Rest_UpsertContract.basePayload('900606', 1);
        terminate.put('terminationId', '3');
        terminate.put('serviceEndDate', String.valueOf(Date.today().addMonths(1)));
        terminate.put('startDate', create.get('startDate'));
        Map<String, Object> revert = Test_Rest_UpsertContract.basePayload('900606', 1);
        revert.put('startDate', create.get('startDate'));
        revert.put('terminationId', '0');

        Test.startTest();
        Util_Rest.RestResult created = Test_Rest_UpsertContract.callRest(create);
        System.assertEquals(true, created.success, String.join(created.messages, '; '));
        Util_Rest.RestResult terminated = Test_Rest_UpsertContract.callRest(terminate);
        System.assertEquals(true, terminated.success, String.join(terminated.messages, '; '));
        Util_Rest.RestResult reverted = Test_Rest_UpsertContract.callRest(revert);
        Test.stopTest();

        System.assertEquals(true, reverted.success, String.join(reverted.messages, '; '));
        //a real termination is on file, so the revert must run the full path (never skipped)
        System.assert(!String.join(reverted.messages, '; ').contains('Skipped'), String.join(reverted.messages, '; '));

        Contract contr = Test_Rest_UpsertContract.getContract('900606-1');
        System.assertEquals('Termination Reverted', contr.Termination_Method__c);
        System.assertEquals(null, contr.Subscription25__Termination_Date__c);
        System.assertEquals(null, contr.Service_End_Date__c);
    }

    // ---- termination process "terminationDate": no terminationId, the method is derived from the dates ----

    private static testMethod void testTerminationDateNoCredit(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900631', new Map<String, Object>{'serviceEndDate' => '2026-06-30', 'contractEndDate' => '2027-01-09'});
        System.assertEquals('No Credit', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2027, 1, 9), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationDateAutoRenewalOff(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900632', new Map<String, Object>{'serviceEndDate' => '2027-01-09', 'contractEndDate' => '2027-01-09'});
        System.assertEquals('Auto renewal off', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2027, 1, 9), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationDateFullCredit(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900633', new Map<String, Object>{'serviceEndDate' => '2026-06-30', 'contractEndDate' => '2026-01-09'});
        System.assertEquals('Full Credit', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2026, 1, 9), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationDatePartialCreditImmediate(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900634', new Map<String, Object>{'serviceEndDate' => '2026-06-30', 'contractEndDate' => '2026-06-30'});
        System.assertEquals('Partial Credit Immediate', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationDatePartialCreditWithCancellationTerm(){
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900635', new Map<String, Object>{'serviceEndDate' => '2026-06-30', 'contractEndDate' => '2026-07-30'});
        System.assertEquals('Partial Credit with Cancellation Term', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2026, 7, 30), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationDateFallbackFirstTerm(){
        //matches no method: never credit, No Credit on the date the contract is invoiced through
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900636', new Map<String, Object>{'serviceEndDate' => '2026-06-30', 'contractEndDate' => '2026-07-31'});
        System.assertEquals('No Credit', contr.Termination_Method__c);
        System.assertEquals(Test_Rest_UpsertContract.invoicedEndDate, contr.Subscription25__Termination_Date__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Service_End_Date__c);
    }

    private static testMethod void testTerminationDateFallbackLaterTerm(){
        //matches no method in a later contract term: also No Credit on the invoiced-through date, never a credit
        Contract contr = Test_Rest_UpsertContract.createAndTerminateByDates('900638', new Map<String, Object>{'startDate' => '2024-01-10', 'serviceEndDate' => '2026-06-20', 'contractEndDate' => '2026-06-25'});
        System.assertEquals('No Credit', contr.Termination_Method__c);
        System.assertEquals(Test_Rest_UpsertContract.invoicedEndDate, contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testTerminationDateClearedIsNoRevert(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        //a revert only works while the termination date is still in the future, so these dates are relative to today
        String startDate = String.valueOf(Date.today().addMonths(-1));
        String endDate = String.valueOf(Date.today().addMonths(1));
        Map<String, Object> create = Test_Rest_UpsertContract.basePayload('900639', 1);
        create.put('startDate', startDate);
        Map<String, Object> terminate = create.clone();
        terminate.put('serviceEndDate', endDate);
        terminate.put('contractEndDate', endDate);

        Test.startTest();
        Util_Rest.RestResult created = Test_Rest_UpsertContract.callRest(create);
        System.assertEquals(true, created.success, String.join(created.messages, '; '));
        Util_Rest.RestResult terminated = Test_Rest_UpsertContract.callRest(terminate);
        System.assertEquals(true, terminated.success, String.join(terminated.messages, '; '));
        System.assertEquals('Partial Credit Immediate', Test_Rest_UpsertContract.getContract('900639-1').Termination_Method__c);
        //no dates while a termination is on file: the termination is cleared, but it is not a revert (no credit cleanup)
        Util_Rest.RestResult reverted = Test_Rest_UpsertContract.callRest(create);
        Test.stopTest();

        System.assertEquals(true, reverted.success, String.join(reverted.messages, '; '));
        Contract contr = Test_Rest_UpsertContract.getContract('900639-1');
        System.assertEquals(null, contr.Termination_Method__c);
        System.assertEquals(null, contr.Subscription25__Termination_Date__c);
        System.assertEquals(null, contr.Service_End_Date__c);
    }

    // ---- multiple base services on one contract ----

    private static testMethod void testOtherBaseServiceBlocksTerminationId(){
        Test_Rest_UpsertContract.assertOnlyProductTerminated(new Map<String, Object>{'terminationId' => '3', 'serviceEndDate' => '2026-06-30'});
    }

    private static testMethod void testOtherBaseServiceBlocksTerminationDate(){
        Test_Rest_UpsertContract.assertOnlyProductTerminated(new Map<String, Object>{'serviceEndDate' => '2026-06-30', 'contractEndDate' => '2026-06-30'});
    }

    private static testMethod void testLastBaseServiceTerminatesContract(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();
        //test contract products stay Draft, let Draft count as Activated here
        Rest_UpsertContract.activeBaseServiceStatuses = new Set<String>{'Activated', 'Draft'};

        Test.startTest();
        Test_Rest_UpsertContract.createTwoBaseServices('900643', '900644');
        Map<String, Object> terminateFirst = Test_Rest_UpsertContract.baseServicePayload('900643', '900643');
        terminateFirst.putAll(new Map<String, Object>{'terminationId' => '3', 'serviceEndDate' => '2026-06-30'});
        Util_Rest.RestResult first = Test_Rest_UpsertContract.callRest(terminateFirst);
        System.assertEquals(true, first.success, String.join(first.messages, '; '));
        Map<String, Object> terminateLast = Test_Rest_UpsertContract.baseServicePayload('900644', '900643');
        terminateLast.putAll(new Map<String, Object>{'terminationId' => '3', 'serviceEndDate' => '2026-07-31'});
        Util_Rest.RestResult last = Test_Rest_UpsertContract.callRest(terminateLast);
        Test.stopTest();

        System.assertEquals(true, last.success, String.join(last.messages, '; '));
        //no other active base service left: the contract is terminated as before
        Contract contr = Test_Rest_UpsertContract.getContract('900643-1');
        System.assertEquals('Partial Credit Immediate', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2026, 7, 31), contr.Subscription25__Termination_Date__c);
    }

    private static testMethod void testDraftBaseServiceDoesNotBlock(){
        //the other base service is still Draft (not Activated): the contract is terminated as before
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        Test.startTest();
        Test_Rest_UpsertContract.createTwoBaseServices('900645', '900646');
        Map<String, Object> terminate = Test_Rest_UpsertContract.baseServicePayload('900645', '900645');
        terminate.putAll(new Map<String, Object>{'terminationId' => '3', 'serviceEndDate' => '2026-06-30'});
        Util_Rest.RestResult result = Test_Rest_UpsertContract.callRest(terminate);
        Test.stopTest();

        System.assertEquals(true, result.success, String.join(result.messages, '; '));
        Contract contr = Test_Rest_UpsertContract.getContract('900645-1');
        System.assertEquals('Partial Credit Immediate', contr.Termination_Method__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), contr.Subscription25__Termination_Date__c);
    }

    //two base services (900641 terminates, 900642 stays active) on one contract: only the contract product is terminated
    private static void assertOnlyProductTerminated(Map<String, Object> termination){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();
        //test contract products stay Draft, let Draft count as Activated here
        Rest_UpsertContract.activeBaseServiceStatuses = new Set<String>{'Activated', 'Draft'};

        Test.startTest();
        Test_Rest_UpsertContract.createTwoBaseServices('900641', '900642');
        Map<String, Object> terminate = Test_Rest_UpsertContract.baseServicePayload('900641', '900641');
        terminate.putAll(termination);
        Util_Rest.RestResult result = Test_Rest_UpsertContract.callRest(terminate);
        Test.stopTest();

        System.assertEquals(true, result.success, String.join(result.messages, '; '));

        Contract contr = Test_Rest_UpsertContract.getContract('900641-1');
        System.assertEquals(null, contr.Termination_Method__c);
        System.assertEquals(null, contr.Subscription25__Termination_Date__c);
        System.assertEquals(Date.newInstance(2026, 6, 30), [SELECT Subscription25__Termination_Date__c FROM Subscription25__Contract_Product__c WHERE extId__c = '900641-1'].Subscription25__Termination_Date__c);
        System.assertEquals(null, [SELECT Subscription25__Termination_Date__c FROM Subscription25__Contract_Product__c WHERE extId__c = '900642-1'].Subscription25__Termination_Date__c);
    }

    private static void createTwoBaseServices(String firstId, String secondId){
        for (String id : new List<String>{firstId, secondId}) {
            Util_Rest.RestResult created = Test_Rest_UpsertContract.callRest(Test_Rest_UpsertContract.baseServicePayload(id, firstId));
            System.assertEquals(true, created.success, String.join(created.messages, '; '));
        }
        System.assertEquals(2, [SELECT Count() FROM Subscription25__Contract_Product__c WHERE Is_Base_Service__c = true AND Subscription25__Contract__r.extId__c = :(firstId + '-1')]);
    }

    private static Map<String, Object> baseServicePayload(String id, String contractId){
        Map<String, Object> payload = Test_Rest_UpsertContract.basePayload(id, 1);
        payload.put('contractId', contractId);
        return payload;
    }

    //Subscription25__Current_End_Date__c right after creation: the date the contract is invoiced through
    private static Date invoicedEndDate;

    private static Contract createAndTerminateByDates(String id, Map<String, Object> dates){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        Map<String, Object> create = Test_Rest_UpsertContract.basePayload(id, 1);
        //contract settings in the dates map also apply to the create call
        for (String key : new List<String>{'renewalTerm', 'startDate'}) {
            if (dates.containsKey(key)) {
                create.put(key, dates.get(key));
            }
        }
        Map<String, Object> terminate = create.clone();
        terminate.putAll(dates);

        Test.startTest();
        Util_Rest.RestResult created = Test_Rest_UpsertContract.callRest(create);
        System.assertEquals(true, created.success, String.join(created.messages, '; '));
        Test_Rest_UpsertContract.invoicedEndDate = Test_Rest_UpsertContract.getContract(id + '-1').Subscription25__Current_End_Date__c;
        Util_Rest.RestResult terminated = Test_Rest_UpsertContract.callRest(terminate);
        Test.stopTest();

        System.assertEquals(true, terminated.success, String.join(terminated.messages, '; '));
        return Test_Rest_UpsertContract.getContract(id + '-1');
    }

    private static testMethod void testPartnerCodeDiscount(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        Product2 discount = Test_Data.createProduct('Partner discount', 'Tst.Partner', 'partner-discount-1', 'Handling', false);
        discount.Is_Partner_Code__c = true;
        Database.insert(discount);
        Database.insert(Test_Data.CreatePricebookEntry(discount.Id, 0, false));
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Subscription - Test' LIMIT 1];
        Database.insert(new PricebookEntry(Product2Id = discount.Id, Pricebook2Id = pb.Id, Unitprice = 0, UseStandardPrice = false, Isactive = true));
        Test_Rest_UpsertContract.addAdministrationProduct(discount.Id);

        Map<String, Object> payload = Test_Rest_UpsertContract.basePayload('900607', 1);
        payload.put('partnerCode', 'PARTNER10');
        payload.put('partnerCodePercentage', 10);

        Test.startTest();
        Util_Rest.RestResult result = Test_Rest_UpsertContract.callRest(payload);
        Test.stopTest();

        System.assertEquals(true, result.success, String.join(result.messages, '; '));

        Subscription25__Contract_Product__c cp = Test_Rest_UpsertContract.getContractProduct('900607-1');
        System.assertEquals(true, cp.Has_Partner_Code__c);
        Subscription25__Contract_Product__c partnerCp = Test_Rest_UpsertContract.getContractProduct('900607-1p');
        System.assertEquals(discount.Id, partnerCp.Subscription25__Product__c);
        //10% discount on the subscription price, booked as a negative price
        System.assertEquals(((cp.Subscription25__Price__c * 10) / 100).setScale(2, RoundingMode.HALF_DOWN) * -1, partnerCp.Subscription25__Price__c);
        System.assertEquals(false, partnerCp.Update_Price_before_Renewal__c);
    }

    // ---- generic helpers ----

    private static Util_Rest.RestResult callRest(Map<String, Object> payload){
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(JSON.serialize(payload));
        return Rest_UpsertContract.handleAction();
    }

    //open-ended base service in its first contract term: 2026-01-10 .. 2027-01-09
    private static Map<String, Object> basePayload(String id, Integer platformId){
        return new Map<String, Object>{
            'id' => id,
            'platformId' => platformId,
            'accountId' => '1',
            'installationId' => '7587',
            'productId' => '9999392',
            'startDate' => '2026-01-10',
            'quantity' => 1,
            'unitPrice' => 25.0,
            'contractTerm' => 12,
            'renewalTerm' => 12,
            'noticeTerm' => 1,
            'orderOffsetTerm' => -1,
            'isBaseService' => true,
            'prepaid' => true,
            'orderReference' => id + '-orderReference'
        };
    }

    private static Contract createAndTerminate(String id, String terminationId, String serviceEndDate){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        Map<String, Object> terminate = Test_Rest_UpsertContract.basePayload(id, 1);
        terminate.put('terminationId', terminationId);
        terminate.put('serviceEndDate', serviceEndDate);

        Test.startTest();
        Util_Rest.RestResult created = Test_Rest_UpsertContract.callRest(Test_Rest_UpsertContract.basePayload(id, 1));
        System.assertEquals(true, created.success, String.join(created.messages, '; '));
        Util_Rest.RestResult terminated = Test_Rest_UpsertContract.callRest(terminate);
        Test.stopTest();

        System.assertEquals(true, terminated.success, String.join(terminated.messages, '; '));
        return Test_Rest_UpsertContract.getContract(id + '-1');
    }

    private static Contract getContract(String extId){
        return [SELECT Id, Status, StartDate, Termination_Method__c, Subscription25__Termination_Date__c, Service_End_Date__c, Subscription25__Current_End_Date__c FROM Contract WHERE extId__c = :extId];
    }

    private static Subscription25__Contract_Product__c getContractProduct(String extId){
        return [
            SELECT Id, Subscription25__Product__c, Subscription25__Price__c, Update_Price_before_Renewal__c, Has_Partner_Code__c,
                Subscription25__Quantity__c, Subscription25__Contract__r.Pricebook2Id, Subscription25__Contract__r.CurrencyIsoCode, Subscription25__Contract__r.AccountId
            FROM Subscription25__Contract_Product__c
            WHERE extId__c = :extId
        ];
    }

    //makes the test account/product known on another platform (extId_<platform>__c, <product>-sv-<platform>)
    private static void addPlatform(String platformId){
        Account acc = [SELECT Id FROM Account WHERE extId_1__c = '1' LIMIT 1];
        acc.put('extId_' + platformId + '__c', '1');
        Database.update(acc);

        Product2 pr = Test_Data.createProduct('MiBlack ' + platformId, 'Tst.Black.12.' + platformId, '9999392-sv-' + platformId, 'Subscription', false);
        pr.contractTerm__c = 12;
        pr.renewalTerm__c = 12;
        pr.Invoice_Period__c = '0';
        Database.insert(pr);
        Database.insert(Test_Data.CreatePricebookEntry(pr.id, 8.95, false));
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'Subscription - Test' LIMIT 1];
        Database.insert(new PricebookEntry(Product2Id = pr.id, Pricebook2Id = pb.Id, Unitprice = 21, UseStandardPrice = false, Isactive = true));

        Test_Rest_UpsertContract.addAdministrationProduct(pr.Id);
    }

    private static void addAdministrationProduct(Id productId){
        Subscription25__Administration__c adm = [SELECT Id FROM Subscription25__Administration__c LIMIT 1];
        Subscription25__VATRate__c vr = [SELECT Id FROM Subscription25__VATRate__c LIMIT 1];
        Database.insert(new Subscription25__Administration_Product__c(
            Subscription25__Administration__c = adm.Id,
            Subscription25__Product__c = productId,
            Subscription25__Ledger_Account__c = '13100',
            Subscription25__Ledger_Account_EU__c = '13200',
            Subscription25__Ledger_Account_Non_EU__c = '13300',
            Subscription25__VATRate__c = vr.Id,
            Subscription25__VATRate_EU__c = vr.Id,
            Subscription25__VATRate_Non_EU__c = vr.Id
        ));
    }

    // ---- end generic ----

    // ---- v1 only: pricing driven by the Product2.Pricing_Platform__c flag ----

    private static testMethod void testPlatformPriceUsedWhenProductIsPricingPlatform(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();
        Product2 pr = [SELECT Id FROM Product2 WHERE extID__c = '9999392-sv-1'];
        pr.Pricing_Platform__c = true;
        Database.update(pr);

        Test.startTest();
        Util_Rest.RestResult result = Test_Rest_UpsertContract.callRest(Test_Rest_UpsertContract.basePayload('900621', 1));
        Test.stopTest();

        System.assertEquals(true, result.success, String.join(result.messages, '; '));
        Subscription25__Contract_Product__c cp = Test_Rest_UpsertContract.getContractProduct('900621-1');
        System.assertEquals(25, cp.Subscription25__Price__c);
        System.assertEquals(false, cp.Update_Price_before_Renewal__c);
    }

    private static testMethod void testPriceCalculatedWhenProductIsNotPricingPlatform(){
        Test_Rest_UpsertContract.setupSubscriptionFixtures();

        Test.startTest();
        Util_Rest.RestResult result = Test_Rest_UpsertContract.callRest(Test_Rest_UpsertContract.basePayload('900622', 1));
        Test.stopTest();

        System.assertEquals(true, result.success, String.join(result.messages, '; '));
        Subscription25__Contract_Product__c cp = Test_Rest_UpsertContract.getContractProduct('900622-1');
        System.assertNotEquals(25, cp.Subscription25__Price__c);
        System.assertEquals(true, cp.Update_Price_before_Renewal__c);
    }

    private static void setupSubscriptionFixtures(){
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

        Subscription25__VATRate__c vr = new Subscription25__VATRate__c(Name = '0 - Test', Subscription25__Hide_On_Invoice__c = false, Subscription25__Default__c = true, Subscription25__Active__c = true, Subscription25__VAT_Percentage__c = 21.0);
        Database.insert(vr);
        Database.insert(new Subscription25__VAT_Code__c(Subscription25__Administration__c = adm1.Id, Subscription25__VATRate__c = vr.Id, Subscription25__VAT_Code__c = 'A0'));
        Database.insert(new Subscription25__Administration_Product__c(
            Subscription25__Administration__c = adm1.id,
            Subscription25__Product__c = pr.id,
            Subscription25__Ledger_Account__c = '13100',
            Subscription25__Ledger_Account_EU__c = '13200',
            Subscription25__Ledger_Account_Non_EU__c = '13300',
            Subscription25__VATRate__c = vr.ID,
            Subscription25__VATRate_EU__c = vr.ID,
            Subscription25__VATRate_Non_EU__c = vr.ID
        ));
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