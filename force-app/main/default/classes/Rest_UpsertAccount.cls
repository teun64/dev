@RestResource(UrlMapping='/UpsertAccount')
global without sharing class Rest_UpsertAccount {
	private static Account accountRecord;
	private static Boolean accountIsNew;
	private static AccessLevel runningMode = AccessLevel.SYSTEM_MODE;

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
			Rest_UpsertAccount.MiAccount miAccount = (Rest_UpsertAccount.MiAccount) JSON.deserialize(reqBody,Rest_UpsertAccount.MiAccount.class);
			logger.setSessionRecordExternalId(sessionId, miAccount.id);
			logger.setCallingSystem(sessionId, miAccount.platformId);

			//upsert accounts and contacts
			result.addedRecords.add(Rest_UpsertAccount.upsertMiAccount(miAccount));

			//contactDTO can be null if only the account is updated.
			//added visitAddress (and/or) billingAddress) as contact,
			result.addedRecords.addAll(Rest_UpsertAccount.upsertMiContacts(miAccount));

			if ((miAccount.platformId != 1) && (miAccount.platformId != 5)) {
				Util_Rest.checkDebtorNumber(miAccount.id,String.valueOf(miAccount.platformId));
			}

			//if everything went right add the following message and set Success to true.
			result.messages.add(
				'Succes: Account and Contact(s) have been added for: ' +
				miAccount.name +
				'. With the following ID: ' +
				miAccount.id +
				'.'
			);
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

		Logger.setSessionRecord(sessionId, Rest_UpsertAccount.accountRecord?.Id, Rest_UpsertAccount.accountRecord?.Name);
		String responseBody = JSON.serialize(result);
		Integer statusCode = result.success ? 200 : 400;
		Logger.finalizeSession(sessionId, responseBody, statusCode);
		Logger.saveAll();

		return result;
	}

	//this function upserts incoming accounts from Moving Intelligence.
	//if everything went well the added accounts will be added to the result object with their ids and object type.
	public static Util_Rest.AddedRecord upsertMiAccount(Rest_UpsertAccount.MiAccount miAcc) {
		if (miAcc.id == null) {
			throw new Util_Rest.UpsertException('Error: An Account was added with no ID.');
		}

		String extIdField = 'extId_' + String.valueOf(miAcc.platformId) + '__c';

		Boolean doEchoesAccountId = (String.valueOf(miAcc.platformId) != '6');

		//System.debug(extIdField);

		//there's an issue here; accounts from MI could have an Exact Id that is already known in SF, while the account in
		//SF does not have an MI id. This happens when account is created in SF, synced to Exact and then from Exact to MI.
		//to fix this, first we collect all Exact Id / MI id pairs and put the MI Id in SF on the accounts. This way, the
		//actual sync will remain as is
		String sSOQL;
		Account acc;
		List<Account> existingAccounts;
		Boolean accountIsNew = false;

		//if this is a base service look for contracts by external id
		sSOQL =
			'SELECT Id, Name, Short_Name__c, RecordTypeId, NumberOfEmployees, NumberOfFulltimeEmployees__c, AccountSource,' +
			' VisitingAddress__Street__s, VisitingAddress__PostalCode__s, VisitingAddress__City__s, VisitingAddress__StateCode__s, VisitingAddress__CountryCode__s, ' +
			' Subscription25__Digital_Invoicing__c, Sales_Language__c, useBillingAddress__c, useShippingAddress__c,' +
			' BillingStreet, BillingPostalCode, BillingCity, BillingStateCode, BillingCountryCode, ' +
			' ShippingStreet, ShippingPostalCode, ShippingCity, ShippingStateCode, ShippingCountryCode, ' +
			' IsBankrupt__c, Is_Blocked__c, isPrivacyMode__c, VAT_Number__c, CoC_Number__c,' +
			' Payment_Method_Contracts__c, Payment_Method_Opportunities__c, FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c,' +
			' Bank_Account__c, Bank_Account_Number__c, Bank_BIC__c,' +
			' SBI_Primary_Code__c, SBI_Secondary_Code_1__c, SBI_Secondary_Code_2__c, HasDealerTasks__c, ContractTerm__c,' +
			' NoticeTerm__c, RenewalTerm__c, OrderOffsetTerm__c, Invoice_Period__c, Subscription_Type__c,' +
			' Contact_Person__c, Contact_Person__r.AccountId, Contact_Person__r.Is_Active__c, Contact_Person__r.' +
			extIdField +
			',' +
			' Contact_Billing__c, Contact_Billing__r.AccountId, Contact_Billing__r.Email, Contact_Billing__r.Is_Active__c, Contact_Billing__r.' +
			extIdField +
			',' +
			' Contact_Shipping__c, Contact_Shipping__r.AccountId, Contact_Shipping__r.Is_Active__c, Contact_Shipping__r.' +
			extIdField +
			',' +
			' MI_Administrator__c, MI_Administrator__r.AccountId, MI_Administrator__r.Is_Active__c, MI_Administrator__r.' +
			extIdField +
			',' +
			' extId_6__c' +
			((doEchoesAccountId) ? (', ' + extIdField) : '') +
			' FROM Account' +
			' WHERE ' + extIdField + ' = \'' + miAcc.id + '\'' + 
			' LIMIT 1';

		existingAccounts = Database.query(sSOQL, Rest_UpsertAccount.runningMode);

		if (existingAccounts.size() == 1) {
			acc = existingAccounts[0];
		}

		if (acc == null) {
			accountIsNew = true;
			acc = new Account();
			acc.put(extIdField, miAcc.id);
			acc.AccountSource = 'Platform';
			acc.useBillingAddress__c = false;
			acc.useShippingAddress__c = false;

			acc.Payment_Method_Opportunities__c = (miAcc.resellerId == 6) ? ((miAcc.platformId == 5) ? '14' : ((miAcc.isBusiness == true) ? '08' : 'p1')) : ((miAcc.bankAccountNumber == null) ? '08' : 'I8');

			if (String.isNotBlank(miAcc.marketId)) {
				acc.Market__c = Util_System.getSalesMarket(miAcc.marketId);
			} else {
				acc.Market__c = (miAcc.platformId == 1) ? 'Security' : 'Fleet';
			}

			if (String.isNotBlank(miAcc.salesChannelId)) {
				acc.Sales_Channel__c = Util_System.getSalesChannel(miAcc.salesChannelId);
			} else {
				acc.Sales_Channel__c = 'Moving Intelligence';
			}
		}

		if ((doEchoesAccountId) && (String.isNotBlank(miAcc.echoesAccountId))) {
			acc.extId_6__c = miAcc.echoesAccountId;
		}

		// restore deactivated state to false
		acc.Deactivated__c = false;
		acc.Name = Util_System.cleanName(miAcc.name);
		acc.Short_Name__c = String.isNotBlank(miAcc.shortName) ? miAcc.shortName: null;
		acc.FinancialDebtorNumberPrevious__c = String.isNotBlank(miAcc.previousDebtorNumber) ? miAcc.previousDebtorNumber : null;
		acc.isPrivacyMode__c = (miAcc.privacyMode != null) ? miAcc.privacyMode : false;

		// 20221101 - TRi - force all UK - Direct Debits to I0
		acc.Bank_Account__c = (String.isNotBlank(miAcc.bankAccountHolder)) ? miAcc.bankAccountHolder : ((String.isNotBlank(acc.Bank_Account__c)) ? acc.Bank_Account__c : acc.Name);
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

		// 20230317 TRi Account has dealer tasks, replacement for the record type b2b_dealer.
		acc.HasDealerTasks__c = (miAcc.isDealer == null) ? false : miAcc.isDealer;

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
		acc.SBI_Secondary_Code_2__c = String.isNotBlank(miAcc.secondarySbiCode2) ? miAcc.secondarySbiCode2: '';
		// 202213 - TRi -> Number of Employees and Number of Fulltime Employees added (No using WSONE_DATA fields)
		if ((miAcc.personnelCount != null) && ((acc.NumberOfEmployees == null) || (acc.NumberOfEmployees <= 0))) {
			acc.NumberOfEmployees = Integer.valueOf(miAcc.personnelCount);
		}
		if ((miAcc.fulltimePersonnelCount != null) && ((acc.NumberOfFulltimeEmployees__c == null) || (acc.NumberOfFulltimeEmployees__c <= 0))) {
			acc.NumberOfFulltimeEmployees__c = Integer.valueOf(miAcc.fulltimePersonnelCount);
		}

		if (miAcc.isBlocked != null) {
			acc.Is_Blocked__c = miAcc.isBlocked;
		}

		if (miAcc.isBankrupt != null) {
			acc.IsBankrupt__c = miAcc.isBankrupt;
		}

		acc.Reseller_Name__c = String.valueOf(miAcc.resellerId);

		// GS 07Dec2023 Added below 4 fields to Mapping
		if (miAcc.contractTerm != null) {
			acc.ContractTerm__c = miAcc.contractTerm;
		}
		if (miAcc.noticeTerm != null) {
			acc.NoticeTerm__c = miAcc.noticeTerm;
		}
		if (miAcc.renewalTerm != null) {
			acc.RenewalTerm__c = miAcc.renewalTerm;
		}
		if (miAcc.orderOffsetTerm != null) {
			acc.OrderOffsetTerm__c = miAcc.orderOffsetTerm;
		}
		if (String.isNotBlank(miAcc.invoicePeriod)) {
			acc.Invoice_Period__c = miAcc.invoicePeriod;
		}
		if (String.isNotBlank(miAcc.subscriptionType)) {
			acc.Subscription_Type__c = miAcc.subscriptionType;
		}

		if (miAcc.visitAddress != null) {
			// visit address -> makes shipping address free for real shipping address
			acc.VisitingAddress__PostalCode__s = (miAcc.visitAddress.PostalCode != null) ? miAcc.visitAddress.PostalCode : '';
			acc.VisitingAddress__City__s = (miAcc.visitAddress.City != null) ? miAcc.visitAddress.City : '';
			acc.VisitingAddress__Street__s = (miAcc.visitAddress.Street != null) ? miAcc.visitAddress.Street : '';
			acc.VisitingAddress__Street__s += (miAcc.visitAddress.Housenumber != null) ? (' ' + miAcc.visitAddress.Housenumber) : '';
			acc.VisitingAddress__CountryCode__s = (miAcc.visitAddress.country != null) ? miAcc.visitAddress.country : '';

			// 	move to contact
			String shippingName = miAcc.visitAddress.firstName;
			if (String.isNotBlank(miAcc.visitAddress.insertion)) {
				shippingName += ' ' + miAcc.visitAddress.insertion;
			}
			shippingName += ' ' + miAcc.visitAddress.surName;

			acc.Shipping_Name__c = Util_System.cleanName(shippingName);
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
			} else {
				acc.useBillingAddress__c = false;

				acc.VisitingAddress__CountryCode__s = miAcc.billingAddress.country;
				acc.VisitingAddress__PostalCode__s = miAcc.billingAddress.PostalCode;
				acc.VisitingAddress__City__s = (miAcc.billingAddress.City != null) ? miAcc.billingAddress.City : '';
				acc.VisitingAddress__Street__s = (miAcc.billingAddress.Street != null) ? miAcc.billingAddress.Street : '';
				acc.VisitingAddress__Street__s += (miAcc.billingAddress.Housenumber != null) ? (' ' + miAcc.billingAddress.Housenumber): '';
			}

			if (acc.useBillingAddress__c) {
				acc.BillingCountryCode = miAcc.billingAddress.country;
				acc.BillingPostalCode = miAcc.billingAddress.PostalCode;
				acc.BillingCity = (miAcc.billingAddress.City != null) ? miAcc.billingAddress.City : '';
				acc.BillingStreet = (miAcc.billingAddress.Street != null) ? miAcc.billingAddress.Street : '';
				acc.BillingStreet += (miAcc.billingAddress.Housenumber != null) ? (' ' + miAcc.billingAddress.Housenumber) : '';
			}

			String billingName = miAcc.billingAddress.firstName;

			if (String.isNotBlank(miAcc.billingAddress.insertion)) {
				billingName += ' ' + miAcc.billingAddress.insertion;
			}

			billingName += ' ' + miAcc.billingAddress.surName;
			acc.Billing_Name__c = Util_System.cleanName(billingName);
			acc.Billing_Email__c = Util_System.sanitizeEmail(miAcc.billingAddress.email);
			acc.Billing_Phone__c = miAcc.billingAddress.phoneNumber;

			acc.Sales_Language__c = ((miAcc.billingAddress.language != null) && (String.IsBlank(acc.Sales_Language__c))) ? miAcc.billingAddress.language.touppercase() : null;
		}

		if (accountIsNew) {
			//before inserting the account, run the duplicate rules
			Boolean duplicateRulesFound = true;
			List<Datacloud.FindDuplicatesResult> findDuplicatesResult = new List<Datacloud.FindDuplicatesResult>();

			try {
				findDuplicatesResult = Datacloud.FindDuplicates.findDuplicates(
				new List<Account>{ acc }
				);
			} catch (System.HandledException e) {

				duplicateRulesFound = false;

			}

			if ((duplicateRulesFound) && (findDuplicatesResult.size() >= 1)) {
				Datacloud.DuplicateResult duplicateResult = findDuplicatesResult.get(0).getDuplicateResults().get(0);
				Datacloud.MatchResult matchResult = duplicateResult.getMatchResults()[0];
				List<Datacloud.MatchRecord> matchRecords = matchResult.getMatchRecords();

				if (matchRecords.size() != 0) {
					for (Datacloud.MatchRecord matchRecord : matchRecords) {
						sSOQL = 'SELECT Id, ' + extIdField + ' FROM Account WHERE Id = \'' + matchRecord.getRecord().Id + '\' LIMIT 1';
						//System.debug(sSOQL);
						List<Account> dupAccts = Database.query(sSOQL, Rest_UpsertAccount.runningMode);

						//System.debug(dupAccts);
						if ((dupAccts.size() == 1) && (String.isBlank((String) dupAccts[0].get(extIdField)))) {
							//System.debug('JA');
							acc.Id = dupAccts[0].Id;
							//dupAccts[0].put(extIdField, miAcc.id);
							//database.update(dupAccts[0],Rest_UpsertAccount.runningMode);
							accountIsNew = false;
							break;
						}
					}
				}
			}
		}

		//System.debug(acc);
		//System.debug(accountIsNew);
		//System.debug(acc.get(extIdField));

		if (String.isNotBlank(miAcc.kickbackId)) {
			sSOQL = 'SELECT Id,' + 
				extIdField +
				' FROM Account' +
				' WHERE ' +
				extIdField +
				' = \'' +
				miAcc.kickbackId +
				'\'' +
				' LIMIT 1';

			list<Account> kbAccts = database.query(sSOQL, Rest_UpsertAccount.runningMode);

			if (kbAccts.size() > 0) {
				acc.Kickback_Reseller__c = kbAccts[0].Id;
			}
		}

		// 20221115 - TRi - Direct Debit fields, to stay in sync with Chiron
		// 20230920 - TRI - Changed to not override the defaults, when value is not supplied
		// 20260521 - TRi - Remove after implenting stripe
		if (String.isNotBlank(miAcc.directDebitStatus)) {
			acc.Direct_Debit_Status__c = miAcc.directDebitStatus;
		}
		if (String.isNotBlank(miAcc.directDebitReference)) {
			acc.Direct_Debit_Previous_Reference__c = miAcc.directDebitReference;
		}
		if (String.isNotBlank(miAcc.directDebitLastTakenDate)) {
			acc.Direct_Debit_Last_Taken_Date__c = Datetime.valueOf(miAcc.directDebitLastTakenDate);
		}
		// 20260521 - TRi - Remove after implenting stripe

		if (accountIsNew) {
			Database.insert(acc, Rest_UpsertAccount.runningMode);

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

			Database.update(acc, Rest_UpsertAccount.runningMode);
		}

		Rest_UpsertAccount.accountRecord = acc;
		Rest_UpsertAccount.accountIsNew = accountIsNew;

		return Util_Rest.makeAddedRecord('Account', miAcc.id, acc.Id);
	}

	//this function upserts incoming accounts from Moving Intelligence.
	//if everything went well the added contacts will be added to the result object with their ids and object type.
	private static List<Util_Rest.AddedRecord> upsertMiContacts(Rest_UpsertAccount.MiAccount miAccount) {
		if (miAccount == null) return null;

		String extIdField = 'extId_' + String.valueOf(miAccount.platformId) + '__c';
		Account acc;
		String sSOQL;
		List<Rest_UpsertAccount.MiContact> miContacts = new List<Rest_UpsertAccount.MiContact>();
		Rest_UpsertAccount.MiContact miVisitContact;
		String visitName;
		Rest_UpsertAccount.MiContact miBillingContact;
		String billingName;
		boolean accountUpdate = false;
		Boolean accUpdateVisit = false;
		Boolean accUpdateShipping = false;
		Boolean accUpdateBilling = false;
		Boolean accUpdateAdmin = false;

		if (Rest_UpsertAccount.accountRecord != null) {
			acc = Rest_UpsertAccount.accountRecord;
			//System.debug(acc);
			//System.debug('account id from static variable: ' + acc.Id);
		} else {
			sSOQL =
				'SELECT Id, ' +
				' Contact_Person__c, Contact_Person__r.Id, Contact_Person__r.Is_Active__c, Contact_Person__r.' +
				extIdField +
				',' +
				' Contact_Billing__c, Contact_Billing__r.Id, Contact_Billing__r.Is_Active__c, Contact_Billing__r.' +
				extIdField +
				',' +
				' Contact_Shipping__c, Contact_Shipping__r.Id, Contact_Shipping__r.Is_Active__c, Contact_Shipping__r.' +
				extIdField +
				',' +
				' MI_Administrator__c, MI_Administrator__r.Id, MI_Administrator__r.Is_Active__c, MI_Administrator__r.' +
				extIdField +
				' FROM Account' +
				' WHERE ' +
				extIdField +
				' = \'' +
				miAccount.id +
				'\'' +
				' LIMIT 1';

			//System.debug(sSOQL);

			acc = Database.Query(sSOQL, Rest_UpsertAccount.runningMode);

			//System.debug('account id from query: ' + acc.Id + ' (' + sSOQL + ')');
		}

		Map<String, AccountContactRelation> acrByContactId = Util_Rest.getAccountContactRelations(acc.Id,'ContactId');

		if ((String.isNotBlank(acc.Contact_Person__c)) && (!acrByContactId.containsKey(acc.Contact_Person__c))) {
			accountUpdate = true;
			acc.Contact_Person__c = null;
		}

		if ((String.isNotBlank(acc.Contact_Billing__c)) && (!acrByContactId.containsKey(acc.Contact_Billing__c))) {
			accountUpdate = true;
			acc.Contact_Billing__c = null;
		}

		if ((String.isNotBlank(acc.Contact_Shipping__c)) && (!acrByContactId.containsKey(acc.Contact_Shipping__c))) {
			accountUpdate = true;
			acc.Contact_Shipping__c = null;
		}

		if ((String.isNotBlank(acc.MI_Administrator__c)) && (!acrByContactId.containsKey(acc.MI_Administrator__c))) {
			accountUpdate = true;
			acc.MI_Administrator__c = null;
		}

		if ((miAccount.visitAddress != null) && String.isNotBlank(miAccount.visitAddress.Id)) {
			miVisitContact = new Rest_UpsertAccount.MiContact();

			miVisitContact.id = miAccount.visitAddress.Id + 'a';
			miVisitContact.accountId = miAccount.visitAddress.accountId;
			miVisitContact.firstName = Util_System.cleanName(miAccount.visitAddress.firstName);
			miVisitContact.insertion = Util_System.cleanName(miAccount.visitAddress.insertion);
			miVisitContact.surName = Util_System.cleanName(miAccount.visitAddress.surName);
			miVisitContact.email = Util_System.sanitizeEmail(miAccount.visitAddress.email);
			miVisitContact.phoneNumber = miAccount.visitAddress.phoneNumber;
			miVisitContact.mobilePhone = miAccount.visitAddress.mobilePhone;
			miVisitContact.otherPhone = miAccount.visitAddress.otherPhone;
			miVisitContact.language = miAccount.visitAddress.language;
			miVisitContact.country = miAccount.visitAddress.country;
			miVisitContact.newsLetter = miAccount.visitAddress.newsLetter;
			miVisitContact.type = 'Main';
			if (Rest_UpsertAccount.accountIsNew) {
				miVisitContact.type += ';Shipping';
			}
			miVisitContact.isActive = true; // value of has account
			miVisitContact.hasDealerTaskAccess = false; //dealer tasks
			miVisitContact.isAdministrator = false;

			visitName = (String.isNotBlank(miVisitContact.firstName)) ? miVisitContact.firstName : '';
			visitName += (String.isNotBlank(miVisitContact.insertion)) ? (' ' + miVisitContact.insertion) : '';
			visitName += (String.isNotBlank(miVisitContact.surName)) ? (' ' + miVisitContact.surName) : '';
			visitName = (String.isNotBlank(visitName)) ? visitName.trim() : '';
		}

		if ((miAccount.billingAddress != null) && String.isNotBlank(miAccount.billingAddress.Id) && ((miAccount.visitAddress == null) || ((miAccount.visitAddress.Id != miAccount.billingAddress.Id) && (miAccount.visitAddress.Email != miAccount.billingAddress.Email)))) {
			miBillingContact = new Rest_UpsertAccount.MiContact();

			miBillingContact.id = miAccount.billingAddress.Id + 'a';
			miBillingContact.accountId = miAccount.billingAddress.accountId;
			miBillingContact.firstName = Util_System.cleanName(miAccount.billingAddress.firstName);
			miBillingContact.insertion = Util_System.cleanName(miAccount.billingAddress.insertion);
			miBillingContact.surName = Util_System.cleanName(miAccount.billingAddress.surName);
			miBillingContact.email = Util_System.sanitizeEmail(miAccount.billingAddress.email);
			miBillingContact.phoneNumber = miAccount.billingAddress.phoneNumber;
			miBillingContact.mobilePhone = miAccount.billingAddress.mobilePhone;
			miBillingContact.otherPhone = miAccount.billingAddress.otherPhone;
			miBillingContact.language = miAccount.billingAddress.language;
			miBillingContact.newsLetter = miAccount.billingAddress.newsLetter;
			miBillingContact.type = 'Invoice';
			if (miAccount.isBusiness) {
				miBillingContact.type += ';Digital';
			}
			miBillingContact.isActive = true; // value of has account
			miBillingContact.hasDealerTaskAccess = false; //dealer tasks
			miBillingContact.isAdministrator = false;

			billingName = (String.isNotBlank(miBillingContact.firstName)) ? miBillingContact.firstName : '';
			billingName += (String.isNotBlank(miBillingContact.insertion)) ? (' ' + miBillingContact.insertion) : '';
			billingName += (String.isNotBlank(miBillingContact.surName)) ? (' ' + miBillingContact.surName) : '';
			billingName = (String.isNotBlank(billingName)) ? billingName.trim() : '';
		} else if (String.isNotBlank(miAccount.visitAddress.Id)) {
			miVisitContact.type += ';Invoice';

			if (miAccount.isBusiness) {
				miVisitContact.type += ';Digital';
			}
		}

		// check visit and or billing exists in changed contact, then override other wise add
		boolean visitNotFound = true;
		boolean billingNotFound = true;
		String contName;

		if (miAccount.contactDTOs != null && !miAccount.contactDTOs.isEmpty()) {
			miContacts.addAll(miAccount.contactDTOs);
			//miContacts.sort();
			Rest_UpsertAccount.MiContact miCont;

			//for (Rest_UpsertAccount.MiContact miCont : miContacts) {
			for (Integer iCount = miContacts.size() - 1; iCount >= 0; iCount--) {
				miCont = miContacts[iCount];

				contName = (String.isNotBlank(miCont.firstName))
				? Util_System.cleanName(miCont.firstName)
				: '';
				contName += (String.isNotBlank(miCont.insertion))
				? (' ' + Util_System.cleanName(miCont.insertion))
				: '';
				contName += (String.isNotBlank(miCont.surName))
				? (' ' + Util_System.cleanName(miCont.surName))
				: '';
				contName = (String.isNotBlank(contName)) ? contName.trim() : '';

				miCont.email = Util_System.sanitizeEmail(miCont.email);
				//miCont.type = (miCont.isAdministrator==null) ? 'L': ((miCont.isAdministrator) ? 'A' : 'L');

				if ((miVisitContact != null) && ((String.isNotBlank(miVisitContact.email) && (miCont.email == miVisitContact.email)) || (String.isNotBlank(visitName) && (visitName == contName)))) {
					// override contact with visit adrress
					miCont.firstName = Util_System.cleanName(miVisitContact.firstName);
					miCont.insertion = Util_System.cleanName(miVisitContact.insertion);
					miCont.surName = Util_System.cleanName(miVisitContact.surName);
					miCont.email = (miCont.email == null) ? miVisitContact.email : miCont.email;
					miCont.phoneNumber = miVisitContact.phoneNumber;
					miCont.mobilePhone = miVisitContact.mobilePhone;
					miCont.otherPhone = miVisitContact.otherPhone;
					miCont.language = miVisitContact.language;
					miCont.newsletter = (miVisitContact.newsletter == null) ? miCont.newsletter : miVisitContact.newsletter;
					if (String.isNotBlank(miCont.type)) {
						miCont.type += ';' + miVisitContact.type;
					} else {
						miCont.type = miVisitContact.type;
					}
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
					miCont.newsletter = (miBillingContact.newsletter == null) ? miCont.newsletter : miBillingContact.newsletter;

					if (String.isNotBlank(miCont.type)) {
						miCont.type += ';' + miBillingContact.type;
					} else {
						miCont.type = miBillingContact.type;
					}

					miCont.isActive = miBillingContact.isActive;

					billingNotFound = false;
				}

				if (miCont.isActive == null) {
					miCont.isActive = true;
				}
			}
		}

		//if ((miAccount.visitAddress != null) && String.isNotBlank(miAccount.visitAddress.Id) && visitNotFound && (miVisitContact != null)) {
		if ((visitNotFound) && (miVisitContact != null)) {
			miContacts.add(miVisitContact);
		}

		if ((billingNotFound) && (miBillingContact != null)) {
			miContacts.add(miBillingContact);
		}

		Map<String, Contact> emailContacts = new Map<String, Contact>();
		Map<String, Contact> extIdContacts = new Map<String, Contact>();
		Map<String, Contact> nameContacts = new Map<String, Contact>();
		Map<String, Contact> newContacts = new Map<String, Contact>();
		Map<String, Contact> updateContacts = new Map<String, Contact>();
		Map<String, AccountContactRelation> upsertACRs = new Map<String, AccountContactRelation>();
		Map<String, AccountContactRelation> updateRoles = new Map<String, AccountContactRelation>();
		Map<String, String> rolesACRs = new Map<String, String>();
		Map<String, Schema.SObjectField> contFieldMap = Schema.SObjectType.Contact.fields.getMap();
		Contact cont;
		Blob blobEmail;
		Boolean uniqueEmail = Util_System.getDataSetting('Contact_UniqueEmailAddresses');

		for (String contactKey : acrByContactId.keyset()) {
			AccountContactRelation curACR = acrByContactId.get(contactKey);
			Contact curContact = curACR.Contact;

			//System.debug('curACR: ' + curACR.Id + '(' + curACR.get(extIdField) + ') - contact: ' + curContact.Id + '(' + curContact.get(extIdField) + ') - email: ' + curContact.Email);

			curContact.Email = Util_System.sanitizeEmail(curContact.Email);

			if (curContact.get(extIdField) != null) {
				curContact.put(extIdField, null);
			}

			//System.debug('curACR: ' + curACR.Id + '(' + curACR.get(extIdField) + ') - contact: ' + curContact.Id + '(' + curContact.get(extIdField) + ') - email: ' + curContact.Email);

			if (curACR.get(extIdField) != null) {
				extIdContacts.put(String.valueOf(curACR.get(extIdField)), curContact);
			}
			if (String.isNotBlank(curContact.Email)) {
				emailContacts.put(curContact.Email, curContact);
			}
			if ((String.isNotBlank(curContact.Name)) && (String.isBlank(curContact.Email))) {
				nameContacts.put(curContact.Name.Trim().toUpperCase(), curContact);
			}

			// determine roles for existing ACRs, to be able to update them it the roles need to be added
			Boolean emptyRoles = (curACR.roles == null) || (curACR.roles == '');
			Boolean rolesUpdate = false;

			if ( (emptyRoles) || (!curACR.roles.contains('Invoice')) && (acc.Contact_Billing__c == curACR.ContactId)) {
				if (emptyRoles) {
					curACR.roles = '';
					emptyRoles = false;
				} else {
					curACR.roles += ';';
				}

				curACR.roles += 'Invoice';
				rolesUpdate = true;
			}

			if ((emptyRoles) || (!curACR.roles.contains('Shipping')) && (acc.Contact_Shipping__c == curACR.ContactId )) {
				if (emptyRoles) {
					curACR.roles = '';
					emptyRoles = false;
				} else {
					curACR.roles += ';';
				}

				curACR.roles += 'Shipping';
				rolesUpdate = true;
			}

			if ((emptyRoles) || (!curACR.roles.contains('Main')) && (acc.Contact_Person__c == curACR.ContactId)) {
				if (emptyRoles) {
					curACR.roles = '';
					emptyRoles = false;
				} else {
					curACR.roles += ';';
				}

				curACR.roles += 'Main';
				rolesUpdate = true;
			}

			if (rolesUpdate) {
				updateRoles.put(curAcr.CompositeKey__c, curACR);
			}

			rolesACRs.put(curAcr.CompositeKey__c, curACR.Roles);
		}

		Boolean newContact;

		//System.debug(miContacts);
		//System.debug(miContacts.size());
		map<String, MiContact> processedContacts = new Map<String, MiContact>();

		for (MiContact miCont : miContacts) {
			if (miCont.id == null) {
				throw new Util_Rest.UpsertException('Error: A Contact was added with no ID');
			}

			newContact = false;

			//determine contact first by extId
			contName = (String.isNotBlank(miCont.firstName)) ? miCont.firstName : '';
			contName += (String.isNotBlank(miCont.insertion)) ? (' ' + miCont.insertion) : '';
			contName += (String.isNotBlank(miCont.surName)) ? (' ' + miCont.surName) : '';
			contName = (String.isNotBlank(contName)) ? contName.trim() : '';
			contName = Util_System.cleanName(contName);

			if (extIdContacts.containsKey(miCont.id)) {
				cont = extIdContacts.get(miCont.id);
			} else if (emailContacts.containsKey(miCont.email)) {
				cont = emailContacts.get(miCont.email);
			} else if ((String.isNotBlank(contName)) && (nameContacts.containsKey(contName.toUpperCase()))) {
				cont = nameContacts.get(contName.toUpperCase());
			} else {
				cont = new Contact();
				cont.LeadSource = 'Platform';
				newContact = true;
			}

			cont.AccountId = acc.Id;
			cont.FirstName = (String.isNotBlank(miCont.surName)) ? Util_System.cleanName(miCont.firstName) : null;
			cont.MiddleName = (String.isNotBlank(miCont.insertion)) ? Util_System.cleanName(miCont.insertion) : null;
			cont.LastName = (String.isNotBlank(miCont.surName)) ? Util_System.cleanName(miCont.surName) : ((String.isNotBlank(miCont.firstName)) ? Util_System.cleanName(miCont.firstName) : ('Error  - ' + miCont.Id));

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
			cont.NewsLetter__c = (miCont.newsLetter == null) ? false : miCont.newsLetter;
			cont.Is_Active__c = (miCont.isActive == null) ? true : miCont.isActive;

			if (newContact) {
				//System.debug('add new');
				newContacts.put(miCont.Id, cont);
			} else {
				//System.debug('update contact');
				updateContacts.put(miCont.Id, cont);
			}

			processedContacts.put(miCont.Id, miCont);

			//System.debug(cont);
		}

		//System.debug('emailContacts');
		//System.debug(emailContacts);

		//System.debug('extIdContacts');
		//System.debug(extIdContacts);

		//System.debug('nameContacts');
		//System.debug(nameContacts);

		//System.debug('newContacts');
		//System.debug(newContacts);

		//System.debug('updateContacts');
		//System.debug(updateContacts.values());

		if (!newContacts.isEmpty()) {
			Database.insert(newContacts.values(), Rest_UpsertAccount.runningMode);
		}

		if (!updateContacts.isEmpty()) {
			Map<Id, Contact> dedupedUpdateContacts = new Map<Id, Contact>();
			for (Contact c : updateContacts.values()) {
				dedupedUpdateContacts.put(c.Id, c);
			}
			Database.update(dedupedUpdateContacts.values(), Rest_UpsertAccount.runningMode);
		}

		List<Util_Rest.AddedRecord> records = new List<Util_Rest.AddedRecord>();
		String extAdministratorField = 'isAdministrator_' + String.valueOf(miAccount.platformId) + '__c';
		String extVisibleField = 'isVisible_' + String.valueOf(miAccount.platformId) + '__c';
		String extDeletedField = 'isDeleted_' + String.valueOf(miAccount.platformId) + '__c';

		for (string platContId : processedContacts.keyset()) {
			MiContact platCont = processedContacts.get(platContId);
			//Contact cont;

			if (newContacts.containsKey(platContId)) {
				cont = newContacts.get(platContId);
			} else if (updateContacts.containsKey(platContId)) {
				cont = updateContacts.get(platContId);
			} else {
				continue;
			}

			AccountContactRelation acr = new AccountContactRelation();
			acr.AccountId = acc.Id;
			acr.ContactId = cont.Id;
			acr.CompositeKey__c = String.valueOf(acc.Id) + String.valueOf(cont.Id);

			//System.debug('running platfromccontact: ' + platCont);
			//System.debug('Remove: ' + acr.CompositeKey__c);

			updateRoles.remove(acr.CompositeKey__c);

			if (rolesACRs.containsKey(acr.CompositeKey__c)) {
				acr.Roles = rolesACRs.get(acr.CompositeKey__c);

				//System.debug('requested platfrom roles: ' + platCont.type);

				if (acr.Roles != null) {
					for (String role : acr.Roles.split(';')) {
						if ((role == null) || (String.isBlank(role))) continue;

						if ((platCont.type == null) || (String.isBlank(platCont.type)) || (!platCont.type.contains(role))) {
							// role is in ACR but not in the incoming contact, so remove it
							acr.Roles = acr.Roles.replace(role, '').replace(';;', ';');

							if (acr.Roles.startsWith(';')) {
								acr.Roles = acr.Roles.substring(1);
							}
							if (acr.Roles.endsWith(';')) {
								acr.Roles = acr.Roles.substring(0, acr.Roles.length() - 1);
							}
						}
					}
				}

				//System.debug('currenct acr.roles ' + acr.Roles);

				if (platCont.type != null) {

					for (String role : platCont.type.split(';')) {
						if ((role == null) || (String.isBlank(role))) continue;

						if ((acr.Roles == null) || (String.isBlank(acr.Roles))) {
							acr.Roles = role;
						} else if (!acr.Roles.contains(role)) {
							acr.Roles += ';' + role;
						}
					}
					//System.debug('Roles to be set: ' + acr.Roles);
				}
			} else {
				acr.Roles = platCont.type;
			}

			acr.put(extIdField, platCont.Id);
			acr.put(extAdministratorField, platCont.isAdministrator);
			acr.put(extVisibleField, platCont.isActive);
			acr.put(extDeletedField, false);

			upsertACRs.put(acr.CompositeKey__c, acr);
		}

		if (!upsertACRs.isEmpty()) {
			Database.upsert(upsertACRs.values(), AccountContactRelation.Fields.CompositeKey__c, false, Rest_UpsertAccount.runningMode);

			for (AccountContactRelation curACR : upsertACRs.values()) {
				if (String.valueOf(curACR.get(extIdField)).right(1) != 'a') {
					records.add(Util_Rest.makeAddedRecord( 'Contact', String.valueOf(curACR.get(extIdField)), String.isNotBlank(curACR.Id) ? curACR.Id : String.isNotBlank(curACR.ContactId) ? curACR.ContactId : '07k000000000000AAA'));
				}
			}
		}

		// maintain existing roles on ACRs, if the contact is updated with no role information, the existing roles will be kept, so only update when there is a change needed
		if (!updateRoles.isEmpty()) {
			//System.debug('updateRoles');
			Database.update(updateRoles.values(), Rest_UpsertAccount.runningMode);
		}

		if ((accountUpdate) || (accUpdateVisit) || (accUpdateShipping) || (accUpdateBilling) || (accUpdateAdmin)) {
			//System.debug('Account = ' + acc);
			Database.update(acc, Rest_UpsertAccount.runningMode);
			Rest_UpsertAccount.accountRecord = acc;
		}

		return records;
	}

	public class MiContactWrapper implements Comparable {
		public MiContact miContY;

		// Constructor
		public MiContactWrapper(MiContact miCont) {
		// Guard against wrapping a null
		if (miCont == null) {
			Exception ex = new NullPointerException();
			ex.setMessage('MiContact argument cannot be null');
			throw ex;
		}
		miContY = miCont;
		}

		// Compare opportunities based on the opportunity amount.
		public Integer compareTo(Object compareTo) {
			// Cast argument to OpportunityWrapper
			MiContactWrapper compareToMiContY = (MiContactWrapper) compareTo;

			// The return value of 0 indicates that both elements are equal.
			Integer returnValue = 0;
			if ((miContY.Id == null) && (compareToMiContY.miContY.Id == null)) {
				// both wrappers have null Amounts
				returnValue = 0;
			} else if ((miContY.Id == null) && (compareToMiContY.miContY.Id != null)) {
				// nulls-first implementation
				returnValue = -1;
			} else if ((MiContY.Id != null) && (compareToMiContY.miContY.Id == null)) {
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

		public MiAccount() {
		}

		public MiAccount(Account acct) {
			this.id = acct.extId_1__c; // platfrom specific -> managed by platform - create, no update
			this.platformId = 1; // platfrom specific -> managed by platform - create, no update
			this.resellerId = Long.valueOf(acct.Reseller_Name__c); // platfrom specific -> managed by platform - create, no update
			this.salesforceId = acct.Id; // platfrom specific -> managed by platform - create, no update
			this.marketId = Util_system.getSalesMarket(acct.Market__c);
			this.salesChannelId = Util_system.getSalesChannel(acct.Sales_Channel__c);
			this.debtorNumber = acct.FinancialDebtorNumber__c != null ? acct.FinancialDebtorNumber__c : acct.Subscription25__Debtor_Numbers__r[0].Subscription25__Debtor_Number__c;
			this.debtorNumber = String.isBlank(this.debtorNumber) ? this.debtorNumber : this.debtorNumber.trim();
			this.previousDebtorNumber = acct.FinancialDebtorNumberPrevious__c; // platfrom specific -> managed by platform - create, no update
			this.name = Util_System.cleanName(acct.Name); // create, updatable -> distribution?
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
			this.fulltimePersonnelCount = (acct.NumberOfFulltimeEmployees__c != null) ? acct.NumberOfFulltimeEmployees__c.longValue() : null; // create, updatable -> distribution? - null prevention
			this.isBlocked = acct.Is_Blocked__c; // create, updatable -> distribution? - managed by salesforce previous exact
			this.isBankrupt = acct.IsBankrupt__c; // create, updatable -> distribution? - managed by salesforce previous exact

			/* this.contactDTOs = new List<Rest_UpsertAccount.MiContact>{
				new Rest_UpsertAccount.MiContact(acct.Contact_Person__r)
			}; */

			Boolean skipMainContact = false; // flag to check if contact person is added to contactDTOs, if not added separately at the end of this constructor
			//System.debug('Init contactDTOs : before');

			List<Rest_UpsertAccount.MiContact> contactDTOs = new List<Rest_UpsertAccount.MiContact>();
			Contact mainContact = acct.Contact_Person__r;
			Contact invoiceContact = acct.Contact_Billing__r;

			//System.debug('Init contactDTOs : after');

			if (acct.AccountContactRelations != null && !acct.AccountContactRelations.isEmpty()) {
				//System.debug('Init contactDTOs : Not null and size: ' + acct.AccountContactRelations.size());

				for (AccountContactRelation acr : acct.AccountContactRelations) {
					if ((acr.ContactId == acct.Contact_Person__c) || acr.Roles.contains('Main')) {
						skipMainContact = true;
						mainContact = acr.Contact;
					}
					if ((acr.ContactId == acct.Contact_Billing__c) || acr.Roles.contains('Invoice')) {
						invoiceContact = acr.Contact;
					}
					//System.debug('Adding contact from ACR to contactDTOs: ' + acr.ContactId);
					contactDTOs.add(new Rest_UpsertAccount.MiContact(acr));
					//System.debug('contact added to contactDTOs: ' + acr.ContactId);
				}

			} 
			
			if ((mainContact != null) && (!skipMainContact)) {
				contactDTOs.add(new Rest_UpsertAccount.MiContact(mainContact));
				//System.debug('contact person added to contactDTOs: ' + mainContact.Id);
			}

			//System.debug('contactDTOs : Size: ' + contactDTOs.size());

			if (!contactDTOs.isEmpty()) {
				this.contactDTOs = contactDTOs;
			}

			//System.debug('contactDTOs : Assigned to class variable');

			//this.visitAddress = new Rest_UpsertAccount.visitAddress(); // consequences other systems - null ??
			//System.debug('MiAccount constructor - visit address : ' + mainContact);
			this.visitAddress = new Rest_UpsertAccount.MiContact(mainContact); // consequences other systems - null ??
			//System.debug('MiAccount constructor - visit address : ' + this.visitAddress);
			this.visitAddress.postalCode = acct.ShippingPostalCode;
			this.visitAddress.city = acct.ShippingCity;
			this.visitAddress.street = acct.ShippingStreet;
			this.visitAddress.country = acct.ShippingCountryCode;
			this.visitAddress.type = 'Main;Shipping';

			//System.debug('MiAccount constructor - visit address : ' + this.visitAddress);

			//this.billingAddress = new Rest_UpsertAccount.billingAddress(); // consequences other systems - null ??
			//System.debug('MiAccount constructor - billing address : ' + billingContact);
			this.billingAddress = new Rest_UpsertAccount.MiContact(invoiceContact); // consequences other systems - null ??
			//System.debug('MiAccount constructor - billing address : ' + this.billingAddress);
			this.billingAddress.postalCode = acct.BillingPostalCode;
			this.billingAddress.city = acct.BillingCity;
			this.billingAddress.street = acct.BillingStreet;
			this.billingAddress.country = acct.BillingCountryCode;
			this.billingAddress.type = 'Invoice';
			if (this.isBusiness) {
				this.billingAddress.type += ';Digital';
			}
			//System.debug('MiAccount constructor - billing address : ' + this.billingAddress);
			//System.debug('MiAccount constructor finished');
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
		public String type; // Main = Visiting, B = Billing, A = Administrator, L = Login
		public Boolean isActive; // value of has account
		public Boolean hasDealerTaskAccess; //dealer tasks
		public Boolean isAdministrator;
		public Boolean newsLetter;

		public MiContact() {
		}

		public MiContact(Contact cont) {
			this.salesforceId = (cont.Id != null) ? cont.Id : null;
			this.firstName = (cont.FirstName != null) ? Util_System.cleanName(cont.FirstName) : null;
			this.insertion = (cont.MiddleName != null) ? Util_System.cleanName(cont.MiddleName) : null;
			this.surName = (cont.LastName != null) ? Util_System.cleanName(cont.LastName) : null;
			this.email = cont.Email;
			this.phoneNumber = cont.Phone;
			this.mobilePhone = cont.MobilePhone;
			this.otherPhone = cont.OtherPhone;
			this.language = cont.Language__c;
			this.isActive = cont.Is_Active__c;
			this.hasDealerTaskAccess = cont.Has_Dealertask_access__c;
			this.isAdministrator = true;
			this.newsLetter = cont.Newsletter__c;
			this.type = '';
		}

		public MiContact(AccountContactRelation acr) {
			Contact cont = acr.Contact;

			this.salesforceId = (acr.Id != null) ? acr.Id : null;
			this.firstName = (cont.FirstName != null) ? Util_System.cleanName(cont.FirstName) : null;
			this.insertion = (cont.MiddleName != null) ? Util_System.cleanName(cont.MiddleName) : null;
			this.surName = (cont.LastName != null) ? Util_System.cleanName(cont.LastName) : null;
			//System.debug('Contact last name: ' + cont.LastName);
			this.email = cont.Email;
			//System.debug('Contact Email: ' + cont.Email);
			this.phoneNumber = cont.Phone;
			this.mobilePhone = cont.MobilePhone;
			this.otherPhone = cont.OtherPhone;
			this.language = cont.Language__c;
			//System.debug('Contact Language: ' + cont.Language__c);
			this.isActive = acr.isVisible_1__c;
			this.hasDealerTaskAccess = acr.hasDealerTasks_1__c;
			this.isAdministrator = true;// forced to true, not sure if acr.isAdministrator_1__c is set;
			this.newsLetter = cont.Newsletter__c;
			//System.debug('Contact Newsletter: ' + cont.Newsletter__c);
			this.type = acr.Roles;
			//System.debug('Contact Roles: ' + acr.Roles);
		}
	}
}
