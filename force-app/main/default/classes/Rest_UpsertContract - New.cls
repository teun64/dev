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
            //system.debug(extIdField);

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

            //System.debug(acc);

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
        String extIdCon = (String.isNotBlank(miContract.contractId) ? miContract.contractId : miContract.id) + '-' + platformId;
        String extIdConProd = miContract.id + '-' + platformId;
        String extIdProd;
        String sSOQL;
        Boolean doSOQL;
        Boolean contrProdIsUpdate = false;
        Boolean doPartnerCode = false;
        Boolean activateContract = false;

        //Invoicing by platform or Subscription25, used to set the first invoicing date
        list<Mi_Sync_Setting__mdt> msss = [SELECT Activate_Contracts__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Invoicing'];

        if (msss.size() > 0) {
            activateContract = msss[0].Activate_Contracts__c;
        }

        system.debug('activateContract : ' + activateContract);

        Account_Contract_Default__mdt acd;
        Subscription25__Contract_Product__c contrProd;
        Contract contr;
        Product2 prd;
        List<Product2> prods;
        Boolean contrIsNew = false;
        Boolean contrTerminationRevert = false;
        Boolean contrProdIsNew = false;
        Boolean contrProdTerminationRevert = false;
        Boolean contrManagedBy = false;
        Boolean doCorrection = false;
        Boolean isBaseService = false;
        Boolean isFirstContractTerm;
        Boolean startDateChange = false;
        Date filterStartDate = Date.valueOf(((micontract.startDate == null) ? '1900-01-01' : micontract.startDate));
        Date contrServiceEndDate;
        Date contrTerminationDate;
        Date contrCurrentEndDate;
        Date contrFirstEndDate;
        Date contrProdServiceEndDate;
        Date contrProdTerminationDate;
        Date contrFirstInvoiceDate;
        Decimal price;
        Id installationId;
        Id hardwareId;
        Integer renewalTerm;
        Integer contractTerm;
        Integer invoiceTerm;
        Integer noticeTerm;
        Integer offsetTerm;
        String financialDebtorNumber;
        String contrPaymentMethod;
        String contrTerminationId;
        String contrStatus = 'Draft';
        String contrProdStatus = contrStatus;

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
            contrProdIsUpdate = (contrProd.Subscription25__Product__r.extId__c != extIdProd);
            contrProdStatus = contrProd.Subscription25__Status__c;

            if ((contrProdStatus == 'Terminated') && (miContract.terminationId != null) & (miContract.terminationId != '0')) {
                throw new Util_System.UpsertException('Error: Contract product is marked as \'Terminated\' and revoke action is missing ,no Contract product (' + miContract.id + ') possible.');
            }
            
            contrProdTerminationDate = contrProd.Subscription25__Termination_Date__c;

            if ((contrProd.Service_End_Date__c == null) &&  (contrProd.Subscription25__Termination_Date__c != null)) {
                contrProd.Service_End_Date__c = contrProd.Subscription25__Termination_Date__c;
            }

            contrProdServiceEndDate = contrProd.Service_End_Date__c;

        } else {
            contrProdIsNew = true;
            contrProd = new Subscription25__Contract_Product__c();
            contrProd.Subscription25__Status__c = contrProdStatus;
        }

        doSOQL = true;
        sSOQL = 'SELECT'
                + ' Id, isBaseService__c, Contract_settings_from_Account__c, Pricing_Platform__c, ContractTerm__c, NoticeTerm__c, RenewalTerm__c, OrderOffsetTerm__c, InvoiceTerm__c, Invoice_Period__c'
                + ' FROM Product2 WHERE';

        if ((contrProdIsNew) || (contrProdIsUpdate)) {

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

        } else if (String.isNotBlank(contrProd.Subscription25__Product__c)) {
            sSOQL += ' Id = \'' + contrProd.Subscription25__Product__c + '\'';
        } else {
            doSOQL = false;            
        }


        system.debug('doSOQL : ' + doSOQL);

        if (doSOQL) {
            sSOQL += ' LIMIT 1';
            prods = Database.query(sSOQL);
        }


        system.debug('sSOQL : ' + sSOQL);
        system.debug('prods : ' + prods);

        if((prods != null) && (prods.size() > 0)) {
            prd = prods[0];

            if ((!prd.isBaseService__c) && (isBaseService)) {
                prd.isBaseService__c = isBaseService;
            }

        } 

        if (prd == null) {
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

            contrStatus = contr.Status;

            if ((contrStatus == 'Terminated') && (miContract.terminationId != null) && (miContract.terminationId != '0')) {
                //if the salesforce contract was already terminated, stop now but skip the termination reverted
                return Util_Rest.makeAddedRecord('Contract/Old', String.valueOf(miContract.id), String.valueOf(contrProd.Id));
            }

            contrManagedBy = contr.Managed_by_Salesforce__c;
            contrTerminationDate = contr.Subscription25__Termination_Date__c;
            financialDebtorNumber = contr.Account.FinancialDebtorNumber__c;
            contrPaymentMethod = String.isNotBlank(contr.Payment_Method__c) ? contr.Payment_Method__c : acc.Payment_Method_Contracts__c;

            if ((contr.Service_End_Date__c == null) &&  (contr.Subscription25__Termination_Date__c != null)) {
                contr.Service_End_Date__c = contr.Subscription25__Termination_Date__c;
            }

            contrServiceEndDate = contr.Service_End_Date__c;

        } else {
            contr = new Contract();
            contr.Status = contrStatus;
            contrIsNew = true;
            contrPaymentMethod = acc.Payment_Method_Contracts__c;
        }

        Rest_UpsertContract.record = contr;
        system.debug(contrProd);
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

        if (contrIsNew) {
            // new contract contract
            if ((Contr.StartDate == null) && (micontract.startDate == null)) {
                throw new Util_System.UpsertException('Error: No Start Date provided, no Contract (' + miContract.id + ') created.');
            }


            contractTerm = ((miContract.contractTerm != null) && (miContract.contractTerm != 0)) ? miContract.contractTerm : Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'ContractTerm__c', contr.ContractTerm);

            if ((contractTerm == null) || (contractTerm <= 0)) {
                throw new Util_System.UpsertException('Error: No or invalid contractTerm (' + ((contractTerm == null) ? '' : String.valueOf(contractTerm) ) + ') supplied, no Contract (' + miContract.id + ') created.');
            }

            contr.StartDate = Date.valueOf(micontract.startDate);
            startDateChange = true;
            contr.AccountId = acc.Id;
            financialDebtorNumber = acc.FinancialDebtorNumber__c;

            if (acc.Reseller_Name__c == null) {
                acc.Reseller_Name__c = '1';
            }

            contr.extId__c = extIdCon;
            contr.System_Platform__c = platformId;
            contr.Sales_Channel__c = Util_System.getSalesChannel((miContract.salesChannelId == null) ? '1' : miContract.salesChannelId);

            Integer adminExternalId = Util_System.getAdminExternalId(Long.valueOf((String.isNotBlank(acc.Reseller_Name__c) ? acc.Reseller_Name__c: '1')));
            String resellerPriceBook = String.valueOf((adminExternalId == 0) ? 1 : adminExternalId);

            sSOQL = 'SELECT Id FROM Pricebook2 WHERE Reseller__c = \'' + resellerPriceBook + '\' AND Type__c = \'Subscriptions\' AND IsActive = true LIMIT 1';

            List<Pricebook2> pbs = Database.Query(sSOQL);

            if (pbs.size() > 0) {
                contr.Pricebook2Id = pbs[0].Id;
            } else {
                throw new Util_System.UpsertException('Error: Valid pricebook found, no Contract (' + miContract.id + ') created.');
            }

            Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);

            contr.Subscription25__Administration__c = admin.Id;
            contr.CurrencyIsoCode = (admin.CurrencyIsoCode != null) ? admin.CurrencyIsoCode : 'EUR';
            contr.Purchase_Origin__c = (miContract.purchaseOrigin != null) ? miContract.purchaseOrigin : 'NEW';

            renewalTerm = ((miContract.renewalTerm != null) && (miContract.renewalTerm != 0)) ? miContract.renewalTerm : Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'RenewalTerm__c', contr.Subscription25__Renewal_Term__c);
            renewalTerm = ((renewalTerm == null) || (renewalTerm == 0)) ? 1 : renewalTerm;

            offsetTerm = (miContract.orderOffsetTerm != null) ? miContract.orderOffsetTerm : Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'OrderOffsetTerm__c', contr.Subscription25__Months_In_Advance__c);
            offsetTerm = (offsetTerm == null) ? 0 : offsetTerm;

            noticeTerm = (miContract.noticeTerm != null) ? miContract.noticeTerm : Rest_UpsertContract.getCurrentProductAccountOrDefaultValue(acc, acd, prd, 'NoticeTerm__c', contr.Subscription25__Notice_Term__c);
            noticeTerm = (noticeTerm == null) ? 0 : noticeTerm;

            contrPaymentMethod = ((micontract.paymentMethod != null) && (micontract.paymentMethod != contrPaymentMethod)) ? micontract.paymentMethod : (((String.isNotBlank(contr.Payment_Method__c)) && (contr.Payment_Method__c == acc.Payment_Method_Contracts__c)) ? null : contrPaymentMethod);

            system.debug('ContracTerm -> ' + contractTerm );
            system.debug('RenewalTerm -> ' + renewalTerm );
            system.debug('NoticeTerm -> ' + noticeTerm );
            system.debug('OrderOffsetTerm -> ' + offsetTerm );

            contr.ContractTerm = contractTerm;
            contr.RenewalTerm__c = renewalTerm;
            contr.Subscription25__Renewal_Term__c = renewalTerm;
            contr.Subscription25__Notice_Term__c = noticeTerm;
            contr.Subscription25__Months_In_Advance__c = offsetTerm;

            contr.Payment_Method__c = contrPaymentMethod;
            contr.isPrepaid__c = (miContract.prePaid != null) ? miContract.prePaid : contr.isPrepaid__c;

            if (prd.isBaseService__c) {
                contr.Base_Product__c = prd.Id;
            }
        }

        if ((installationId != null) && (installationId != contr.Entity__c)) {
            contr.Entity__c = installationId;
        }
        if (miContract.hardwareId == '<>') {
            contr.Entity__c  = null;
            contr.Hardware__c = null;
        } else if ((hardwareId != null) && (hardwareId != contr.Hardware__c)) {
            contr.Hardware__c = hardwareId;
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
              
        if ((contrProdIsNew) || (contrProdIsUpdate)) {
            // new contract line, exisiting contract
            if ((micontract.startDate == null) && (contrProd.Subscription25__Start_Date__c == null)) {
                contrProd.Subscription25__Start_Date__c =  contr.StartDate;
            } else {

                if ((contrProd.Subscription25__Start_Date__c != null) && (contrProd.Subscription25__Start_Date__c != Date.valueOf(micontract.startDate)) && (contrProdStatus == ' Activated')) {
                    throw new Util_Rest.UpsertException('Error: The \'Activated\' Contract Product (' + miContract.id + ') requests a Start Date change, this is not allowed!');
                }

                contrProd.Subscription25__Start_Date__c = Date.valueOf(micontract.startDate);

                if ((contrProd.Subscription25__Start_Date__c < contr.StartDate) && (prd.isBaseService__c) && ((contrStatus == 'Draft') || (contrStatus == 'Ready'))) {
                    contr.StartDate = contrProd.Subscription25__Start_Date__c;
                    startDateChange = true;
                }   
            }

            contr.Base_Product__c = ((prd.isBaseService__c)) ? prd.Id : contr.Base_Product__c ;

            if ((miContract.partnerCode != null) && (!contrProd.Has_Partner_Code__c)) {
                contrProd.Has_Partner_Code__c = true;
                contrProd.Partner_Code__c = miContract.partnerCode;
                contrProd.Partner_Percentage__c = Decimal.valueOf((miContract.partnerCodePercentage == null) ? 0 : miContract.partnerCodePercentage);
                doPartnerCode = true;
            }

            if (micontract.paymentMethod != null) {
                contrProd.Payment_Method__c = micontract.paymentMethod;
            } else {
                contrProd.Payment_Method__c = (String.isNotBlank(contrProd.Payment_Method__c)) ? contrProd.Payment_Method__c : contrPaymentMethod;
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
            contrProd.Subscription25__Quantity__c = ((miContract.quantity != null) && (miContract.quantity != 0)) ? miContract.quantity : ((contrProd.Subscription25__Quantity__c != null) ? contrProd.Subscription25__Quantity__c : 1.0);
            price = contrProd.Subscription25__Price__c;

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

            //check should this be set 
            
            //contrProd.Subscription25__End_Date__c = contrProdServiceEndDate;
            //contrProd.Service_End_Date__c = contrProdServiceEndDate;
            contrProd.Subscription25__Termination_Date__c = contrProdTerminationDate;
            //

        }

        if (startDateChange) {
            contrFirstInvoiceDate = ((miContract.contrFirstInvoiceDate != null) && (contr.StartDate != Date.valueOf(miContract.contrFirstInvoiceDate))) ? Date.valueOf(miContract.contrFirstInvoiceDate) : contr.Subscription25__First_Invoice_Date__c;
            contr.Subscription25__First_Invoice_Date__c = contrFirstInvoiceDate;
            contr.Is_Imported__c = ((contrFirstInvoiceDate != null) && (contr.StartDate != contrFirstInvoiceDate));
        }

        contrFirstEndDate = contr.StartDate.addMonths(contr.ContractTerm).addDays(-1);
        contrCurrentEndDate = (contr.Subscription25__Current_End_Date__c != null) ? contr.Subscription25__Current_End_Date__c : contrFirstEndDate;
        isFirstContractTerm = (contrCurrentEndDate == contrFirstEndDate);


        //INVOICE TERMS SET AS
        //Contract is new or when the 1st base setting is coming allong
        if ((contrIsNew) || ((!contrIsNew) && ((contrStatus == 'Ready') || (contrStatus == 'Draft')) && (prd.isBaseService__c))) {

            if ((miContract.invoiceTerm != null) && (miContract.invoiceTerm != 0)) {
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
                contr.Subscription25__Invoice_Cycle__c = ((contrStatus == 'Draft') && (isFirstContractTerm) && (!contr.Is_Imported__c)) ? contr.ContractTerm : contr.RenewalTerm__c ;
            }

            contr.Subscription25__Invoice_Cycle__c = (contr.Subscription25__Invoice_Cycle__c == 0) ? contr.RenewalTerm__c : contr.Subscription25__Invoice_Cycle__c;
            
            contr.Subscription25__Renewal_Term__c = contr.RenewalTerm__c;

            system.debug('RenewalTerm (InvoiceTerm Check) -> ' + contr.Subscription25__Renewal_Term__c );
            system.debug('InvoiceTerm (Contract Check) -> ' + contr.Subscription25__Invoice_Cycle__c );

            if (contr.Subscription25__Renewal_Term__c < contr.Subscription25__Invoice_Cycle__c) {
                contr.Subscription25__Renewal_Term__c = contr.Subscription25__Invoice_Cycle__c;
            }

            system.debug('RenewalTerm (InvoiceTerm Check) -> ' + contr.Subscription25__Renewal_Term__c );

        }

        if ((contr.Is_Imported__c) && (contr.Subscription25__First_Invoice_Date__c == null) && (contrCurrentEndDate != null)) {

            contr.Subscription25__First_Invoice_Date__c =  contrCurrentEndDate.addDays(1);
            //if the contract has a first invoice date that is after the termination date, set the first invoice date
            //to the termination date + 1 day
            if(contr.Subscription25__Termination_Date__c != null && contr.Subscription25__Termination_Date__c <= contr.Subscription25__First_Invoice_Date__c){
                contr.Subscription25__First_Invoice_Date__c = contr.Subscription25__Termination_Date__c.addDays(1);
            }
            system.debug('Subscription25__First_Invoice_Date__c Should be here-> ' + contr.Subscription25__First_Invoice_Date__c);
        }

        // TERMINATION RULES
        if (String.isBlank(miContract.terminationId) && (miContract.contractEndDate != null) && (contr.System_Platform__c == '1')) {
            miContract.terminationId = '5';
        }

        if (String.isNotBlank(miContract.terminationId)) {
            contr.Termination_Method__c = Util_System.getTerminationOption(miContract.terminationId);

            // '0' => 'Termination Reverted','1' => 'No Credit','2' => 'Full Credit','3' => 'Partial Credit Immediate' ,'4' => 'Partial Credit with Cancellation Term', '5' => 'Auto renewal off'
            if (contr.Termination_Method__c == 'Termination Reverted') {
                contrProdTerminationDate = null;
                contrProdServiceEndDate = null;
                contrProdTerminationRevert = true;
            } else if (miContract.serviceEndDate != null) {
                contrProdServiceEndDate = Date.valueOf(miContract.serviceEndDate);

                switch on contr.Termination_Method__c {
                    when 'No Credit' {
                        contrProdTerminationDate = contrCurrentEndDate;
                    } 
                    when 'Full Credit' {
                        // Full Credit based on the Invoice tern or Contract Term
                        if (isFirstContractTerm) {
                            contrProdTerminationDate = contr.StartDate.addDays(-1);

                        } else {
                            contrProdTerminationDate = contrCurrentEndDate.addMonths(renewalTerm * -1);
                        }
                    } 
                    when 'Partial Credit Immediate' {
                        contrProdTerminationDate = contrProdServiceEndDate;
                    } 
                    when 'Partial Credit with Cancellation Term' {
                        // renwal_Term__c toevoegen?
                        contrProdTerminationDate = contrProdServiceEndDate.addMonths(((renewalTerm == 12) ? 1 : renewalTerm));
                    } 
                    when 'Auto renewal off' {
                        contrProdTerminationDate = contrCurrentEndDate;
                        contrProdServiceEndDate = contrProdTerminationDate;
                    }            
                }
            } else if (miContract.contractEndDate != null) {
                contrProdServiceEndDate = Date.valueOf(miContract.contractEndDate);
                
                switch on contr.Termination_Method__c {
                    when 'Auto renewal off' {
                        contrProdTerminationDate = contrProdServiceEndDate;
                    }            
                }

            } else {
                contrProdTerminationDate = null;
                contrProdServiceEndDate = null;
            }

        } else {
            // 20240807 Original process based on serviceEndDate and contractEndDate
            contr.Termination_Method__c =  null;

            system.debug('contrCurrentEndDate');
            // before going in edit mode, check the end date -> terminated edit needed
            if (miContract.serviceEndDate != null) {
                contrProdServiceEndDate = Date.valueOf(miContract.serviceEndDate);

                if (miContract.contractEndDate != null) {
                    contrProdTerminationDate = Date.valueOf(miContract.contractEndDate);
                } else {
                    //if no contractEndDate is provided, the current end date of the contract?
                    //20240524 -
                    if (contrProd.Subscription25__Termination_Date__c != null) {
                        contrProdTerminationDate = contrProd.Subscription25__Termination_Date__c;
                    } else if (contr.Subscription25__Termination_Date__c != null) {
                        contrProdTerminationDate = contr.Subscription25__Termination_Date__c;
                    } else {
                        contrProdTerminationDate = contrCurrentEndDate;
                    }
                }
            } else if (miContract.contractEndDate != null) {
                contrProdTerminationDate = Date.valueOf(miContract.contractEndDate);

                if (contrProd.Service_End_Date__c != null) {
                    contrProdServiceEndDate = contrProd.Service_End_Date__c;
                } else if (contr.Service_End_Date__c != null) {
                    contrProdServiceEndDate = contr.Service_End_Date__c;
                } else {
                    contrProdServiceEndDate = contrProdTerminationDate;
                }

            } else {
                contrProdTerminationDate = null;
                contrProdServiceEndDate = null;
            }

            contrProdTerminationRevert = ((contrProdTerminationDate == null) && (contrProd.Subscription25__Termination_Date__c != null) && ((contrProdStatus == 'Terminated')));
        }

        // set enddate contrProduct
        Boolean contrProdTerminate = false;
        Boolean contrTerminate = false;

        contrProd.Service_End_Date__c = contrProdServiceEndDate;
        contrProd.Subscription25__Termination_Date__c = contrProdTerminationDate;

        if ((contrProdTerminationDate != null) && (contrProdTerminationDate != contrCurrentEndDate)) {

            if ((prd.isBaseService__c) && (!contrProdIsNew)) {

                //determine the other contract products with a base service setting, 
                contrProds = [SELECT
                    Id
                FROM
                    Subscription25__Contract_Product__c
                WHERE
                    Subscription25__Contract__c = :contrProd.Subscription25__Contract__c 
                    AND Is_Base_Service__c = true
                    AND Subscription25__Product__r.Subscription25__Cost_Type__c != 'NON_RECURRING'
                    AND Subscription25__Status__c != 'Terminated'
                    AND Id != :contrProd.Id];


                if (contrProds.size() == 0) {
                    contrTerminate = true;

                    system.debug('contrProdServiceEndDate -> ' +  contrProdServiceEndDate);
                    system.debug('contrProdTerminationDate -> ' + contrProdTerminationDate);
                    system.debug('contrServiceEndDate -> ' + contrServiceEndDate);
                    system.debug('contrTerminationDate -> ' + contrTerminationDate);
                    system.debug('contrstatus -> ' + contrstatus);


                    contr.Termination_By__c = miContract.cancellationByEmail;
                    contr.Termination_New_Customer__c = miContract.cancellationNewCustomerEmail;
                    contr.Termination_Internal__c = (miContract.cancellationWithLoginAs != null) ? miContract.cancellationWithLoginAs : false;
                    contr.Subscription25__Termination_Reason__c = miContract.cancellationReason;
                    //contr.Termination_Reason__c = miContract.cancellationReason;
                    contr.Termination_Remark__c = miContract.cancellationRemark;

                    //set the termination date based on the end date from the platform
                    if ((contrProdServiceEndDate != null) && ((contrTerminationDate == null) || ((contrStatus == 'Closed') && (contrProdTerminationDate < contrTerminationDate)))) {
                        //Termination date set base on cancelation period (wet van damme), service_end_date_c set base on the end date of the service -> termination date and invoice periods in sync
                        //20220603 - TRi - When creditfrom date is null, it will be set to the Subscription25__Current_End_Date__c or miContract.currentEndDate when Subscription25__Current_End_Date__c is null
                        contr.Subscription25__Termination_Date__c = contrProdTerminationDate;
                        contr.Service_End_Date__c = contrProdServiceEndDate;
                        
                    } else if((contrStatus != 'Terminated') && (contrProdTerminationDate == null)) {
                        contr.Subscription25__Termination_Date__c = null;
                        contr.Service_End_Date__c = null;
                    }

                }

            }

            doCorrection = ((!contrIsNew) && (!contrProdIsNew) && (contrCurrentEndDate != contrProdTerminationDate));
            contrProdTerminate = !contrTerminate;
        }

        system.debug('Before Upsert -> ' + contr);
        system.debug('Subscription25__First_Invoice_Date__c -> ' + contr.Subscription25__First_Invoice_Date__c);
        //upsert the contract
        Database.upsert(contr);

        system.debug('Before Activate -> ' + contr);
        //if the contract was new or draft and activateContract = true, update it to activated
        if ((contrStatus == 'Draft') && (prd.isBaseService__c) && (activateContract)) {
            Database.update(new Contract(Id = contr.Id, Status = 'Activated'));
        }

        if (contrProd.Subscription25__Contract__c == null) {
            contrProd.Subscription25__Contract__c = contr.Id;
           //Database.upsert(contrProd);
        }

        system.debug('financialDebtorNumber -> ' + financialDebtorNumber);

        contrProd.DoActivate__c = (contrProd.Subscription25__Status__c  == 'Draft');

        //Upsert the contract product to Database
        // Only 1 database action preferred, also check execution of the flows for activating contract products

        if (!doCorrection) {
            contrProd.Service_End_Date__c = contrProdServiceEndDate;
            contrProd.Subscription25__Termination_Date__c = contrProdTerminationDate;
        }

        Database.upsert(contrProd, Subscription25__Contract_Product__c.fields.extId__c);

        //correcten, move to procedure
        system.debug('Do Correction -> ' + doCorrection);

        if (doCorrection) {
            string type = (contrTerminate) ? 'contract' : ((contrProdTerminate) ? 'contractproduct' : 'none');
            string state = (type != 'none') ? 'save' : 'query';
            
            doCorrection(contrProd, contrProdTerminationDate, contrProdServiceEndDate, type, state);
        }

        system.debug('contrProdIsNew ->' + contrProdIsNew);

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

                cpPartner.Subscription25__Status__c = contrProd.Subscription25__Status__c;
                cpPartner.DoActivate__c = contrProd.DoActivate__c;
                cpPartner.Subscription25__Start_Date__c = contrProd.Subscription25__Start_Date__c;
                //cpPartner.extId__c = extIdCon;
                //cpPartner.Is_Base_Service__c = isBaseService;
                cpPartner.Subscription25__Product__c = productId;
                // Partner code only works for first period, discount divided by Exact, balance sheet product doesn't need an enddate, costs taken at once
                cpPartner.Subscription25__End_Date__c = contrCurrentEndDate;
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

        Util_System.setStatusCascadePrevention(false);

        //Util_Rest.makeAddedRecord('Contract/Old', String.valueOf(miContract.id), String.valueOf(contService.Id));
        return Util_Rest.makeAddedRecord('Contract/Old', String.valueOf(miContract.id), String.valueOf(contrProd.Id));
    }

    public static boolean doCorrection(Subscription25__Contract_Product__c contrProd, Date terminationDate, Date serviceEndDate,String type, String state) {
        Boolean returnValue = false;

        //contrProd.Subscription25__Termination_Date__c = Date.valueOf(miContract.serviceEndDate);
        // ------ Move to invocable, with the of 14 days waiting time (TRi 23/06/2022)
        //Only run a credit invoices action when the creditFromDate and the endDate are not the same, otherwise you get an creditinvoice for one day ...
        //20220701 - TRi - Changed the condition from endDate tot the Subscription25__Current_End_Date__c, endDate is to strickt
        //20220704 - TRi - Removed the condition, contrServiceEndDate and terminationDate can be empty, Lex adviced to add 1 day to the termination day
        //20220711 - TRI - Added check on Subscription25__Exclude_From_Corrections__c (only one correction is allowed)
        //20220822 - TRi - Added check on Start Date == Termination date, not equals requires an additonal day
        //if((contrProd.Id != null) && (terminationDate != Date.valueOf(miContract.currentEndDate)) && (contrProd.Subscription25__Exclude_From_Corrections__c == false)) {
        //instantiate the corrector with the termination date at the end of the current month
        Subscription25.Neko_Contract_0.ContractProductCorrectorInput corInput = new Subscription25.Neko_Contract_0.ContractProductCorrectorInput();

        //input.contractProductIds = new Set<Id>{contrProd.Id};
        Map<Id, Subscription25__Contract_Product__c> cps; 

        if (type == 'Contract') {
            cps = new Map<Id, Subscription25__Contract_Product__c>([
                SELECT Id
                FROM Subscription25__Contract_Product__c
                WHERE Subscription25__Status__c IN ('Ready', 'Activated', 'Closed')
                    AND Subscription25__Exclude_From_Corrections__c = false
                    AND Subscription25__Contract__c = :contrProd.Subscription25__Contract__c
                ]);
        } else {
            cps = new Map<Id, Subscription25__Contract_Product__c>();
            cps.put(contrProd.id,contrProd);
        }

        if (cps.size() != 0) {
            corInput.contractProductIds = cps.keySet();

            Date createCorrectionsFrom = (contrProd.Subscription25__Start_Date__c  == terminationDate) ? terminationDate : terminationDate.addDays(1);
            system.debug('createCorrectionsFrom -> ' + createCorrectionsFrom);
            system.debug('productTerminationDate -> ' + terminationDate);


            //input.createCorrectionsFrom = miContract.contractEndDate != null ? Date.valueOf(miContract.contractEndDate) : contrProd.Subscription25__Termination_Date__c;
            /*
            if (contrProd.Subscription25__Start_Date__c == terminationDate) {
                corInput.createCorrectionsFrom = terminationDate;
            } else {
                corInput.createCorrectionsFrom = terminationDate.addDays(1);
            }
            */
            corInput.createCorrectionsFrom = createCorrectionsFrom;
            corInput.saveCorrections = (state == 'save');

            Subscription25.Neko_Contract_0.ContractProductCorrector cor = new Subscription25.Neko_Contract_0.ContractProductCorrector(corInput);
            cor.runCorrection();

            if (state == 'save') {
                cor.saveCorrection();
            } 

            List<Subscription25__Contract_Product__c> cpu = new list<Subscription25__Contract_Product__c>();
            for (ID id : cps.keySet()) {
                cpu.add(new Subscription25__Contract_Product__c(
                    Id = id,
                    Subscription25__Exclude_From_Corrections__c = true,
                    Service_End_Date__c = serviceEndDate,
                    Subscription25__Termination_Date__c = terminationDate));
            }

            returnValue = true;

            if (cpu.size() > 0) {
                Database.update(cpu);
            }
        }

        return returnValue;
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
        String contrFirstInvoiceDate; // Date When sub25 should take over invoicing, only set on create (where the crontract is draft)
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

    //private class CustomException extends Exception {}
}