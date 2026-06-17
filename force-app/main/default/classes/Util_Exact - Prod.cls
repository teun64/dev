public without sharing class Util_Exact {
	//bit of a weird way to do this, but it's quick and it works well
	//ADMIN_CODE is stored in a custom setting, all endpoints need the admin code in them
	//private static final String ADMIN_CODE = Exact_Settings__c.getAll().get('ADMIN_CODE').String_Value__c;

	private static final String ACCOUNT_ENDPOINT = 'api/v1/{0}/crm/Accounts';
	private static final String ACCOUNT_GET_ENDPOINT = 'api/v1/{0}/bulk/CRM/Accounts';
	private static final String ADDRESS_ENDPOINT = 'api/v1/{0}/crm/Addresses';
	private static final String BANK_ACCOUNT_ENDPOINT = 'api/v1/{0}/crm/BankAccounts';
	private static final String CONTACT_ENDPOINT = 'api/v1/{0}/crm/Contacts';
	private static final String MANDATE_ENDPOINT = 'api/v1/{0}/cashflow/DirectDebitMandates';
	private static final String ORDER_ENDPOINT = 'api/v1/{0}/salesorder/SalesOrders';
	private static final String ARTICLE_ENDPOINT = 'api/v1/{0}/logistics/Items';
	private static final String ARTICLE_GET_ENDPOINT = 'api/v1/{0}/bulk/Logistics/Items';
	private static final String SALES_INVOICE_ENDPOINT = 'api/v1/{0}/salesinvoice/SalesInvoices';
	private static final String SALES_INVOICE_GET_ENDPOINT = 'api/v1/{0}/bulk/salesinvoice/SalesInvoices';
	private static final String SALES_INVOICE_PRINT_ENDPOINT = 'api/v1/{0}/salesinvoice/PrintedSalesInvoices';

/*	private static Map<String, Reseller_Setting__mdt> resellerSettingMap;
	public static Reseller_Setting__mdt getResellerMetadata(String resellerMiId){
		if(Util_Exact.resellerSettingMap == null){
			Util_Exact.resellerSettingMap = new Map<String, Reseller_Setting__mdt>();
			List<Reseller_Setting__mdt> resSetts = [
				SELECT Id, ExactId__c, MI_ID__c, Sync_to_Exact__c FROM Reseller_Setting__mdt
			];
			for(Reseller_Setting__mdt resSett : resSetts){
				Util_Exact.resellerSettingMap.put(resSett.MI_ID__c, resSett);
			}
		}
		return Util_Exact.resellerSettingMap.get(resellerMiId);
	}*/

	@future(callout=true)
	public static void syncAccountAsync(Id acctId, String logGUID){
		Util_Exact.syncAccount(acctId, logGUID);
	}

	@future(callout=true)
	public static void syncAccountAsync(Id acctId){
		Util_Exact.syncAccount(acctId);
	}

	public static List<String> syncAccount(Id acctId){
		//Logger logger = Logger.getInstance();
        //String sessionId = logger.startSession(RestContext.request, 'RestUpsertAccount', 'S'); // TODO: Set calling system?

		return Util_Exact.syncAccount(acctId, null);
	}

	public static List<String> syncAccount(Id acctId, String logGUID){
		//, FinancialAccountClassification3__c, depending on salesforce case
		Account acct = [
			SELECT Id, RecordType.DeveloperName, VAT_Number__c, CoC_Number__c
				, Reseller_Name__c, Market__c, Relation_Type__c, Sales_Channel__c, Customer_Type__c
				, Block_Syncing_Exact__c, Name, OwnerId, Payment_Method_Contracts__c, Exact_Account_Name__c
				, ShippingStreet, ShippingPostalCode, ShippingCity, ShippingCountryCode
				, BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode, Billing_Phone__c, Billing_Email__c
				, Bank_Account_Number__c, Bank_Account__c, Bank_BIC__c, Bank_Country__c 
				, FinancialDebtorCheck__c, FinancialNumberOfDebtors__c, FinancialReplaceDebtorNumber__c
				, FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c, FinancialIdAccount__c, FinancialIdVisitingAddress__c,  FinancialIdBillingAddress__c,  FinancialIdShippingAddress__c,  FinancialIdBankAccount__c, FinancialIdBankMandate__c
				, FinancialAccountClassification1__c, FinancialAccountClassification2__c, FinancialAccountClassification3__c
				, Contact_person__c, Contact_person__r.FinancialIdContact__c, Contact_person__r.FirstName, Contact_person__r.MiddleName, Contact_person__r.LastName, Contact_person__r.Email, Contact_person__r.Phone					
				, Contact_Billing__c, Contact_Billing__r.FinancialIdContact__c, Contact_Billing__r.FirstName, Contact_Billing__r.MiddleName, Contact_Billing__r.LastName, Contact_Billing__r.Email, Contact_Billing__r.Phone					
				, Contact_Shipping__c, Contact_Shipping__r.FinancialIdContact__c, Contact_Shipping__r.FirstName, Contact_Shipping__r.MiddleName, Contact_Shipping__r.LastName, Contact_Shipping__r.Email, Contact_Shipping__r.Phone					
			FROM Account
			WHERE Id = :acctId
		];

		List<String> msgs = new List<String>();
		Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', 'E', 'Account', 'sync2Exact', acctId, acct.Exact_Account_Name__c, null);
		Subscription25__Debtor_Number__c curDebNr;
		String namedCredential; //this is used below the try block, where the logs get saved.

		try {
			//system.debug(acct);
            
			//niet shipping country = NL, validatie zoals B2C
			//skip validation for unit tests... ew

			//List<Profile> profiles = [SELECT Id, Name FROM Profile WHERE Id=:userinfo.getProfileId() LIMIT 1];
			//String profileName = profiles[0].Name;
			//system.debug(profileName);
			Boolean skipDataCheck = FeatureManagement.checkPermission('cp_miIntegrationSkipDataCheck');
			//system.debug(skipDataCheck);

			if (!skipDataCheck) {
				if(acct.Reseller_Name__c == '1' && acct.RecordType.DeveloperName != 'B2C' && acct.ShippingCountryCode == 'NL' && acct.Block_Syncing_Exact__c){
					throw new Util_System.CustomException('This account is not validated by Web Services, this validation has to be completed before this account can be synchronised.');
				} else if (Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c) && (String.isBlank(acct.Bank_Account_Number__c) || String.isBlank(acct.Bank_Account__c))){
					//Reseller 1 requires an bank account
					throw new Util_System.CustomException('This account can not be synchronised because the bank account is not filled in.');
				} else if (String.isBlank(acct.ShippingCountryCode) || String.isBlank(acct.ShippingStreet) || String.isBlank(acct.ShippingPostalCode) || String.isBlank(acct.ShippingCity)){
					throw new Util_System.CustomException('This account can not be synchronised because the shipping address is not filled in.');
				} else if (String.isBlank(acct.BillingCountryCode) || String.isBlank(acct.BillingStreet) || String.isBlank(acct.BillingPostalCode) || String.isBlank(acct.BillingCity)){
					throw new Util_System.CustomException('This account can not be synchronised because the billing address is not filled in.');
				}
			}

			Integer adminExternalId = Util_System.getAdminExternalId(Long.valueOf(acct.Reseller_Name__c));
			Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);

			//make sure sync is enabled for this administration
			//remove reseller when go live subscription25
			if(admin.Subscription25__Synchronisation__c != 'Exact' || !admin.Subscription25__Active__c){
				throw new Util_System.CustomException('This accounts reseller does not synchronize with Exact');
			}

			String adminCode = admin.Subscription25__Twinfield_Company_Code__c;
			namedCredential = admin.Subscription25__Named_Credential__c;

			//track if we have to save the debtor number in the end
			Boolean saveDebtorNumber = false;
			
			List<Subscription25__Debtor_Number__c> debtorNumbers = [
				SELECT Id, Subscription25__Composite_Key__c, Subscription25__Administration__c, Subscription25__Debtor_Number__c, 
					Exact_Id__c, Exact_Bank_Account_ID__c, Exact_Billing_Address_ID__c, Exact_Contact_ID__c, Exact_Mandate_Id__c
				FROM Subscription25__Debtor_Number__c
				WHERE Subscription25__Administration__c = :admin.Id
					AND Subscription25__Account__c = :acct.Id
			];

			//if there is no debtor number on the account for this administration yet, instantiate a new one now
			//this will contain all the Exact Ids for this account in this administration (fields on account are
			//still present and used, because for now, accounts will only be synced to 1 administration)

			if (debtorNumbers.size() >= 1) {
				curDebNr = debtorNumbers[0];
				debtorNumbers.remove(0);
			}

			if (curDebNr == null) {
				curDebNr = new Subscription25__Debtor_Number__c();
				curDebNr.Subscription25__Account__c = acct.Id;
				curDebNr.Subscription25__Administration__c = admin.Id;
				curDebNr.Subscription25__Composite_Key__c = '' + acct.Id + admin.Id;
				curDebNr.Subscription25__Debtor_Number__c = '';
				curDebNr.Exact_Id__c = '';
				saveDebtorNumber = true;
			} else if (String.isBlank(curDebNr.Exact_Id__c)) {
				//check on exact id, when empty, clear debtor number and exact relations
				if (acct.FinancialDebtorCheck__c) {
					curDebNr.Subscription25__Debtor_Number__c = '';
				}

				saveDebtorNumber = true;
			}

			//system.debug(curDebNr);

			//if this throws an FinancialSyncException, it's caught all the way at the end, because we don't want
			//the function to continue when the account itself fails.
			//system.debug('account');

			boolean isNewExactAccount = false;

			String previousExactID = (curDebNr.Exact_Id__c == null) ? '' : curDebNr.Exact_Id__c;

			String accountMethod = Util_Exact.syncAccount(acct, curDebNr, adminCode, namedCredential, mainLog.GUID__c);
			saveDebtorNumber |= accountMethod == 'POST'; //if this was an insert, we have to update the account later
			saveDebtorNumber |= accountMethod == 'pseudoPOST';

			if ((!String.isBlank(previousExactID) && (curDebNr.Exact_Id__c != previousExactID) && (accountMethod != 'pseudoPOST')) || (accountMethod == 'POST')) {
				curDebNr.Exact_Contact_Id__c = '';
				curDebNr.Exact_Billing_Address_Id__c = '';
				curDebNr.Exact_Bank_Account_Id__c = '';				
				curDebNr.Exact_Mandate_Id__c = '';
				isNewExactAccount = true;				
			}

			//once more into the fray for contacts
			//system.debug('contact');
			if(!String.isBlank(curDebNr.Exact_Id__c) && acct.Contact_person__c != null) {
				try {
					//system.debug('doSyncContact');					
					String contactMethod = Util_Exact.syncContact(acct, curDebNr, adminCode, namedCredential, mainLog.GUID__c);
					saveDebtorNumber |= contactMethod == 'POST'; //same logic, if we posted, that means we have to save.
				} catch(Util_System.FinancialSyncException e){
					//same handling of FinancialSyncExceptions
					mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
					mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
					msgs.add(e.getMessage());
				}
			}
			
			//now we can also create/update the billing address, this method also populates the Exact_Billing_Address_Id__c field
			//on the given account (and debtor number), it returns the method that it applied (so we know if DML on the account is required)
			//only sync billing address if it differs from the shipping address
			//system.debug('billing address');
			if(!String.isBlank(curDebNr.Exact_Id__c) && !String.isBlank(acct.BillingCity) && (acct.BillingStreet != acct.ShippingStreet || acct.BillingPostalCode != acct.ShippingPostalCode
					|| acct.BillingCity != acct.ShippingCity || acct.BillingCountryCode != acct.ShippingCountryCode)){
				try {
					String billingMethod = Util_Exact.syncBillingAddress(acct, curDebNr, adminCode, namedCredential, mainLog.GUID__c);
					saveDebtorNumber |= billingMethod == 'POST'; //if the billing address was an insert, we have to save the account so the id gets updated
				} catch(Util_System.FinancialSyncException e){
					//same handling of FinancialSyncExceptions as all the way below
					mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
					mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
					msgs.add(e.getMessage());
				}
			}

			//do the same for the bank account
			//system.debug('bank account');
			if(!String.isBlank(curDebNr.Exact_Id__c) && !String.isBlank(acct.Bank_Account_Number__c)){
				try {
					String previousExactBankAccountId = curDebNr.Exact_Bank_Account_Id__c;
					String bankAcctMethod = Util_Exact.syncBankAccount(acct, isNewExactAccount, curDebNr, adminCode, namedCredential, mainLog.GUID__c);

					//saveDebtorNumber |= (bankAcctMethod == 'POST'); //same logic, if we posted, that means we have to save.
					saveDebtorNumber |= (previousExactBankAccountId != curDebNr.Exact_Bank_Account_Id__c); //same logic, if we posted, that means we have to save.

					//do the mandate only if the bank account was created
					//if(((bankAcctMethod == 'POST') || String.isBlank(curDebNr.Exact_Mandate_ID__c)) && String.isNotBlank(curDebNr.Exact_Bank_Account_ID__c) && Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c)){
					if(((previousExactBankAccountId != curDebNr.Exact_Bank_Account_Id__c) || String.isBlank(curDebNr.Exact_Mandate_ID__c)) && String.isNotBlank(curDebNr.Exact_Bank_Account_ID__c) && Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c)){
							//system.debug('mandate');
						String mandateMethod = Util_Exact.syncMandate(acct, curDebNr, adminCode, namedCredential, mainLog.GUID__c);

						saveDebtorNumber |= (mandateMethod == 'POST'); //20230331 - TRi added, same logic, if we posted, that means we have to save.
					}
				} catch(Util_System.FinancialSyncException e){
					//same handling of FinancialSyncExceptions
					mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
					mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
					msgs.add(e.getMessage());
				}
			}

			if(saveDebtorNumber){
				try {
					//
					//we have to load the Debtor number from exact here
					//System.debug('Debtor Number (Befor Save) -> ' + acct.FinancialDebtorNumber__c );

					//we have to load the Debtor number from exact here
					if(String.isBlank(curDebNr.Subscription25__Debtor_Number__c)){
						//System.debug('Why is the debtor blank');
						curDebNr.Subscription25__Debtor_Number__c = Util_Exact.getDebtorNumber(curDebNr.Exact_Id__c, adminCode, namedCredential, mainLog.GUID__c);
					}

					if (curDebNr.Subscription25__Debtor_Number__c <> acct.FinancialDebtorNumber__c) {
						acct.FinancialIdAccount__c = curDebNr.Exact_Id__c;
						acct.FinancialDebtorNumber__c = curDebNr.Subscription25__Debtor_Number__c;
						//store all the exact ids and debtor number
						Database.update(acct);
					}
					//System.debug('Debtor Number- Debtor Number (After Save) -> ' + curDebNr.Subscription25__Debtor_Number__c );
					//System.debug('Debtor Number- Account (After Save) -> ' + acct.FinancialDebtorNumber__c );

					//also store the actual debtor number on the debtor number record
					Database.upsert(curDebNr, Subscription25__Debtor_Number__c.Subscription25__Composite_Key__c);
					//system.debug(curDebNr);
				} catch(Util_System.FinancialSyncException e){
					//same handling of FinancialSyncExceptions
					mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
					mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
					msgs.add(e.getMessage());
				}
			}

			if (debtorNumbers.size() >= 1) {
				database.delete(debtorNumbers);
			}

		} catch(Util_System.FinancialSyncException e){
			//FinancialSyncException is thrown by Util_Exact.doRequest, happens when exact returns an error (validation or something, exact side)
			//when this happens, this function should continue (so for instance, only address creation fails). The
			//actual error will be logged in the OAuth log, status of the exact log should be WARNING or something
			//the messages should be relayed on to the user
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


		mainlog.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
		mainlog.extId__c = (curDebNr == null) ? '' : curDebNr.Exact_Id__c;
		//now save the logs and the tokens
		//system.debug('deze');
		Database.upsert(mainLog, Event_Log__c.GUID__c);
		//system.debug('die');
		Util_OAuth.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		//system.debug('oeps');
		return msgs;
	}

	private static String syncAccount(Account acct, Subscription25__Debtor_Number__c debNr, String adminCode, String namedCredential, String logGuid){
		Util_Exact.ExactAccount exactAcct = new Util_Exact.ExactAccount(acct, debNr);

		//set up the request to upsert the account. On update we have to use PUT, with the GUID in the URL
		String endpoint = String.format(Util_Exact.ACCOUNT_ENDPOINT, new List<String>{adminCode});
		String getEndpoint = String.format(Util_Exact.ACCOUNT_GET_ENDPOINT, new List<String>{adminCode});
		String method = 'POST';
		string getMethod = 'GET';
		Boolean pseudoPost = false;

		//if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
		if (!acct.FinancialDebtorCheck__c && !acct.FinancialReplaceDebtorNumber__c) {
			//if (acct.Reseller_Name__c == '5') {
			Map<String, String> accountParams = new Map<String, String>();
			String exactCode = String.isNotBlank(exactAcct.Code) ? ('                  ' + exactAcct.Code) : null;
			exactCode = String.isNotBlank(exactCode) ? exactCode.right(18) : null;
	
			List<String> accountFilters = new List<String>();
			Boolean accountFilterSet = false;

			if (String.isNotBlank(debNr.Exact_ID__c)) {
				accountFilters.add('(ID eq guid\''+debNr.Exact_ID__c+'\')');
				accountFilterSet = true;
			}

			if (String.isNotBlank(exactCode)) {
				accountFilters.add('(Code eq \''+exactCode+'\')');
				accountFilterSet = true;
			}

			String getName = Util_Exact.odataString(exactAcct.Name);
			String getAddressLine1 = Util_Exact.odataString(exactAcct.AddressLine1);

			//system.debug(getName);
			//system.debug(getAddressLine1);			

			if (String.isNotBlank(getName) && String.isNotBlank(getAddressLine1)) {
				List<String> accountNameFilter = new List<String>();
				Boolean accountNAmeFilterSet = false;
				String getPostcode = Util_Exact.odataString(exactAcct.Postcode);
				String getCity = Util_Exact.odataString(exactAcct.City);
				//system.debug(getPostcode);
				//system.debug(getCity);

				//AddressLine1 = EncodingUtil.urlEncode(AddressLine1, 'UTF-8');

				accountNameFilter.add('(Name eq \''+getName+'\')');
				accountNameFilter.add('(AddressLine1 eq \''+getAddressLine1+'\')');
				
				if (String.isNotBlank(getPostcode)) {
					accountNameFilter.add('(Postcode eq \''+getPostcode+'\')');
					accountNAmeFilterSet = true;
				}

				if (String.isNotBlank(getCity)) {
					accountNameFilter.add('(City eq \''+getCity+'\')');
					accountNAmeFilterSet = true;
				}

				if (accountNAmeFilterSet) {
					//accountFilters.add('((Name eq \''+exactAcct.Name+'\') and (AddressLine1 eq \''+exactAcct.AddressLine1+'\') and (Postcode eq \''+exactAcct.Postcode+'\') and (City eq \''+exactAcct.City+'\'))');
					accountFilters.add('('+String.join(accountNameFilter, ' and ')+')');
					accountFilterSet = true;
				}
			}

			if (accountFilterSet) {
				//accountParams.put('$format', 'json');
				accountParams.put('$select', 'ID,Code,Name,AddressLine1,Postcode,City,Country,Phone,Email,ChamberOfCommerce,VATNumber,SearchCode,MainContact');
				accountParams.put('$filter', String.join(accountFilters, ' or '));
				accountParams.put('$orderby', 'Code desc');

				string getResponse = Util_Exact.doRequest(namedCredential, endpoint, accountParams, getMethod, null, logGuid);
				//system.debug(getResponse);

				if (string.isNotBlank(getResponse)) {
					Util_Exact.ExactGetAccounts financialAccounts = (Util_Exact.ExactGetAccounts)JSON.deserialize(getResponse, Util_Exact.ExactGetAccounts.class);

					system.debug(financialAccounts);
					if ((financialAccounts.results != null) && (financialAccounts.results.size() >= 1)) {
						if (debNr.Exact_Id__c != financialAccounts.results[0].ID) {
							debNr.Exact_Id__c = financialAccounts.results[0].ID;
							acct.FinancialIdAccount__c = financialAccounts.results[0].ID;
							debNr.Exact_Contact_Id__c = null;
							debNr.Exact_Billing_Address_Id__c = null;
							debNr.Exact_Bank_Account_Id__c = null;
							debnr.Exact_Mandate_ID__c = null;
						}

						if (exactAcct.Code != financialAccounts.results[0].Code) {
							exactAcct.Code = financialAccounts.results[0].Code;
							debNr.Subscription25__Debtor_Number__c = financialAccounts.results[0].Code;
							acct.FinancialDebtorNumber__c = financialAccounts.results[0].Code;
						}

						if (debNr.Exact_Contact_Id__c != financialAccounts.results[0].MainContact) {
							//exactAcct.MainContact = financialAccounts.results[0].MainContact;
							debNr.Exact_Contact_Id__c = financialAccounts.results[0].MainContact;
						}

						acct.FinancialNumberOfDebtors__c = financialAccounts.results.size();
					}

					acct.FinancialDebtorCheck__c = true;
					acct.FinancialReplaceDebtorNumber__c = false;
					pseudoPost = true;
				}
			}	
		}

		if (String.isNotBlank(debNr.Exact_ID__c)) {
			endpoint += '(guid\''+debNr.Exact_ID__c+'\')';
			method = 'PUT'; 
		}

		//system.debug(method);
		//system.debug(exactAcct);
		
		string response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(exactAcct), logGuid);

		//if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
		if(method == 'POST'){
			//system.debug(response);
			Util_Exact.ExactAccount responseAccount = (Util_Exact.ExactAccount)JSON.deserialize(response, Util_Exact.ExactAccount.class);

			//system.debug(responseAccount);
			//system.debug('Exact_ID - Debtor Number: ' + responseAccount.ID);
			//system.debug('Debtor Number  - Debtor Number: ' + responseAccount.Code);
			debNr.Exact_ID__c = responseAccount.ID;
			debNr.Subscription25__Debtor_Number__c = responseAccount.Code;
			acct.FinancialDebtorCheck__c = true;
			acct.FinancialReplaceDebtorNumber__c = false;
			acct.FinancialNumberOfDebtors__c = 1;

		} else if (pseudoPost) {
			method = 'pseudoPOST';
		}

		return method;
	}

	private static string odataString(String str) {
		
		if (String.isBlank(str)) {
			return str;
		}

		String retStr = str.replaceAll('\'','\'\'');
		retStr = retStr.replaceAll('[\\s]',' ');
		retStr = retStr.replaceAll('[*|\\t]','');
		retStr = retStr.replace('  ',' ');
		retStr = retStr.trim();
		retstr = EncodingUtil.urlEncode(retstr, 'UTF-8');

		return retStr;
	}

	private static String syncBillingAddress(Account acct, Subscription25__Debtor_Number__c debNr, String adminCode, String namedCredential, String logGuid){
		Util_Exact.ExactAddress billAddress = new Util_Exact.ExactAddress(acct, debNr);

		//set up the request to upsert the address. On update we have to use PUT, with the GUID in the URL
		String endpoint = String.format(Util_Exact.ADDRESS_ENDPOINT, new List<String>{adminCode});
		String method = 'POST';

		//if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
		if(!String.isBlank(debNr.Exact_Billing_Address_ID__c)){
			endpoint += '(guid\''+debNr.Exact_Billing_Address_ID__c+'\')';
			method = 'PUT';
		}
		String response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(billAddress), logGuid);

		//if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
		if(method == 'POST'){
			Util_Exact.ExactAddress responseAddress = (Util_Exact.ExactAddress)JSON.deserialize(response, Util_Exact.ExactAddress.class);
			//acct.Exact_Billing_Address_Id__c = responseAddress.ID;
			debNr.Exact_Billing_Address_ID__c = responseAddress.ID;
			//20230328 - TRi forces account update when saving debtornummer
			acct.FinancialDebtorNumber__c = '';
			acct.FinancialIdBillingAddress__c = responseAddress.ID;
		}
		return method;
	}

	private static String syncBankAccount(Account acct, boolean isNewExactAccount, Subscription25__Debtor_Number__c debNr, String adminCode, String namedCredential, String logGuid){
		Util_Exact.ExactBankAccount bankAccount = new Util_Exact.ExactBankAccount(acct, debNr);

		//set up the request to upsert the bank account. On update we have to use PUT, with the GUID in the URL
		String endpoint = String.format(Util_Exact.BANK_ACCOUNT_ENDPOINT, new List<String>{adminCode});
		String method;
		String response;

		//if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
		//update bank account is not possible, only update of the main field is allowed
		//if(!String.isBlank(debNr.Exact_Bank_Account_ID__c)){
		//	endpoint += '(guid\''+debNr.Exact_Bank_Account_ID__c+'\')';
		//	method = 'PUT';
		//}
		if (isNewExactAccount) {
			method = 'POST';		
			response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(bankAccount), logGuid);
		}

		if ((!isNewExactAccount) || ((response == '500') && (String.isBlank(debNr.Exact_Bank_Account_ID__c)) && (String.isNotBlank(bankAccount.BankAccount)))) {
			// 20230328 - TRi - BankAccount exists retrieve it and update it
			Map<String, String> params = new Map<String, String>();
			params.put('$select', 'ID,BICCode,BankAccountHolderName,Main,BankAccount');
	
			List<String> codeFilters = new List<String>();
			codeFilters.add('Account eq guid\''+debNr.Exact_ID__c+'\'');
			codeFilters.add('BankAccount eq \''+bankAccount.BankAccount+'\'');

			params.put('$filter', String.join(codeFilters, ' and '));
			//system.debug('start check exact bankaccount');

			method = 'GET';
			response = Util_Exact.doRequest(namedCredential, endpoint, params, method, null, logGuid);

			Util_Exact.ExactBankAccounts financialBankAccounts = (Util_Exact.ExactBankAccounts)JSON.deserialize(response, Util_Exact.ExactBankAccounts.class);

			if (financialBankAccounts.results.size() >= 1) {
				debNr.Exact_Bank_Account_ID__c = financialBankAccounts.results[0].ID;
				//system.debug('exact bankaccount - Number : ' + financialBankAccounts.results[0].BankAccount);
				//system.debug('exact bankaccount - ID : ' + financialBankAccounts.results[0].ID);
				//20230328 - TRi forces account update when saving debtornummer
				acct.FinancialDebtorNumber__c = '';
				acct.FinancialIdBankAccount__c = financialBankAccounts.results[0].ID;
				//acct.Bank_BIC__c = financialBankAccounts.results[0].BICCode;

				if ((!financialBankAccounts.results[0].Main) || ((financialBankAccounts.results[0].BankAccountHolderName != acct.Bank_Account__c) && (String.isNotBlank(acct.Bank_Account__c)))) {
					// set bankaccount to main
					method = 'PUT';
					endpoint += '(guid\''+debNr.Exact_Bank_Account_ID__c+'\')';
					response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(bankAccount), logGuid);
					if (!financialBankAccounts.results[0].Main) {
						// kill the mandate to get a new one
						debNr.Exact_Mandate_ID__c = ''; 
					}
				}

			} else {
				// no bank existing bank account found, post the new one
				method = 'POST';
				response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(bankAccount), logGuid);

				if (response == '500') {
					throw new Util_System.CustomException('The bankaccount (' + acct.Bank_Account_Number__c + ') is not accepted by the financial system, please check!');
				} else {
					//20230328 - TRi forces account update when saving debtornummer
					acct.FinancialDebtorNumber__c = '';
					debNr.Exact_Mandate_ID__c = '';
					acct.FinancialIdBankMandate__c = '';
				}
			}
		} 
		
		if(method == 'POST') {
			//if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
			//post requires new mandate, make id blank
			Util_Exact.ExactBankAccount responseBankAccount = (Util_Exact.ExactBankAccount)JSON.deserialize(response, Util_Exact.ExactBankAccount.class);
			//system.debug(responseBankAccount);
			debNr.Exact_Bank_Account_ID__c = responseBankAccount.ID;
			debNr.Exact_Mandate_ID__c = '';
			//20230328 - TRi forces account update when saving debtornummer
			acct.FinancialDebtorNumber__c = '';
			//acct.Bank_BIC__c = responseBankAccount.BICCode;
			acct.FinancialIdBankAccount__c = responseBankAccount.ID;
			acct.FinancialIdBankMandate__c = '';
		}

		return method;
	}

	private static String syncMandate(Account acct, Subscription25__Debtor_Number__c debNr, String adminCode, String namedCredential, String logGuid){
		Util_Exact.ExactMandate mandate = new Util_Exact.ExactMandate(acct, debNr);

		//set up the request to upsert the bank account. On update we have to use PUT, with the GUID in the URL
		String endpoint = String.format(Util_Exact.MANDATE_ENDPOINT, new List<String>{adminCode});
		String method = 'POST';
		//if we have an Exact Id on the account, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
		if(!String.isBlank(debNr.Exact_Mandate_ID__c)){
			endpoint += '(guid\''+debNr.Exact_Mandate_ID__c+'\')';
			method = 'PUT';
		}
		String response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(mandate), logGuid);

		//if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
		if(method == 'POST'){
			Util_Exact.ExactMandate responseMandate = (Util_Exact.ExactMandate)JSON.deserialize(response, Util_Exact.ExactMandate.class);
			debNr.Exact_Mandate_ID__c = responseMandate.ID;
			acct.FinancialDebtorNumber__c = '';
			acct.FinancialIdBankMandate__c = responseMandate.ID;
		}
		return method;
	}

	private static String syncContact(Account acct, Subscription25__Debtor_Number__c debNr, String adminCode, String namedCredential, String logGuid){
		Util_Exact.ExactContact cont = new Util_Exact.ExactContact(acct, debNr);
		//system.debug('syncContact');
		//system.debug(cont);
		//set up the request to upsert the contact. On update we have to use PUT, with the GUID in the URL
		String endpoint = String.format(Util_Exact.CONTACT_ENDPOINT, new List<String>{adminCode});
		//system.debug(endpoint);
		String method = 'POST';

		//if we have an Exact Id on the debtor number, that means this will be an update, using the PUT method and adding the GUID to the endpoint.
		if(String.isNotBlank(debNr.Exact_Contact_ID__c)){
			//we're now returning 'PUT' here, without actually calling out, because apparently updating a contact
			//is not allowed through the api (LEX) Wil je dit ff nakijken ajb ?
			endpoint += '(guid\''+debNr.Exact_Contact_ID__c+'\')';
			method = 'PUT';
		}

		//system.debug(method);
		//system.debug(endpoint);
		String response = Util_Exact.doRequest(namedCredential, endpoint, null, method, JSON.serialize(cont), logGuid);
		//system.debug(response);
		//if we POSTed, that means we considered it an insert, get the exact id from the response and add it to the account
		if(method == 'POST'){
			Util_Exact.ExactContact reponseContact = (Util_Exact.ExactContact)JSON.deserialize(response, Util_Exact.ExactContact.class);
			//acct.Exact_Contact_Id__c = reponseContact.ID;
			debNr.Exact_Contact_ID__c = reponseContact.ID;
			//system.debug(reponseContact);
		}
		return method;
	}

	public static String getDebtorNumber(String exactAccountId, String adminCode, String namedCredential, String logGuid){
		String endpoint = String.format(Util_Exact.ACCOUNT_GET_ENDPOINT, new List<String>{adminCode});
		endpoint += '?$filter=ID+eq+guid\''+exactAccountId+'\'&select=Code';
		//endpoint += '(guid\''+exactAccountId+'\')?$select=Code';
		
		String response = Util_Exact.doRequest(namedCredential, endpoint, null, 'GET', null, logGuid);

		Util_Exact.ExactItems allItems = (Util_Exact.ExactItems)JSON.deserialize(response, Util_Exact.ExactItems.class);
		return allItems.results[0].Code;
	}

	@future(callout=true)
	public static void syncOrderAsync(Id orderId, String logGUID){
		Util_Exact.syncOrder(orderId, logGUID);
	}

	@future(callout=true)
	public static void syncOrderAsync(Id orderId){
		Util_Exact.syncOrder(orderId);
	}

	public static List<String> syncOrder(Id orderId){
		return 	Util_Exact.syncOrder(orderId, null);
	}

	public static List<String> syncOrder(Id orderId, String logGUID){
		Order curOrder = [
			SELECT Id, OrderNumber, Opportunity.Name, Opportunity.Customer_Reference__c, Exact_Id__c, Exact_Order_Number__c, Payment_Method__c, Payment_Method_Result__c, Payment_Reference__c,
				Opportunity.Installation_Notes__c, Opportunity.Sales_Contact__r.Name, Opportunity.Sales_Contact__r.Email, Opportunity.Sales_Contact__r.Phone,
				Opportunity.OwnerId, AccountId, Account.Exact_Account_Name__c, Account.Reseller_Name__c, Account.Contact_Person__c, Account.Bank_Account_Number__c,
				Sales_Channel__c, Reseller__c, 
				(SELECT Id, UnitPrice, Quantity, Product_Name__c, Product_Code_Customer__c, Partner_Code__c, PricebookEntry.Product2Id, PricebookEntry.Product2.Name, PricebookEntry.Product2.ProductCode, PricebookEntry.Product2.Generate_Partner_Code__c, PricebookEntry.Product2.RecordType.DeveloperName
				FROM OrderItems)
			FROM Order
			WHERE Id = :orderId
		];

		Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', 'E', 'Order', 'sync2Exact', orderId, String.valueOf(curOrder.OrderNumber), null);
		List<String> msgs = new List<String>();

		String namedCredential;
		try {
			if(!String.isBlank(curOrder.Exact_Id__c)){
				throw new Util_System.CustomException('This order was already synchronised');
			}

			//determine the external id of the administration, based on the reseller name, so we can load the debtor number
			Integer adminExternalId = Util_System.getAdminExternalId(Long.valueOf(curOrder.Account.Reseller_Name__c));
			Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);

			//make sure sync is enabled for this administration
			if((admin.Subscription25__Synchronisation__c != 'Exact' || !admin.Subscription25__Active__c) && (admin.Reseller__c != '1')) {
				throw new Util_System.CustomException('This accounts reseller does not synchronize with Exact');
			}

			String adminCode = admin.Subscription25__Twinfield_Company_Code__c;
			namedCredential = admin.Subscription25__Named_Credential__c;

			List<Subscription25__Debtor_Number__c> debtorNumbers = [
				SELECT Id, Subscription25__Debtor_Number__c, Exact_Id__c, Exact_Bank_Account_ID__c, Exact_Billing_Address_ID__c, Exact_Contact_ID__c, Exact_Mandate_Id__c
				FROM Subscription25__Debtor_Number__c
				WHERE Subscription25__Administration__c = :admin.Id
					AND Subscription25__Account__c = :curOrder.AccountId
			];

			Subscription25__Debtor_Number__c curDebNr;
			Boolean saveDebtorNumber = false;
			if (debtorNumbers.size() == 1) {

				curDebNr = debtorNumbers[0];
				/*if (!test.isRunningTest() && (String.isBlank(debtorNumbers[0].Exact_Id__c) || String.isBlank(debtorNumbers[0].Exact_Contact_ID__c))) {
					throw new Util_System.CustomException('The account has an invalid debtor number in Exact or the contact person is missing');*/

				if (!test.isRunningTest() && (String.isBlank(curDebNr.Exact_Id__c))) {
					throw new Util_System.CustomException('The account has an invalid debtor number in Exact or is not synced jet');
				}

				if (String.isBlank(curDebNr.Exact_Contact_ID__c)) {
					Account acct;

					if (curOrder.Account.Contact_Person__c == null) {
						list<contact> contacts = [Select Id from contact where AccountId = :curOrder.AccountId Order by Platform_IDs__c desc Limit 1];

						Contact cont = (contacts.size() == 1) ? contacts[0] : null;

						if (cont == null) {
							throw new Util_System.CustomException('No contact person available for Account (' + curOrder.Account.Exact_Account_Name__c + '), syncing order not possible!');
						}

						Account accUpd = new Account();
						
						accUpd.Id = curOrder.AccountId;
						accUpd.Contact_Person__c = cont.Id;
						Database.update(accUpd);

					}
					acct = [
						SELECT Id, RecordType.DeveloperName, VAT_Number__c, Reseller_Name__c, Market__c, Relation_Type__c, Sales_Channel__c
							, FinancialDebtorCheck__c, FinancialNumberOfDebtors__c, FinancialReplaceDebtorNumber__c
							, FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c, FinancialIdAccount__c, FinancialIdVisitingAddress__c,  FinancialIdBillingAddress__c,  FinancialIdShippingAddress__c,  FinancialIdBankAccount__c, FinancialIdBankMandate__c
							, FinancialAccountClassification1__c, FinancialAccountClassification2__c, FinancialAccountClassification3__c
							, Customer_Type__c, CoC_Number__c
							, Block_Syncing_Exact__c, Name, OwnerId, Payment_Method_Contracts__c, Exact_Account_Name__c
							, ShippingStreet, ShippingPostalCode, ShippingCity, ShippingCountryCode
							, BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode, Billing_Phone__c, Billing_Email__c
							, Bank_Account_Number__c, Bank_Account__c, Bank_BIC__c, Bank_Country__c
							, Contact_person__r.FirstName, Contact_person__r.MiddleName, Contact_person__r.LastName, Contact_person__r.Email, Contact_person__r.Phone					
						FROM Account
						WHERE Id = :curOrder.AccountId];

					//system.debug('Account : ' + acct);
					//system.debug('LogId : ' + mainLog.GUID__c);

					//once more into the fray for contacts
					//system.debug('contact');
					try {					
						String contactMethod = Util_Exact.syncContact(acct, curDebNr, adminCode, namedCredential, mainLog.GUID__c);
						saveDebtorNumber |= contactMethod == 'POST'; //same logic, if we posted, that means we have to save.
					} catch(Util_System.FinancialSyncException e){
						//same handling of FinancialSyncExceptions
						mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
						mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
						msgs.add(e.getMessage());
					}												
				}

			} else {
				if(debtorNumbers.size() == 0){
					throw new Util_System.CustomException('The account has not been synchronised with Exact');
				} else {
					throw new Util_System.CustomException('The account has multiple debtor numbers, syncing not possible');
				}
			}

			if ((String.isBlank(curOrder.Payment_Method__c)) || ((!String.isBlank(curOrder.Payment_Method__c)) && (curOrder.Payment_Method__c.left(1) == 'I') /*&& (curOrder.Account.Reseller_Name__c == '6')*/ && (String.isBlank(curOrder.Account.Bank_Account_Number__c)))) {
				curOrder.Payment_Method__c = '08';
			}

			//first we have to load all the items that we need from Exact
			//Set<String> codes = Util_System.collectStringValues(curOrder.OrderItems, 'PricebookEntry.Product2.ProductCode');
			//Map<String, String> exactItemIds = Util_Exact.getExactItemIds(namedCredential, adminCode, codes, mainLog.GUID__c);

			//Exact items GUID's are storded on the Subscription25__Administration_Product__c object.
			//Procedure get them is : 1st try to get tehm from Subscription25__Administration_Product__c and 2nd from exact and store them in Subscription25__Administration_Product__c
			set<Id> productIds = Util_System.collectIdValues(curOrder.OrderItems, 'PricebookEntry.Product2Id', false);
			//system.debug('Products : ' +  productIds);
			set<String> codes = new set<String>();
			list<Subscription25__Administration_Product__c> adminProds2Update = new list<Subscription25__Administration_Product__c>();
			map<String, String> exactItemIds = new map<String, String>();

			Subscription25__Administration_Product__c[] adminProds = [
					SELECT 
						Id, Subscription25__Product__c, Subscription25__Product__r.ProductCode, Exact_Id__c 
					FROM 
						Subscription25__Administration_Product__c 
					WHERE 
						Subscription25__Administration__c = :admin.Id and Subscription25__Product__c in :productIds 
					LIMIT 
						10000];
			for(Subscription25__Administration_Product__c adminProd: adminProds) {
				if (String.isBlank(adminProd.Exact_Id__c)) {
					//system.debug('Prductcode: '  + adminProd.Subscription25__Product__r.ProductCode);
					codes.add(adminProd.Subscription25__Product__r.ProductCode);
					adminProds2Update.add(adminProd);
				} else {
					exactItemIds.put(adminProd.Subscription25__Product__r.ProductCode, adminProd.Exact_Id__c);
				}			
			}

			if (!codes.isEmpty()) {
				//system.debug('Codes: '  + codes);
				Map<String, String> exactItemIds2Add = Util_Exact.getExactItemIds(namedCredential, adminCode, codes, mainLog.GUID__c);

				if (!exactItemIds2Add.isEmpty()) {
					for (Subscription25__Administration_Product__c adminProd: adminProds2Update) {
						adminProd.Exact_Id__c = exactItemIds2Add.get(adminProd.Subscription25__Product__r.ProductCode);

						//system.debug(exactItemIds2Add.get(adminProd.Subscription25__Product__r.ProductCode));
						//system.debug(adminProd.Exact_Id__c );

						if (!String.isBlank(adminProd.Exact_Id__c)) {
							exactItemIds.put(adminProd.Subscription25__Product__r.ProductCode, adminProd.Exact_Id__c);
							//system.debug('put : ' + adminProd.Subscription25__Product__r.ProductCode + ', ' + adminProd.Exact_Id__c );
						}
					}

				}
			}

			if (productIds.size() <> exactItemIds.size()) {
				throw new Util_System.CustomException('Some of the order items are not available in exact');
			}
			//system.debug('Number check passed');

			//for now, we only allow creations of SalesOrders in Exact, so no need to check for POST/PUT or url hackies
			Util_Exact.ExactOrder exactOrd = new Util_Exact.ExactOrder(curOrder, exactItemIds, curDebNr, admin);
			String endpoint = String.format(Util_Exact.ORDER_ENDPOINT, new List<String>{adminCode});
			//system.debug('response = ' + response);
			String response = '';
			try {
				response = Util_Exact.doRequest(namedCredential, endpoint, null, 'POST', JSON.serialize(exactOrd), mainLog.GUID__c);
				Util_Exact.ExactOrder responseOrder = (Util_Exact.ExactOrder)JSON.deserialize(response, Util_Exact.ExactOrder.class);
				//system.debug('responseOrder = ' + responseOrder);
				curOrder.Exact_Id__c = responseOrder.OrderID;
				curOrder.Exact_Order_Number__c = (responseOrder.OrderNumber != null) ? String.valueOf(responseOrder.OrderNumber): '';
			} catch(Util_System.FinancialSyncException e) {
				//same handling of FinancialSyncExceptions
				mainlog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
				mainlog.Message__c += 'response = ' + response + '\n';
				mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
				msgs.add('FinancialSyncException - Unhandled exception occurred.');
			} catch(Exception e) {
				//all other exceptions are caught and the function does not continue. message to the user should be a generic
				//error message
				mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
				mainlog.Message__c += 'response = ' + response + '\n';
				mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
				msgs.add('Unhandled exception occurred.');
			}
			//system.debug(responseOrder);
			//system.debug(responseOrder.OrderID);
			//system.debug(responseOrder.OrderNumber);

			//system.debug('Database Updates');
			if (!adminProds2Update.isEmpty()) {
				//system.debug('Database Updates - Administration_Product__c');
				Database.update(adminProds2Update);
			}

			if (saveDebtorNumber) {
				Database.update(curDebNr);
			}
			//system.debug('Database Updates - Order');
			Database.update(curOrder);
		} catch(Util_System.FinancialSyncException e){
			//FinancialSyncException also stops the entire transaction, giving ERROR as that status.
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
		mainlog.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
		mainlog.extId__c = curOrder.Exact_Id__c;
		Database.upsert(mainLog, Event_Log__c.GUID__c);
		//system.debug('mainlog -> ' + mainLog);
		Util_OAuth.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		return msgs;
	}

	//this function loads Items/Articles from Exact based on the given codes. The resulting IDs have to be used in the
	//request to create SalesOrderLines
	public static Map<String, String> getExactItemIds(String namedCredential, String adminCode, Set<String> codes, String logGuid){
		Map<String, String> params = new Map<String, String>();
		params.put('$select', 'ID,Code');

		List<String> codeFilters = new List<String>();
		for(String code : codes){
			codeFilters.add('Code eq \''+code+'\'');
		}
		params.put('$filter', String.join(codeFilters, ' or '));
		String endpoint = String.format(Util_Exact.ARTICLE_GET_ENDPOINT, new List<String>{adminCode});
		String response = Util_Exact.doRequest(namedCredential, endpoint, params, 'GET', null, logGuid);

		Util_Exact.ExactItems allItems = (Util_Exact.ExactItems)JSON.deserialize(response, Util_Exact.ExactItems.class);
		Map<String, String> itemIds = new Map<String, String>();
		for(Util_Exact.ExactItem item : allItems.results){
			itemIds.put(item.Code, item.Id);
		}
		return itemIds;
	}
	public static List<String> finalizeInvoice(Id invoiceId){
		return Util_Exact.finalizeInvoice(invoiceId, null);
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
			//first of all, we need to get the GUID of the invoice, we can get that based on the order number
			Map<String, String> invoiceDetails = Util_Exact.getInvoiceDetails(namedCredential, inv.Subscription25__Exact_Order_Number__c, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);

			//if the invoice already has an invoice number, store it on the invoice, and we're done
			if(!String.isBlank((String)invoiceDetails.get('InvoiceNumber'))){
				inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
			} else {
				//now we can do the call to actually finalize the invoice
				//String templateId = Util_Exact.getExactInvoiceTemplateId(admin.Id, inv.Payment_Method__c, inv.Subscription25__Total_Amount__c);
				String templateId = Util_Exact.getExactInvoiceTemplateId(inv.Reseller__c, inv.Payment_Method_Result__c, inv.Subscription25__Total_Amount__c);
				
				Util_Exact.finalizeInvoice(namedCredential, invoiceDetails.get('InvoiceID'), inv.Subscription25__Invoice_Date__c, templateId, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);

				inv.Subscription25__Finalized_In_Exact__c = true;

				//now we can get the invoice details again to get the invoice number
				try {
					invoiceDetails = Util_Exact.getInvoiceDetails(namedCredential, inv.Subscription25__Exact_Order_Number__c, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);

					string invoiceNumber = String.isBlank(invoiceDetails.get('InvoiceNumber')) ? '' : invoiceDetails.get('InvoiceNumber');

					invoiceNumber = (invoiceNumber == 'null') ? '' : invoiceNumber;

					if (String.isNotBlank(invoiceNumber)) {
						inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
					}

				} catch(Exception e){
					//if loading the invoice number fails, just leave this be, next time the job runs, it'll try to reload
					//the invoice number
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
			//FinancialSyncException also stops the entire transaction, giving ERROR as that status.
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
		Util_OAuth.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		return msgs;
	}

	//this method is called from Batch_FinalizeInvoices, in case the invoice was already printed in Exact,
	//but does not have an invoice number yet
	public static List<String> loadInvoiceNumber(Id invoiceid){
		return Util_Exact.loadInvoiceNumber(invoiceid, null);
	}

	public static List<String> loadInvoiceNumber(Id invoiceid, String logGUID){
		Subscription25__Invoice__c inv = [
			SELECT Id, Name, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c,
				Subscription25__Invoice_Date__c, Payment_Method__c, Payment_Method_Result__c, Subscription25__Total_Amount__c,
				Subscription25__Administration__r.Subscription25__Named_Credential__c,
				Subscription25__Administration__r.Subscription25__Twinfield_Company_Code__c,
				Subscription25__Administration__r.Subscription25__Invoice_Number_Prefix__c,
				Subscription25__Finalized_In_Exact__c
			FROM Subscription25__Invoice__c
			WHERE Id = :invoiceId
		];
		Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S','E','Invoice', 'loadInvoiceNumber', invoiceId, inv.Name, null);
		List<String> msgs = new List<String>();
		String namedCredential;
		try {
			if(!inv.Subscription25__Finalized_In_Exact__c){
				throw new Util_System.CustomException('This invoice is not yet synced');
			}

			if(!String.isBlank(inv.Subscription25__Invoice_Number__c)){
				throw new Util_System.CustomException('This invoice is already finalized');
			}

			//determine the external id of the administration, based on the reseller name, so we can load the debtor number
			Subscription25__Administration__c admin = inv.Subscription25__Administration__r;

			namedCredential = admin.Subscription25__Named_Credential__c;

			//load the invoice details, which contains the invoice number
			Map<String, String> invoiceDetails = Util_Exact.getInvoiceDetails(namedCredential, inv.Subscription25__Exact_Order_Number__c, admin.Subscription25__Twinfield_Company_Code__c, mainLog.GUID__c);
			//if the invoice status from exact is not 50, that means the actual printing failed, so disable that checkbox
			if(invoiceDetails.get('Status') != '50'){
				inv.Subscription25__Finalized_In_Exact__c = false;
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
			//FinancialSyncException also stops the entire transaction, giving ERROR as that status.
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
		Util_OAuth.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		return msgs;
	}

	private static String getExactInvoiceTemplateId(String reseller, String paymentMethod, Decimal amount){
		string templateId = '';
		string paymentCondition = (amount < 0) ? 'cr' : paymentMethod;

		if (String.isNotBlank(reseller) && String.isNotBlank(paymentCondition)) {
			templateId = [Select Exact_Invoice_Template__c from Payment_Setting__mdt where Reseller__c = :reseller and Method__c = :paymentCondition Limit 1].Exact_Invoice_Template__c;
		}

		return templateId;		
	}

	/*
	private static String getExactInvoiceTemplateId2(Id adminId, String paymentCondition, Decimal amt){
		Map<Id, String> creditTemplates = new Map<Id, String>();
		//aec4f695-47f3-46c2-b9c1-2d039c0c060d - UK Credit previous setting '4167b9ca-69b9-45aa-b6bb-0d5d5aa30c1f'
		creditTemplates.put('a0U3W000002VuQiUAK', '9e7b7d67-b7a4-40df-94e1-544a14fbca41'); //nl
		creditTemplates.put('a0U3W000003fB6QUAU', '82ed45e2-04e7-45a7-a4f1-75a906f576ca'); //de
		creditTemplates.put('a0U3W0000041AZtUAM', 'aec4f695-47f3-46c2-b9c1-2d039c0c060d'); //uk

		Map<Id, Map<String, String>> invoiceTemplateIds = new Map<Id, Map<String, String>>();
		invoiceTemplateIds.put('a0U3W000002VuQiUAK', new Map<String, String>()); //nl
		invoiceTemplateIds.put('a0U3W000003fB6QUAU', new Map<String, String>()); //de
		invoiceTemplateIds.put('a0U3W0000041AZtUAM', new Map<String, String>()); //uk

		//nl
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('08', 'e5840693-5b9d-4b9b-a397-4b4f25a51228');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('14', 'e5840693-5b9d-4b9b-a397-4b4f25a51228');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('30', 'e5840693-5b9d-4b9b-a397-4b4f25a51228');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('60', 'e5840693-5b9d-4b9b-a397-4b4f25a51228');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('I0', 'c46c05ea-1f4d-4870-8d3d-edd40b6b0592');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('I3', 'c46c05ea-1f4d-4870-8d3d-edd40b6b0592');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('I4', 'c46c05ea-1f4d-4870-8d3d-edd40b6b0592');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('I8', 'c46c05ea-1f4d-4870-8d3d-edd40b6b0592');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('C', '4681638d-6a1f-481f-8297-59e8aa26a32d');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('p0', 'f68dc67b-e199-4b32-b6c2-9aef9ee1595b');
		invoiceTemplateIds.get('a0U3W000002VuQiUAK').put('p1', 'f68dc67b-e199-4b32-b6c2-9aef9ee1595b');
		//de
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('08', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('14', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('30', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('60', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('I0', 'eb35f303-94e9-4a49-bfee-d76d8c3cf89e');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('I3', 'eb35f303-94e9-4a49-bfee-d76d8c3cf89e');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('I4', 'eb35f303-94e9-4a49-bfee-d76d8c3cf89e');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('I8', 'eb35f303-94e9-4a49-bfee-d76d8c3cf89e');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('C', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('p0', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		invoiceTemplateIds.get('a0U3W000003fB6QUAU').put('p1', '82ed45e2-04e7-45a7-a4f1-75a906f576ca');
		//uk
		//86e0f81e-878d-4c64-8b92-1fc3d947849a - UK Direct Debit I0, I3, I4, I8
		//2e5ddea3-89eb-4feb-b167-3723f0e99577 - UK Card Payment p0, p1, C
		//922a4ff1-e47c-4797-a91d-ee0ccba32834 - UK On account 08, 14, 30, 60
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('08', '922a4ff1-e47c-4797-a91d-ee0ccba32834');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('14', '922a4ff1-e47c-4797-a91d-ee0ccba32834');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('30', '922a4ff1-e47c-4797-a91d-ee0ccba32834');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('60', '922a4ff1-e47c-4797-a91d-ee0ccba32834');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('I0', '86e0f81e-878d-4c64-8b92-1fc3d947849a');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('I3', '86e0f81e-878d-4c64-8b92-1fc3d947849a');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('I4', '86e0f81e-878d-4c64-8b92-1fc3d947849a');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('I8', '86e0f81e-878d-4c64-8b92-1fc3d947849a');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('C', '2e5ddea3-89eb-4feb-b167-3723f0e99577');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('p0', '2e5ddea3-89eb-4feb-b167-3723f0e99577');
		invoiceTemplateIds.get('a0U3W0000041AZtUAM').put('p1', '2e5ddea3-89eb-4feb-b167-3723f0e99577');

		String templateId;
		if(amt < 0 && creditTemplates.containsKey(adminId)){
			templateId = creditTemplates.get(adminId);
		} else if(invoiceTemplateIds.containsKey(adminId) && invoiceTemplateIds.get(adminId).containsKey(paymentCondition)){
			templateId = invoiceTemplateIds.get(adminId).get(paymentCondition);
		}
		return templateId;
	}
	*/

	private static Map<String, String> getInvoiceDetails(String namedCredential, String orderNumber, String adminCode, String logGuid){
		Map<String, String> params = new Map<String, String>();
		params.put('$select', 'InvoiceID,InvoiceNumber,Status');
		params.put('$filter', 'OrderNumber eq ' + orderNumber);
		String endpoint = String.format(Util_Exact.SALES_INVOICE_GET_ENDPOINT, new List<String>{adminCode});
		String response = Util_Exact.doRequest(namedCredential, endpoint, params, 'GET', null, logGuid);

		Util_Exact.ExactInvoices allInvoices = (Util_Exact.ExactInvoices)JSON.deserialize(response, Util_Exact.ExactInvoices.class);
		Map<String, String> details = new Map<String, String>();
		details.put('InvoiceID', allInvoices.results[0].InvoiceID);
		details.put('InvoiceNumber', allInvoices.results[0].InvoiceNumber);
		details.put('Status', ''+allInvoices.results[0].Status);
		return details;
	}

	private static void finalizeInvoice(String namedCredential, String invoiceId, Date invDate, String templateId, String adminCode, String logGuid){
		//Since we're only posting 2 fields, i'll just set up the request using a map
		//.... 2 days later.....
		//now that we're at 4 fields, maybe it's time to switch to inner class....
		// update the Sales Channel

		Map<String, Object> reqMap = new Map<String, Object>();
		reqMap.put('InvoiceID', invoiceId);
		reqMap.put('InvoiceDate', Util_System.formatDate(invDate, 'yyyy-MM-dd'));
		if(!String.isBlank(templateId)){
			reqMap.put('DocumentLayout', templateId);
		}
		reqMap.put('SendEmailToCustomer', false);
		reqMap.put('SendInvoiceToCustomerPostbox', false);
		reqMap.put('SendOutputBasedOnAccount', false);

		String endpoint = String.format(Util_Exact.SALES_INVOICE_PRINT_ENDPOINT, new List<String>{adminCode});

		String response = Util_Exact.doRequest(namedCredential, endpoint, null, 'POST', JSON.serialize(reqMap), logGuid);
		//System.debug(response);
	}

	private static void finalizeInvoiceOrg(String namedCredential, String invoiceId, Date invDate, String templateId, String adminCode, String logGuid){
		//Since we're only posting 2 fields, i'll just set up the request using a map
		//.... 2 days later.....
		//now that we're at 4 fields, maybe it's time to switch to inner class....
		Map<String, Object> reqMap = new Map<String, Object>();
		reqMap.put('InvoiceID', invoiceId);
		reqMap.put('InvoiceDate', Util_System.formatDate(invDate, 'yyyy-MM-dd'));
		if(!String.isBlank(templateId)){
			reqMap.put('DocumentLayout', templateId);
		}
		reqMap.put('SendEmailToCustomer', false);

		String endpoint = String.format(Util_Exact.SALES_INVOICE_PRINT_ENDPOINT, new List<String>{adminCode});

		String response = Util_Exact.doRequest(namedCredential, endpoint, null, 'POST', JSON.serialize(reqMap), logGuid);
		//System.debug(response);
	}

	private static String doRequest(String namedCredential, String endpoint, Map<String, String> params, String method, String requestBody, String logGuid){
		Util_OAuth session = Util_OAuth.getInstance(namedCredential, logGuid);
		String response = '';
		Boolean wasException = false;
		try {
			//system.debug(requestBody);
			//system.debug(params);

			HttpResponse res = session.doRequest(endpoint, params, method, requestBody);

			//system.debug(res);

			//if the response has status code 204, that means that a PUT was successful, in which case
			//no response body is given. We shouldn't try to actually get the response in that case
			if (res.getStatusCode() == 204){
				//system.debug('RESPONSE : 204');
				return response;
			} else  if ((res.getStatusCode() == 500) && (endpoint.contains('BankAccounts'))) {
				// shortcut to retrieve existing bank account, id not stored in salesforce
				return '500';
			}

			Map<String, Object> dirtyResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
			//system.debug(res.getBody());
			if(dirtyResponse.containsKey('error')){
				Map<String, Object> errMap = (Map<String, Object>)dirtyResponse.get('error');
				Map<String, Object> msgMap = (Map<String, Object>)errMap.get('message');
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
			//rethrow custom exceptions (these are the errors given by exact), make sure these are handled
			//at some point in the stack, otherwise finally will not execute, refresh tokens will be invalid
			//and general unpleasantness occurs
			wasException = true;
			throw exactEx;
		} catch(Exception ex){
			wasException = true;
			//System.debug(ex);
		}
		//system.debug('doRequest : ' + response);
		return response;
	}



/*	private static Map<Id, String> userExactIds;
	private static String getUserExactId(){
		return Util_Exact.getUserExactId(UserInfo.getUserId());
	}

	private static String getUserExactId(Id userId){
		if(Util_Exact.userExactIds == null){
			Util_Exact.userExactIds = new Map<Id, String>();
			List<User> users = [SELECT Id, Exact_Id__c FROM User];
			for(User usr : users){
				Util_Exact.userExactIds.put(usr.Id, usr.Exact_Id__c);
			}
		}
		return Util_Exact.userExactIds.get(userId);
	}*/

	private static Map<Id, Map<String, Map<String, String>>> relationIds;
	//private static String getExactRelationId(Id adminId, Account acct, String field){
	private static String getExactRelationId(Id adminId, String relation, String value){
		if(Util_Exact.relationIds == null){
			Util_Exact.relationIds = new Map<Id, Map<String, Map<String, String>>>();
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
				if(!Util_Exact.relationIds.containsKey(curAdminId)){
					Util_Exact.relationIds.put(curAdminId, new Map<String, Map<String, String>>());
				}
				if(!Util_Exact.relationIds.get(curAdminId).containsKey(curType)){
					Util_Exact.relationIds.get(curAdminId).put(curType, new Map<String, String>());
				}
				Util_Exact.relationIds.get(curAdminId).get(curType).put(curVal, curExactId);
			}
		}

		return Util_Exact.relationIds.get(adminId).get(relation).get(value);
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
		//private String AccountManager;
		private String PaymentConditionSales; //Code of Exact_Payment_Method__c
		private String Classification1; //GUID of type relatie (Relation_type__c)
		private String Classification2; //GUID of type klant (Customer_Type__c)
		private String Classification3; //GUID of Reseller (Custom metadata)
		private String MainContact;
		//private Util_Exact.ExactBankAccounts BankAccounts;
		//private String Classification4; //GUID of Reseller (Custom metadata)
		//private String PaymentConditionSales;

		private ExactAccount(Account acct, Subscription25__Debtor_Number__c debNr){
			//this.Code = acct.FinancialDebtorNumber__c;

			if (!String.isBlank(debNr.Subscription25__Debtor_Number__c)) {
				this.Code = debNr.Subscription25__Debtor_Number__c;
			}
			this.Name = acct.Exact_Account_Name__c;
			this.AddressLine1 = acct.ShippingStreet;
			this.Postcode = acct.ShippingPostalCode;
			this.City = acct.ShippingCity;
			//this.Country = Util_System.getISO2CountryCode(acct.ShippingCountry);
			this.Country = acct.ShippingCountryCode;
			this.Phone = acct.Billing_Phone__c;
			this.Email = acct.Billing_Email__c;
			this.ChamberOfCommerce = (acct.CoC_Number__c != '-') ? acct.CoC_Number__c  : '';  //Gen25 26/11/2020 change: acct.WSONE_DATA__DossierNumber__c;
			this.VATNumber = (acct.VAT_Number__c != '-') ? acct.VAT_Number__c : ''; //Gen25 23/1/2020 change: acct.WSONE_DATA__VATNumber__c;
			if (String.isNotBlank(acct.FinancialDebtorNumberPrevious__c)) {
				this.SearchCode = acct.FinancialDebtorNumberPrevious__c;
			}
			this.Status = 'C'; //Account is type Customer
			//this.AccountManager = Util_Exact.getUserExactId(acct.OwnerId);
			this.PaymentConditionSales = acct.Payment_Method_Contracts__c;
			if (String.isNotBlank(debNr.Exact_Contact_Id__c)) {
				this.MainContact = debNr.Exact_Contact_Id__c;
			}
			try {
				Integer reseller = (String.isNotBlank(acct.Reseller_Name__c)) ? Util_System.getAdminExternalId(Long.valueOf(acct.Reseller_Name__c)) : 1;
				string classificationId;

				classificationId = (String.isNotBlank(acct.FinancialAccountClassification1__c)) ? Util_Exact.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C1', acct.FinancialAccountClassification1__c): '';
				this.Classification1 = (String.isNotBlank(classificationId)) ? classificationId :  null ;
				//system.debug('C1 = ' + classificationId);

				classificationId = (String.isNotBlank(acct.FinancialAccountClassification2__c)) ? Util_Exact.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C2', acct.FinancialAccountClassification2__c) : '';
				this.Classification2 = (String.isNotBlank(classificationId)) ? classificationId :  null ;
				//system.debug('C2 = ' + classificationId);

				classificationId = (String.isNotBlank(acct.FinancialAccountClassification3__c)) ? Util_Exact.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C3', acct.FinancialAccountClassification3__c): '';
				//classificationId = (String.isNotBlank(acct.Sales_Channel__c)) ? Util_Exact.getExactRelationId(Util_System.getAdministration(reseller).Id, 'C3', acct.Sales_Channel__c): '';
				this.Classification3 = (String.isNotBlank(classificationId)) ? classificationId :  null ;
				//system.debug('C3 = ' + classificationId);

			} catch(Exception e){}
			//this.Classification2 = Util_Exact.getExactRelationId(debNr.Subscription25__Administration__c, acct, 'Customer_Type__c');
			/*Reseller_Setting__mdt resSett = Util_Exact.getResellerMetadata(acct.Reseller_Name__c);
			if(resSett != null){
				this.Classification3 = resSett.ExactId__c;
			}*/
		}
	}

	private class ExactGetAccount {
		private String ID;
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
		private String MainContact;
		//private Util_Exact.ExactBankAccounts BankAccounts;
	}

	private class ExactGetAccounts {
		private List<Util_Exact.ExactGetAccount> results;
	}

	private class ExactAddress {
		private String ID;
		private String Account;
		private String AddressLine1;
		private String Postcode;
		private String City;
		private String Country; //should be a country code
		private String Contact;
		private Integer Type; //Visit=1, Postal=2, Invoice=3, Delivery=4

		private ExactAddress(Account acct, Subscription25__Debtor_Number__c debNr){
			this.Account = debNr.Exact_ID__c;
			this.AddressLine1 = acct.BillingStreet;
			this.Postcode = acct.BillingPostalCode;
			this.City = acct.BillingCity;
			//this.Country = Util_System.getISO2CountryCode(acct.BillingCountry);
			this.Country = acct.BillingCountryCode;
			this.Contact = debNr.Exact_Contact_ID__c;
			this.Type = 3; //altijd invoice
		}
	}

	private class ExactBankAccounts {
		private List<Util_Exact.ExactBankAccount> results;
	}

	private class ExactBankAccount {
		private String ID;
		private String Account;
		private String BankAccount;
		private String BankAccountHolderName;
		private String BICCode;
		private Boolean Main;

		private ExactBankAccount(Account acct, Subscription25__Debtor_Number__c debNr){
			this.Account = debNr.Exact_ID__c;
			this.BankAccount = acct.Bank_Account_Number__c;
			this.BankAccountHolderName = acct.Bank_Account__c;
			//this.BICCode = acct.Bank_BIC__c;
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

		private ExactMandate(Account acct, Subscription25__Debtor_Number__c debNr){
			this.Account = debNr.Exact_ID__c;
			this.BankAccount = debNr.Exact_Bank_Account_ID__c;
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

		private ExactContact(Account acct, Subscription25__Debtor_Number__c debNr){
			this.Account = debNr.Exact_ID__c;
			this.FirstName = acct.Contact_person__r.FirstName;
			this.MiddleName = acct.Contact_person__r.MiddleName;
			this.LastName = acct.Contact_person__r.LastName;
			this.Email = acct.Contact_person__r.Email;
			this.Phone = acct.Contact_person__r.Phone;
		}
	}

	private class ExactOrder {
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
		private List<Util_Exact.ExactOrderLine> SalesOrderLines;


		private ExactOrder(Order ord, Map<String, String> itemIds, Subscription25__Debtor_Number__c debNr, Subscription25__Administration__c admin){
			this.InvoiceTo = debNr.Exact_Id__c;
			this.OrderedBy = debNr.Exact_Id__c;
			if(!String.isBlank(debNr.Exact_Contact_Id__c)){
				this.OrderedByContactPerson = debNr.Exact_Contact_Id__c;
			}
			this.OrderDate = DateTime.now();
			this.PaymentCondition = ord.Payment_Method_Result__c;
			if (!String.isBlank(ord.Payment_Reference__c)) {
				this.PaymentReference = ord.Payment_Reference__c;
			}
			this.Description = ord.Opportunity.Name;
			this.YourRef = ord.Opportunity.Customer_Reference__c;
			this.Remarks = '';
			if(ord.Opportunity.Sales_Contact__c != null && ord.Opportunity.Sales_Contact__c != ord.Account.Contact_Person__c){
				List<String> ll = new List<String>();
				ll.add(ord.Opportunity.Sales_Contact__r.Name);
				if(ord.Opportunity.Sales_Contact__r.Email != null){
					ll.add(ord.Opportunity.Sales_Contact__r.Email);
				}
				if(ord.Opportunity.Sales_Contact__r.Phone != null){
					ll.add(ord.Opportunity.Sales_Contact__r.Phone);
				}
				this.Remarks = String.join(ll, '\r\n');
			}

			string warehouseId = '';

			if (ord.Reseller__c == '1') {
				this.SalesChannel = Util_Exact.getExactRelationId(admin.Id, 'SC', ord.Sales_Channel__c);
				warehouseId = Util_Exact.getExactRelationId(admin.Id, 'WH', ord.Sales_Channel__c);
			}
				
			this.WarehouseID = String.isNotBlank(warehouseId) ? warehouseId : admin.Warehouse_Exact_Id__c;
			
			this.SalesOrderLines = new List<Util_Exact.ExactOrderLine>();
			integer i = 0;
			for(OrderItem oi : ord.OrderItems){
				i += 1;
				this.SalesOrderLines.add(new Util_Exact.ExactOrderLine(ord, oi, i, itemIds));
			}
		}
	}

	private class ExactOrderLine {
		private String Item; //GUID of an item in Exact, apparently mandatory...
		private Decimal Quantity;
		private Decimal UnitPrice;
		private String CustomerItemCode;
		private String Description;
		private String Notes; //populated with some sort of string with lines with a product with a certain type

		private ExactOrderLine(Order ord, OrderItem oi, Integer i, Map<String, String> itemIds){
			this.Item = itemIds.get(oi.PricebookEntry.Product2.ProductCode);
			this.Quantity = oi.Quantity;
			this.UnitPrice = oi.UnitPrice;
			// 20220823 - TRi - Product_Name__c added to handle the translations for product.name on order item level
			this.Description = (oi.Product_Code_Customer__c != null) ? oi.Product_Code_Customer__c + ' ' : '';
			this.Description += (oi.Product_Name__c != null) ? oi.Product_Name__c : oi.PricebookEntry.Product2.Name;

			if ((oi.Partner_Code__c != null) && (oi.PricebookEntry.Product2.RecordType.DeveloperName == 'SubscriptionP') && (oi.PricebookEntry.Product2.Generate_Partner_Code__c)) {
				this.Notes = '--------------------------------------------------------------------------------' + '\n';
				this.Notes += 'Partner code : ' + oi.Partner_Code__c + '\n';
				this.Notes += '--------------------------------------------------------------------------------' + '\n';
			} else {
				this.Notes = '';
			}

			if((i == 1) && !String.isBlank(ord.Opportunity.Installation_Notes__c)){
				this.Notes += ord.Opportunity.Installation_Notes__c;
			}
		}
	}

	private class ExactItems {
		private List<Util_Exact.ExactItem> results;
	}

	private class ExactItem {
		private String Code;
		private String ID;
	}

	private class ExactInvoices {
		private List<Util_Exact.ExactInvoice> results;
	}

	private class ExactInvoice {
		private String InvoiceID;
		private String InvoiceNumber;
		private Integer Status;
	}

}
