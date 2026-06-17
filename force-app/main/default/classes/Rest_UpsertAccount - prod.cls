@RestResource(UrlMapping='/UpsertAccount')
global without sharing class Rest_UpsertAccount {
	private static Account record;

	@HttpPost
	global static Util_Rest.RestResult handleAction() {
		//result is needed for returning a custom object to the sender
		//this object is used b`y MI to determine which records have been added successfully to SF.
		Util_Rest.RestResult result = new Util_Rest.RestResult();
        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, 'RestUpsertAccount', 'S'); // TODO: Set calling system?
		Savepoint savePoint = Database.setSavepoint();
		Boolean uniqueEmail = Util_System.getDataSetting('Contact_UniqueEmailAddresses');

		try {
			Util_Rest.isRestEntry = true;
			//deserialize the incoming account from the request-body to a MiAccount object.
			//needs to be done manually since the incoming json does not have a MiAccount object wrapper.
			String reqBody = RestContext.request.requestBody.toString();
			//System.debug(reqBody);
			Rest_UpsertAccount.MiAccount miAccount = (Rest_UpsertAccount.MiAccount) JSON.deserialize(reqBody, Rest_UpsertAccount.MiAccount.class);
            logger.setSessionRecordExternalId(sessionId, miAccount.id);
            logger.setCallingSystem(sessionId, miAccount.platformId);

			//upsert accounts and contacts
			result.addedRecords.add(Rest_UpsertAccount.upsertMiAccount(miAccount));

			//contactDTO can be null if only the account is updated.
			//added visitAddress (and/or) billingAddress) as contact,
			result.addedRecords.addAll(Rest_UpsertAccount.upsertMiContacts(miAccount));

			// Shipping contacts needs to be added.

			// 20230324 - TRi - Replaced debtor number check to the end of this procedure, the account is completed and the contacts are in place, the account is as complete
			// as it can gets in this stage.
			// 20230327 - TRi - Moved to Rest_UpsertContract for Platform 1, prevent creating debtor numbers for empty accounts. If Other platforms are connected with
			// contracts, the excluded them as well


			if((miAccount.platformId != 1) && (miAccount.platformId != 5)){
				Util_Rest.checkDebtorNumber(miAccount.id, String.valueOf(miAccount.platformId));
			}

			//if everything went right add the following message and set Success to true.
			result.messages.add('Succes: Account and Contact(s) have been added for: ' + miAccount.name +  '. With the following ID: ' + miAccount.id + '.');
			result.success = true;

			Util_Rest.isRestEntry = false;
		} catch (Exception e) {
			//when an error occurs: rollback the database and add the error messages to the result object, set success to false and clear the AddedRecords since none have been added.
			Database.rollback(savePoint);
			result.messages.add('Error: ' + e + ' ---STACK-- ' + e.getStackTraceString() + '---LINE----' + e.getLineNumber());
			result.addedRecords.clear();
			result.success = false;

			Util_Rest.isRestEntry = false;
		}

		Logger.setSessionRecord(sessionId, Rest_UpsertAccount.record?.Id, Rest_UpsertAccount.record?.Name);
        String responseBody = JSON.serialize(result);
        Integer statusCode = result.success ? 200 : 400;
        Logger.finalizeSession(sessionId, responseBody, statusCode);
        Logger.saveAll();

		return result;
	}

	//this function upserts incoming accounts from Moving Intelligence.
	//if everything went well the added accounts will be added to the result object with their ids and object type.
	public static Util_Rest.AddedRecord upsertMiAccount(Rest_UpsertAccount.MiAccount miAcc){
		if(miAcc.id == null){
			throw new Util_Rest.UpsertException('Error: An Account was added with no ID.');
		}

		String extIdField = 'extId_' + String.valueOf(miAcc.platformId) + '__c';

		Boolean doEchoesAccountId = (String.valueOf(miAcc.platformId) != '6');

		//system.debug(extIdField);

		//there's an issue here; accounts from MI could have an Exact Id that is already known in SF, while the account in
		//SF does not have an MI id. This happens when account is created in SF, synced to Exact and then from Exact to MI.
		//to fix this, first we collect all Exact Id / MI id pairs and put the MI Id in SF on the accounts. This way, the
		//actual sync will remain as is
		String sSOQL;
		Account acc;
		List<Account> existingAccounts;
        Boolean accountIsNew = false;

        //if this is a base service look for contracts by external id
		if(miAcc.id != null) {
			sSOQL = 'SELECT Id, Name, Short_Name__c, RecordTypeId, NumberOfEmployees, NumberOfFulltimeEmployees__c, AccountSource,'
				+ ' VisitingAddress__Street__s, VisitingAddress__PostalCode__s, VisitingAddress__City__s, VisitingAddress__StateCode__s, VisitingAddress__CountryCode__s, '
				+ ' Subscription25__Digital_Invoicing__c, Sales_Language__c, useBillingAddress__c, useShippingAddress__c,'
				+ ' IsBankrupt__c, Is_Blocked__c, isPrivacyMode__c, VAT_Number__c, CoC_Number__c,'
				+ ' Payment_Method_Contracts__c, Payment_Method_Opportunities__c, FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c,'
				+ ' Bank_Account__c, Bank_Account_Number__c, Bank_BIC__c,'
				+ ' SBI_Primary_Code__c, SBI_Secondary_Code_1__c, SBI_Secondary_Code_2__c, HasDealerTasks__c, ContractTerm__c,'
				+ ' NoticeTerm__c, RenewalTerm__c, OrderOffsetTerm__c, Invoice_Period__c, Subscription_Type__c,'
				+ ' Contact_Person__c, Contact_Person__r.AccountId, Contact_Person__r.Is_Active__c, Contact_Person__r.'  + extIdField + ','
				+ ' Contact_Billing__c, Contact_Billing__r.AccountId, Contact_Billing__r.Email, Contact_Billing__r.Is_Active__c, Contact_Billing__r.' + extIdField + ','
				+ ' Contact_Shipping__c, Contact_Shipping__r.AccountId, Contact_Shipping__r.Is_Active__c, Contact_Shipping__r.' + extIdField + ','
				+ ' MI_Administrator__c, MI_Administrator__r.AccountId, MI_Administrator__r.Is_Active__c, MI_Administrator__r.' + extIdField + ','
				+ ' extId_6__c' + ((doEchoesAccountId) ? (', ' + extIdField) : '')
				+ ' FROM Account'
				+ ' WHERE ' + extIdField + ' = \'' + miAcc.id + '\''
				+ ' LIMIT 1';

			existingAccounts = Database.query(sSOQL);

			if(existingAccounts.size() == 1){
				acc = existingAccounts[0];

				if ((String.isNotBlank(acc.Contact_Person__c)) && (acc.id != acc.Contact_Person__r.AccountId)) {
					acc.Contact_Person__c = null;
				}

				if ((String.isNotBlank(acc.Contact_Billing__c)) && (acc.id != acc.Contact_Billing__r.AccountId)) {
					acc.Contact_Billing__c = null;
				}

				if ((String.isNotBlank(acc.Contact_Shipping__c)) && (acc.id != acc.Contact_Shipping__r.AccountId)) {
					acc.Contact_Shipping__c = null;
				}

				if ((String.isNotBlank(acc.MI_Administrator__c)) && (acc.id != acc.MI_Administrator__r.AccountId)) {
					acc.MI_Administrator__c = null;
				}
			}
		}

        if(acc == null){
			accountIsNew = true;
			acc = new Account();
			acc.put(extIdField, miAcc.id);
			acc.AccountSource = 'Platform';
			acc.useBillingAddress__c = false;
			acc.useShippingAddress__c = false;
		}

		if ((doEchoesAccountId) && (String.isNotBlank(miAcc.echoesAccountId))) {
			acc.extId_6__c = miAcc.echoesAccountId;
		}

		acc.Name = miAcc.name;
		acc.Short_Name__c = String.isNotBlank(miAcc.shortName) ? miAcc.shortName : null;
		acc.FinancialDebtorNumberPrevious__c = String.isNotBlank(miAcc.previousDebtorNumber) ? miAcc.previousDebtorNumber : null;
		acc.isPrivacyMode__c = (miAcc.privacyMode != null) ? miAcc.privacyMode : false;

		// 20221101 - TRi - force all UK - Direct Debits to I0
		acc.Bank_Account__c = (String.isNotBlank(miAcc.bankAccountHolder)) ? miAcc.bankAccountHolder : ((String.isNotBlank(acc.Bank_Account__c)) ? acc.Bank_Account__c : acc.Name) ;
		if (String.isNotBlank(miAcc.bankAccountNumber)) {
			acc.Bank_Account_Number__c = miAcc.bankAccountNumber;
		}
		if (String.isNotBlank(miAcc.bankAccountBic)) {
			acc.Bank_BIC__c = miAcc.bankAccountBic;
		}
		if (String.isBlank(miAcc.paymentMethodExactCode)) {
			acc.Payment_Method_Contracts__c = (miAcc.resellerId == 6) ? ((miAcc.bankAccountNumber == null) ? '08' : 'I0') : ((miAcc.bankAccountNumber == null) ? ((miAcc.platformId == 5) ? '14' : '08') : 'I8');
		} else {
			acc.Payment_Method_Contracts__c = ((miAcc.resellerId == 6) && (miAcc.paymentMethodExactCode.toUpperCase().left(1) == 'I')) ? ((miAcc.bankAccountNumber == null) ? '08' : 'I0') : miAcc.paymentMethodExactCode;
		}

		if (accountIsNew) {
			acc.Payment_Method_Opportunities__c = (miAcc.resellerId == 6) ? ((miAcc.platformId == 5) ? '14' : ((miAcc.isBusiness == true) ? '08' : 'p1' )) : ((miAcc.bankAccountNumber == null) ? '08' : 'I8');
		}

		// 20230317 TRi Account has dealer tasks, replacement for the record type b2b_dealer.
		acc.HasDealerTasks__c = (miAcc.isDealer==null) ? false : miAcc.isDealer;

		if (miAcc.isBusiness) {
			acc.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId();
			acc.VAT_Number__c = (String.isNotBlank(miAcc.vatNumber)) ? miAcc.vatNumber : (String.isNotBlank(acc.VAT_Number__c)) ? acc.VAT_Number__c : null;
			acc.CoC_Number__c = (String.isNotBlank(miAcc.cocNumber)) ? miAcc.cocNumber : (String.isNotBlank(acc.CoC_Number__c)) ? acc.CoC_Number__c : null;
		} else {
			acc.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();
			acc.VAT_Number__c = null;
			acc.CoC_Number__c = null;
		}

		//acc.RecordTypeId = miAcc.isBusiness ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId() : Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();

		acc.SBI_Primary_Code__c = String.isNotBlank(miAcc.primarySbiCode) ? miAcc.primarySbiCode : '';
		acc.SBI_Secondary_Code_1__c = String.isNotBlank(miAcc.secondarySbiCode1) ? miAcc.secondarySbiCode1 : '';
		acc.SBI_Secondary_Code_2__c = String.isNotBlank(miAcc.secondarySbiCode2) ? miAcc.secondarySbiCode2 : '';
		// 202213 - TRi -> Number of Employees and Number of Fulltime Employees added (No using WSONE_DATA fields)
        if ((miAcc.personnelCount != null) && ((acc.NumberOfEmployees == null) || (acc.NumberOfEmployees <= 0))) {
		    acc.NumberOfEmployees = Integer.valueOf(miAcc.personnelCount);
        }
        if ((miAcc.fulltimePersonnelCount != null) && ((acc.NumberOfFulltimeEmployees__c == null) || (acc.NumberOfFulltimeEmployees__c <= 0))) {
		    acc.NumberOfFulltimeEmployees__c =  Integer.valueOf(miAcc.fulltimePersonnelCount);
        }
		// 20221115 - TRi - Direct Debit fields, to stay in sync with Chiron
		// 20230920 - TRI - Changed to not override the defaults, when value is not supplied
		if (String.isNotBlank(miAcc.directDebitStatus)) {
			acc.Direct_Debit_Status__c = miAcc.directDebitStatus;
		}
		if (String.isNotBlank(miAcc.directDebitReference)) {
			acc.Direct_Debit_Previous_Reference__c = miAcc.directDebitReference;
		}
		if (String.isNotBlank(miAcc.directDebitLastTakenDate)) {
			acc.Direct_Debit_Last_Taken_Date__c = Datetime.valueOf(miAcc.directDebitLastTakenDate);
		}

		if (miAcc.isBlocked != null) {
			acc.Is_Blocked__c =  miAcc.isBlocked;
		}

		if (miAcc.isBankrupt != null) {
			acc.IsBankrupt__c =  miAcc.isBankrupt;
		}

		acc.Reseller_Name__c = String.valueOf(miAcc.resellerId);
		// GS 07Dec2023 Added below 4 fields to Mapping
		if(miAcc.contractTerm != null) {
			acc.ContractTerm__c = miAcc.contractTerm;
		}
		if(miAcc.noticeTerm != null) {
			acc.NoticeTerm__c = miAcc.noticeTerm;
		}
		if(miAcc.renewalTerm != null) {
			acc.RenewalTerm__c = miAcc.renewalTerm;
		}
		if(miAcc.orderOffsetTerm != null) {
			acc.OrderOffsetTerm__c = miAcc.orderOffsetTerm;
		}
		if(String.isNotBlank(miAcc.invoicePeriod)) {
			acc.Invoice_Period__c = miAcc.invoicePeriod;
		}
		if(String.isNotBlank(miAcc.subscriptionType)) {
			acc.Subscription_Type__c = miAcc.subscriptionType;
		}

		if (miAcc.visitAddress != null) {
			// visit address -> makes shipping address free for real shipping address
			acc.VisitingAddress__PostalCode__s = (miAcc.visitAddress.PostalCode != null) ? miAcc.visitAddress.PostalCode : '';
			acc.VisitingAddress__City__s = (miAcc.visitAddress.City != null) ? miAcc.visitAddress.City : '';
			acc.VisitingAddress__Street__s = (miAcc.visitAddress.Street != null) ? miAcc.visitAddress.Street : '';
			acc.VisitingAddress__Street__s += (miAcc.visitAddress.Housenumber != null) ? (' ' + miAcc.visitAddress.Housenumber) : '';
			acc.VisitingAddress__CountryCode__s = (miAcc.visitAddress.country != null) ? miAcc.visitAddress.country : '';

			/*
			// 20260323 - TRi - Check Flow, should take care for shipping
			if (!acc.useShippingAddress__c) {
				// for now copy visiting address to shipping
				acc.ShippingPostalCode = acc.VisitingAddress__PostalCode__s;
				acc.ShippingCity = acc.VisitingAddress__City__s;
				acc.ShippingStreet = acc.VisitingAddress__Street__s;
				acc.ShippingStateCode = acc.VisitingAddress__StateCode__s;
				acc.ShippingCountryCode = acc.VisitingAddress__CountryCode__s;
			}
			*/

			// 	move to contact
			String shippingName = miAcc.visitAddress.firstName;
			if (String.isNotBlank(miAcc.visitAddress.insertion)) {
				shippingName += ' ' + miAcc.visitAddress.insertion;
			}
			shippingName += ' ' + miAcc.visitAddress.surName;

			acc.Shipping_Name__c = shippingName;
			acc.Shipping_Email__c = Util_System.sanitizeEmail(miAcc.visitAddress.email);
			acc.Shipping_Phone__c = miAcc.visitAddress.phoneNumber;
			acc.Sales_Language__c = ((miAcc.visitAddress.language != null) && (String.IsBlank(acc.Sales_Language__c))) ? miAcc.visitAddress.language.touppercase() : null;
		}

		if (miAcc.billingAddress != null) {

			if (miAcc.visitAddress != null) {

				Boolean sameStreet = (((miAcc.visitAddress.street == null) && (miAcc.billingAddress.street == null)) || (miAcc.visitAddress.street.tolowercase() == miAcc.billingAddress.street.tolowercase()));
				Boolean samePostalCode = (((miAcc.visitAddress.postalcode == null) && (miAcc.billingAddress.postalcode == null)) || (miAcc.visitAddress.postalcode.touppercase() == miAcc.billingAddress.postalcode.touppercase()));
				Boolean sameCity = (((miAcc.visitAddress.city == null) && (miAcc.billingAddress.city == null)) || (miAcc.visitAddress.city.touppercase() == miAcc.billingAddress.city.touppercase()));
				Boolean sameCountry = (((miAcc.visitAddress.country == null) && (miAcc.billingAddress.country == null)) || (miAcc.visitAddress.country.touppercase() == miAcc.billingAddress.country.touppercase()));

				if (miAcc.visitAddress.Id == miAcc.billingAddress.Id) {
					// same address -> make shipping address free
					acc.useBillingAddress__c = false;
				} else if (sameStreet && samePostalCode && sameCity && sameCountry) {
					acc.useBillingAddress__c = false;
				} else {
					acc.useBillingAddress__c = true;
				}

			}

			if (acc.useBillingAddress__c) {
				acc.BillingCountryCode = miAcc.billingAddress.country;
				acc.BillingPostalCode = miAcc.billingAddress.PostalCode;
				acc.BillingCity = (miAcc.billingAddress.City != null) ? miAcc.billingAddress.City : '';
				acc.BillingStreet = (miAcc.billingAddress.Street != null) ? miAcc.billingAddress.Street: '';
				acc.BillingStreet += (miAcc.billingAddress.Housenumber != null) ? (' ' + miAcc.billingAddress.Housenumber) : '';
			}


			String billingName = miAcc.billingAddress.firstName;
			if (String.isNotBlank(miAcc.billingAddress.insertion)) {
				billingName += ' ' + miAcc.billingAddress.insertion;
			}
			billingName += ' ' + miAcc.billingAddress.surName;
			acc.Billing_Name__c = billingName;
			acc.Billing_Email__c = Util_System.sanitizeEmail(miAcc.billingAddress.email);
			acc.Billing_Phone__c = miAcc.billingAddress.phoneNumber;
			acc.Sales_Language__c = ((miAcc.billingAddress.language != null) && (String.IsBlank(acc.Sales_Language__c))) ? miAcc.billingAddress.language.touppercase() : null;
		}

		if(accountIsNew){
			//before inserting the account, run the duplicate rules
			Boolean duplicateRulesFound = true;
			List<Datacloud.FindDuplicatesResult> findDuplicatesResult = new List<Datacloud.FindDuplicatesResult>();

			try {
				findDuplicatesResult = Datacloud.FindDuplicates.findDuplicates(new List<Account>{acc});
			} catch(System.HandledException e){
				//if(e.getMessage().startsWith('No active duplicate rules are defined for the')){
					duplicateRulesFound = false;
				//}
			}

			if ((duplicateRulesFound) && (findDuplicatesResult.size() >= 1)) {

				Datacloud.DuplicateResult duplicateResult = findDuplicatesResult.get(0).getDuplicateResults().get(0);
				Datacloud.MatchResult matchResult = duplicateResult.getMatchResults()[0];
				List<Datacloud.MatchRecord> matchRecords = matchResult.getMatchRecords();

				if(matchRecords.size() != 0){
					for(Datacloud.MatchRecord matchRecord : matchRecords){

						sSOQL = 'SELECT Id, ' + extIdField + ' FROM Account WHERE Id = \'' + matchRecord.getRecord().Id + '\' LIMIT 1';
						//system.debug(sSOQL);
						List<Account> dupAccts = Database.query(sSOQL);

						//system.debug(dupAccts);
						if((dupAccts.size() == 1) && (String.isBlank((String)dupAccts[0].get(extIdField)))) {
							//system.debug('JA');
							acc.Id = dupAccts[0].Id;
							//dupAccts[0].put(extIdField, miAcc.id);
							//database.update(dupAccts[0]);
							accountIsNew = false;
							break;
						}
					}
				}
			}
		}

		//system.debug(acc);
		//system.debug(accountIsNew);
		//system.debug(acc.get(extIdField));

		if (String.isNotBlank(miAcc.kickbackId)) {
			sSOQL = 'SELECT Id,' + extIdField
			+ ' FROM Account'
			+ ' WHERE ' + extIdField + ' = \'' + miAcc.kickbackId + '\''
			+ ' LIMIT 1';

			list<Account> kbAccts = database.query(sSOQL);

			if (kbAccts.size() > 0) {
				acc.Kickback_Reseller__c = kbAccts[0].Id;
			}
		}

		Rest_UpsertAccount.record = acc;

		// restore deactivated state to false
		acc.Deactivated__c = false;

		if(accountIsNew){
			if (String.isNotBlank(miAcc.marketId)) {
				acc.Market__c = Util_System.getSalesMarket(miAcc.marketId);
			} else {
				acc.Market__c =  (miAcc.platformId == 1) ? 'Security' : 'Fleet';
			}

			if (String.isNotBlank(miAcc.salesChannelId)) {
				acc.Sales_Channel__c = Util_System.getSalesChannel(miAcc.salesChannelId);
			} else {
				acc.Sales_Channel__c =  'Moving Intelligence';
			}

			Database.insert(acc);

			//if the reseller is not 1, 2, 3 or 4, trigger a call to exact as well
			/*
			Set<String> excludedResellers = new Set<String>{'2', '3', '4'};
			if(!excludedResellers.contains(acc.Reseller_Name__c)){
				Util_Exact.syncAccountAsync(acc.Id);
			} */
		} else {
			if (acc.Contact_Billing__r.Email == null) {
				acc.Subscription25__Digital_Invoicing__c = false;
			}

			Database.update(acc);
		}

		return Util_Rest.makeAddedRecord('Account', miAcc.id, acc.Id);
	}

	//this function upserts incoming accounts from Moving Intelligence.
	//if everything went well the added contacts will be added to the result object with their ids and object type.
	private static List<Util_Rest.AddedRecord> upsertMiContacts(Rest_UpsertAccount.MiAccount miAccount){

		if (miAccount == null) return null;

		String extIdField = 'extId_' + String.valueOf(miAccount.platformId) + '__c';
		List<Rest_UpsertAccount.MiContact> miContacts = new List<Rest_UpsertAccount.MiContact>();
		Rest_UpsertAccount.MiContact miVisitContact;
		String visitName;
		Rest_UpsertAccount.MiContact miBillingContact;
		String billingName;
		Boolean accUpdateVisit = false;
		Boolean accUpdateShipping = false;
		Boolean accUpdateBilling = false;
		Boolean accUpdateAdmin = false;

		if ((miAccount.visitAddress != null) && String.isNotBlank(miAccount.visitAddress.Id)) {
			miVisitContact = new Rest_UpsertAccount.MiContact();

			miVisitContact.id = miAccount.visitAddress.Id + 'a';
			miVisitContact.accountId = miAccount.visitAddress.accountId;
			miVisitContact.firstName = miAccount.visitAddress.firstName;
			miVisitContact.insertion = miAccount.visitAddress.insertion;
			miVisitContact.surName = miAccount.visitAddress.surName;
			miVisitContact.email = Util_System.sanitizeEmail(miAccount.visitAddress.email);
			miVisitContact.phoneNumber = miAccount.visitAddress.phoneNumber;
			miVisitContact.mobilePhone = miAccount.visitAddress.mobilePhone;
			miVisitContact.otherPhone = miAccount.visitAddress.otherPhone;
			miVisitContact.language = miAccount.visitAddress.language;
			miVisitContact.street = miAccount.visitAddress.street;
			miVisitContact.houseNumber = miAccount.visitAddress.houseNumber;
			miVisitContact.postalCode = miAccount.visitAddress.postalCode;
			miVisitContact.city = miAccount.visitAddress.city;
			miVisitContact.country = miAccount.visitAddress.country;miVisitContact.newsLetter = miAccount.visitAddress.newsLetter;
			miVisitContact.type = 'V';
			miVisitContact.isActive = true; // value of has account
			miVisitContact.hasDealerTaskAccess = false; //dealer tasks
			miVisitContact.isAdministrator = false;

			visitName = (String.isNotBlank(miVisitContact.firstName)) ? miVisitContact.firstName : '';
			visitName += (String.isNotBlank(miVisitContact.insertion)) ? (' ' + miVisitContact.insertion) : '';
			visitName += (String.isNotBlank(miVisitContact.surName)) ? (' ' + miVisitContact.surName) : '';
			visitName = (String.isNotBlank(visitName)) ? visitName.trim() : '';
		}

		if((miAccount.billingAddress != null) && String.isNotBlank(miAccount.billingAddress.Id) && ((miAccount.visitAddress == null) || ((miAccount.visitAddress.Id != miAccount.billingAddress.Id) && (miAccount.visitAddress.Email != miAccount.billingAddress.Email)))) {
			miBillingContact = new Rest_UpsertAccount.MiContact();

			miBillingContact.id = miAccount.billingAddress.Id + 'a';
			miBillingContact.accountId = miAccount.billingAddress.accountId;
			miBillingContact.firstName = miAccount.billingAddress.firstName;
			miBillingContact.insertion = miAccount.billingAddress.insertion;
			miBillingContact.surName = miAccount.billingAddress.surName;
			miBillingContact.email = Util_System.sanitizeEmail(miAccount.billingAddress.email);
			miBillingContact.phoneNumber = miAccount.billingAddress.phoneNumber;
			miBillingContact.mobilePhone = miAccount.billingAddress.mobilePhone;
			miBillingContact.otherPhone = miAccount.billingAddress.otherPhone;
			miBillingContact.language = miAccount.billingAddress.language;
			miBillingContact.street = miAccount.billingAddress.street;
			miBillingContact.houseNumber = miAccount.billingAddress.houseNumber;
			miBillingContact.postalCode = miAccount.billingAddress.postalCode;
			miBillingContact.city = miAccount.billingAddress.city;
			miBillingContact.country = miAccount.billingAddress.country;
			miBillingContact.newsLetter = miAccount.billingAddress.newsLetter;
			miBillingContact.type = 'B';
			miBillingContact.isActive = true; // value of has account
			miBillingContact.hasDealerTaskAccess = false; //dealer tasks
			miBillingContact.isAdministrator = false;

			billingName = (String.isNotBlank(miBillingContact.firstName)) ? miBillingContact.firstName : '';
			billingName += (String.isNotBlank(miBillingContact.insertion)) ? (' ' + miBillingContact.insertion) : '';
			billingName += (String.isNotBlank(miBillingContact.surName)) ? (' ' + miBillingContact.surName) : '';
			billingName = (String.isNotBlank(billingName)) ? billingName.trim() : '';
		} else if (String.isNotBlank(miAccount.visitAddress.Id)) {
			miVisitContact.type += ',B';
		}

		// check visit and or billing exists in changed contact, then override other wise add
		boolean visitNotFound = true;
		boolean billingNotFound = true;
		String contName;

		if(miAccount.contactDTOs != null && !miAccount.contactDTOs.isEmpty()){
			miContacts.addAll(miAccount.contactDTOs);
			//miContacts.sort();
			Rest_UpsertAccount.MiContact miCont;

			//for (Rest_UpsertAccount.MiContact miCont : miContacts) {
			for(Integer iCount = miContacts.size()-1; iCount >=0; iCount--) {
				miCont = miContacts[iCount];

				contName = (String.isNotBlank(miCont.firstName)) ? miCont.firstName : '';
				contName += (String.isNotBlank(miCont.insertion)) ? (' ' + miCont.insertion) : '';
				contName += (String.isNotBlank(miCont.surName)) ? (' ' + miCont.surName) : '';
				contName = (String.isNotBlank(contName)) ? contName.trim() : '';

				miCont.email = Util_System.sanitizeEmail(miCont.email);
				miCont.type = (miCont.isAdministrator==null) ? 'L': ((miCont.isAdministrator) ? 'A' : 'L');

				if ((miVisitContact != null) && ((String.isNotBlank(miVisitContact.email) && (miCont.email == miVisitContact.email)) || (String.isNotBlank(visitName) && (visitName == contName)))) {
					// override contact with visit adrress
					miCont.firstName = miVisitContact.firstName;
					miCont.insertion = miVisitContact.insertion;
					miCont.surName = miVisitContact.surName;
					miCont.email = (miCont.email == null) ? miVisitContact.email : miCont.email;
					miCont.phoneNumber = miVisitContact.phoneNumber;
					miCont.mobilePhone = miVisitContact.mobilePhone;
					miCont.otherPhone = miVisitContact.otherPhone;
					miCont.language = miVisitContact.language;
					miCont.street = miVisitContact.street;
					miCont.houseNumber = miVisitContact.houseNumber;
					miCont.postalCode = miVisitContact.postalCode;
					miCont.city = miVisitContact.city;
					miCont.country = miVisitContact.country;
					miCont.newsletter = (miVisitContact.newsletter == null) ? miCont.newsletter : miVisitContact.newsletter;
					miCont.type += ',' + miVisitContact.type;
					miCont.isActive = miVisitContact.isActive;

					visitNotFound = false;
				}

				if ((miBillingContact != null) && ((miVisitContact == null) || (miVisitContact.Id != miBillingContact.Id)) && ((String.isNotBlank(miBillingContact.email) && (miCont.email == miBillingContact.email)) || (String.isNotBlank(billingName) && (billingName == contName)))) {
				//if ((miAccount.billingAddress != null) && ((String.isNotBlank(miAccount.billingAddress.Id) && ((miAccount.visitAddress == null) || (miAccount.visitAddress.Id != miAccount.billingAddress.Id)) && String.isNotBlank(miBillingContact.email) && (miCont.email == miBillingContact.email)) || (String.isNotBlank(miAccount.billingAddress.Id) && String.isNotBlank(billingName) && (billingName == contName))) {
					// override contact with billing adrress
					miCont.firstName = miBillingContact.firstName;
					miCont.insertion = miBillingContact.insertion;
					miCont.surName = miBillingContact.surName;
					miCont.email = (miCont.email == null) ? miBillingContact.email : miCont.email;
					miCont.phoneNumber = miBillingContact.phoneNumber;
					miCont.mobilePhone = miBillingContact.mobilePhone;
					miCont.otherPhone = miBillingContact.otherPhone;
					miCont.language = miBillingContact.language;
					miCont.street = miBillingContact.street;
					miCont.houseNumber = miBillingContact.houseNumber;
					miCont.postalCode = miBillingContact.postalCode;
					miCont.city = miBillingContact.city;
					miCont.country = miBillingContact.country;
					miCont.newsletter = (miBillingContact.newsletter == null) ? miCont.newsletter : miBillingContact.newsletter;
					miCont.type += ',' + miBillingContact.type;
					miCont.isActive = miBillingContact.isActive;

					billingNotFound = false;
				}

				if (miCont.isActive == null){
					miCont.isActive = true;
				}
			}
		}

		if ((miAccount.visitAddress != null) && String.isNotBlank(miAccount.visitAddress.Id) && visitNotFound && (miVisitContact != null)) {
			miContacts.add(miVisitContact);
		}

		if ((miAccount.billingAddress != null) && String.isNotBlank(miAccount.billingAddress.Id) && ((miAccount.visitAddress == null) || (miAccount.visitAddress.Id != miAccount.billingAddress.Id)) && billingNotFound && (miBillingContact != null)) {
			miContacts.add(miBillingContact);
		}

		// 20200703 - Tri - Added MI_Administrator
		String sSOQL = 'SELECT Id, '
			+ ' Contact_Person__c, Contact_Person__r.Id, Contact_Person__r.Is_Active__c, Contact_Person__r.'  + extIdField + ','
			+ ' Contact_Billing__c, Contact_Billing__r.Id, Contact_Billing__r.Is_Active__c, Contact_Billing__r.' + extIdField + ','
			+ ' Contact_Shipping__c, Contact_Shipping__r.Id, Contact_Shipping__r.Is_Active__c, Contact_Shipping__r.' + extIdField + ','
			+ ' MI_Administrator__c, MI_Administrator__r.Id, MI_Administrator__r.Is_Active__c, MI_Administrator__r.' + extIdField
			+ ' FROM Account'
			+ ' WHERE ' + extIdField + ' = \'' + miAccount.id + '\''
			+ ' LIMIT 1';

		//system.debug(sSOQL);

		Account acc = Database.Query(sSOQL);

		sSOQL = 'SELECT '
				+ 'Id, ' + extIdField
				+ ', Name, FirstName, MiddleName, LastName, Email, Email_Encrypted__c, LeadSource'
				+ ' FROM Contact'
				+ ' WHERE Account.'+ extIdField + ' = \'' + miAccount.id + '\'';

		List<Contact> sfContacts = Database.Query(sSOQL);

		Map<String, Contact> emailContacts = new Map<String, Contact>();
		Map<String, Contact> extIdContacts = new Map<String, Contact>();
		Map<String, Contact> nameContacts = new Map<String, Contact>();
		List<Contact> newContacts = new List<Contact>();
		Map<String, Contact> updateContacts = new Map<String, Contact>();
		//List<Contact> updateContacts = new List<Contact>();
		List<Contact> conts = new List<Contact>();
		Map<String, Schema.SObjectField> contFieldMap = Schema.SObjectType.Contact.fields.getMap();
		Contact cont;
		Blob blobEmail;
		Boolean uniqueEmail = Util_System.getDataSetting('Contact_UniqueEmailAddresses');

		//if (!sfContacts.isEmpty()) {
		for (Contact curContact :sfContacts) {
			curContact.Email = Util_System.sanitizeEmail(curContact.Email);
			
			if (curContact.get(extIdField) != null) {
				//system.debug('String.valueOf(curContact.get(extIdField) = ' + String.valueOf(curContact.get(extIdField)));
				extIdContacts.put(String.valueOf(curContact.get(extIdField)), curContact);
			}
			if (String.isNotBlank(curContact.Email)) {
				emailContacts.put(curContact.Email, curContact);
			}
			if ((String.isNotBlank(curContact.Name)) && (String.isBlank(curContact.Email))) {
				nameContacts.put(curContact.Name.Trim().toUpperCase(), curContact);
			}
		}
		//}

		Boolean newContact;

		system.debug(miContacts);
		system.debug(miContacts.size());

		for (MiContact miCont :miContacts) {
			if(miCont.id == null){
				throw new Util_Rest.UpsertException('Error: A Contact was added with no ID');
			}
			newContact = false;

			//determine contact first by extId
			contName = (String.isNotBlank(miCont.firstName)) ? miCont.firstName : '';
			contName += (String.isNotBlank(miCont.insertion)) ? (' ' + miCont.insertion) : '';
			contName += (String.isNotBlank(miCont.surName)) ? (' ' + miCont.surName) : '';
			contName = (String.isNotBlank(contName)) ? contName.trim() : '';

			if (extIdContacts.containsKey(miCont.id)) {
				cont = extIdContacts.get(miCont.id);
			} else if (emailContacts.containsKey(miCont.email)) {
				cont = emailContacts.get(miCont.email);
			} else if((String.isNotBlank(contName)) && (nameContacts.containsKey(contName.toUpperCase()))) {
				cont = nameContacts.get(contName.toUpperCase());
			} else {
				cont = new Contact();
				cont.LeadSource = 'Platform';
				newContact = true;
			}

			//system.debug('check id : ' + cont.get(extIdField));
			//system.debug('check id(last) : ' + String.valueOf(cont.get(extIdField)).right(1));

			if ((cont.get(extIdField) == null)  || ((cont.get(extIdField) != null) && (cont.get(extIdField) != miCont.Id) && (String.valueOf(miCont.Id).right(1) != 'a'))) {
				cont.put(extIdField, miCont.Id);
			}

			system.debug('check id (result): ' + cont.get(extIdField));

			cont.AccountId = acc.Id;
			cont.FirstName = (String.isNotBlank(miCont.surName)) ? miCont.firstName: null;		
			cont.MiddleName = miCont.insertion;
			cont.LastName = (String.isNotBlank(miCont.surName)) ? miCont.surName : ((String.isNotBlank(miCont.firstName)) ? miCont.firstName : ('Error  - ' + miCont.Id));


			if (miCont.Email != null) {
				blobEmail = Crypto.generateDigest('SHA3-512', Blob.valueOf(miCont.Email));
				cont.Email_Encrypted__c = EncodingUtil.convertToHex(blobEmail);
				cont.Email = miCont.email;
				cont.Unique_Key__c = (!uniqueEmail) ? acc.Id + '|' : '';
				cont.Unique_Key__c += cont.Email_Encrypted__c;
			} else {
				cont.Email = null;
				cont.Email_Encrypted__c = null;
				cont.Unique_Key__c = null;
			}

			cont.Phone = miCont.phoneNumber;
			cont.MobilePhone = miCont.mobilePhone;
			cont.OtherPhone = miCont.otherPhone;
			cont.Language__c = (miCont.language != null) ? miCont.language.touppercase() : null;
			cont.MailingStreet = (miCont.street != null) ? miCont.street: '';
			cont.MailingStreet += (miCont.houseNumber != null) ? (' ' + miCont.houseNumber) : '';
			cont.MailingPostalCode = miCont.postalCode;
			cont.MailingCity = miCont.city;
			cont.MailingCountryCode = miCont.country;
			cont.NewsLetter__c = (miCont.newsLetter==null) ? false : miCont.newsLetter;
			cont.Is_Active__c = (miCont.isActive==null)?true:miCont.isActive;
			cont.Is_Administrator__c = (miCont.isAdministrator==null)?false:miCont.isAdministrator;
			cont.Has_Dealertask_access__c = (miCont.hasDealerTaskAccess==null)?false:miCont.hasDealerTaskAccess;

			// Main Contact
			if (miCont.type.contains('V') && ((acc.Contact_Person__r == null) || (acc.Contact_Person__r.get(extIdField) != cont.get(extIdField))) && !accUpdateVisit) {
				Contact visitCont;

				if (acc.Contact_Person__r == null) {
					visitCont = new Contact();
					visitCont.put(extIdField,cont.get(extIdField));
				} else {
					visitCont = acc.Contact_Person__r;
				}

				acc.Contact_Person__r = visitCont;
				accUpdateVisit = true;
			}

			// Shipping Contact
			if (miCont.type.contains('V') && ((acc.Contact_Shipping__r == null)|| (acc.Contact_Shipping__r.get(extIdField) != cont.get(extIdField))) && !accUpdateShipping) {
				Contact shippingCont;

				if (acc.Contact_Shipping__r == null) {
					shippingCont = new Contact();
					shippingCont.put(extIdField,cont.get(extIdField));
				} else {
					shippingCont = acc.Contact_Shipping__r;
				}

				acc.Contact_Shipping__r = shippingCont;

				accUpdateShipping = true;
			}

			// Billing Contact
			if (miCont.type.contains('B') && ((acc.Contact_Billing__r == null) || (acc.Contact_Billing__r.get(extIdField) != cont.get(extIdField))) && !accUpdateBilling) {
				Contact billingCont;

				if (acc.Contact_Billing__r == null) {
					billingCont = new Contact();
					billingCont.put(extIdField,cont.get(extIdField));
				} else {
					billingCont = acc.Contact_Billing__r;
				}

				acc.Contact_Billing__r = billingCont;
				accUpdateBilling = true;
			}

			// Administrator Contact
			if (miCont.type.contains('A') &&  ((acc.MI_Administrator__r == null) || (acc.MI_Administrator__r.get(extIdField) != cont.get(extIdField))) && !accUpdateAdmin) {
				Contact adminCont;

				if (acc.MI_Administrator__r == null) {
					adminCont = new Contact();
					adminCont.put(extIdField,cont.get(extIdField));
				} else {
					adminCont = acc.MI_Administrator__r;
				}

				acc.MI_Administrator__r = adminCont;
				accUpdateAdmin = true;
			}

			if (newContact) {
				system.debug('add new');
				newContacts.add(cont);
			} else {
				system.debug('update contact');
				updateContacts.put(cont.id,cont);
			}

			system.debug(cont);

		}

		system.debug('emailContacts');
		system.debug(emailContacts);

		system.debug('extIdContacts');
		system.debug(extIdContacts);

		system.debug('nameContacts');
		system.debug(nameContacts);
		
		system.debug('newContacts');
		system.debug(newContacts);

		system.debug('updateContacts');
		system.debug(updateContacts.values());

		system.debug('conts');
		system.debug(conts);

		if (!newContacts.isEmpty()) {
			//Database.upsert(newContacts, contFieldMap.get(extIdField));
			Database.insert(newContacts);
			conts.addAll(newContacts);
		}
		if (!updateContacts.isEmpty()) {
			Database.update(updateContacts.values());
			conts.addAll(updateContacts.values());
		}

		List<Util_Rest.AddedRecord> records = new List<Util_Rest.AddedRecord>();

		for (Contact curCont :conts){

			if (String.valueOf(curCont.get(extIdField)).right(1) != 'a') {
				records.add(Util_Rest.makeAddedRecord('Contact', String.valueOf(curCont.get(extIdField)), curCont.Id));
			}
		}

		if ((accUpdateVisit) || (accUpdateShipping) || (accUpdateBilling) || (accUpdateAdmin))  {
			system.debug('Account = ' + acc);
			Database.update(acc);
		}

		return records;
	}

	public class MiContactWrapper implements Comparable {

		public MiContact miContY;

		// Constructor
		public MiContactWrapper(MiContact miCont) {
			// Guard against wrapping a null
			if(miCont == null) {
				Exception ex = new NullPointerException();
				ex.setMessage('MiContact argument cannot be null');
				throw ex;
			}
			miContY = miCont;
		}

		// Compare opportunities based on the opportunity amount.
		public Integer compareTo(Object compareTo) {
			// Cast argument to OpportunityWrapper
			MiContactWrapper compareToMiContY = (MiContactWrapper)compareTo;

			// The return value of 0 indicates that both elements are equal.
			Integer returnValue = 0;
			if ((miContY.Id == null) && (compareToMiContY.miContY.Id == null)) {
				// both wrappers have null Amounts
				returnValue = 0;
			} else if ((miContY.Id == null) && (compareToMiContY.miContY.Id != null)){
				// nulls-first implementation
				returnValue = -1;
			} else if ((MiContY.Id != null) && (compareToMiContY.miContY.Id == null)){
				// nulls-first implementation
				returnValue = 1;
			} else if (miContY.Id > compareToMiContY.miContY.Id) {
				// Set return value to a positive value.
				returnValue = 1;
			} else if (miContY.Id < compareToMiContY.miContY.Id) {
				// Set return value to a negative value.
				returnValue = -1;
			}
			return returnValue;
		}
	}

	//these classes are used for deserializing the incoming JSON file.
	public class MiAccount {
		public String id;
		public String echoesAccountId; // echoes platform id, used when a account is migrated to this plaftorm, used by the Europetrack Platform 
		public Long platformId;
		public String marketId; //1 Security, 2 Fleet, 3 Internal, Platform 1 -> default security, 2 -> default fleet, 3 default tbd, 4 default n/a, 5 default fleet;
		public String salesChannelId;
		public String salesforceId;
		public String kickbackId;
		public Boolean privacyMode;
		public String debtorNumber;
		public String previousDebtorNumber;
		public String name;
		public String shortName;
		public Boolean isBusiness;
		public String vatNumber;
		public String cocNumber;
		public String paymentMethodExactCode;
		public String bankAccountHolder;
		public String bankAccountNumber;
		public String bankAccountBic;
		public Boolean isDealer;
		public Boolean isBlocked;
		public Boolean isBankrupt;
		public Long resellerId;
		public String primarySbiCode;
		public String secondarySbiCode1;
		public String secondarySbiCode2;
		public Long personnelCount;
		public Long fulltimePersonnelCount;
		public String directDebitStatus;
		public String directDebitReference;
		public String directDebitLastTakenDate;
		public List<Rest_UpsertAccount.MiContact> contactDTOs;
		// GS 07Dec2023 Added below fields.
		public Integer contractTerm;
		public Integer noticeTerm;
		public Integer renewalTerm;
		public Integer orderOffsetTerm;
		public String invoicePeriod; //values '0' Contract period, '1' Monthly, '3' Quarterly, '12' Yearly and 'Order' (not for subscriptions)
		public String subscriptionType; //values 'Professional', 'Ultimate' and 'Premium'

		//public Rest_UpsertAccount.visitAddress visitAddress;
		//public Rest_UpsertAccount.billingAddress billingAddress;
		public Rest_UpsertAccount.MiContact visitAddress;
		public Rest_UpsertAccount.MiContact billingAddress;

		public MiAccount(){}

		public MiAccount(Account acct){
			this(acct, null);
		}

		public MiAccount(Account acct, String debtorNumber){
			this.id = acct.extId_1__c; // platfrom specific -> managed by platform - create, no update
			this.platformId = 1;  // platfrom specific -> managed by platform - create, no update
			this.resellerId = Long.valueOf(acct.Reseller_Name__c); // platfrom specific -> managed by platform - create, no update
			this.salesforceId = acct.Id; // platfrom specific -> managed by platform - create, no update
			this.marketId = Util_system.getSalesMarket(acct.Market__c);
			this.salesChannelId = Util_system.getSalesChannel(acct.Sales_Channel__c);
			this.debtorNumber = !String.isBlank(debtorNumber) ? debtorNumber : acct.FinancialDebtorNumber__c; // platfrom specific -> managed by platform - create, update, distribution
			this.previousDebtorNumber = acct.FinancialDebtorNumberPrevious__c; // platfrom specific -> managed by platform - create, no update
			this.name = acct.Name; // create, updatable -> distribution?
			this.shortName = acct.Short_Name__c;
			this.isBusiness = acct.isBusiness__c; // create, updatable -> distribution?
			this.privacyMode = acct.isPrivacyMode__c; // create, is this generic or platform specific
			this.vatNumber = acct.VAT_Number__c; // create, updatable -> distribution?
			this.cocNumber = acct.CoC_Number__c; // create, updatable -> distribution?
			this.paymentMethodExactCode = acct.Payment_Method_Contracts__c; // create, updatable -> distribution?
			this.bankAccountHolder = acct.Bank_Account__c; // create, updatable -> distribution? - null prevention
			this.bankAccountNumber = acct.Bank_Account_Number__c; // create, updatable -> distribution? - null prevention
			this.bankAccountBic = acct.Bank_BIC__c; // create, updatable -> distribution? - null prevention
			this.primarySbiCode = acct.SBI_Primary_Code__c; // create, updatable -> distribution? - null prevention
			this.secondarySbiCode1 = acct.SBI_Secondary_Code_1__c; // create, updatable -> distribution? - null prevention
			this.secondarySbiCode2 = acct.SBI_Secondary_Code_2__c; // create, updatable -> distribution? - null prevention
			this.personnelCount = acct.NumberOfEmployees; // create, updatable -> distribution? - null prevention
			this.fulltimePersonnelCount = acct.NumberOfFulltimeEmployees__c != null ? acct.NumberOfFulltimeEmployees__c.longValue() : null;  // create, updatable -> distribution? - null prevention
			this.isBlocked = acct.Is_Blocked__c;  // create, updatable -> distribution? - managed by salesforce previous exact
			this.isBankrupt = acct.IsBankrupt__c;  // create, updatable -> distribution? - managed by salesforce previous exact

			this.contactDTOs = new List<Rest_UpsertAccount.MiContact>{new Rest_UpsertAccount.MiContact(acct.Contact_Person__r)};

			//this.visitAddress = new Rest_UpsertAccount.visitAddress(); // consequences other systems - null ??
			this.visitAddress = new Rest_UpsertAccount.MiContact(); // consequences other systems - null ??
			this.visitAddress.postalCode = acct.ShippingPostalCode;
			this.visitAddress.city = acct.ShippingCity;
			this.visitAddress.street = acct.ShippingStreet;
			this.visitAddress.country = acct.ShippingCountryCode;
			this.visitAddress.email = acct.Shipping_Email__c;
			this.visitAddress.phoneNumber = acct.Shipping_Phone__c;
			this.visitAddress.mobilePhone = acct.Contact_Person__r.MobilePhone;
			this.visitAddress.otherPhone = acct.Contact_Person__r.OtherPhone;
			this.visitAddress.language = acct.Sales_Language__c;
			this.visitAddress.firstName = acct.Contact_Person__r.FirstName;
			this.visitAddress.insertion = acct.Contact_Person__r.MiddleName;
			this.visitAddress.surName = acct.Contact_Person__r.LastName;
			this.visitAddress.newsLetter = acct.Contact_Person__r.Newsletter__c;
			this.visitAddress.type = 'V';

			//this.billingAddress = new Rest_UpsertAccount.billingAddress(); // consequences other systems - null ??
			this.billingAddress = new Rest_UpsertAccount.MiContact(); // consequences other systems - null ??
			this.billingAddress.postalCode = acct.BillingPostalCode;
			this.billingAddress.city = acct.BillingCity;
			this.billingAddress.street = acct.BillingStreet;
			this.billingAddress.country = acct.BillingCountryCode;
			this.billingAddress.email = acct.Billing_Email__c;
			this.billingAddress.phoneNumber = acct.Billing_Phone__c;
			this.billingAddress.mobilePhone = acct.Contact_Billing__r.MobilePhone;
			this.billingAddress.otherPhone = acct.Contact_Billing__r.OtherPhone;
			this.billingAddress.language = acct.Sales_Language__c;
			this.billingAddress.firstName = acct.Contact_Billing__r.FirstName;
			this.billingAddress.insertion = acct.Contact_Billing__r.MiddleName;
			this.billingAddress.surName = acct.Contact_Billing__r.LastName;
			this.billingAddress.newsLetter = acct.Contact_Billing__r.Newsletter__c;
			this.billingAddress.type = 'B';
		}
	}

	public class MiContact {
		public String id;
		public Id salesforceId;
		public String accountId;
		public String firstName;
		public String insertion;
		public String surName;
		public String email;
		public String function;
		public String phoneNumber;
		public String mobilePhone;
		public String otherPhone;
		public String language;
		public String street;
		public String houseNumber;
		public String postalCode;
		public String city;
		public String country;
		public String type; // V = Visiting, B = Billing, A = Administrator, L = Login
		public Boolean isActive; // value of has account
		public Boolean hasDealerTaskAccess; //dealer tasks
		public Boolean isAdministrator;
		public Boolean newsLetter;

		public MiContact(){}

		public MiContact(Contact cont){
			this.salesforceId = cont.Id;
			//this.accountId = '';
			this.firstName = cont.FirstName;
			this.insertion = cont.MiddleName;
			this.surName = cont.LastName;
			this.email = cont.Email;
			this.function = cont.Title;
			this.phoneNumber = cont.Phone;
			this.mobilePhone = cont.MobilePhone;
			this.otherPhone = cont.OtherPhone;
			this.language = cont.Language__c;
			this.street = cont.MailingStreet;
			this.postalCode = cont.MailingPostalCode;
			this.city = cont.MailingCity;
			this.country = cont.MailingCountryCode;
			this.isActive = cont.Is_Active__c;
			this.hasDealerTaskAccess = cont.Has_Dealertask_access__c;
			this.isActive = cont.Is_Active__c;
			this.isAdministrator = true;
			this.newsLetter = cont.Newsletter__c;
			this.type = (cont.Has_Dealertask_access__c) ? 'A': 'L';
		}
	}
}
