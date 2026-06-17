@RestResource(urlMapping='/UpsertContract')
global with sharing class Rest_UpsertContract {
    private static Contract record;

    @HttpPost
    global static Util_Rest.RestResult handleAction(){
        String reqBody = RestContext.request.requestBody.toString();
        return Rest_UpsertContract.handleAction(reqBody);
    }

    public static Util_Rest.RestResult handleAction(String req){
        Util_Rest.RestResult result = new Util_Rest.RestResult();
        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, 'RestUpsertContract', 'S'); // TODO: Set calling system?
        Savepoint savePoint = Database.setSavepoint();

        string sSOQL;
        String platformId;
        String extIdField;
        Account acc;

        try {
            Util_Rest.isRestEntry = true;

            Rest_UpsertContract.ContractProduct miContract = (Rest_UpsertContract.ContractProduct)JSON.deserialize(req, Rest_UpsertContract.ContractProduct.class);
            logger.setSessionRecordExternalId(sessionId, miContract.id);
            logger.setCallingSystem(sessionId, miContract.platformId);

            if(miContract.id == null){
                throw new Util_System.UpsertException('Error: Empty ID provided, no contract(product) created.');
            }

            if (miContract.platformId == null) {
                throw new Util_System.UpsertException('Error: No Platform Id provided, no contract(product) (' + miContract.id + ') created.');
            }

            platformId = String.valueOf(miContract.platformId);
            logger.setCallingSystem(sessionId, platformId);
            extIdField = 'extId_' + platformId + '__c';

            if (miContract.productId == null) {
                throw new Util_System.UpsertException('Error: No Product Id provided, no contract(product) (' + miContract.id + ') created.');
            }

            if (miContract.accountId == null) {
                throw new Util_System.UpsertException('Error: No Account provided, no contract(product) (' + miContract.id + ') created.');
            } else {
                sSOQL = 'SELECT Id, Recordtype.DeveloperName, Reseller_Name__c, Market__c, Sales_Channel__c, FinancialDebtorNumber__c, Payment_Method_Contracts__c'
                + ' , ContractTerm__c, NoticeTerm__c, RenewalTerm__c, OrderOffsetTerm__c, InvoiceTerm__c, Invoice_Period__c, Subscription__c'
                + ' FROM Account'
                + ' WHERE '
                + extIDField + ' = \'' + miContract.accountId + '\'';

                List<Account> accts = Database.Query(sSOQL);
                //List<Account> accts = [SELECT Id, Reseller_Name__c FROM Account WHERE G25_ExtID_Account__c = :miContract.accountId];
                if(accts.size() > 0){
                    acc = accts.get(0);
                } else {
                    throw new Util_System.UpsertException('Error: No Account (' + miContract.accountId + ') found, no contract(product) (' + miContract.id + ') created.');
                }
            }

            if (String.isBlank(acc.FinancialDebtorNumber__c)) {
                // check debtornumber on accounts for baseservices, if an account hasn't a debtornumber, it prevents subscriptio25__contract_product__c from activation.
               Util_Rest.checkDebtorNumber(miContract.accountId, platformId);
            }

            result.addedRecords.add(Rest_UpsertContract.upsertMiContract(miContract, platformId, acc));
            result.success = true;
            result.messages.add('Succes: An Contract was added with ID: ' + miContract.id);

            Util_Rest.isRestEntry = false;

        }   catch(Util_System.UpsertException e){
            System.debug(e);
            Database.rollback(savePoint);

            result.success = false;
            result.messages.add('Error: ' + e);
            result.addedRecords.clear();

            Util_Rest.isRestEntry = false;
        }   catch(Exception e){
            System.debug(e);
            Database.rollback(savePoint);

            result.success = false;
            result.messages.add('Error: ' + e);
            result.addedRecords.clear();

            Util_Rest.isRestEntry = false;
        }

        Logger.setSessionRecord(sessionId, Rest_UpsertContract.record?.Id, Rest_UpsertContract.record?.Name);
        String responseBody = JSON.serialize(result);
        Integer statusCode = result.success ? 200 : 400;
        Logger.finalizeSession(sessionId, responseBody, statusCode);
        Logger.saveAll();

        return result;
    }

    private static Util_Rest.AddedRecord upsertMiContract(Rest_UpsertContract.ContractProduct miContract, String platformId, Account acc){
        Util_System.setStatusCascadePrevention(true);
        Util_Rest.AddedRecord contractorService;
        String extIdCon = (String.isNotBlank(miContract.contractId) ? miContract.contractId : miContract.id) + '-' + platformId;
        String extIdConProd = miContract.id + '-' + platformId;
        String extIdProd;

        String sSOQL;
        Boolean doSOQL;
        Boolean doProduct = false;
        Boolean doPartnerCode = false;
        Boolean activateContract;

        //Invoicing by platform or Subscription25, used to set the first invoicing date
        list<Mi_Sync_Setting__mdt> msss = [SELECT Activate_Contracts__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Invoicing'];

        if (msss.size() > 0) {
            activateContract = msss[0].Activate_Contracts__c;
        }

        Boolean managedBy = false;
        Boolean doCorrection = false;

        //if it's a base service, create/update the contract
        Subscription25__Contract_Product__c contrProd;
        Contract contr;
        String financialDebtorNumber;
        String paymentMethod;
        Account_Contract_Default__mdt acd;
        Boolean contrIsNew = false;
        Boolean contrProdIsNew = false;
        Date filterStartDate = Date.valueOf(((micontract.startDate == null) ? '1900-01-01' : micontract.startDate));
        Date contractServiceEndDate;
        String contractTerminationId;
        Date contractTerminationDate;
        Date contractCurrentEndDate;
        Date contractFirstEndDate;
        Date productServiceEndDate;
        Date productTerminationDate;
        Id installationId;
        Id hardwareId;
        List<Product2> prods;
        Product2 prd;

        Boolean isFirstContractTerm;

        Boolean isBaseService = false;

        if (miContract.isBaseService != null) {
            isBaseService = miContract.isBaseService;
        }
        extIdProd = miContract.productId + '-sv-'+ platformId;

        //try to load the contract product (so we know if we have to initialize fields)
        List<Subscription25__Contract_Product__c> contrProds = [SELECT
                    Id
                    , Subscription25__Contract__c
                    , Subscription25__Product__c
                    , Subscription25__Product__r.extID__c
                    , Subscription25__Quantity__c
                    , Subscription25__Price__c
                    , Subscription25__Setup_Cost__c
                    , Subscription25__Start_Date__c
                    , Subscription25__End_Date__c
                    , Subscription25__Termination_Date__c
                    , Subscription25__Status__c
                    , Subscription25__Exclude_From_Corrections__c
                    , DoActivate__c
                    , Update_Price_before_Renewal__c
                    , Is_Base_Service__c
                    , Has_Partner_Code__c
                    , extId__c
                    , Parent__c
                    , Partner_Code__c
                    , Partner_Percentage__c
                    , Invoice_Product_Name__c
                    , Service_End_Date__c
                    , isPrepaid__c
                    , Payment_Method__c
                    , Payment_Processor_Reference__c
                    , Payment_Processor_Amount_Gross__c
                FROM
                    Subscription25__Contract_Product__c
                WHERE
                    extId__c = :extIdConProd];


        if(contrProds.size() > 0){
            contrProd = contrProds[0];
            doProduct = (contrProd.Subscription25__Product__r.extId__c != extIdProd);
        } else {
            contrProdIsNew = true;
            doProduct = true;
            contrProd = new Subscription25__Contract_Product__c();
        }


        doSOQL = true;
        sSOQL = 'SELECT'
                + ' Id, isBaseService__c, Contract_settings_from_Account__c, Pricing_Platform__c, ContractTerm__c, NoticeTerm__c, RenewalTerm__c, OrderOffsetTerm__c, InvoiceTerm__c, Invoice_Period__c'
                + ' FROM Product2 WHERE';

        //system.debug(sSOQL);

        if (doProduct) {

            if ((isBaseService) || (String.isNotBlank(miContract.productId))){
                system.debug('Before: ' + extIdProd);
                extIdProd = Util_System.getReplacedProductId(extIdProd);
                system.debug('After: ' + extIdProd);
                sSOQL += ' extID__c = \'' + extIdProd + '\'';
            } else if (String.isNotBlank(acc.Subscription__c)) {
                sSOQL += ' Id = \'' + acc.Subscription__c + '\'';
            } else {
                doSOQL = false;
            }

        } else {
            sSOQL += ' Id = \'' + contrProd.Subscription25__Product__c + '\'';
        }

        if (doSOQL) {
            sSOQL += ' LIMIT 1';
            prods = Database.query(sSOQL);
        }

        if(prods.size() > 0) {
            prd = prods[0];

            if ((!prd.isBaseService__c) && (isBaseService)) {
                prd.isBaseService__c = isBaseService;
            }

        } else {
            throw new Util_System.UpsertException('Error: Product not found for article (' + ((miContract.productId != null) ? miContract.productId : '<not provided>') + '), no contract(product) (' + miContract.id + ') created.');
        }

        system.debug(prd);


        // 20240220 - TRi - This restpoint handles contract product and additonl is handles contracts when it is a base service 1 st check should be on the contract product

        String extIdAsset = (miContract.installationId != null) ? miContract.installationId + '-in-' : ((miContract.hardwareId != null) && (miContract.hardwareId != '<>')) ? miContract.hardwareId + '-hw-' : 'external-id-';
        extIdAsset += platformId;

        List<Asset> assets = [SELECT Id, ParentId FROM Asset WHERE extId__c = :extIdAsset];

        if (assets.size() > 0){
            installationId = (miContract.installationId != null) ? assets[0].Id : null;
            hardwareId = (miContract.installationId != null) ? assets[0].ParentId : assets[0].Id;
        }

        //if this is a base service look for contracts by external id
        List<Contract> existingConts;
        doSOQL = true;
        sSOQL = 'SELECT '
                + 'Id, Name, AccountId, Status, StartDate, ContractTerm, Subscription25__Current_End_Date__c, Termination_Method__c, Subscription25__Termination_Date__c, Service_End_Date__c, Subscription25__Invoice_Cycle__c, Invoice_Period__c, Subscription25__First_Invoice_Date__c'
                + ', Subscription25__Renewal_Term__c, RenewalTerm__c, Subscription25__Notice_Term__c, Subscription25__Months_In_Advance__c, Hardware__c, Entity__c,Payment_Method__c, Is_Imported__c, isPrepaid__c'
                + ', Pricebook2Id, CurrencyIsoCode, Managed_by_Salesforce__c, Account.FinancialDebtorNumber__c '
                + 'FROM Contract WHERE';

        system.debug(sSOQL);

        if (!contrProdIsNew) {
            sSOQL += ' id = \'' + contrProd.Subscription25__Contract__c + '\'';
        } else if ((isBaseService) || (String.isNotBlank(miContract.contractId))){
            sSOQL += ' extID__c = :extIdCon';
        } else if (installationId != null) {
            sSOQL += ' Entity__c = :installationId AND StartDate <= :filterStartDate AND Subscription25__Current_End_Date__c >= :filterStartDate';
        } else if (hardwareId != null) {
            sSOQL += ' Hardware__c = :hardwareId AND StartDate <= :filterStartDate AND Subscription25__Current_End_Date__c >= :filterStartDate';
        } else {
            doSOQL = false;
        }

        system.debug(sSOQL);

        if (doSOQL) {
            sSOQL += ' LIMIT 1';
            existingConts = Database.query(sSOQL);
        }

        system.debug(existingConts);

        if(existingConts.size() > 0){
            contr = existingConts[0];
            managedBy = contr.Managed_by_Salesforce__c;
            contractTerminationDate = contr.Subscription25__Termination_Date__c;
            financialDebtorNumber = contr.Account.FinancialDebtorNumber__c;
            paymentMethod = String.isNotBlank(contr.Payment_Method__c) ? contr.Payment_Method__c : acc.Payment_Method_Contracts__c;

            if ((contr.Service_End_Date__c == null) &&  (contr.Subscription25__Termination_Date__c != null)) {
                contr.Service_End_Date__c = contr.Subscription25__Termination_Date__c;
            }

            contractServiceEndDate = contr.Service_End_Date__c;

        } else {
            contr = new Contract();
            contr.Status = 'Draft';
            contrIsNew = true;
            paymentMethod = acc.Payment_Method_Contracts__c;
        }



        Rest_UpsertContract.record = contr;

        if ((contr.Status == 'Terminated') && (((miContract.terminationId != null) && (miContract.terminationId != '0')) || (contr.Subscription25__Termination_Date__c != null))) {
            //if the salesforce contract was already terminated, stop now.
            return Util_Rest.makeAddedRecord('Contract/Old', String.valueOf(miContract.id), String.valueOf(contrProd.Id));
        }

        integer renewalTerm;

        if ((contrIsNew) || (doProduct)) {

            if ((miContract.renewalTerm != null) && (miContract.renewalTerm != 0)) {
                renewalTerm = miContract.renewalTerm;
            } else {
                renewalTerm = Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'RenewalTerm__c', contr.Subscription25__Renewal_Term__c);
            }

            renewalTerm = ((renewalTerm == null) || (renewalTerm == 0)) ? 1 : renewalTerm; 

            // start date is required, otherwise quit
            if ((contr.startdate == null) && (micontract.startDate == null)) {
                throw new Util_System.UpsertException('Error: No Start Date provided, no contract(product) (' + miContract.id + ') created.');
            }

            if ((micontract.startDate != null) && (contr.startdate != Date.valueOf(micontract.startDate))) {
                contr.startdate = Date.valueOf(micontract.startDate);
            }
             
            contr.AccountId = acc.Id;
            financialDebtorNumber = acc.FinancialDebtorNumber__c;

            if (acc.Reseller_Name__c == null) {
                acc.Reseller_Name__c = '1';
            }

            List<Account_Contract_Default__mdt> acds = [SELECT
                                                            id, DeveloperName, ContractTerm__c, RenewalTerm__c, NoticeTerm__c, OrderOffsetTerm__c, InvoiceTerm__c, Invoice_Period__c
                                                        FROM
                                                            Account_Contract_Default__mdt
                                                        WHERE
                                                            RecordType__c = :acc.Recordtype.DeveloperName AND Reseller__c = :acc.Reseller_Name__c AND Market__c = :acc.Market__c AND Sales_Channel__c = :acc.Sales_Channel__c
                                                        ORDER BY
                                                            CreatedDate__c Desc
                                                        LIMIT
                                                            1];

            if (acds.size() > 0) {
                acd = acds.get(0);
            }

            contr.extId__c = extIdCon;
            contr.System_Platform__c = platformId;
            contr.Entity__c = installationId;
            contr.Hardware__c = hardwareId;
            contr.Sales_Channel__c = Util_System.getSalesChannel((miContract.salesChannelId == null) ? '1' : miContract.salesChannelId);

            Integer adminExternalId = Util_System.getAdminExternalId(Long.valueOf((String.isNotBlank(acc.Reseller_Name__c) ? acc.Reseller_Name__c: '1')));

            String resellerPriceBook = String.valueOf((adminExternalId == 0) ? 1 : adminExternalId);

            //20211111 - gen25/tri - upcomming change to multiple to pricebooks per country/region
            sSOQL = 'SELECT Id FROM Pricebook2 WHERE Reseller__c = \'' + resellerPriceBook + '\' AND Type__c = \'Subscriptions\' AND IsActive = true LIMIT 1';

            List<Pricebook2> pbs = Database.Query(sSOQL);

            if (pbs.size() > 0) {
                contr.Pricebook2Id = pbs[0].Id;
            } else {
                throw new Util_System.UpsertException('Error: Valid pricebook found, no contract(product) (' + miContract.id + ') created.');
            }

            system.debug(pbs[0]);

            Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);

            system.debug(adminExternalId);
            system.debug(admin);

            contr.Subscription25__Administration__c = admin.Id;
            contr.CurrencyIsoCode = (admin.CurrencyIsoCode != null) ? admin.CurrencyIsoCode : 'EUR';


            contr.Purchase_Origin__c = (miContract.purchaseOrigin != null) ? miContract.purchaseOrigin : 'NEW';

            if  ((miContract.firstInvoiceDate != null) && (contr.StartDate != Date.valueOf(miContract.firstInvoiceDate))) {
                contr.Subscription25__First_Invoice_Date__c = Date.valueOf(miContract.firstInvoiceDate);
                contr.Is_Imported__c = true;
            }
            // RG/Gen25 - Changed below values from API to account or product values
            // TR - Implement correct order

            if (miContract.orderOffsetTerm != null) {
                contr.Subscription25__Months_In_Advance__c = miContract.orderOffsetTerm;
            } else {
                contr.Subscription25__Months_In_Advance__c = Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'OrderOffsetTerm__c', contr.Subscription25__Months_In_Advance__c);
            }

            if (contr.Subscription25__Months_In_Advance__c == null) {
                contr.Subscription25__Months_In_Advance__c = 0;
            }

            contr.RenewalTerm__c = renewalTerm;
            contr.Subscription25__Renewal_Term__c = renewalTerm;

            if (miContract.contractTerm != null) {
                contr.ContractTerm = miContract.contractTerm;
            } else {
                contr.ContractTerm = Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'ContractTerm__c', contr.ContractTerm);
            }
            
            if (miContract.noticeTerm != null) {
                contr.Subscription25__Notice_Term__c = miContract.noticeTerm;
            } else {
                contr.Subscription25__Notice_Term__c = Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'NoticeTerm__c', contr.Subscription25__Notice_Term__c);
            }

            system.debug('ContracTerm -> ' + contr.ContractTerm );
            system.debug('RenewalTerm -> ' + contr.Subscription25__Renewal_Term__c );
            system.debug('NoticeTerm -> ' + contr.Subscription25__Notice_Term__c );
            system.debug('OrderOffsetTerm -> ' + contr.Subscription25__Months_In_Advance__c );

            if ((miContract.paymentMethod != null) && (miContract.paymentMethod != paymentMethod)) {
                contr.Payment_Method__c = miContract.paymentMethod;
            } else if ((String.isNotBlank(contr.Payment_Method__c)) && (contr.Payment_Method__c == acc.Payment_Method_Contracts__c)) {
                contr.Payment_Method__c = null;
            }

            if (miContract.prePaid != null) {
                contr.isPrepaid__c = miContract.prePaid;
            }
        } else {
            if ((installationId != null) && (installationId != contr.Entity__c)) {
                contr.Entity__c = installationId;
            }
            if (miContract.hardwareId == '<>') {
                contr.Entity__c  = null;
                contr.Hardware__c = null;
            } else if ((hardwareId != null) && (hardwareId != contr.Hardware__c)) {
                contr.Hardware__c = hardwareId;
            }
        }

        if (contr.ContractTerm == null) {
            throw new Util_System.UpsertException('Error: No contractTerm supplied, no contract(product) (' + miContract.id + ') created.');
        }

        if (miContract.paymentProviderReference != null) {
            contr.Payment_Processor_Reference__c = miContract.paymentProviderReference;
        }
        if (miContract.paymentProviderAmountPaid != null) {
            contr.Payment_Processor_Amount_Gross__c = miContract.paymentProviderAmountPaid;
        }

        if (miContract.orderReference != null) {
            contr.Purchase_Order_Number__c = Util_System.cleanString(miContract.orderReference);
        }

        contractFirstEndDate = contr.StartDate.addMonths(contr.ContractTerm).addDays(-1);
        contractCurrentEndDate = (contr.Subscription25__Current_End_Date__c != null) ? contr.Subscription25__Current_End_Date__c : contractFirstEndDate;
        isFirstContractTerm = (contractCurrentEndDate == contractFirstEndDate);

        if (String.isNotBlank(miContract.terminationId)) {
            contr.Termination_Method__c = Util_System.getTerminationOption(miContract.terminationId);

            // '0' => 'Termination Reverted','1' => 'No Credit','2' => 'Full Credit','3' => 'Partial Credit Immediate' ,'4' => 'Partial Credit with Cancellation Term'
            if (contr.Termination_Method__c == 'Termination Reverted') {
                productTerminationDate = null;
                productServiceEndDate = null;
            } else if (miContract.serviceEndDate != null) {
                productServiceEndDate = Date.valueOf(miContract.serviceEndDate);

                switch on contr.Termination_Method__c {
                    when 'No Credit' {
                        productTerminationDate = contractCurrentEndDate;
                    } 
                    when 'Full Credit' {
                        // Full Credit based on the Invoice tern or Contract Term
                        if (isFirstContractTerm) {
                            productTerminationDate = contr.StartDate.addDays(-1);

                        } else {
                            productTerminationDate = contractCurrentEndDate.addMonths(renewalTerm * -1);
                        }
                    } 
                    when 'Partial Credit Immediate' {
                        productTerminationDate = productServiceEndDate;
                    } 
                    when 'Partial Credit with Cancellation Term' {
                        // renwal_Term__c toevoegen?
                        productTerminationDate = productServiceEndDate.addMonths(((renewalTerm == 12) ? 1 : renewalTerm));
                    }           
                }
            } else if (miContract.contractEndDate != null) {
                productServiceEndDate = Date.valueOf(miContract.contractEndDate);
            } else {
                productTerminationDate = null;
                productServiceEndDate = null;
            }

        } else {
            // 20240807 Original process based on serviceEndDate and contractEndDate
            contr.Termination_Method__c =  null;

            system.debug('contractCurrentEndDate');
            // before going in edit mode, check the end date -> terminated edit needed
            if (miContract.serviceEndDate != null) {
                productServiceEndDate = Date.valueOf(miContract.serviceEndDate);

                if (miContract.contractEndDate != null) {
                    productTerminationDate = Date.valueOf(miContract.contractEndDate);
                } else {
                    //if no contractEndDate is provided, the current end date of the contract?
                    //20240524 -
                    if (contrProd.Subscription25__Termination_Date__c != null) {
                        productTerminationDate = contrProd.Subscription25__Termination_Date__c;
                    } else if (contr.Subscription25__Termination_Date__c != null) {
                        productTerminationDate = contr.Subscription25__Termination_Date__c;
                    } else {
                        productTerminationDate = contractCurrentEndDate;
                    }
                }
            } else if (miContract.contractEndDate != null) {
                productTerminationDate = Date.valueOf(miContract.contractEndDate);

                if (contrProd.Service_End_Date__c != null) {
                    productServiceEndDate = contrProd.Service_End_Date__c;
                } else if (contr.Service_End_Date__c != null) {
                    productServiceEndDate = contr.Service_End_Date__c;
                } else {
                    productServiceEndDate = productTerminationDate;
                }

            } else {
                productTerminationDate = null;
                productServiceEndDate = null;
            }
        }

        // Allowed Changes isbaseSerivice
        if ((prd.isBaseService__c) && (doProduct)) {
            system.debug('productServiceEndDate -> ' +  productServiceEndDate);
            system.debug('productTerminationDate -> ' + productTerminationDate);
            system.debug('contractServiceEndDate -> ' + contractServiceEndDate);
            system.debug('contractTerminationDate -> ' + contractTerminationDate);
            system.debug('contr.status -> ' + contr.status);

            contr.Base_Product__c = prd.Id;
            contr.Termination_By__c = miContract.cancellationByEmail;
            contr.Termination_New_Customer__c = miContract.cancellationNewCustomerEmail;
            contr.Termination_Internal__c = (miContract.cancellationWithLoginAs != null) ? miContract.cancellationWithLoginAs : false;
            contr.Subscription25__Termination_Reason__c = miContract.cancellationReason;
            //contr.Termination_Reason__c = miContract.cancellationReason;
            contr.Termination_Remark__c = miContract.cancellationRemark;

            //set the termination date based on the end date from the platform
            if ((productServiceEndDate != null) && ((contractTerminationDate == null) || ((contr.status == 'Closed') && (productTerminationDate < contractTerminationDate)))) {
                //Termination date set base on cancelation period (wet van damme), service_end_date_c set base on the end date of the service -> termination date and invoice periods in sync
                //20220603 - TRi - When creditfrom date is null, it will be set to the Subscription25__Current_End_Date__c or miContract.currentEndDate when Subscription25__Current_End_Date__c is null
                contr.Subscription25__Termination_Date__c = productTerminationDate;
                contr.Service_End_Date__c = productServiceEndDate;
                doCorrection = (contractCurrentEndDate != productTerminationDate);
            } else if((contr.Status != 'Terminated') && (productTerminationDate == null)) {
                contr.Subscription25__Termination_Date__c = null;
                contr.Service_End_Date__c = null;
            }

            if (miContract.invoiceTerm != null) {
                contr.Subscription25__Invoice_Cycle__c = miContract.invoiceTerm;
            } else if (contr.Subscription25__Invoice_Cycle__c == null) {
                contr.Subscription25__Invoice_Cycle__c = Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'InvoiceTerm__c', contr.Subscription25__Invoice_Cycle__c);
            }

            if ((contr.Subscription25__Invoice_Cycle__c != null) && (contr.Subscription25__Invoice_Cycle__c > 12)) {
                contr.Subscription25__Invoice_Cycle__c = 0;
            }

            if ((String.isBlank(contr.Invoice_Period__c)) || (contr.Invoice_Period__c != String.valueOf(contr.Subscription25__Invoice_Cycle__c))) {
                contr.Invoice_Period__c = String.valueOf(contr.Subscription25__Invoice_Cycle__c);
            }

            system.debug('InvoiceTerm (Setting) -> ' + contr.Subscription25__Invoice_Cycle__c );
            system.debug('InvoiceTerm (Setting) -> ' + contr.Invoice_Period__c );

            if (contr.Invoice_Period__c  == '0') {
                contr.Subscription25__Invoice_Cycle__c = ((contr.Status == 'Draft') && (isFirstContractTerm) && (!contr.Is_Imported__c)) ? contr.ContractTerm : contr.RenewalTerm__c ;
            }

            contr.Subscription25__Invoice_Cycle__c = (contr.Subscription25__Invoice_Cycle__c == 0) ? contr.RenewalTerm__c : contr.Subscription25__Invoice_Cycle__c;
            
            contr.Subscription25__Renewal_Term__c = contr.RenewalTerm__c;

            system.debug('RenewalTerm (InvoiceTerm Check) -> ' + contr.Subscription25__Renewal_Term__c );
            system.debug('InvoiceTerm (Contract Check) -> ' + contr.Subscription25__Invoice_Cycle__c );

            if (contr.Subscription25__Renewal_Term__c < contr.Subscription25__Invoice_Cycle__c) {
                contr.Subscription25__Renewal_Term__c = contr.Subscription25__Invoice_Cycle__c;
            }

            system.debug('RenewalTerm (InvoiceTerm Check) -> ' + contr.Subscription25__Renewal_Term__c );

            if ((contr.Is_Imported__c) && (contr.Subscription25__First_Invoice_Date__c == null) && (contractCurrentEndDate != null)) {

                contr.Subscription25__First_Invoice_Date__c =  contractCurrentEndDate.addDays(1);
                //if the contract has a first invoice date that is after the termination date, set the first invoice date
                //to the termination date + 1 day
                if(contr.Subscription25__Termination_Date__c != null && contr.Subscription25__Termination_Date__c <= contr.Subscription25__First_Invoice_Date__c){
                    contr.Subscription25__First_Invoice_Date__c = contr.Subscription25__Termination_Date__c.addDays(1);
                }
                system.debug('Subscription25__First_Invoice_Date__c Should be here-> ' + contr.Subscription25__First_Invoice_Date__c);
            }

            system.debug('Before Upsert -> ' + contr);
            system.debug('Subscription25__First_Invoice_Date__c -> ' + contr.Subscription25__First_Invoice_Date__c);
            //upsert the contract
            Database.upsert(contr);

            system.debug('Before Activate -> ' + contr);
            //if the contract was new or draft and activateContract = true, update it to activated
            if((contr.Status == 'Draft') && (activateContract)) {
                Database.update(new Contract(Id = contr.Id, Status = 'Activated'));
            }

        }

        system.debug('Do Correction -> ' + doCorrection);

        if (doCorrection) {
            //contrProd.Subscription25__Termination_Date__c = Date.valueOf(miContract.serviceEndDate);
            // ------ Move to invocable, with the of 14 days waiting time (TRi 23/06/2022)
            //Only run a credit invoices action when the creditFromDate and the endDate are not the same, otherwise you get an creditinvoice for one day ...
            //20220701 - TRi - Changed the condition from endDate tot the Subscription25__Current_End_Date__c, endDate is to strickt
            //20220704 - TRi - Removed the condition, contractServiceEndDate and terminationDate can be empty, Lex adviced to add 1 day to the termination day
            //20220711 - TRI - Added check on Subscription25__Exclude_From_Corrections__c (only one correction is allowed)
            //20220822 - TRi - Added check on Start Date == Termination date, not equals requires an additonal day
            //if((contrProd.Id != null) && (terminationDate != Date.valueOf(miContract.currentEndDate)) && (contrProd.Subscription25__Exclude_From_Corrections__c == false)) {
            //instantiate the corrector with the termination date at the end of the current month
            Subscription25.Neko_Contract_0.ContractProductCorrectorInput input = new Subscription25.Neko_Contract_0.ContractProductCorrectorInput();

            //input.contractProductIds = new Set<Id>{contrProd.Id};
            Map<Id, Subscription25__Contract_Product__c> cps = new Map<Id, Subscription25__Contract_Product__c>([
                SELECT Id
                FROM Subscription25__Contract_Product__c
                WHERE Subscription25__Status__c IN ('Ready', 'Activated', 'Closed')
                    AND Subscription25__Exclude_From_Corrections__c = false
                    AND Subscription25__Contract__c = :contr.Id
            ]);

            input.contractProductIds = cps.keySet();

            //input.createCorrectionsFrom = miContract.contractEndDate != null ? Date.valueOf(miContract.contractEndDate) : contrProd.Subscription25__Termination_Date__c;
            if (contr.startdate  == productTerminationDate) {
                input.createCorrectionsFrom = productTerminationDate;
            } else {
                input.createCorrectionsFrom = productTerminationDate.addDays(1);
            }
            input.saveCorrections = true;
            Subscription25.Neko_Contract_0.ContractProductCorrector corrector = new Subscription25.Neko_Contract_0.ContractProductCorrector(input);
            corrector.runCorrection();
            corrector.saveCorrection();

            List<Subscription25__Contract_Product__c> cpu = new list<Subscription25__Contract_Product__c>();
            for (ID id : cps.keySet()) {
                cpu.add(new Subscription25__Contract_Product__c(
                    Id = id,
                    Subscription25__Exclude_From_Corrections__c = true,
                    Service_End_Date__c = productServiceEndDate,
                    Subscription25__Termination_Date__c = productTerminationDate));
            }

            if (cpu.size() > 0) {
                Database.update(cpu);
            }

        }

        system.debug('contrProdIsNew ->' + contrProdIsNew);

        if (contrProdIsNew) {
            contrProd.Subscription25__Contract__c = contr.Id;
            contrProd.Subscription25__Start_Date__c = contr.StartDate;
        }

        if (!managedBy) {
            if ((miContract.partnerCode != null) && (!contrProd.Has_Partner_Code__c)) {
                contrProd.Has_Partner_Code__c = true;
                contrProd.Partner_Code__c = miContract.partnerCode;
                contrProd.Partner_Percentage__c = Decimal.valueOf((miContract.partnerCodePercentage == null) ? 0 : miContract.partnerCodePercentage);
                doPartnerCode = true;
            }

            if (miContract.paymentMethod != null) {
                contrProd.Payment_Method__c = miContract.paymentMethod;
            } else {
                contrProd.Payment_Method__c = (String.isNotBlank(contrProd.Payment_Method__c)) ? contrProd.Payment_Method__c : paymentMethod;
            }

            if (miContract.prePaid != null) {
                contrProd.isPrepaid__c = miContract.prePaid;
            }

            if (miContract.paymentProviderReference != null) {
                contrProd.Payment_Processor_Reference__c = miContract.paymentProviderReference;
            }

            if (miContract.paymentProviderAmountPaid != null) {
                contrProd.Payment_Processor_Amount_Gross__c = miContract.paymentProviderAmountPaid;
            }

            contrProd.extId__c = extIdConProd;
            contrProd.Is_Base_Service__c = prd.isBaseservice__c;
            contrProd.Subscription25__Product__c = prd.Id;
            contrProd.Subscription25__End_Date__c = productServiceEndDate;
            contrProd.Subscription25__Termination_Date__c = productTerminationDate;
            contrProd.Service_End_Date__c = productServiceEndDate;
            contrProd.Subscription25__Quantity__c = (miContract.quantity != null) ? miContract.quantity : ((contrProd.Subscription25__Quantity__c != null) ? contrProd.Subscription25__Quantity__c : 1.0);
            decimal price = contrProd.Subscription25__Price__c;

            if ((prd.Pricing_Platform__c) && (miContract.unitPrice != null)) {
                price = miContract.unitPrice;
            } else {
                prd.Pricing_Platform__c = false;
                PricebookEntry pbe = Util_PriceCalculation.getPricebookEntry(
                prd.Id,
                contr.Pricebook2Id,
                contr.CurrencyIsoCode,
                contr.accountId,
                Math.round(contrProd.Subscription25__Quantity__c),
                0.0);
                price = (pbe != null) ? pbe.SalesPrice__c : 0;
            }

            system.debug('Rounding -> ' + price);

            price = price.setScale(2, RoundingMode.HALF_DOWN);

            contrProd.Subscription25__Price__c = price;

            system.debug('contrProd.Subscription25__Price__c -> ' + contrProd.Subscription25__Price__c);

            contrProd.Update_Price_before_Renewal__c = (!prd.Pricing_Platform__c);
            system.debug('Update_Price_before_Renewal__c -> ' + contrProd.Update_Price_before_Renewal__c);

            if (String.isNotBlank(miContract.invoiceProductName)) {
                contrProd.Invoice_Product_Name__c = miContract.invoiceProductName;
            }

            system.debug('contrProd.Invoice_Product_Name__c -> ' + contrProd.Invoice_Product_Name__c);

            // 20240304 - TRi -Store Payment info on the contract product, this makes the contract more flexible to add other products


            system.debug('financialDebtorNumber -> ' + financialDebtorNumber);

            if ((String.isBlank(contrProd.Subscription25__Status__c)) || (contrProd.Subscription25__Status__c  == 'Draft')) {
                if (String.isNotBlank(financialDebtorNumber)) {
                    contrProd.Subscription25__Status__c = 'Activated';
                } else {
                    contrProd.Subscription25__Status__c = 'Draft';
                    contrProd.DoActivate__c = true;
                }
            }

            //Upsert the contract product to Database
            // Only 1 database action preferred, also check execution of the flows for activating contract products

            Database.upsert(contrProd, Subscription25__Contract_Product__c.fields.extId__c);


            system.debug('doPartnerCode -> ' + doPartnerCode);

            if (doPartnerCode) {
                List<OrderItem> orderItemList = [SELECT Id, product2Id, UnitPrice FROM OrderItem WHERE Partner_Code__c = :contrProd.Partner_Code__c LIMIT 1];
                Boolean balanceSheet = false;
                Id productId;
                price = 0;


                if (orderItemList.size() > 0) {
                    // order item found with partner code -> subscription is bought as part of a package. Actions:
                    // - make a counter booking on the balance sheet
                    balanceSheet = true;
                    productId = orderItemList[0].product2Id;
                    price = orderItemList[0].UnitPrice;

                } else {
                    // ordenary partner code, actions
                    // - find Discount product
                    // - add discount product as non recurring to the contract
                    prods = [SELECT Id FROM Product2 WHERE RecordType.DeveloperName = 'Handling' and Is_Partner_Code__c = true LIMIT 1];

                    if (prods.size() > 0) {
                        productId = prods[0].Id;
                        price = ((contrProd.Subscription25__Price__c * contrProd.Partner_Percentage__c) / 100);
                        price = price.setScale(2, RoundingMode.HALF_DOWN);
                    }
                }

                if (productId != null) {
                    // price should be negative,because it is a a discount
                    price *= -1;
                    Subscription25__Contract_Product__c cpPartner = new Subscription25__Contract_Product__c();
                    cpPartner.Subscription25__Contract__c = contr.Id;
                    cpPartner.Parent__c = contrProd.Id;
                    if (String.isNotBlank(contrProd.extId__c)) {
                        cpPartner.extId__c = contrProd.extId__c;
                        cpPartner.extId__c += 'p';
                    }

                    if (String.isNotBlank(financialDebtorNumber)) {
                        cpPartner.Subscription25__Status__c = 'Activated';
                    } else {
                        cpPartner.Subscription25__Status__c = 'Draft';
                        cpPartner.DoActivate__c = true;
                    }

                    cpPartner.Subscription25__Start_Date__c = contrProd.Subscription25__Start_Date__c;
                    //cpPartner.extId__c = extIdCon;
                    //cpPartner.Is_Base_Service__c = isBaseService;
                    cpPartner.Subscription25__Product__c = productId;
                    // Partner code only works for first period, discount divided by Exact, balance sheet product doesn't need an enddate, costs taken at once
                    cpPartner.Subscription25__End_Date__c = contractCurrentEndDate;
                    //set termination date !! IMPORTANT !! Otherwise partner code becomes recurring
                    cpPartner.Subscription25__Termination_Date__c  = cpPartner.Subscription25__End_Date__c;
                    cpPartner.Subscription25__Setup_Cost__c = (balanceSheet) ? price : 0;
                    cpPartner.Subscription25__Price__c = (balanceSheet) ? 0 : price;
                    cpPartner.Subscription25__Quantity__c = (miContract.quantity != null) ? miContract.quantity : 1.0;
                    cpPartner.Update_Price_before_Renewal__c = false;
                    cpPartner.isPrepaid__c = contrProd.isPrepaid__c;
                    cpPartner.Payment_Method__c = contrProd.Payment_Method__c;
                    cpPartner.Payment_Processor_Reference__c = contrProd.Payment_Processor_Reference__c;
                    cpPartner.Payment_Processor_Amount_Gross__c = contrProd.Payment_Processor_Amount_Gross__c;

                    Database.insert(cpPartner);
                }
            }
        }

        Util_System.setStatusCascadePrevention(false);

        //Util_Rest.makeAddedRecord('Contract/Old', String.valueOf(miContract.id), String.valueOf(contService.Id));
        return Util_Rest.makeAddedRecord('Contract/Old', String.valueOf(miContract.id), String.valueOf(contrProd.Id));
    }

    private class ContractProduct {
        String id;
        String salesforceId;
        Long platformId; // ''
        String accountId; // the relation to the customer, use internal platform id
        String salesChannelId; //split to assign the contracts to brands, Moving Intelligence, EuropTrack, SlimmGPS
        String contractId; // TPA adjustment, possible to give contract ID, when given, this contract is taken as contract id, when not exists in salesforce, contract is created. when empty than ommitted
        String hardwareId; // hardwareId or installationId can be provided, installationId is domininant, when both are given hardwareId is ignored.
        String installationId; // intallationID, when given it also provides the hardwareId
        String productId; //formally articleId;, the relation between the salesforce product and the platform product/article
        String terminationId; // terminationOpions are: '0' => 'Termination Reverted','1' => 'No Credit','2' => 'Full Credit', '3' => 'Partial Credit Immediate', '4' => 'Partial Credit with Cancellation Term' when terminationId is given, the contractEndDate is ommitted
        String startDate; // Start date, update to match Datedefinition
        String serviceEndDate; // formally endDate, the date the platform services are endded, works in combination with the terminationId, the terminationDate is calculated base on this endDate in combination with the terminationId
        String contractEndDate; // formally creditFromDate, the Financial/actual End Date of this Contract, when not provided, the serviceEndDate is taken
        String firstInvoiceDate; // Date When sub25 should take over invoicing, only set on create (where the crontract is draft)
        Integer contractTerm; // PeriodInMonths; // Contract Term
        Integer renewalTerm; // ProlongationPeriod; // Renewal term
        Integer noticeTerm; // ProlongationPeriod; // Renewal term
        Integer invoiceTerm; // allows setting the invoice cycle, when set the first contract term is not used as the invoice cycle 0 = contractTerm
        Integer orderOffsetTerm; // allows setting the offset for the creation of the recuring orders, in advance (positive) or backwards (negatief) or 0 creates the order on the required date.
        Boolean isBaseService; // is kenmerk van product, legacy behouden
        String  invoiceProductName; //20231222 - TRi - Alternative Product Name for legacy situations where free (text) products are used to create a subscription, when regulair products are not suitable!
        Integer quantity;
        Double unitPrice; // 20240126, the monthly price of this contract product (NET Price (List Price - price agreement) excluding VAT)
        Boolean prePaid; //hierin staat of periode die begint op periodStartDate betaald is of niet, we krijgen later ook een discountpercentage die op dezeflde manier moet werken
        String  paymentMethod;
        String  paymentProviderReference;
        Double  paymentProviderAmountPaid;
        String  purchaseOrigin; //Possible values: NEW, SERVICE_CHANGE, ENTITY_CHANGE
        String  orderReference;
        String partnerCode; // the partner code used for this contract
        Double partnerCodePercentage; //the discount percentage used in combination with the partner code
        String cancellationReason;
        String cancellationRemark;
        String cancellationByEmail;
        String cancellationNewCustomerEmail;
        Boolean cancellationWithLoginAs;
    }

    private static Integer getCurrentProductAccountOrDefaultValue(Account acc, Account_Contract_Default__mdt acd, Product2 prod, String fieldName, Decimal currentValue) {
        /*if (prod == null) {
            return null;
        } else if (acc.get(fieldName) != null && prod.Contract_settings_from_Account__c) {
            return Integer.valueOf(acc.get(accountFieldName));
        }
        return Integer.valueOf(prod.get(accountFieldName)); */

        if (prod == null) {
            if (currentValue != null) {
                return Integer.valueOf(currentValue);
            } else {
                return null;
            }
        } else if (prod.Contract_settings_from_Account__c) {
            if (acc.get(fieldName) == null) {
                //defaults from meta data else current value as fallback
                if (acd != null) {
                    //product fallback
                    return Integer.valueOf(acd.get(fieldName));
                } else if (currentValue != null) {
                        return Integer.valueOf(currentValue);
                } else if (prod.get(fieldName) != null) {
                    Integer.valueOf(prod.get(fieldName));
                } else {
                    return null;
                }
            } else {
                return Integer.valueOf(acc.get(fieldName));
            }
        }

        return Integer.valueOf(prod.get(fieldName));

    }

    private class CustomException extends Exception {}
}