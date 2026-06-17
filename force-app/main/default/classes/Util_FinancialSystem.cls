public without sharing class Util_FinancialSystem {
    //bit of a weird way to do this, but it's quick and it works well
    //ADMIN_CODE is stored in a custom setting, all endpoints need the admin code in them
    //private static final String ADMIN_CODE = Exact_Settings__c.getAll().get('ADMIN_CODE').String_Value__c;

    private static final String ACCOUNT_ENDPOINT = 'api/v1/{0}/crm/Accounts';
    public static final String ACCOUNT_GET_ENDPOINT = 'api/v1/{0}/bulk/CRM/Accounts';
    public static final String ACCOUNT_SYNC_ENDPOINT = '/api/v1/{0}/sync/CRM/Accounts';
    private static final String ADDRESS_ENDPOINT = 'api/v1/{0}/crm/Addresses';
    private static final String BANK_ACCOUNT_ENDPOINT = 'api/v1/{0}/crm/BankAccounts';

    private static final String CONTACT_ENDPOINT = 'api/v1/{0}/crm/Contacts';
    private static final String MANDATE_ENDPOINT = 'api/v1/{0}/cashflow/DirectDebitMandates';
    public static final String ORDER_ENDPOINT = 'api/v1/{0}/salesorder/SalesOrders';
    private static final String ORDER_LINES_ENDPOINT = 'api/v1/{0}/salesorder/SalesOrderLines';
    private static final String ARTICLE_ENDPOINT = 'api/v1/{0}/logistics/Items';
    private static final String ARTICLE_GET_ENDPOINT = 'api/v1/{0}/bulk/Logistics/Items';
    private static final String SALES_INVOICE_ENDPOINT = 'api/v1/{0}/salesinvoice/SalesInvoices';
    private static final String SALES_INVOICE_GET_ENDPOINT = 'api/v1/{0}/bulk/salesinvoice/SalesInvoices';
    private static final String SALES_INVOICE_PRINT_ENDPOINT = 'api/v1/{0}/salesinvoice/PrintedSalesInvoices';

    private static Map<Integer, String> FATAL_ERROR_CODES = new Map<Integer, String> {
        400 => 'Malformed request',
        401 => 'Authentication failure',
        429 => 'Limit reached',
        500 => 'Data validation error'
    };

    // Name of the platform cache object that contains the Exact Limits.
    @TestVisible
    private static final String EXACT_LIMIT_CACHE_NAME = 'ExactLimit';

    // Exception messages
    public static final String EX_LIMITS = 'Limit reached. Wait until the limits reset before calling out';

    @Future(Callout=true)
    public static void syncAccountAsync(Id acctId, String logGUID){
        Util_FinancialSystem.syncAccount(acctId, logGUID);
    }

    @Future(Callout=true)
    public static void syncAccountAsync(Id acctId){
        Util_FinancialSystem.syncAccount(acctId);
    }

    public static List<String> syncAccount(Id acctId){
        return Util_FinancialSystem.syncAccount(acctId, null);
    }

    public static List<String> syncAccount(Id acctId, String logGUID) {
        String SYNC_NAME = 'Exact - Account Sync';
        List<String> messages = new List<String>();

        Integer countRunningLogs = [
            SELECT Count()
            FROM Event_Log__c
            WHERE Related_Record_Id__c = :acctId
                AND Action__c = :SYNC_NAME
                AND Status__c NOT IN :Util_Event.FINISHED_EVENT_STATUS
        ];
        if (countRunningLogs > 0) {
            messages.add('Failed: Account sync was already scheduled');
            return messages;
        }

        Inv_Integration.Request req = new Inv_Integration.Request();
        req.integrationDefinitionName = SYNC_NAME;
        req.relatedRecordId = acctId;
        List<Inv_Integration.Request> requests = new List<Inv_Integration.Request> { req };
        List<Inv_Integration.Result> responses = Inv_Integration.execute(requests);

        for (Inv_Integration.Result res : responses) {
            if (res.isSuccess) {
                messages.add('Success: Account sync scheduled');
            } else {
                String message = String.format('Failed: {0}', new List<String> { res.message });
                messages.add(message);
            }
        }
        return messages;
    }

    // public static List<String> syncAccount(Id acctId, String logGUID) {
        // // Throws an exception if there is not enough capacity within Exact limits
        // Util_FinancialSystem.getLimits().reserveCapacity(8);

        // Account acct = [
        //  SELECT Id, RecordType.DeveloperName, VAT_Number__c, CoC_Number__c
        //      , Reseller_Name__c, Market__c, Relation_type__c, Sales_Channel__c, Customer_Type__c
        //      , Block_Syncing_Exact__c, Name, OwnerId, Payment_Method_Contracts__c, Exact_Account_Name__c
        //      , ShippingStreet, ShippingPostalCode, ShippingCity, ShippingCountryCode
        //      , BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode, Billing_Phone__c, Billing_Email__c
        //      , VisitingAddress__Street__s, VisitingAddress__PostalCode__s, VisitingAddress__City__s, VisitingAddress__StateCode__s, VisitingAddress__CountryCode__s
        //      , Bank_Account_Number__c, Bank_Account__c, Bank_BIC__c, Bank_Country__c
        //      , FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c, FinancialIdAccount__c, FinancialIdVisitingAddress__c,  FinancialIdBillingAddress__c,  FinancialIdShippingAddress__c,  FinancialIdBankAccount__c, FinancialIdBankMandate__c
        //      , FinancialAccountClassification1__c, FinancialAccountClassification2__c, FinancialAccountClassification3__c
        //      , Contact_person__c, Contact_person__r.FirstName, Contact_person__r.MiddleName, Contact_person__r.LastName, Contact_person__r.Email, Contact_person__r.Phone
        //      , Contact_Billing__c, Contact_Billing__r.FirstName, Contact_Billing__r.MiddleName, Contact_Billing__r.LastName, Contact_Billing__r.Email, Contact_Billing__r.Phone
        //      , Contact_Shipping__c, Contact_Shipping__r.FirstName, Contact_Shipping__r.MiddleName, Contact_Shipping__r.LastName, Contact_Shipping__r.Email, Contact_Shipping__r.Phone
        //      , (
        //          SELECT Id, FinancialIdContact__c, Roles, ContactId,
        //          Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone
        //          FROM AccountContactRelations
        //      )
        //  FROM Account
        //  WHERE Id = :acctId
        // ];

        // // Map relation by Contact Id
        // Map<Id, AccountContactRelation> relationByContactId = new Map<Id, AccountContactRelation>();
        // for (AccountContactRelation relation : acct.AccountContactRelations) {
        //  relationByContactId.put(relation.ContactId, relation);
        // }

        // List<String> msgs = new List<String>();
        // Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', 'E', 'Account', 'sync2Exact', acctId, acct.Exact_Account_Name__c, null);

        // String namedCredential;

        // try {
        //  //niet shipping country = NL, validatie zoals B2C
        //  //skip validation for unit tests... ew
        //  Boolean skipDataCheck = FeatureManagement.checkPermission('cp_miIntegrationSkipDataCheck');
        //  if (!skipDataCheck) {
        //      if(acct.Reseller_Name__c == '1' && acct.RecordType.DeveloperName != 'B2C' && acct.ShippingCountryCode == 'NL' && acct.Block_Syncing_Exact__c){
        //          throw new Util_System.CustomException('This account is not validated by Web Services, this validation has to be completed before this account can be synchronised.');
        //      } else if (Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c) && (String.isBlank(acct.Bank_Account_Number__c) || String.isBlank(acct.Bank_Account__c))){
        //          //Reseller 1 requires an bank account
        //          throw new Util_System.CustomException('This account can not be synchronised because the bank account is not filled in.');
        //      } else if (String.isBlank(acct.ShippingCountryCode) || String.isBlank(acct.ShippingStreet) || String.isBlank(acct.ShippingPostalCode) || String.isBlank(acct.ShippingCity)){
        //          throw new Util_System.CustomException('This account can not be synchronised because the shipping address is not filled in.');
        //      } else if (String.isBlank(acct.BillingCountryCode) || String.isBlank(acct.BillingStreet) || String.isBlank(acct.BillingPostalCode) || String.isBlank(acct.BillingCity)){
        //          throw new Util_System.CustomException('This account can not be synchronised because the billing address is not filled in.');
        //      }
        //  }

        //  Integer adminExternalId = Util_System.getAdminExternalId(Long.valueOf(acct.Reseller_Name__c));
        //  Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);

        //  //make sure sync is enabled for this administration
        //  //remove reseller when go live subscription25
        //  if(admin.Subscription25__Synchronisation__c != 'Exact' || !admin.Subscription25__Active__c){
        //      throw new Util_System.CustomException('This accounts reseller does not synchronize with Exact');
        //  }

        //  String adminCode = admin.Subscription25__Twinfield_Company_Code__c;
        //  namedCredential = admin.Subscription25__Named_Credential__c;

        //  String previousExactID = acct.FinancialIdAccount__c ?? '';

        //  // Send account to Exact
        //  String accountMethod = Util_FinancialSystem.syncAccount(acct, admin, mainLog.GUID__c);
        //  Boolean saveAccount = accountMethod == 'POST'; //if this was an insert, we have to update the account later

        //  if ((!String.isBlank(previousExactID) && (acct.FinancialIdAccount__c != previousExactID)) || (accountMethod == 'POST')) {
        //      acct.FinancialIdBillingAddress__c = null;
        //      acct.FinancialIdVisitingAddress__c = null;
        //      acct.FinancialIdShippingAddress__c = null;
        //      acct.FinancialIdBankAccount__c = null;
        //      acct.FinancialIdBankMandate__c = null;
        //  }

        //  //once more into the fray for contacts
        //  if(!String.isBlank(acct.FinancialIdAccount__c) && acct.Contact_person__c != null) {
        //      try {
        //          // Sned Contact to Exact
        //          AccountContactRelation relation = relationByContactId.get(acct.Contact_person__c);
        //          String contactMethod = Util_FinancialSystem.syncContact(acct, relation, admin, mainLog.GUID__c);
        //          saveAccount |= contactMethod == 'POST'; //same logic, if we posted, that means we have to save.
        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions
        //          mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }

        //  //now we can also create/update the billing address, this method also populates the Exact_Billing_Address_Id__c field
        //  //on the given account (and debtor number), it returns the method that it applied (so we know if DML on the account is required)
        //  //only sync billing address if it differs from the shipping address
        //  if (!String.isBlank(acct.FinancialIdAccount__c) && !String.isBlank(acct.BillingCity)){
        //      try {
        //          // Send Billing Address to Exact
        //          String billingMethod = Util_FinancialSystem.syncBillingAddress(acct, admin, mainLog.GUID__c);
        //          saveAccount |= billingMethod == 'POST'; //if the billing address was an insert, we have to save the account so the id gets updated
        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions as all the way below
        //          mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }

        //  //do the same for the shipping address
        //  if (!String.isBlank(acct.FinancialIdAccount__c) && !String.isBlank(acct.ShippingCity)
        //      && (acct.ShippingStreet != acct.BillingStreet || acct.ShippingPostalCode != acct.BillingPostalCode || acct.ShippingCity != acct.BillingCity || acct.ShippingCountryCode != acct.BillingCountryCode)){
        //      try {
        //          // Send Shipping Address to Exact
        //          String shippingMethod = Util_FinancialSystem.syncShippingAddress(acct, admin, mainLog.GUID__c);
        //          saveAccount |= shippingMethod == 'POST'; //if the billing address was an insert, we have to save the account so the id gets updated
        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions as all the way below
        //          mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }

        //  //do the same for the visiting address
        //  if (!String.isBlank(acct.FinancialIdAccount__c) && !String.isBlank(acct.VisitingAddress__City__s)
        //      && (acct.VisitingAddress__Street__s != acct.BillingStreet || acct.VisitingAddress__PostalCode__s != acct.BillingPostalCode || acct.VisitingAddress__City__s != acct.BillingCity || acct.VisitingAddress__CountryCode__s != acct.BillingCountryCode)
        //      && (acct.VisitingAddress__Street__s != acct.ShippingStreet || acct.VisitingAddress__PostalCode__s != acct.ShippingPostalCode || acct.VisitingAddress__City__s != acct.ShippingCity || acct.VisitingAddress__CountryCode__s != acct.ShippingCountryCode)){
        //      try {
        //          // Send Visiting Address to Exact
        //          String visitingMethod = Util_FinancialSystem.syncVisitingAddress(acct, admin, mainLog.GUID__c);
        //          saveAccount |= visitingMethod == 'POST'; //if the billing address was an insert, we have to save the account so the id gets updated
        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions as all the way below
        //          mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }

        //  //do the same for the bank account
        //  if(!String.isBlank(acct.FinancialIdAccount__c) && !String.isBlank(acct.Bank_Account_Number__c)){
        //      try {
        //          String previousExactBankAccountId = acct.FinancialIdBankAccount__c;
        //          // Send Bank Account to Exact
        //          String bankAcctMethod = Util_FinancialSystem.syncBankAccount(acct, admin, mainLog.GUID__c);
        //          Boolean hasNewBankAccount = previousExactBankAccountId != acct.FinancialIdBankAccount__c;
        //          saveAccount |= hasNewBankAccount; //same logic, if we posted, that means we have to save.

        //          //do the mandate only if the bank account was created
        //          if ((hasNewBankAccount || String.isBlank(acct.FinancialIdBankMandate__c))
        //              && String.isNotBlank(acct.FinancialIdBankAccount__c)
        //              && Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c)) {

        //              String mandateMethod = Util_FinancialSystem.syncMandate(acct, admin, mainLog.GUID__c);
        //              saveAccount |= mandateMethod == 'POST'; //20230331 - TRi added, same logic, if we posted, that means we have to save.
        //          }
        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions
        //          mainLog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainLog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }

        //  if(saveAccount){
        //      try {
        //          //we have to load the Debtor number from exact here
        //          if(String.isBlank(acct.FinancialDebtorNumber__c)){
        //              acct.FinancialDebtorNumber__c = Util_FinancialSystem.getDebtorNumber(acct, admin, mainLog.GUID__c);
        //          }
        //          Database.update(acct);

        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions
        //          mainLog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainLog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }
        // } catch(Util_System.FinancialSyncException e){
        //  //Util_System.FinancialSyncExceptionis thrown by Util_FinancialSystem.doRequest, happens when exact returns an error (validation or something, exact side)
        //  //when this happens, this function should continue (so for instance, only address creation fails). The
        //  //actual error will be logged in the OAuth log, status of the exact log should be WARNING or something
        //  //the messages should be relayed on to the user
        //  mainLog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        //  mainLog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //  msgs.add(e.getMessage());
        // } catch(Util_System.CustomException e){
        //  //custom exceptions are thrown by some custom validation (account already synced, etc)
        //  //should be logged and shown to the user, should stop execution of this function altogether
        //  //status of the exact log should be ERROR
        //  mainLog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        //  mainLog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //  msgs.add(e.getMessage());
        // } catch(Exception e){
        //  //all other exceptions are caught and the function does not continue. message to the user should be a generic
        //  //error message
        //  mainLog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
        //  mainLog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //  msgs.add('Unhandled exception occurred.');
        // }

        // mainLog.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
        // mainLog.extId__c = (acct == null) ? '' : acct.FinancialIdAccount__c;
        // //now save the logs and the tokens
        // Database.upsert(mainLog, Event_Log__c.GUID__c);
        // Util_OAuth2.getInstance(namedCredential, mainLog.GUID__c).saveToken();
        // return msgs;
    // }

    public static String syncAccount(Account acc, Subscription25__Administration__c admin, String logGuid){
        Util_FinancialSystem.ExactAccount exactacc = new Util_FinancialSystem.ExactAccount(acc);

        //set up the request to upsert the account. On update we have to use PUT, with the GUID in the URL
        String endpoint = String.format(Util_FinancialSystem.ACCOUNT_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
        String method = 'POST';

        //if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
        if(!String.isBlank(acc.FinancialIdAccount__c)){
            endpoint += '(guid\''+acc.FinancialIdAccount__c+'\')';
            method = 'PUT';
        }
        String response = Util_FinancialSystem.doRequest(admin, endpoint, null, method, JSON.serialize(exactacc), logGuid);

        //if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
        if(method == 'POST'){
            Util_FinancialSystem.ExactAccount responseAccount = (Util_FinancialSystem.ExactAccount)JSON.deserialize(response, Util_FinancialSystem.ExactAccount.class);
            acc.FinancialIdAccount__c = responseAccount.ID;
            acc.FinancialDebtorNumber__c = responseAccount.Code;
        }

        return method;
    }

    public static String syncVisitingAddress(Account acct, Subscription25__Administration__c admin, String logGuid) {
        Util_FinancialSystem.VisitingAddress address = new Util_FinancialSystem.VisitingAddress(acct);
        return Util_FinancialSystem.syncAddress(address, Util_FinancialSystem.VisitingAddress.class, admin, logGuid);
    }

    public static String syncBillingAddress(Account acct, Subscription25__Administration__c admin, String logGuid) {
        Util_FinancialSystem.BillingAddress address = new Util_FinancialSystem.BillingAddress(acct);
        return Util_FinancialSystem.syncAddress(address, Util_FinancialSystem.BillingAddress.class, admin, logGuid);
    }

    public static String syncShippingAddress(Account acct, Subscription25__Administration__c admin, String logGuid) {
        Util_FinancialSystem.ShippingAddress address = new Util_FinancialSystem.ShippingAddress(acct);
        return Util_FinancialSystem.syncAddress(address, Util_FinancialSystem.ShippingAddress.class, admin, logGuid);
    }

    private static String syncAddress(Util_FinancialSystem.ExactAddress address, Type addressClass, Subscription25__Administration__c admin, String logGuid) {

        //set up the request to upsert the address. On update we have to use PUT, with the GUID in the URL
        String endpoint = String.format(Util_FinancialSystem.ADDRESS_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
        String method = 'POST';

        //if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
        if(!String.isBlank(address.getAddressId())){
            endpoint += '(guid\''+address.getAddressId()+'\')';
            method = 'PUT';
        }
        String response = Util_FinancialSystem.doRequest(admin, endpoint, null, method, JSON.serialize(address), logGuid);

        //if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
        if(method == 'POST') {
            Util_FinancialSystem.ExactAddress responseAddress = (Util_FinancialSystem.ExactAddress) JSON.deserialize(response, addressClass);
            // acct.Exact_Billing_Address_Id__c = responseAddress.ID;
            // debNr.Exact_Billing_Address_ID__c = responseAddress.ID;
            address.setAddressId(responseAddress.ID);
        }
        return method;
    }

    public static String syncBankAccount(Account acct, Subscription25__Administration__c admin, String logGuid){
        Util_FinancialSystem.ExactBankAccount bankAccount = new Util_FinancialSystem.ExactBankAccount(acct);

        // Set up the request to upsert the bank account. On update we have to use PUT, with the GUID in the URL
        String namedCredential = admin.Subscription25__Named_Credential__c;
        String endpoint = String.format(Util_FinancialSystem.BANK_ACCOUNT_ENDPOINT, new List<String>{admin.Subscription25__Twinfield_Company_Code__c});
        String method;
        String response;

        Boolean isCreate = String.isBlank(acct.FinancialIdBankAccount__c);
        if (isCreate) {
            // Create new bank account in exact
            try {
                method = 'POST';
                response = Util_FinancialSystem.doRequest(admin, endpoint, null, method, JSON.serialize(bankAccount), logGuid);
                Util_FinancialSystem.ExactBankAccount createResult = (Util_FinancialSystem.ExactBankAccount) JSON.deserialize(response, Util_FinancialSystem.ExactBankAccount.class);
                // Set response ID and BIC
                acct.FinancialIdBankAccount__c = createResult.ID;
                acct.Bank_BIC__c = createResult.BICCode;
                // Force account update when saving debtornummer
                acct.FinancialDebtorNumber__c = null;
                // Kill the mandate to get a new one
                acct.FinancialIdBankMandate__c = null;

            } catch(Util_System.FinancialSyncException e) {
                if (e.getMessage()?.contains('De volgende gegevens bestaan reeds')) {
                    // Bank account already exists in exact
                    isCreate = false;
                } else {
                    // Unknown error message, rethrow for logging
                    throw e;
                }
            }
        }
        if (!isCreate) {
            // Was already created, or duplicate found -> Get bank account from exact and update
            Map<String, String> params = new Map<String, String>();
            params.put('$select', 'ID,BICCode,BankAccountHolderName,Main,BankAccount');

            List<String> codeFilters = new List<String>();
            codeFilters.add('Account eq guid\''+acct.FinancialIdAccount__c+'\'');
            codeFilters.add('BankAccount eq \''+bankAccount.BankAccount+'\'');
            params.put('$filter', String.join(codeFilters, ' and '));

            method = 'GET';
            response = Util_FinancialSystem.doRequest(admin, endpoint, params, method, null, logGuid);
            Util_FinancialSystem.ExactBankAccounts allBankAccounts = (Util_FinancialSystem.ExactBankAccounts) JSON.deserialize(response, Util_FinancialSystem.ExactBankAccounts.class);

            if (!allBankAccounts.results.isEmpty()) {
                // If it was indeed found, set results
                Util_FinancialSystem.ExactBankAccount foundBankAccount = allBankAccounts.results.get(0);
                acct.FinancialIdBankAccount__c = foundBankAccount.ID;
                acct.Bank_BIC__c = foundBankAccount.BICCode;
                //20230328 - TRi forces account update when saving debtornummer
                acct.FinancialDebtorNumber__c = null;

                if (!foundBankAccount.Main) {
                    // Kill the mandate to get a new one
                    acct.FinancialIdBankMandate__c = null;
                    // Set to main
                    method = 'PUT';
                    endpoint += '(guid\''+acct.FinancialIdBankAccount__c+'\')';
                    response = Util_FinancialSystem.doRequest(admin, endpoint, null, method, JSON.serialize(bankAccount), logGuid);
                }
            }
        }

        return method;
    }

    public static String syncMandate(Account acct, Subscription25__Administration__c admin, String logGuid){
        Util_FinancialSystem.ExactMandate mandate = new Util_FinancialSystem.ExactMandate(acct);

        //set up the request to upsert the bank account. On update we have to use PUT, with the GUID in the URL
        String endpoint = String.format(Util_FinancialSystem.MANDATE_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
        String method = 'POST';
        //if we have an Exact Id on the account, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
        if(!String.isBlank(acct.FinancialIdBankMandate__c)){
            endpoint += '(guid\''+acct.FinancialIdBankMandate__c+'\')';
            method = 'PUT';
        }
        String response = Util_FinancialSystem.doRequest(admin, endpoint, null, method, JSON.serialize(mandate), logGuid);

        //if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
        if(method == 'POST'){
            Util_FinancialSystem.ExactMandate responseMandate = (Util_FinancialSystem.ExactMandate)JSON.deserialize(response, Util_FinancialSystem.ExactMandate.class);
            acct.FinancialIdBankMandate__c = responseMandate.ID;
        }
        return method;
    }

    public static String syncContact(Account acct, Contact con, AccountContactRelation relation, Subscription25__Administration__c admin, String logGuid){
        Util_FinancialSystem.ExactContact cont = new Util_FinancialSystem.ExactContact(acct, con, relation);

        //set up the request to upsert the contact. On update we have to use PUT, with the GUID in the URL
        String endpoint = String.format(Util_FinancialSystem.CONTACT_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
        String method = 'POST';

        //if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
        if(!String.isBlank(relation.FinancialIdContact__c)){
            //we're now returning 'PUT' here, without actually calling out, because apparently updating a contact
            //is not allowed through the api (LEX) Wil je dit ff nakijken ajb ?
            endpoint += '(guid\''+relation.FinancialIdContact__c+'\')';
            method = 'PUT';
            return method;
        }
        System.debug(method);
        String response = Util_FinancialSystem.doRequest(admin, endpoint, null, method, JSON.serialize(cont), logGuid);
        System.debug(response);

        //if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
        if(method == 'POST'){
            Util_FinancialSystem.ExactContact reponseContact = (Util_FinancialSystem.ExactContact)JSON.deserialize(response, Util_FinancialSystem.ExactContact.class);
            relation.FinancialIdContact__c = reponseContact.ID;
        }
        System.debug(relation.FinancialIdContact__c);
        return method;
    }

    public static String getDebtorNumber(Account acc, Subscription25__Administration__c admin, String logGuid){
        String exactAccountId = acc.FinancialIdAccount__c;
        String adminCode = admin.Subscription25__Twinfield_Company_Code__c;
        String namedCredential = admin.Subscription25__Named_Credential__c;
        String endpoint = String.format(Util_FinancialSystem.ACCOUNT_GET_ENDPOINT, new List<String>{adminCode});
        endpoint += '?$filter=ID+eq+guid\''+exactAccountId+'\'&$select=Code';

        String response = Util_FinancialSystem.doRequest(admin, endpoint, null, 'GET', null, logGuid);

        Util_FinancialSystem.ExactItems allItems = (Util_FinancialSystem.ExactItems)JSON.deserialize(response, Util_FinancialSystem.ExactItems.class);
        return allItems.results.get(0).Code;
    }

    @Future(Callout=true)
    public static void syncOrderAsync(Id orderId, String logGUID){
        Util_FinancialSystem.syncOrder(orderId, logGUID);
    }

    @Future(Callout=true)
    public static void syncOrderAsync(Id orderId){
        Util_FinancialSystem.syncOrder(orderId);
    }

    public static List<String> syncOrder(Id orderId){
        return  Util_FinancialSystem.syncOrder(orderId, null);
    }

    public static List<String> syncOrder(Id orderId, String logGUID) {
        String SYNC_NAME = 'Exact - Order Sync';
        List<String> messages = new List<String>();

        Integer countRunningLogs = [
            SELECT Count()
            FROM Event_Log__c
            WHERE Related_Record_Id__c = :orderId
                AND Action__c = :SYNC_NAME
                AND Status__c NOT IN :Util_Event.FINISHED_EVENT_STATUS
        ];
        if (countRunningLogs > 0) {
            messages.add('Failed: Order sync was already scheduled');
            return messages;
        }

        Inv_Integration.Request req = new Inv_Integration.Request();
        req.integrationDefinitionName = SYNC_NAME;
        req.relatedRecordId = orderId;
        List<Inv_Integration.Request> requests = new List<Inv_Integration.Request> { req };
        List<Inv_Integration.Result> responses = Inv_Integration.execute(requests);

        for (Inv_Integration.Result res : responses) {
            if (res.isSuccess) {
                messages.add('Success: Order sync scheduled');
            } else {
                String message = String.format('Failed: {0}', new List<String> { res.message });
                messages.add(message);
            }
        }
        return messages;
    }

    // public static List<String> syncOrder(Id orderId, String logGUID){
        // Order curOrder = [
        //  SELECT Id, OrderNumber, Contract__c, Opportunity.Name, Opportunity.Customer_Reference__c, Exact_Id__c, Exact_Order_Number__c, Payment_Method__c, Payment_Method_Result__c, Payment_Reference__c,
        //      Opportunity.Installation_Notes__c, Opportunity.Sales_Contact__r.Name, Opportunity.Sales_Contact__r.Email, Opportunity.Sales_Contact__r.Phone,
        //      Opportunity.OwnerId, AccountId, Account.FinancialIdAccount__c, Account.Exact_Account_Name__c, Account.Reseller_Name__c, Account.Contact_person__c, Account.Bank_Account_Number__c,
        //      Sales_Channel__c, Reseller__c, (
        //          SELECT Id, UnitPrice, Quantity, Product_Name__c, Product_Code_Customer__c, Partner_Code__c, PricebookEntry.Product2Id, PricebookEntry.Product2.Name, PricebookEntry.Product2.ProductCode, PricebookEntry.Product2.Generate_Partner_Code__c, PricebookEntry.Product2.RecordType.DeveloperName
        //          FROM OrderItems
        //      )
        //  FROM Order
        //  WHERE Id = :orderId
        // ];

        // Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', 'E', 'Order', 'sync2Exact', orderId, String.valueOf(curOrder.OrderNumber), null);
        // List<String> msgs = new List<String>();

        // String namedCredential;
        // try {
        //  if(!String.isBlank(curOrder.Exact_Id__c)){
        //      throw new Util_System.CustomException('This order was already synchronised');
        //  }

        //  // Find financial contact
        //  AccountContactRelation financialContact;
        //  List<AccountContactRelation> financialContacts = [
        //      SELECT Id, FinancialIdContact__c,
        //          Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone
        //      FROM AccountContactRelation
        //      WHERE AccountId = :curOrder.AccountId
        //          AND ContactId = :curOrder.Account.Contact_person__c
        //          AND Roles INCLUDES ('Billing')
        //  ];
        //  if (!financialContacts.isEmpty()) {
        //      financialContact = financialContacts.get(0);
        //  } else {
        //      throw new Util_System.CustomException('This account does not have a billing contact assigned');
        //  }

        //  //determine the external id of the administration, based on the reseller name, so we can load the debtor number
        //  Integer adminExternalId = Util_System.getAdminExternalId(Long.valueOf(curOrder.Account.Reseller_Name__c));
        //  Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);
        //  namedCredential = admin.Subscription25__Named_Credential__c;

        //  //make sure sync is enabled for this administration
        //  if((admin.Subscription25__Synchronisation__c != 'Exact' || !admin.Subscription25__Active__c) && (admin.Reseller__c != '1')) {
        //      throw new Util_System.CustomException('This accounts reseller does not synchronize with Exact');
        //  }

        //  if (!test.isRunningTest() && String.isBlank(curOrder.Account.FinancialIdAccount__c)) {
        //      throw new Util_System.CustomException('The account has an invalid debtor number in Exact or is not synced yet');
        //  }

        //  Boolean saveAccount = false;
        //  Account acct;
        //  if (String.isBlank(financialContact.FinancialIdContact__c)) {
        //      acct = [
        //          SELECT Id, RecordType.DeveloperName, VAT_Number__c, FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c, Reseller_Name__c, Market__c, Relation_Type__c, Sales_Channel__c
        //              , Customer_Type__c, CoC_Number__c, FinancialIdAccount__c
        //              , Block_Syncing_Exact__c, Name, OwnerId, Payment_Method_Contracts__c, Exact_Account_Name__c
        //              , ShippingStreet, ShippingPostalCode, ShippingCity, ShippingCountryCode
        //              , BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode, Billing_Phone__c, Billing_Email__c
        //              , Bank_Account_Number__c, Bank_Account__c, Bank_BIC__c, Bank_Country__c
        //              , Contact_person__r.FirstName, Contact_person__r.MiddleName, Contact_person__r.LastName, Contact_person__r.Email, Contact_person__r.Phone
        //          FROM Account
        //          WHERE Id = :curOrder.AccountId
        //      ];

        //      //once more into the fray for contacts
        //      try {
        //          String contactMethod = Util_FinancialSystem.syncContact(acct, financialContact, admin, mainLog.GUID__c);
        //          saveAccount |= contactMethod == 'POST'; //same logic, if we posted, that means we have to save.
        //      } catch(Util_System.FinancialSyncException e){
        //          //same handling of FinacialSyncExceptions
        //          mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
        //          mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //          msgs.add(e.getMessage());
        //      }
        //  }

        //  if ((String.isBlank(curOrder.Payment_Method__c)) || ((!String.isBlank(curOrder.Payment_Method__c)) && (curOrder.Payment_Method__c.left(1) == 'I') /*&& (curOrder.Account.Reseller_Name__c == '6')*/ && (String.isBlank(curOrder.Account.Bank_Account_Number__c)))) {
        //      curOrder.Payment_Method__c = '08';
        //  }

        //  //Exact items GUID's are storded on the Subscription25__Administration_Product__c object.
        //  //Procedure get them is : 1st try to get tehm from Subscription25__Administration_Product__c and 2nd from exact and store them in Subscription25__Administration_Product__c
        //  set<Id> productIds = Util_System.collectIdValues(curOrder.OrderItems, 'PricebookEntry.Product2Id', false);
        //  //system.debug('Products : ' +  productIds);
        //  set<String> codes = new set<String>();
        //  list<Subscription25__Administration_Product__c> adminProds2Update = new list<Subscription25__Administration_Product__c>();
        //  map<String, String> exactItemIds = new map<String, String>();

        //  Subscription25__Administration_Product__c[] adminProds = [
        //      SELECT Id, Subscription25__Product__c, Subscription25__Product__r.ProductCode, Exact_Id__c
        //      FROM Subscription25__Administration_Product__c
        //      WHERE Subscription25__Administration__c = :admin.Id and Subscription25__Product__c in :productIds
        //      LIMIT 10000
        //  ];
        //  for(Subscription25__Administration_Product__c adminProd: adminProds) {
        //      if (String.isBlank(adminProd.Exact_Id__c)) {
        //          //system.debug('Prductcode: '  + adminProd.Subscription25__Product__r.ProductCode);
        //          codes.add(adminProd.Subscription25__Product__r.ProductCode);
        //          adminProds2Update.add(adminProd);
        //      } else {
        //          exactItemIds.put(adminProd.Subscription25__Product__r.ProductCode, adminProd.Exact_Id__c);
        //      }
        //  }

        //  if (!codes.isEmpty()) {
        //      Map<String, String> exactItemIds2Add = Util_FinancialSystem.getExactItemIds(admin, codes, mainLog.GUID__c);

        //      if (!exactItemIds2Add.isEmpty()) {
        //          for (Subscription25__Administration_Product__c adminProd: adminProds2Update) {
        //              adminProd.Exact_Id__c = exactItemIds2Add.get(adminProd.Subscription25__Product__r.ProductCode);

        //              if (!String.isBlank(adminProd.Exact_Id__c)) {
        //                  exactItemIds.put(adminProd.Subscription25__Product__r.ProductCode, adminProd.Exact_Id__c);
        //              }
        //          }
        //      }
        //  }

        //  if (productIds.size() <> exactItemIds.size()) {
        //      throw new Util_System.CustomException('Some of the order items are not available in exact');
        //  }


        //  //for now, we only allow creations of SalesOrders in Exact, so no need to check for POST/PUT or url hackies
        //  Util_FinancialSystem.ExactOrder exactOrd = new Util_FinancialSystem.ExactOrder(curOrder, exactItemIds, acct, financialContact, admin);
        //  String endpoint = String.format(Util_FinancialSystem.ORDER_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
        //  String response = Util_FinancialSystem.doRequest(admin, endpoint, null, 'POST', JSON.serialize(exactOrd), mainLog.GUID__c);
        //  Util_FinancialSystem.ExactOrder responseOrder = (Util_FinancialSystem.ExactOrder)JSON.deserialize(response, Util_FinancialSystem.ExactOrder.class);
        //  curOrder.Exact_Id__c = responseOrder.OrderID;
        //  curOrder.Exact_Order_Number__c = (responseOrder.OrderNumber != null) ? String.valueOf(responseOrder.OrderNumber): '';
        //  System.debug(responseOrder);
        //  System.debug(curOrder.Exact_Order_Number__c);

        //  // Get synced Order Lines for the Ids
        //  Util_FinancialSystem.ExactOrderLines orderLines = Util_FinancialSystem.getSalesOrderLines(admin, curOrder.Exact_Id__c, mainLog.GUID__c);
        //  // Map found Order Lines by exact Item Id
        //  Map<String, Util_FinancialSystem.ExactOrderLine> linesByItemId = new Map<String, Util_FinancialSystem.ExactOrderLine>();
        //  for (Util_FinancialSystem.ExactOrderLine line : orderLines.results) {
        //      linesByItemId.put(line.Item, line);
        //  }
        //  // Match and set order ids
        //  for(OrderItem oi : curOrder.OrderItems) {
        //      String itemId = exactItemIds.get(oi.PricebookEntry.Product2.ProductCode);
        //      Util_FinancialSystem.ExactOrderLine line = linesByItemId.get(itemId);
        //      oi.FinancialId__c = line?.ID;
        //  }

        //  // Do the same for Contract Products
        //  List<Subscription25__Contract_Product__c> contractProductUpdates = new List<Subscription25__Contract_Product__c>();
        //  List<Subscription25__Contract_Product__c> contractProducts = [
        //      SELECT Id, Subscription25__Product__r.ProductCode
        //      FROM Subscription25__Contract_Product__c
        //      WHERE Subscription25__Contract__c = :curOrder.Contract__c
        //          AND Subscription25__Product__c IN :productIds
        //          AND FinancialIdProduct__c = NULL
        //  ];
        //  for (Subscription25__Contract_Product__c contractProduct : contractProducts) {
        //      contractProduct.FinancialIdProduct__c = exactItemIds.get(contractProduct.Subscription25__Product__r.ProductCode);
        //      contractProductUpdates.add(contractProduct);
        //  }
        //  Database.update(curOrder);

        //  if (!adminProds2Update.isEmpty()) {
        //      Database.update(adminProds2Update);
        //  }
        //  if (!contractProductUpdates.isEmpty()) {
        //      Database.update(contractProductUpdates);
        //  }
        //  if (saveAccount) {
        //      Database.update(acct);
        //  }
        // } catch(Util_System.FinancialSyncException e){
        //  //Util_System.FinancialSyncExceptionalso stops the entire transaction, giving ERROR as that status.
        //  mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        //  mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //  msgs.add(e.getMessage());
        // } catch(Util_System.CustomException e){
        //  //custom exceptions are thrown by some custom validation (account already synced, etc)
        //  //should be logged and shown to the user, should stop execution of this function altogether
        //  //status of the exact log should be ERROR
        //  mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        //  mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //  msgs.add(e.getMessage());
        // } catch(Exception e){
        //  //all other exceptions are caught and the function does not continue. message to the user should be a generic
        //  //error message
        //  mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
        //  mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
        //  msgs.add('Unhandled exception occurred.');
        // }

        // //now save the logs and the tokens
        // mainlog.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
        // mainlog.extId__c = curOrder.Exact_Id__c;
        // Database.upsert(mainLog, Event_Log__c.GUID__c);
        // //system.debug('mainlog -> ' + mainLog);
        // Util_OAuth2.getInstance(namedCredential, mainLog.GUID__c).saveToken();
        // return msgs;
    // }

    //this function loads Items/Articles from Exact based on the given codes. The resulting IDs have to be used in the
    //request to create SalesOrderLines
    public static Map<String, String> getExactItemIds(Subscription25__Administration__c admin, Set<String> codes, String logGuid){
        Map<String, String> params = new Map<String, String>();
        params.put('$select', 'ID,Code');

        List<String> codeFilters = new List<String>();
        for(String code : codes){
            codeFilters.add('Code eq \''+code+'\'');
        }
        params.put('$filter', String.join(codeFilters, ' or '));
        String endpoint = String.format(Util_FinancialSystem.ARTICLE_GET_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
        String response = Util_FinancialSystem.doRequest(admin, endpoint, params, 'GET', null, logGuid);

        Util_FinancialSystem.ExactItems allItems = (Util_FinancialSystem.ExactItems)JSON.deserialize(response, Util_FinancialSystem.ExactItems.class);
        Map<String, String> itemIds = new Map<String, String>();
        for(Util_FinancialSystem.ExactItem item : allItems.results){
            itemIds.put(item.Code, item.Id);
        }
        return itemIds;
    }

    public static Util_FinancialSystem.ExactOrderLines getSalesOrderLines(Subscription25__Administration__c admin, String salesOrderId, String logGuid){
        Map<String, String> params = new Map<String, String>();
        params.put('$filter', 'OrderID eq guid\''+ salesOrderId +'\'');
        params.put('$select', 'ID,CustomerItemCode,Description,Item,Notes,Quantity,UnitPrice');

        String endpoint = String.format(Util_FinancialSystem.ORDER_LINES_ENDPOINT, new List<String>{
            admin.Subscription25__Twinfield_Company_Code__c
        });
        String response = Util_FinancialSystem.doRequest(admin, endpoint, params, 'GET', null, logGuid);

        Util_FinancialSystem.ExactOrderLines orderLines = (Util_FinancialSystem.ExactOrderLines)JSON.deserialize(response, Util_FinancialSystem.ExactOrderLines.class);
        return orderLines;
    }

    public static List<String> finalizeInvoice(Id invoiceId){
        return Util_FinancialSystem.finalizeInvoice(invoiceId, null);
    }

    public static List<String> finalizeInvoice(Id invoiceId, String logGUID){

        Subscription25__Invoice__c inv = [
            SELECT Id, Name, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c,
                Subscription25__Invoice_Date__c, Payment_Method__c, Payment_Method_Result__c, Subscription25__Total_Amount__c,
                Subscription25__Administration__r.Subscription25__Named_Credential__c,
                Subscription25__Administration__r.Subscription25__Twinfield_Company_Code__c,
                Subscription25__Administration__r.Subscription25__Invoice_Number_Prefix__c,
                Reseller__c, Sales_Channel__c
            FROM Subscription25__Invoice__c
            WHERE Id = :invoiceId
        ];

        Event_Log__c mainLog = Util_Event.getLog(logGUID,'S', 'E', 'Invoice', 'finalize2Exact', invoiceId, inv.Name, '');
        List<String> msgs = new List<String>();
        String namedCredential;
        try {
            if(String.isBlank(inv.Subscription25__Exact_Order_Number__c)){
                throw new Util_System.CustomException('This invoice is not yet synced');
            }
            if(!String.isBlank(inv.Subscription25__Invoice_Number__c)){
                throw new Util_System.CustomException('This invoice is already finalized');
            }

            //determine the external id of the administration, based on the reseller name, so we can load the debtor number
            Subscription25__Administration__c admin = inv.Subscription25__Administration__r;
            namedCredential = admin.Subscription25__Named_Credential__c;
            // Throws an exception if there is not enough capacity within Exact limits
            Util_FinancialSystem.getLimits(admin).reserveCapacity(3);

            //first of all, we need to get the GUID of the invoice, we can get that based on the order number
            Map<String, String> invoiceDetails = Util_FinancialSystem.getInvoiceDetails(admin, inv.Subscription25__Exact_Order_Number__c, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);

            //if the invoice already has an invoice number, store it on the invoice, and we're done
            if(!String.isBlank((String)invoiceDetails.get('InvoiceNumber'))) {
                inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
            } else {
                //now we can do the call to actually finalize the invoice
                String templateId = Util_FinancialSystem.getExactInvoiceTemplateId(inv.Reseller__c, inv.Payment_Method_Result__c, inv.Subscription25__Total_Amount__c);

                Util_FinancialSystem.finalizeInvoice(admin, invoiceDetails.get('InvoiceID'), inv.Subscription25__Invoice_Date__c, templateId, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);
                inv.Invoice_Printed_In_Exact__c = true;

                //now we can get the invoice details again to get the invoice number
                try {
                    invoiceDetails = Util_FinancialSystem.getInvoiceDetails(admin, inv.Subscription25__Exact_Order_Number__c, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);

                    string invoiceNumber = String.isBlank(invoiceDetails.get('InvoiceNumber')) ? '' : invoiceDetails.get('InvoiceNumber');
                    invoiceNumber = (invoiceNumber == 'null') ? '' : invoiceNumber;

                    if (String.isNotBlank(invoiceNumber)) {
                        inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
                    }
                } catch(Exception e) {
                    //if loading the invoice number fails, just leave this be, next time the job runs, it'll try to reload the invoice number
                }
            }

            Boolean curEru = Util_System.getEruIluvatar();
            if(!curEru){
                Util_System.setEruIluvatar(true);
            }
            Database.update(inv);
            if(!curEru){
                Util_System.setEruIluvatar(false);
            }
        } catch(Util_System.FinancialSyncException e){
            //Util_System.FinancialSyncExceptionalso stops the entire transaction, giving ERROR as that status.
            mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
            mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            msgs.add(e.getMessage());
        } catch(Util_System.CustomException e){
            //custom exceptions are thrown by some custom validation (account already synced, etc)
            //should be logged and shown to the user, should stop execution of this function altogether
            //status of the exact log should be ERROR
            mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
            mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            msgs.add(e.getMessage());
        } catch(Exception e){
            //all other exceptions are caught and the function does not continue. message to the user should be a generic
            //error message
            mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
            mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            msgs.add('Unhandled exception occurred.');
        }

        //now save the logs and the tokens
        Database.upsert(mainLog, Event_Log__c.GUID__c);
        Util_OAuth2.getInstance(namedCredential, mainLog.GUID__c).saveToken();
        return msgs;
    }

    //this method is called from Batch_FinalizeInvoices, in case the invoice was already printed in Exact,
    //but does not have an invoice number yet
    public static List<String> loadInvoiceNumber(Id invoiceid){
        return Util_FinancialSystem.loadInvoiceNumber(invoiceid, null);
    }

    public static List<String> loadInvoiceNumber(Id invoiceid, String logGUID){
        Subscription25__Invoice__c inv = [
            SELECT Id, Name, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c,
                Subscription25__Invoice_Date__c, Payment_Method__c, Payment_Method_Result__c, Subscription25__Total_Amount__c,
                Subscription25__Administration__r.Subscription25__Named_Credential__c,
                Subscription25__Administration__r.Subscription25__Twinfield_Company_Code__c,
                Subscription25__Administration__r.Subscription25__Invoice_Number_Prefix__c,
                Invoice_Printed_In_Exact__c
            FROM Subscription25__Invoice__c
            WHERE Id = :invoiceId
        ];
        Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S','E','Invoice', 'loadInvoiceNumber', invoiceId, inv.Name, null);
        List<String> msgs = new List<String>();
        String namedCredential;
        try {
            if(!inv.Invoice_Printed_In_Exact__c){
                throw new Util_System.CustomException('This invoice is not yet synced');
            }
            if(!String.isBlank(inv.Subscription25__Invoice_Number__c)){
                throw new Util_System.CustomException('This invoice is already finalized');
            }

            //determine the external id of the administration, based on the reseller name, so we can load the debtor number
            Subscription25__Administration__c admin = inv.Subscription25__Administration__r;
            namedCredential = admin.Subscription25__Named_Credential__c;
            // Throws an exception if there is not enough capacity within Exact limits
            Util_FinancialSystem.getLimits(admin).reserveCapacity(1);

            //load the invoice details, which contains the invoice number
            Map<String, String> invoiceDetails = Util_FinancialSystem.getInvoiceDetails(admin, inv.Subscription25__Exact_Order_Number__c, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);
            //if the invoice status from exact is not 50, that means the actual printing failed, so disable that checkbox
            if (invoiceDetails.get('Status') != '50') {
                inv.Invoice_Printed_In_Exact__c = false;
            } else {
                inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
            }

            Boolean curEru = Util_System.getEruIluvatar();
            if(!curEru){
                Util_System.setEruIluvatar(true);
            }
            Database.update(inv);
            if(!curEru){
                Util_System.setEruIluvatar(false);
            }
        } catch(Util_System.FinancialSyncException e){
            //Util_System.FinancialSyncExceptionalso stops the entire transaction, giving ERROR as that status.
            mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
            mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            msgs.add(e.getMessage());
        } catch(Util_System.CustomException e){
            //custom exceptions are thrown by some custom validation (account already synced, etc)
            //should be logged and shown to the user, should stop execution of this function altogether
            //status of the exact log should be ERROR
            mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
            mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            msgs.add(e.getMessage());
        } catch(Exception e){
            //all other exceptions are caught and the function does not continue. message to the user should be a generic
            //error message
            mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
            mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
            msgs.add('Unhandled exception occurred.');
        }

        //now save the logs and the tokens
        Database.upsert(mainLog, Event_Log__c.GUID__c);
        Util_OAuth2.getInstance(namedCredential, mainLog.GUID__c).saveToken();
        return msgs;
    }

    public static String getExactInvoiceTemplateId(String reseller, String paymentMethod, Decimal amount){
        string templateId = '';
        string paymentCondition = (amount < 0) ? 'cr' : paymentMethod;

        if (String.isNotBlank(reseller) && String.isNotBlank(paymentCondition)) {
            templateId = [Select Exact_Invoice_Template__c from Payment_Setting__mdt where Reseller__c = :reseller and Method__c = :paymentCondition Limit 1].Exact_Invoice_Template__c;
        }

        return templateId;
    }

    public static Map<String, String> getInvoiceDetails(Subscription25__Administration__c admin, String orderNumber, String adminCode, String logGuid){
        Map<String, String> params = new Map<String, String>();
        params.put('$select', 'InvoiceID,InvoiceNumber,Status');
        params.put('$filter', 'OrderNumber eq ' + orderNumber);
        String endpoint = String.format(Util_FinancialSystem.SALES_INVOICE_GET_ENDPOINT, new List<String>{adminCode});
        String response = Util_FinancialSystem.doRequest(admin, endpoint, params, 'GET', null, logGuid);

        Util_FinancialSystem.ExactInvoices allInvoices = (Util_FinancialSystem.ExactInvoices)JSON.deserialize(response, Util_FinancialSystem.ExactInvoices.class);
        Map<String, String> details = new Map<String, String>();
        details.put('InvoiceID', allInvoices.results[0].InvoiceID);
        details.put('InvoiceNumber', allInvoices.results[0].InvoiceNumber);
        details.put('Status', ''+allInvoices.results[0].Status);
        return details;
    }

    public static void finalizeInvoice(Subscription25__Administration__c admin, String invoiceId, Date invDate, String templateId, String adminCode, String logGuid){
        //Since we're only posting 2 fields, i'll just set up the request using a map
        //.... 2 days later.....
        //now that we're at 4 fields, maybe it's time to switch to inner class....
        // update the Sales Channel

        Map<String, Object> reqMap = new Map<String, Object>();
        reqMap.put('InvoiceID', invoiceId);
        reqMap.put('InvoiceDate', Util_System.formatDate(invDate, 'yyyy-MM-dd'));
        // if(!String.isBlank(templateId)){
        //  reqMap.put('DocumentLayout', templateId);
        // }
        reqMap.put('SendEmailToCustomer', false);
        reqMap.put('SendInvoiceToCustomerPostbox', false);
        reqMap.put('SendOutputBasedOnAccount', false);

        String endpoint = String.format(Util_FinancialSystem.SALES_INVOICE_PRINT_ENDPOINT, new List<String>{adminCode});

        String response = Util_FinancialSystem.doRequest(admin, endpoint, null, 'POST', JSON.serialize(reqMap), logGuid);
        System.debug(response);
    }

    // This is unused?
    // private static void finalizeInvoiceOrg(String namedCredential, String invoiceId, Date invDate, String templateId, String adminCode, String logGuid){
    //  //Since we're only posting 2 fields, i'll just set up the request using a map
    //  //.... 2 days later.....
    //  //now that we're at 4 fields, maybe it's time to switch to inner class....
    //  Map<String, Object> reqMap = new Map<String, Object>();
    //  reqMap.put('InvoiceID', invoiceId);
    //  reqMap.put('InvoiceDate', Util_System.formatDate(invDate, 'yyyy-MM-dd'));
    //  if(!String.isBlank(templateId)){
    //      reqMap.put('DocumentLayout', templateId);
    //  }
    //  reqMap.put('SendEmailToCustomer', false);

    //  String endpoint = String.format(Util_FinancialSystem.SALES_INVOICE_PRINT_ENDPOINT, new List<String>{adminCode});

    //  String response = Util_FinancialSystem.doRequest(admin, endpoint, null, 'POST', JSON.serialize(reqMap), logGuid);
    // }

    public static String doRequest(Subscription25__Administration__c admin, String endpoint, Map<String, String> params, String method, String requestBody, String logGuid){
        SYstem.debug('any');
        Util_OAuth2 session = Util_OAuth2.getInstance(admin.Subscription25__Named_Credential__c, logGuid);
        String response = '';
        Boolean wasException = false;
        try {
            if(Util_FinancialSystem.getLimits(admin).limitReached()) {
                // Too many tries, retry later.
                Util_System.IntegrationException ex = new Util_System.IntegrationException('Limit reached. Wait until the limits reset before calling out');
                ex.isRetryable = true;
                throw ex;
            }

            HttpResponse res = session.doRequest(endpoint, params, method, requestBody);
            System.debug(res);
            System.debug(res.getBody());
            Util_FinancialSystem.logLimits(res, admin);

            //if the response has status code 204, that means that a PUT was successful, in which case
            //no response body is given. We shouldn't try to actually get the response in that case
            if (res.getStatusCode() == 204){
                return response;
            }
            if (res.getStatusCode() == 429) {
                // Too many tries, retry later.
                Util_System.IntegrationException ex = new Util_System.IntegrationException('Limit reached. Wait until the limits reset before calling out');
                ex.isRetryable = true;
                throw ex;
            }

            Map<String, Object> dirtyResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());

            if(dirtyResponse.containsKey('error')){
                Map<String, Object> errMap = (Map<String, Object>)dirtyResponse.get('error');
                Map<String, Object> msgMap = (Map<String, Object>)errMap.get('message');

                // Throw an exception that can be retried
                throw new Util_System.FinancialSyncException((String)msgMap.get('value'));

            } else {
                //some ugly stuff here to remove some fields from the response because otherwise deserialization fails
                try {
                    Map<String, Object> tmp = (Map<String, Object>)dirtyResponse.get('d');
                    tmp.remove('SalesOrderLines');
                    tmp.remove('Approved');
                    tmp.remove('Created');
                    tmp.remove('DeliveryDate');
                    tmp.remove('Modified');
                    tmp.remove('OrderDate');
                    tmp.remove('BankAccounts');
                } catch(Exception e){}

                response = JSON.serialize(dirtyResponse.get('d'));
            }

        } catch(Util_System.FinancialSyncException exactEx){
            System.debug(exactEx);
            //rethrow custom exceptions (these are the errors given by exact), make sure these are handled
            //at some point in the stack, otherwise finally will not execute, refresh tokens will be invalid
            //and general unpleasantness occurs
            wasException = true;
            throw exactEx;
        } catch(Exception ex){
            System.debug(ex);
            wasException = true;
        }
        return response;
    }

    public static HttpRequest getExactRequest(String endpointURI, String requestBody, String requestMethod, Map<String, String> parameters) {
        HttpRequest request = new HttpRequest();
        request.setTimeout(120000);
        request.setCompressed(false);
        request.setHeader('Cache-Control', 'private');
        request.setHeader('Connection', 'Keep-Alive');
        request.setHeader('Accept', 'application/json');

        // When sending a payload, set the content length and the request body
        if(!String.isBlank(requestBody)){
            request.setHeader('Content-Length', String.valueOf(requestBody.length()));
            request.setBody(requestBody);
        }

        if(requestMethod != 'GET'){
            request.setHeader('Content-Type', 'application/json');
            if(!endpointURI.contains('DirectDebitMandates')) {
                //20230228 TRi - Addition to retrieve complete posted record back DirectDebitMandates are excluded
                request.setHeader('Prefer', 'return=representation');
            }
        } else if (requestMethod == 'GET' && !(parameters == null || parameters.isEmpty())) {
            String parameterString = Util_System.getParameterString(parameters);
            endpointURI = endpointURI + '?' + parameterString;
            endpointURI = endpointURI.replace(' ', '+');
        }
        request.setMethod(requestMethod);
        request.setEndpoint(endpointURI);
        return request;
    }
    public static HttpResponse doExactRequest(HttpRequest request, Subscription25__Administration__c admin) {
        if(Util_FinancialSystem.getLimits(admin).limitReached()) {
            throw new Util_System.FinancialSyncException(Util_FinancialSystem.EX_LIMITS);
        }
        HttpResponse response = new Http().send(request);
        Util_FinancialSystem.logLimits(response, admin);
        return response;
    }
    /**
     * Set the Limits provided by the Exact API responses and store them in Cache
     * @param response Exact API HttpResponse
     */
    public static void logLimits(HttpResponse response, Subscription25__Administration__c admin) {
        Util_FinancialSystem.Limits l = Util_FinancialSystem.getLimits(admin);

        Set<String> responseHeaders = new Set<String>();
        responseHeaders.addAll(response.getHeaderKeys());

        l.minutelyLimit = responseHeaders.contains('X-RateLimit-Minutely-Limit') ? Integer.valueOf(response.getHeader('X-RateLimit-Minutely-Limit')) : l.minutelyLimit;
        l.minutelyRemaining = responseHeaders.contains('X-RateLimit-Minutely-Remaining') ? Integer.valueOf(response.getHeader('X-RateLimit-Minutely-Remaining')) : l.minutelyRemaining;
        // Set minutely reset to start of next minute
        DateTime now = DateTime.now();
        l.minutelyReset = DateTime.newInstance(now.year(), now.Month(), now.day(), now.hour(), now.minute() + 1, 0).getTime();

        l.dailyLimit = responseHeaders.contains('X-RateLimit-Limit') ? Integer.valueOf(response.getHeader('X-RateLimit-Limit')) : l.dailyLimit;
        l.dailyRemaining = responseHeaders.contains('X-RateLimit-Remaining') ? Integer.valueOf(response.getHeader('X-RateLimit-Remaining')) : l.dailyRemaining;
        l.dailyReset = responseHeaders.contains('X-RateLimit-Reset') ? Long.valueOf(response.getHeader('X-RateLimit-Reset')) : l.dailyReset;

        if(response.getStatusCode() > 299 || response.getStatusCode() < 200) {
            l.consecutiveErrors = l.consecutiveErrors + 1;
        } else {
            l.consecutiveErrors = 0;
        }
        Cache.Org.put(Util_FinancialSystem.getCacheName(admin), l);
    }

    /**
     * Get the Limits as these are currently in the cache. If not present, defaults are returned.
     * @return Limit Object containing the current Exact Limits.
     */
    public static Util_FinancialSystem.Limits getLimits(Subscription25__Administration__c admin) {
        if(Cache.Org.contains(Util_FinancialSystem.getCacheName(admin))) {
            return (Util_FinancialSystem.Limits) Cache.Org.get(Util_FinancialSystem.getCacheName(admin));
        } else {
            Util_FinancialSystem.Limits l = new Util_FinancialSystem.Limits(admin);
            Cache.Org.put(Util_FinancialSystem.getCacheName(admin), l);
            return l;
        }
    }

    public static String getCacheName(Subscription25__Administration__c admin) {
        return String.format('{0}{1}', new List<String> {
            Util_FinancialSystem.EXACT_LIMIT_CACHE_NAME,
            admin.Name
        });
    }

    private static Map<Id, Map<String, Map<String, String>>> relationIds;
    //private static String getExactRelationId(Id adminId, Account acct, String field){
    private static String getExactRelationId(Id adminId, String relation, String value){
        if(Util_FinancialSystem.relationIds == null){
            Util_FinancialSystem.relationIds = new Map<Id, Map<String, Map<String, String>>>();
            List<Exact_Relation_Setting__c> setts = [
                SELECT Id, Administration__c, Classification__c, Acting_Value__c, Exact_ID__c
                FROM Exact_Relation_Setting__c
            ];

            for(Exact_Relation_Setting__c sett : setts){
                Id curAdminId = sett.Administration__c;
                String curType = sett.Classification__c;
                //String curField = (curRelationType == '1') ? 'Relation_Type__c' : (!String.isBlank(sett.Customer_Type__c) ? 'Customer_Type__c' : (!String.isBlank(sett.Market__c) ? 'Market__c' : 'Sales_Channel__c'));
                //String curVal = (String)sett.get(curField);
                String curVal = sett.Acting_Value__c;
                String curExactId = sett.Exact_ID__c;
                //system.debug(sett );
                if(!Util_FinancialSystem.relationIds.containsKey(curAdminId)){
                    Util_FinancialSystem.relationIds.put(curAdminId, new Map<String, Map<String, String>>());
                }
                if(!Util_FinancialSystem.relationIds.get(curAdminId).containsKey(curType)){
                    Util_FinancialSystem.relationIds.get(curAdminId).put(curType, new Map<String, String>());
                }
                Util_FinancialSystem.relationIds.get(curAdminId).get(curType).put(curVal, curExactId);
            }
        }

        return Util_FinancialSystem.relationIds.get(adminId).get(relation).get(value);
    }

    private class ExactAccount {
        private String ID;
        //private transient String Code; //we're only supposed to get this back
        private String Code; //we're only supposed to get this back
        private String Name;
        private String AddressLine1;
        private String Postcode;
        private String City;
        private String Country; //should be a country code
        private String Phone;
        private String Email;
        private String ChamberOfCommerce;
        private String VATNumber;
        private String SearchCode;
        private String Status;
        private String AccountManager;
        private String PaymentConditionSales; //Code of Exact_Payment_Method__c
        private String Classification1; //GUID of type relatie (Relation_type__c)
        private String Classification2; //GUID of type klant (Customer_Type__c)
        private String Classification3; //GUID of Reseller (Custom metadata)
        //private String Classification4; //GUID of Reseller (Custom metadata)
        //private String PaymentConditionSales;

        private ExactAccount(Account acct){
            //this.Code = acct.FinancialDebtorNumber__c;

            if (!String.isBlank(acct.FinancialDebtorNumber__c)) {
                this.Code = acct.FinancialDebtorNumber__c;
            }
            this.Name = acct.Exact_Account_Name__c;
            // Addresses are synced separately so that their IDs may be stored
            // this.AddressLine1 = acct.ShippingStreet;
            // this.Postcode = acct.ShippingPostalCode;
            // this.City = acct.ShippingCity;
            // this.Country = acct.ShippingCountryCode;
            this.Phone = acct.Billing_Phone__c;
            this.Email = acct.Billing_Email__c;
            this.ChamberOfCommerce = (acct.CoC_Number__c != '-') ? acct.CoC_Number__c  : '';  //Gen25 26/11/2020 change: acct.WSONE_DATA__DossierNumber__c;
            this.VATNumber = (acct.VAT_Number__c != '-') ? acct.VAT_Number__c : ''; //Gen25 23/1/2020 change: acct.WSONE_DATA__VATNumber__c;
            if (String.isNotBlank(acct.FinancialDebtorNumberPrevious__c)) {
                this.SearchCode = acct.FinancialDebtorNumberPrevious__c;
            }
            this.Status = 'C'; //Account is type Customer
            //this.AccountManager = Util_FinancialSystem.getUserExactId(acct.OwnerId);
            this.PaymentConditionSales = acct.Payment_Method_Contracts__c;
            try {
                Integer reseller = (String.isNotBlank(acct.Reseller_Name__c)) ? Util_System.getAdminExternalId(Long.valueOf(acct.Reseller_Name__c)) : 1;
                string classificationId;

                classificationId = (String.isNotBlank(acct.FinancialAccountClassification1__c)) ? Util_FinancialSystem.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C1', acct.FinancialAccountClassification1__c): '';
                this.Classification1 = (String.isNotBlank(classificationId)) ? classificationId :  null ;
                //system.debug('C1 = ' + classificationId);

                classificationId = (String.isNotBlank(acct.FinancialAccountClassification2__c)) ? Util_FinancialSystem.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C2', acct.FinancialAccountClassification2__c) : '';
                this.Classification2 = (String.isNotBlank(classificationId)) ? classificationId :  null ;
                //system.debug('C2 = ' + classificationId);

                classificationId = (String.isNotBlank(acct.FinancialAccountClassification3__c)) ? Util_FinancialSystem.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C3', acct.FinancialAccountClassification3__c): '';
                //classificationId = (String.isNotBlank(acct.Sales_Channel__c)) ? Util_FinancialSystem.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C3', acct.Sales_Channel__c): '';
                this.Classification3 = (String.isNotBlank(classificationId)) ? classificationId :  null ;
                //system.debug('C3 = ' + classificationId);

            } catch(Exception e){}
            //this.Classification2 = Util_FinancialSystem.getExactRelationId(debNr.Subscription25__Administration__c, acct, 'Customer_Type__c');
            /*Reseller_Setting__mdt resSett = Util_FinancialSystem.getResellerMetadata(acct.Reseller_Name__c);
            if(resSett != null){
                this.Classification3 = resSett.ExactId__c;
            }*/
        }
    }

    private abstract class ExactAddress {
        private transient Schema.SObjectField field;
        private transient Account acct;
        private String ID; // Only used in deserialization
        private String Account;
        private String AddressLine1;
        private String Postcode;
        private String City;
        private String Country; //should be a country code
        private String Contact;
        private Integer Type; //Visit=1, Postal=2, Invoice=3, Delivery=4

        private ExactAddress(Account acct, Schema.SObjectField field) {
            this.acct = acct;
            this.field = field;
        }

        public String getAddressId() {
            return (String) acct.get(field);
        }

        public void setAddressId(String addressID) {
            this.acct.put(this.field, addressID);
        }
    }

    private class VisitingAddress extends ExactAddress {
        public VisitingAddress(Account acct) {
            Super(acct, Schema.Account.FinancialIdVisitingAddress__c);
            this.ID = acct.FinancialIdVisitingAddress__c;
            this.Account = acct.FinancialIdAccount__c;
            this.AddressLine1 = acct.VisitingAddress__Street__s;
            this.Postcode = acct.VisitingAddress__PostalCode__s;
            this.City = acct.VisitingAddress__City__s;
            this.Country = acct.VisitingAddress__CountryCode__s;
            this.Type = 1;
        }
    }

    private class BillingAddress extends ExactAddress {
        public BillingAddress(Account acct) {
            Super(acct, Schema.Account.FinancialIdBillingAddress__c);
            this.ID = acct.FinancialIdBillingAddress__c;
            this.Account = acct.FinancialIdAccount__c;
            this.AddressLine1 = acct.BillingStreet;
            this.Postcode = acct.BillingPostalCode;
            this.City = acct.BillingCity;
            this.Country = acct.BillingCountryCode;
            this.Type = 3;
        }
    }

    public class ShippingAddress extends ExactAddress {
        public ShippingAddress(Account acct) {
            Super(acct, Schema.Account.FinancialIdShippingAddress__c);
            this.ID = acct.FinancialIdShippingAddress__c;
            this.Account = acct.FinancialIdAccount__c;
            this.AddressLine1 = acct.ShippingStreet;
            this.Postcode = acct.ShippingPostalCode;
            this.City = acct.ShippingCity;
            this.Country = acct.ShippingCountryCode;
            this.Type = 4;
        }
    }

    private class ExactBankAccounts {
        private List<Util_FinancialSystem.ExactBankAccount> results;
    }

    private class ExactBankAccount {
        private String ID;
        private String Account;
        private String BankAccount;
        private String BankAccountHolderName;
        private String BICCode;
        private Boolean Main;

        private ExactBankAccount(Account acct) {
            this.Account = acct.FinancialIdAccount__c;
            this.BankAccount = acct.Bank_Account_Number__c;
            this.BankAccountHolderName = acct.Bank_Account__c;
            this.BICCode = acct.Bank_BIC__c;
            // 20230928 - TRi - force to true, bank account salesforce should always be the main bank account
            this.Main = true;
        }
    }

    private class ExactMandate {
        private String ID;
        private String Account;
        private String BankAccount;
        private Boolean Main;
        private Date SignatureDate;
        private Boolean FirstSend;
        private Integer Type;
        private Integer PaymentType;

        private ExactMandate(Account acct){
            this.Account = acct.FinancialIdAccount__c;
            this.BankAccount = acct.FinancialIdBankAccount__c;
            this.Main = true;
            this.SignatureDate = Date.today();
            this.FirstSend = true;
            this.Type = 0; //core
            this.PaymentType = 1; //recurring
        }
    }

    private class ExactContact {
        private String ID;
        private String Account;
        private String FirstName;
        private String MiddleName;
        private String LastName;
        private String Email;
        private String Phone;

        private ExactContact(Account acct, Contact con, AccountContactRelation relation){
            this.Account = acct.FinancialIdAccount__c;
            this.FirstName = con.FirstName;
            this.MiddleName = con.MiddleName;
            this.LastName = con.LastName;
            this.Email = con.Email;
            this.Phone = con.Phone;
        }
    }

    public class ExactOrder {
        private String OrderID;
        private String OrderNumber;
        private String InvoiceTo; //GUID of a customer, assigned by Exact
        private String OrderedBy;
        private String OrderedByContactPerson;
        private DateTime OrderDate;
        private String PaymentCondition;
        private String PaymentReference;
        private String Description;
        private String Remarks; //should be populated with contact person information
        private String SalesChannel;
        private String YourRef;
        private String WarehouseID;
        //private String Salesperson;
        //private transient Integer OrderNumber;
        private List<Util_FinancialSystem.ExactOrderLine> SalesOrderLines;


        public ExactOrder(Order ord, Map<String, String> itemIds, Account acct, AccountContactRelation relation, Subscription25__Administration__c admin){
            this(ord, ord.Opportunity, itemIds, acct, relation, admin);
        }

        public ExactOrder(Order ord, Opportunity opp, Map<String, String> itemIds, Account acct, AccountContactRelation relation, Subscription25__Administration__c admin){
            this(ord, ord.Opportunity, ord.OrderItems, itemIds, acct, relation, admin);
        }

        public ExactOrder(Order ord, Opportunity opp, List<OrderItem> items, Map<String, String> itemIds, Account acct, AccountContactRelation relation, Subscription25__Administration__c admin){
            this.InvoiceTo = acct.FinancialIdAccount__c;
            this.OrderedBy = acct.FinancialIdAccount__c;
            if(!String.isBlank(relation.FinancialIdContact__c)){
                this.OrderedByContactPerson = relation.FinancialIdContact__c;
            }
            this.OrderDate = DateTime.now();
            this.PaymentCondition = ord.Payment_Method_Result__c;
            if (!String.isBlank(ord.Payment_Reference__c)) {
                this.PaymentReference = ord.Payment_Reference__c;
            }
            this.Description = opp.Name;
            this.YourRef = opp.Customer_Reference__c;
            this.Remarks = '';
            if(opp.Sales_Contact__c != null && opp.Sales_Contact__c != acct.Contact_Person__c){
                List<String> ll = new List<String>();
                ll.add(opp.Sales_Contact__r.Name);
                if(opp.Sales_Contact__r.Email != null){
                    ll.add(opp.Sales_Contact__r.Email);
                }
                if(opp.Sales_Contact__r.Phone != null){
                    ll.add(opp.Sales_Contact__r.Phone);
                }
                this.Remarks = String.join(ll, '\r\n');
            }

            string warehouseId = '';

            if (ord.Reseller__c == '1') {
                this.SalesChannel = Util_FinancialSystem.getExactRelationId(admin.Id, 'SC', ord.Sales_Channel__c);
                warehouseId = Util_FinancialSystem.getExactRelationId(admin.Id, 'WH', ord.Sales_Channel__c);
            }

            this.WarehouseID = String.isNotBlank(warehouseId) ? warehouseId : admin.Warehouse_Exact_Id__c;

            this.SalesOrderLines = new List<Util_FinancialSystem.ExactOrderLine>();
            integer i = 0;
            for(OrderItem oi : items){
                i += 1;
                this.SalesOrderLines.add(new Util_FinancialSystem.ExactOrderLine(ord, opp, oi, i, itemIds));
            }
        }

        public String getOrderId() {
            return this.OrderID;
        }

        public String getOrderNumber() {
            return this.OrderNumber;
        }
    }

    public class ExactOrderLines {
        private List<Util_FinancialSystem.ExactOrderLine> results;

        public List<Util_FinancialSystem.ExactOrderLine> getResults() {
            return this.results;
        }
    }

    public class ExactOrderLine {
        private String ID;
        private String Item; //GUID of an item in Exact, apparently mandatory...
        private Decimal Quantity;
        private Decimal UnitPrice;
        private String CustomerItemCode;
        private String Description;
        private String Notes; //populated with some sort of string with lines with a product with a certain type

        private ExactOrderLine(Order ord, Opportunity opp, OrderItem oi, Integer i, Map<String, String> itemIds) {
            this.Item = itemIds.get(oi.Product2.ProductCode);
            this.Quantity = oi.Quantity;
            this.UnitPrice = oi.UnitPrice;
            // 20220823 - TRi - Product_Name__c added to handle the translations for product.name on order item level
            this.Description = (oi.Product_Code_Customer__c != null) ? oi.Product_Code_Customer__c + ' ' : '';
            this.Description += (oi.Product_Name__c != null) ? oi.Product_Name__c : oi.Product2.Name;

            if ((oi.Partner_Code__c != null) && (oi.Product2.RecordType.DeveloperName == 'SubscriptionP') && (oi.Product2.Generate_Partner_Code__c)) {
                this.Notes = '--------------------------------------------------------------------------------' + '\n';
                this.Notes += 'Partner code : ' + oi.Partner_Code__c + '\n';
                this.Notes += '--------------------------------------------------------------------------------' + '\n';
            } else {
                this.Notes = '';
            }

            if((i == 1) && !String.isBlank(opp.Installation_Notes__c)){
                this.Notes += opp.Installation_Notes__c;
            }
        }

        public String getId() {
            return this.ID;
        }

        public String getItemId() {
            return this.Item;
        }
    }

    private class ExactItems {
        private List<Util_FinancialSystem.ExactItem> results;
    }

    private class ExactItem {
        private String Code;
        private String ID;
    }

    private class ExactInvoices {
        private List<Util_FinancialSystem.ExactInvoice> results;
    }

    private class ExactInvoice {
        private String InvoiceID;
        private String InvoiceNumber;
        private Integer Status;
    }

    /**
     * Contains info on the Exact Limitations and other settings.
     */
    public class Limits {
        public Integer dailyLimit;
        public Integer dailyRemaining;
        public Long dailyReset;
        public Integer minutelyLimit;
        public Integer minutelyRemaining;
        public Long minutelyReset;
        public Integer consecutiveErrors;
        public Integer accountSyncTimeStamp;

        // Set default Values
        public Limits(Subscription25__Administration__c admin) {
            // GS May want to change this if and when Exact ever decides to release a proper API...
            this.dailyLimit = admin.Daily_Limit__c?.intValue();
            this.dailyRemaining = admin.Daily_Limit__c?.intValue();
            this.dailyReset = 0;
            this.minutelyLimit = 60;
            this.minutelyRemaining = 60;
            this.minutelyReset = 0;
            this.consecutiveErrors = 0;
            this.accountSyncTimeStamp = 1;
        }

        public Boolean limitReached() {
            if(this.dailyRemaining <= 1) {
                System.debug('Daily');
                return true;
            } else if(this.minutelyRemaining <= 1 && this.dailyReset > System.now().getTime()) {
                System.debug('Minute');
                return true;
            } else if(this.consecutiveErrors >= 2) {
                System.debug('Consecutive');
                // More than two consecutive errors will block the application. Means that the integration will want to
                // call something that will work first.
                return true;
            }
            return false;
        }
        public void setAccountSyncTimestamp(Integer value) {
            this.accountSyncTimeStamp = value;
        }

        public void reserveCapacity(Integer numberOfCalls) {
            if (!this.hasCapacity(numberOfCalls)) {
                throw new Util_System.FinancialSyncException(Util_FinancialSystem.EX_LIMITS);
            }
        }

        public Boolean hasCapacity(Integer numberOfCalls) {
            this.evaluateReset();
            return this.hasMinutelyCapacity(numberOfCalls)
                && this.hasDailyCapacity(numberOfCalls);
        }

        private Boolean hasMinutelyCapacity(Integer numberOfCalls) {
            Boolean hasExpired = this.minutelyReset < System.now().getTime();
            Boolean hasCapacity = this.minutelyRemaining >= numberOfCalls;
            return hasCapacity;
        }

        private Boolean hasDailyCapacity(Integer numberOfCalls) {
            Boolean hasExpired = this.dailyReset < System.now().getTime();
            Boolean hasCapacity = this.dailyRemaining >= numberOfCalls;
            return hasCapacity;
        }

        private void evaluateReset() {
            this.minutelyRemaining = Util_FinancialSystem.hasTimeExpired(this.minutelyReset)
                ? this.minutelyLimit
                : this.minutelyRemaining;
            this.dailyRemaining = Util_FinancialSystem.hasTimeExpired(this.dailyReset)
                ? this.dailyLimit
                : this.dailyRemaining;
        }
    }

    private static Boolean hasTimeExpired(Long resetTime) {
        return resetTime <= System.now().getTime();
    }
}