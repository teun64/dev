@RestResource(UrlMapping='/v2/UpsertAccount')
global with sharing class Rest_UpsertAccountV2 {

	@HttpPost
	global static void handlePost() {
        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, 'RestUpsertAccountV2', 'S'); // TODO: Set calling system?
		Savepoint savePoint = Database.setSavepoint();
		Boolean uniqueEmail = Util_System.getDataSetting('Contact_UniqueEmailAddresses');

        Util_Rest.isRestEntry = true;
		Util_Rest.RestResult result = new Util_Rest.RestResult();
        try {
            Rest_UpsertAccountV2.ExtAccount extAccount = Rest_UpsertAccountV2.getRequestBody();
            Rest_UpsertAccountV2.UpsertResult upsertResult = Rest_UpsertAccountV2.upsertAccount(extAccount);
            logger.setSessionRecordExternalId(sessionId, extAccount.id);
            logger.setCallingSystem(sessionId, extAccount.platformId);

			//if everything went right add the following message and set Success to true.
			result.messages.add('Succes: Account and Contact(s) have been added for: ' + extAccount.name +  '. With the following ID: ' + extAccount.id + '.');
            result.addAddedRecord('Account', upsertResult.sfAccount, extAccount.getExternalIdField());
            result.addAddedRecords('Contact', upsertResult.sfAccountContactRelations, extAccount.getExternalIdField());
			result.success = true;
            RestContext.response.statusCode = 200;

        } catch(JSONException e) {
            // JSON could not be deserialized, rollback database and report error
            Database.rollback(savePoint);
            result.addError('Error: Invalid JSON');
            RestContext.response.statusCode = 400;

        } catch(Util_Rest.UpsertException e) {
            // Account could not be processed, rollback database and report error
            Database.rollback(savePoint);
            result.addError('Error: ' + e.getMessage());
            RestContext.response.statusCode = 400;

        } catch(Exception e) {
            // Unexpected error, rollback database and report error
            Database.rollback(savePoint);
            result.addError('Error: ' + e + ' ---STACK-- ' + e.getStackTraceString() + '---LINE----' + e.getLineNumber());
            RestContext.response.statusCode = 500;
        }
        // Set response body
        RestContext.response.responseBody = result.getJSONBlob();

        // Finalize logging
        Logger.finalizeSession(sessionId, RestContext.response);
        Logger.saveAll();
        Util_Rest.isRestEntry = false;
    }

    public static Rest_UpsertAccountV2.ExtAccount getRequestBody() {
        String reqBody = RestContext.request.requestBody?.toString();
        Rest_UpsertAccountV2.ExtAccount extAccount = (Rest_UpsertAccountV2.ExtAccount) JSON.deserialize(reqBody, Rest_UpsertAccountV2.ExtAccount.class);
        extAccount.init();
        return extAccount;
    }

    public static Rest_UpsertAccountV2.UpsertResult upsertAccount(Rest_UpsertAccountV2.ExtAccount extAcc) {
		if(extAcc.id == null){
			throw new Util_Rest.UpsertException('Error: An Account was added with no ID.');
		}
        // Find or create new Account
        Account sfAcc = Rest_UpsertAccountV2.findAccount(extAcc)
            ?? Rest_UpsertAccountV2.createAccount(extAcc);

        // Upsert account
        Rest_UpsertAccountV2.updateAccountValues(sfAcc, extAcc);
        Account duplicate = Rest_UpsertAccountV2.findDuplicateAccount(sfAcc, extAcc);
        Rest_UpsertAccountV2.handleDuplicate(sfAcc, duplicate);
        Rest_UpsertAccountV2.handleKickback(sfAcc, extAcc);
        Database.upsert(sfAcc);

        // Upsert contacts
        Rest_UpsertAccountV2.getContactRelationData(extAcc);
        List<Contact> sfContacts = Rest_UpsertAccountV2.handleContacts(sfAcc, extAcc);
        System.debug(JSON.serializePretty([SELECT Id, Name, EMail FROM Contact WHERE AccountId = :sfAcc.Id]));
        System.debug(JSON.serializePretty(sfContacts));
        Database.upsert(sfContacts);

        // Upsert account contact relations
        List<AccountContactRelation> relations = Rest_UpsertAccountV2.handleAccountContactRelations(extAcc, sfAcc, sfContacts);
        System.debug(JSON.serializePretty([SELECT Id, ContactId, ExtId_1__c FROM AccountContactRelation WHERE AccountId = :sfAcc.Id]));
        System.debug(JSON.serializePretty(relations));
        Database.upsert(relations);

        Rest_UpsertAccountV2.removeUnusedAddressContacts(sfAcc, extAcc);

        // 20230324 - TRi - Replaced debtor number check to the end of this procedure, the account is completed and the contacts are in place, the account is as complete
        // as it can gets in this stage.
        // 20230327 - TRi - Moved to Rest_UpsertContract for Platform 1, prevent creating debtor numbers for empty accounts. If Other platforms are connected with
        // contracts, the excluded them as well
        if(extAcc.platformId != 1 && extAcc.platformId != 5){
            Util_Rest.checkDebtorNumber(extAcc.id, String.valueOf(extAcc.platformId));
        }

        Rest_UpsertAccountV2.UpsertResult result = new Rest_UpsertAccountV2.UpsertResult();
        result.sfAccount = sfAcc;
        result.sfContacts = sfContacts;
        result.sfAccountContactRelations = relations;
        return result;
    }

    private static Account createAccount(Rest_UpsertAccountV2.ExtAccount extAcc) {
        Account sfAcc = new Account();
        sfAcc.put(extAcc.getExternalIdField(), extAcc.Id);
        sfAcc.AccountSource = 'Platform';

        if (String.isNotBlank(extAcc.marketId)) {
            sfAcc.Market__c = Util_System.getSalesMarket(extAcc.marketId);
        } else {
            sfAcc.Market__c = extAcc.platformId == 1 ? 'Security' : 'Fleet';
        }
        if (String.isNotBlank(extAcc.salesChannelId)) {
            sfAcc.Sales_Channel__c = Util_System.getSalesChannel(extAcc.salesChannelId);
        } else {
            sfAcc.Sales_Channel__c = 'Moving Intelligence';
        }

        return sfAcc;
    }

    private static Account findAccount(Rest_UpsertAccountV2.ExtAccount extAcc) {
        String extAccId = extAcc.Id;
        String sSOQL = 'SELECT Id, Name, Bank_Account__c, NumberOfEmployees, NumberOfFulltimeEmployees__c, AccountSource, VAT_Number__c, CoC_Number__c, Short_Name__c, '
            + ' VisitingAddress__c, VisitingAddress__City__s, VisitingAddress__CountryCode__s, VisitingAddress__PostalCode__s, VisitingAddress__StateCode__s, VisitingAddress__Street__s, '
            + ' useBillingAddress__c, BillingAddress, BillingCity, BillingCountryCode, BillingPostalCode, BillingStateCode, BillingStreet, '
            + ' useShippingAddress__c, ShippingAddress, ShippingCity, ShippingCountryCode, ShippingPostalCode, ShippingStateCode, ShippingStreet, '
            //+ ' Contact_Person__c, Contact_Person__r.AccountId, Contact_Person__r.Is_Active__c, Contact_Person__r.{0}, '
            //+ ' Contact_Billing__c, Contact_Billing__r.AccountId, Contact_Billing__r.Is_Active__c, Contact_Billing__r.{0}, '
            //+ ' Contact_Shipping__c, Contact_Shipping__r.AccountId, Contact_Shipping__r.Is_Active__c, Contact_Shipping__r.{0}, '
            //+ ' MI_Administrator__c, MI_Administrator__r.AccountId, MI_Administrator__r.Is_Active__c, MI_Administrator__r.{0}, '
            + '{0}'
            + ' FROM Account'
            + ' WHERE {0} = :extAccId'
            + ' LIMIT 1';
        sSOQL = String.format(sSOQL, new List<String> { extAcc.getExternalIdField() });

        List<Account> existingAccounts = Database.query(sSOQL);

        if (existingAccounts.size() == 1) {
            return existingAccounts.get(0);
        }
        return null;
    }

    private static void updateAccountValues(Account sfAcc, Rest_UpsertAccountV2.ExtAccount extAcc) {
        sfAcc.Name = extAcc.name;
		sfAcc.FinancialDebtorNumberPrevious__c = String.isNotBlank(extAcc.previousDebtorNumber) ? extAcc.previousDebtorNumber : '';
		sfAcc.isPrivacyMode__c = extAcc.privacyMode ?? false;

		// 20201112 - Gen25/Tri VAT and CoC are possible filled in by customer and not valid
		// Stored in temporary field en copied to WSONE equivalent when WSONE value is empty ....
		sfAcc.VAT_Number__c = String.isBlank(sfAcc.VAT_Number__c) && String.isNotBlank(extAcc.vatNumber) ? extAcc.vatNumber : String.isNotBlank(sfAcc.VAT_Number__c) ? sfAcc.VAT_Number__c : null;
		sfAcc.CoC_Number__c = String.isBlank(sfAcc.CoC_Number__c) && String.isNotBlank(extAcc.cocNumber) ? extAcc.cocNumber : String.isNotBlank(sfAcc.CoC_Number__c) ? sfAcc.CoC_Number__c : null;

		// 20221101 - TRi - force all UK - Direct Debits to I0
		sfAcc.Bank_Account__c = (String.isNotBlank(extAcc.bankAccountHolder))
            ? extAcc.bankAccountHolder
            : String.isNotBlank(sfAcc.Bank_Account__c)
                ? sfAcc.Bank_Account__c
                : sfAcc.Name;
        Util_System.setIfNotBlank(sfAcc, Account.Bank_Account_Number__c, extAcc.bankAccountNumber);
        //20260114 - TRi - skip syncing customer BIC
        //Util_System.setIfNotBlank(sfAcc, Account.Bank_BIC__c, extAcc.bankAccountBic);

        if (String.isBlank(extAcc.paymentMethodExactCode)) {
			//sfAcc.Payment_Method_Contracts__c = (extAcc.resellerId == 6) ? ((extAcc.bankAccountNumber == null) ? '08' : 'I0') : ((extAcc.bankAccountNumber == null) ? ((extAcc.platformId == 5) ? '14' : '08') : 'I8');
            sfAcc.Payment_Method_Contracts__c = (extAcc.bankAccountNumber == null) ? ((extAcc.platformId == 5) ? '14' : '08') : 'I8';
		} else {
			//sfAcc.Payment_Method_Contracts__c = ((extAcc.resellerId == 6) && (extAcc.paymentMethodExactCode.toUpperCase().left(1) == 'I')) ? ((extAcc.bankAccountNumber == null) ? '08' : 'I0') : extAcc.paymentMethodExactCode;
            sfAcc.Payment_Method_Contracts__c = (extAcc.bankAccountNumber == null) ? '08' : extAcc.paymentMethodExactCode;
		}

        Boolean accountIsNew = sfAcc.Id == null;
		if (accountIsNew) {
			sfAcc.Payment_Method_Opportunities__c = (extAcc.resellerId == 6) ? ((extAcc.platformId == 5) ? '14' : ((extAcc.isBusiness == true) ? '08' : 'p1' )) : ((extAcc.bankAccountNumber == null) ? '08' : 'I8');
		}

		// 20230317 TRi Account has dealer tasks, replacement for the record type b2b_dealer.
		sfAcc.HasDealerTasks__c = extAcc.isDealer ?? false;

		sfAcc.RecordTypeId = extAcc.isBusiness
            ? Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId()
            : Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();

        Util_System.setIfNotBlank(sfAcc, Account.SBI_Primary_Code__c, extAcc.primarySbiCode);
        Util_System.setIfNotBlank(sfAcc, Account.SBI_Secondary_Code_1__c, extAcc.secondarySbiCode1);
        Util_System.setIfNotBlank(sfAcc, Account.SBI_Secondary_Code_2__c, extAcc.secondarySbiCode2);
		// 202213 - TRi -> Number of Employees and Number of Fulltime Employees added (No using WSONE_DATA fields)
        if ((extAcc.personnelCount != null) && ((sfAcc.NumberOfEmployees == null) || (sfAcc.NumberOfEmployees <= 0))) {
		    sfAcc.NumberOfEmployees = Integer.valueOf(extAcc.personnelCount);
        }
        if ((extAcc.fulltimePersonnelCount != null) && ((sfAcc.NumberOfFulltimeEmployees__c == null) || (sfAcc.NumberOfFulltimeEmployees__c <= 0))) {
		    sfAcc.NumberOfFulltimeEmployees__c =  Integer.valueOf(extAcc.fulltimePersonnelCount);
        }
		// 20221115 - TRi - Direct Debit fields, to stay in sync with Chiron
		// 20230920 - TRI - Changed to not override the defaults, when value is not supplied
        Util_System.setIfNotBlank(sfAcc, Account.Direct_Debit_Status__c, extAcc.directDebitStatus);
        Util_System.setIfNotBlank(sfAcc, Account.Direct_Debit_Previous_Reference__c, extAcc.directDebitReference);
        Util_System.setIfNotBlank(sfAcc, Account.Direct_Debit_Last_Taken_Date__c, extAcc.directDebitLastTakenDate);

        // 20250305 - tri : extAcc.isBlocked, only set it when offered
		//sfAcc.Is_Blocked__c = extAcc.isBlocked ?? false;
		if (extAcc.isBlocked != null) {
			sfAcc.Is_Blocked__c =  extAcc.isBlocked;
		}

		sfAcc.Reseller_Name__c = String.valueOf(extAcc.resellerId);

		// GS 07Dec2023 Added below 4 fields to Mapping
        Util_System.setIfNotNull(sfAcc, Account.ContractTerm__c, extAcc.contractTerm);
        Util_System.setIfNotNull(sfAcc, Account.NoticeTerm__c, extAcc.noticeTerm);
        Util_System.setIfNotNull(sfAcc, Account.RenewalTerm__c, extAcc.renewalTerm);
        Util_System.setIfNotNull(sfAcc, Account.OrderOffsetTerm__c, extAcc.orderOffsetTerm);
        Util_System.setIfNotBlank(sfAcc, Account.Invoice_Period__c, extAcc.invoicePeriod);
        Util_System.setIfNotBlank(sfAcc, Account.Subscription_Type__c, extAcc.subscriptionType);

        Address extVisitingAddress;
        Address extBillingAddress;
        Address extShippingAddress;

		if (extAcc.visitAddress != null) {
			// visit address -> makes shipping address free for real shipping address
            Util_System.setIfNotBlank(sfAcc, Account.VisitingAddress__Street__s, extAcc.visitAddress.getStreet());
            Util_System.setIfNotBlank(sfAcc, Account.VisitingAddress__City__s, extAcc.visitAddress.City);
            Util_System.setIfNotBlank(sfAcc, Account.VisitingAddress__PostalCode__s, extAcc.visitAddress.PostalCode);
            Util_System.setIfNotBlank(sfAcc, Account.VisitingAddress__CountryCode__s, extAcc.visitAddress.country);

			// for now copy visiting address to shipping
            Util_System.setIfNotBlank(sfAcc, Account.ShippingStreet, sfAcc.VisitingAddress__Street__s);
            Util_System.setIfNotBlank(sfAcc, Account.ShippingCity, sfAcc.VisitingAddress__City__s);
            Util_System.setIfNotBlank(sfAcc, Account.ShippingPostalCode, sfAcc.VisitingAddress__PostalCode__s);
            Util_System.setIfNotBlank(sfAcc, Account.ShippingCountryCode, sfAcc.VisitingAddress__CountryCode__s);

			// 	move to contact and account contact relation
			//sfAcc.Shipping_Name__c = extAcc.visitAddress.getName();
			//sfAcc.Shipping_Email__c = extAcc.visitAddress.email;
			//sfAcc.Shipping_Phone__c = extAcc.visitAddress.phoneNumber;
			//sfAcc.Sales_Language__c = extAcc.visitAddress.language?.touppercase();
		}

		if (extAcc.billingAddress != null) {
            Util_System.setIfNotBlank(sfAcc, Account.BillingStreet, extAcc.billingAddress.getStreet());
            Util_System.setIfNotBlank(sfAcc, Account.BillingCity, extAcc.billingAddress.City);
            Util_System.setIfNotBlank(sfAcc, Account.BillingPostalCode, extAcc.billingAddress.PostalCode);
            Util_System.setIfNotBlank(sfAcc, Account.BillingCountryCode, extAcc.billingAddress.country);


			// 	move to contact and account contact relation
			//sfAcc.Billing_Name__c = extAcc.billingAddress.getName();
			//sfAcc.Billing_Email__c = extAcc.billingAddress.email;
			//sfAcc.Billing_Phone__c = extAcc.billingAddress.phoneNumber;
			//sfAcc.Sales_Language__c = extAcc.billingAddress.language?.touppercase();
		}
    }

    private static Account findDuplicateAccount(Account sfAcc, Rest_UpsertAccountV2.ExtAccount extAcc) {
        List<Datacloud.FindDuplicatesResult> findDuplicatesResult;

        try {
            findDuplicatesResult = Datacloud.FindDuplicates.findDuplicates(new List<Account> { sfAcc });
        } catch(System.HandledException e){
            // Could not find duplicates rules
        }

        if (findDuplicatesResult != null && !findDuplicatesResult.isEmpty()) {

            Datacloud.DuplicateResult duplicateResult = findDuplicatesResult.get(0).getDuplicateResults().get(0);
            Datacloud.MatchResult matchResult = duplicateResult.getMatchResults().get(0);
            List<Datacloud.MatchRecord> matchRecords = matchResult.getMatchRecords();

            for(Datacloud.MatchRecord matchRecord : matchRecords){
                Id recordId = matchRecord.getRecord().Id;
                String sSOQL = 'SELECT Id, {0} FROM Account WHERE Id = :recordId LIMIT 1';
                sSOQL = String.format(sSOQL, new List<String> { extAcc.getExternalIdField() });
                List<Account> dupAccts = Database.query(sSOQL);

                if(!dupAccts.isEmpty() && String.isBlank((String) dupAccts.get(0).get(extAcc.getExternalIdField()))) {
                    return dupAccts.get(0);
                }
            }
        }
        return null;
    }

    private static void handleDuplicate(Account sfAcc, Account duplicate) {
        if (sfAcc.Id != null || duplicate == null) {
            return;
        }
        sfAcc.Id = duplicate.Id;
    }

    private static void handleKickback(Account sfAcc, Rest_UpsertAccountV2.ExtAccount extAcc) {
        if (String.isBlank(extAcc.kickbackId)) {
            return;
        }
        String kickbackId = extAcc.kickbackId;
        String sSOQL = 'SELECT Id, {0}'
            + ' FROM Account'
            + ' WHERE {0} = :kickbackId'
            + ' LIMIT 1';
        sSOQL = String.format(sSOQL, new List<String> { extAcc.getExternalIdField() });
        list<Account> kbAccts = database.query(sSOQL);

        if (!kbAccts.isEmpty()) {
            sfAcc.Kickback_Reseller__c = kbAccts.get(0).Id;
        }
    }

    private static void getContactRelationData(Rest_UpsertAccountV2.ExtAccount extAcc) {
        // Gather external ids
        Set<String> extIds = new Set<String>();

        for (Rest_UpsertAccountV2.ExtContact extCon : extAcc.getContactDTOs()) {
            extIds.add(extCon.getId());
        }
        if (extAcc.visitAddress != null) {
            extIds.add(extAcc.visitAddress.getId());
        }
        if (extAcc.billingAddress != null) {
            extIds.add(extAcc.billingAddress.getId());
        }

        // Query by external id
        String sSOQL = 'SELECT Id, AccountId, ContactId, Roles, {0} FROM AccountContactRelation WHERE {0} IN :extIds';
        sSOQL = String.format(sSOQL, new List<String> { extAcc.getExternalIdField() });
        System.debug(sSOQL);
        System.debug(extIds);
        List<AccountContactRelation> result = (List<AccountContactRelation>) Database.queryWithBinds(sSOQL, new Map<String, Object> {
            'extIds' => extIds
        }, AccessLevel.SYSTEM_MODE);
        System.debug(result);

        // Map results by exteral
        Map<String, AccountContactRelation> relations = new Map<String, AccountContactRelation>();
        for (AccountContactRelation relation : result) {
            relations.put(String.valueOf(relation.get(extAcc.getExternalIdField())), relation);
        }

        // Map relation to mi contact
        for (Rest_UpsertAccountV2.ExtContact dto : extAcc.getContactDTOs()) {
            dto.relation = relations.get(dto.getId());
        }
        if (extAcc.visitAddress != null) {
            extAcc.visitAddress.relation = relations.get(extAcc.visitAddress.getId());
        }
        if (extAcc.billingAddress != null) {
            extAcc.billingAddress.relation = relations.get(extAcc.billingAddress.getId());
        }
    }

    private static List<Contact> handleContacts(Account sfAcc, Rest_UpsertAccountV2.ExtAccount extAcc) {
        // Create a Salesforce Contact for every MI Contact
        List<Contact> sfContacts = new List<Contact>();
        Boolean uniqueEmail = Util_System.getDataSetting('Contact_UniqueEmailAddresses'); 

        if (extAcc.visitAddress != null) {
            extAcc.visitAddress.sfContact = Rest_UpsertAccountV2.createContact(extAcc.visitAddress, uniqueEmail, sfAcc.Id);
        }
        if (extAcc.billingAddress != null) {
            extAcc.billingAddress.sfContact = Rest_UpsertAccountV2.createContact(extAcc.billingAddress, uniqueEmail, sfAcc.Id);
        }
        for (Rest_UpsertAccountV2.ExtContact dto : extAcc.getContactDTOs()) {
            dto.sfContact = Rest_UpsertAccountV2.createContact(dto, uniqueEmail, sfAcc.Id);
        }

        // Ensure there are no duplicates created
        Rest_UpsertAccountV2.dedupeContacts(extAcc);

        // Rebuild result contact list to ensure they are unique and only contain Contacts assigned to a MI Contact
        Set<Contact> sfContactSet = new Set<Contact>();
        if (extAcc.visitAddress?.sfContact != null) {
            sfContactSet.add(extAcc.visitAddress.sfContact);
        }
        if (extAcc.billingAddress?.sfContact != null) {
            sfContactSet.add(extAcc.billingAddress.sfContact);
        }
        for (Rest_UpsertAccountV2.ExtContact dto : extAcc.getContactDTOs()) {
            sfContactSet.add(dto.sfContact);
        }
        sfContacts = new List<Contact>(sfContactSet);

        // Ensure there are no duplicates according to the Duplicate Rules
        Rest_UpsertAccountV2.runContactDuplicateRules(sfContacts);

        // Set Account Id only if it is an insert
        for (Contact sfCon : sfContacts) {
            if (sfCon.Id == null) {
                sfCon.AccountId = sfAcc.Id;
            }
        }

        return sfContacts;
    }

    private static Contact createContact(Rest_UpsertAccountV2.ExtContact extCon, Boolean uniqueEmail, String sfAccId) {
        if(extCon.getId() == null){
            throw new Util_Rest.UpsertException('Error: A Contact was added with no ID');
        }
        Contact sfCon = new Contact(
            Id = extCon.relation?.ContactId,
            FirstName = extCon.firstName,
            MiddleName = extCon.insertion,
            LastName = extCon.surName,
            Phone = extCon.phoneNumber,
            MobilePhone = extCon.mobilePhone,
            OtherPhone = extCon.otherPhone,
            Language__c = extCon.language?.toUppercase(),
            MailingStreet = extCon.getStreet(),
            MailingPostalCode = extCon.postalCode,
            MailingCity = extCon.city,
            MailingCountryCode = extCon.country,
            Is_Administrator__c = extCon.isAdministrator ?? false,
            Has_Dealertask_access__c = extCon.hasDealerTaskAccess ?? false,
            NewsLetter__c = extCon.newsLetter ?? false,
            Is_Active__c = extCon.isActive ?? true,
            //DoNotEmail__c = true,
            Is_Address_Contact__c = !extCon.isDTO
        );
        if (extCon.Email != null) {
            sfCon.Email = extCon.email;
            Blob blobEmail = Crypto.generateDigest('SHA3-512', Blob.valueOf(sfCon.Email));
            sfCon.Email_Encrypted__c = EncodingUtil.convertToHex(blobEmail);
            sfCon.Unique_Key__c = (!uniqueEmail) ? sfAccId + '|' : '';
            sfCon.Unique_Key__c += sfCon.Email_Encrypted__c;
        } else {
            sfCon.Email = null;
            sfCon.Email_Encrypted__c = null;
            sfCon.Unique_Key__c = null;
        }
        System.debug(sfCon.id);
        return sfCon;
    }

    // private static void dedupeContacts(Rest_UpsertAccountV2.ExtAccount extAcc) {
    //     for (Integer i = 0; i < extAcc.getContactDTOs().size(); i++) {
    //         for (Integer j = i + 1; j < extAcc.getContactDTOs().size(); j++) {
    //             Rest_UpsertAccountV2.ExtContact compareContact = extAcc.getContactDTOs().get(i);
    //             Rest_UpsertAccountV2.ExtContact toContact = extAcc.getContactDTOs().get(j);

    //             if (compareContact.isSameExtContact(toContact)) {

    //             }
    //         }
    //     }
    // }

    // // Ensures duplicate miContacts are pointing to the same SObjects and merges collisions. First parameter field values takes priority. For external ids,
    // private static void mergeContacts(Rest_UpsertAccountV2.ExtContact record, Rest_UpsertAccountV2.ExtContact duplicate, String extIdField) {
    //     // Maintain primary values
    //     duplicate.sfContact = record.sfContact;

    //     // DTO external id takes priority
    //     if (duplicate.isDTO) {
    //         record.sfContact.Id = duplicate.sfContact.Id;
    //     }

    //     // Merge duplicate address contact into DTO contact
    //     if (duplicate.isDTO && duplicate.relation?.Id != null && duplicate.relation != record.relation) {
    //         Database.merge(duplicate.sfContact, new Contact(Id = record.relation.ContactId));
    //     }
    // }

    // private static void handleDuplicateContacts(Account sfAcc, Rest_UpsertAccountV2.ExtAccount extAcc) {

    //     // Merge existing visiting address contact, if required
    //     if (extAcc.visitAddress != null) {
    //         Rest_UpsertAccountV2.handleDuplicateContact(extAcc.visitAddress);
    //     }
    //     // Do the same for billing addresses
    //     if (extAcc.billingAddress != null) {
    //         Rest_UpsertAccountV2.handleDuplicateContact(extAcc.billingAddress);
    //     }
    // }

    // private static void handleDuplicateContact(Rest_UpsertAccountV2.ExtContact extCon) {
    //     if (extCon.relation == null) {
    //         // No preexisting contact
    //         return;
    //     }
    //     if (extCon.createdContact.Id == null) {
    //         // If a created contact is the same as the existing contact, update it
    //         extCon.createdContact.Id = extCon.existingContact.Id;

    //     } else if (extCon.createdContact.Id != null
    //         && extCon.createdContact.Id != extCon.existingContact.Id
    //         && extCon.getId().endsWith('a')) {
    //         // If a created contact and an existing contact do not match, and this was an address contact, merge them into the new contact
    //         Database.merge(extCon.createdContact, extCon.existingContact);
    //     }

    //     // If no criteria is match, leave existing contact as is
    // }

    private static void runContactDuplicateRules(List<Contact> sfContacts) {
        List<Datacloud.FindDuplicatesResult> findDuplicatesResult;

        System.debug('dedup');
        System.debug(sfContacts);
        try {
            findDuplicatesResult = Datacloud.FindDuplicates.findDuplicates(sfContacts);
        } catch(System.HandledException e){
            // Could not find duplicates rules
            System.debug(e);
        }
        System.debug(findDuplicatesResult);

        if (findDuplicatesResult?.isEmpty() != false) {
            // findDuplicatesResult is null or empty
            return;
        }
        System.debug('succc');

        for (Integer i = sfContacts.size(); --i >= 0;) {
            Contact con = sfContacts.get(i);
            // Get duplicate rules applied to record
            Datacloud.FindDuplicatesResult findResults = findDuplicatesResult.get(i);
            System.debug('res');

            for (Datacloud.DuplicateResult duplicateResult : findResults.getDuplicateResults()) {
                if (duplicateResult.isAllowSave()) {
                    // This duplicate rule is not strictly enforced
                    continue;
                }
                System.debug('rul');
                for (DataCloud.MatchResult matchResult : duplicateResult.getMatchResults()) {
                    for (Datacloud.MatchRecord matchRecord : matchResult.getMatchRecords()) {
                        System.debug('match');
                        if (con.Id == null) {
                            System.debug('set');
                            // Set record Id if doesn't have one
                            con.Id = matchRecord.getRecord().Id;
                        } else {
                            // TODO: Mismatch with duplicate, query duplicate with relation for more information
                            throw new Util_Rest.UpsertException(String.format('Error: Could not upsert record {0} due to duplicate record {1}', new List<String> {
                                con.Id,
                                matchRecord.getRecord().Id
                            }));
                        }
                    }
                }
            }
        }
    }

    private static void dedupeContacts(Rest_UpsertAccountV2.ExtAccount extAcc) {
        // Compare visiting to billing first
        Rest_UpsertAccountV2.handleCollisions(extAcc.visitAddress, extAcc.billingAddress, false);

        for (Integer i = 0; i < extAcc.getContactDTOs().size(); i++) {
            Rest_UpsertAccountV2.ExtContact compareDTO = extAcc.getContactDTOs().get(i);
            // Compare DTO to visiting and billing
            Rest_UpsertAccountV2.handleCollisions(compareDTO, extAcc.visitAddress, true);
            Rest_UpsertAccountV2.handleCollisions(compareDTO, extAcc.billingAddress, true);

            // Compare to DTOs that have not been validated yet (and not to itself)
            for (Integer j = i + 1; j < extAcc.getContactDTOs().size(); j++) {
                Rest_UpsertAccountV2.ExtContact toDTO = extAcc.getContactDTOs().get(j);
                Rest_UpsertAccountV2.handleCollisions(compareDTO, toDTO, false);
            }
        }
    }

    private static void handleCollisions(Rest_UpsertAccountV2.ExtContact primary, Rest_UpsertAccountV2.ExtContact secondary, Boolean isDtoToAddress) {
        if (primary == null || secondary == null) {
            return;
        }
        System.debug(isDtoToAddress);
        System.debug(primary.id);
        System.debug(primary.sfContact);
        System.debug(secondary.id);
        System.debug(secondary.sfContact);
        if (primary.sfContact.Id == secondary.sfContact.Id && primary.isSameExtContact(secondary)) {
            System.debug('c1');
            // Contacts are the same: Deduplicate in processing contact list
            if (isDtoToAddress) {
                // If primary is DTO and secondary an address, use secondary field values as they could be more up-to-date
                primary.sfContact = secondary.sfContact;
                primary.relation = secondary.relation;
                primary.sfContact.Is_Address_Contact__c = false;
            } else {
                // Use primary ID and field values
                secondary.sfContact = primary.sfContact;
                secondary.relation = primary.relation;
            }


        } else if (primary.sfContact.Id != null && primary.sfContact.Id == secondary.sfContact.Id && !primary.isSameExtContact(secondary)) {
            System.debug('c2');
            // Previously they were the same (existing) contact but became different: Unset secondary contact in order to create a new one
            secondary.sfContact.Id = null;
            secondary.relation = null;

        } else if (primary.sfContact.Id != secondary.sfContact.Id && primary.isSameExtContact(secondary)) {
            System.debug('c3');
            // Previously they were different, but became same: Try merge
            if (primary.sfContact.Id != null && secondary.sfContact.Id != null) {
                // Both ids exist, merge in DB
                System.debug(JSON.serialize(primary));
                System.debug(JSON.serialize(secondary));
                System.debug('merging ' + primary.sfContact + ':' + secondary.sfContact);
                Database.merge(primary.sfContact, secondary.sfContact.Id);
            }

            // Deduplicate in processing contact list
            if (isDtoToAddress) {
                System.debug(primary.id);
                System.debug(primary.sfContact);
                System.debug(secondary.id);
                System.debug(secondary.sfContact);
                // If primary is DTO and secondary an address, use secondary field values as they could be more up-to-date, but keep DTO id if it exists
                if (primary.sfContact.Id != null) {
                    System.debug('setting ID: ' + primary.sfContact.Id);
                    secondary.sfContact.Id = primary.sfContact.Id;
                }
                primary.sfContact = secondary.sfContact;
                primary.relation = secondary.relation;
                primary.sfContact.Is_Address_Contact__c = false;
                System.debug(primary.id);
                System.debug(primary.sfContact);
                System.debug(secondary.id);
                System.debug(secondary.sfContact);
            } else {
                // If primary doesn't have an id, keep secondary id
                if (primary.sfContact.Id == null) {
                    primary.sfContact.Id = secondary.sfContact.Id;
                }
                // Deduplicate prioritizing primary
                secondary.sfContact = primary.sfContact;
                secondary.relation = primary.relation;
            }
        }
        // Otherwise: No collision, continue
    }

    private static List<AccountContactRelation> handleAccountContactRelations(Rest_UpsertAccountV2.ExtAccount extAcc, Account sfAcc, List<Contact> sfContacts) {
        // Requery relations
        Map<Id, AccountContactRelation> relationByContactId = Rest_UpsertAccountV2.getAccountContactRelations(sfAcc, sfContacts, extAcc.getExternalIdField());

        // Add all DTO contacts
        for (Rest_UpsertAccountV2.ExtContact dto : extAcc.getContactDTOs()) {
            Contact sfCon = dto.sfContact;
            Set<String> roles = new Set<String>();

            if (dto.isAdministrator == true) {
                roles.add(Rest_UpsertAccountV2.Roles.Administrator.name());
            }

            // Find or create AccountContactRelation
            AccountContactRelation relation = relationByContactId.get(sfCon.Id);

            if (relation == null) {
                relation = Rest_UpsertAccountV2.createAccountContactRelation(sfAcc, sfCon);
                relationByContactId.put(sfCon.Id, relation);
            }

            // Assign roles
            Rest_UpsertAccountV2.updateAccountContactRelation(relation, dto, extAcc.getExternalIdField(), roles);
        }
        // Add visiting address
        if (extAcc.visitAddress != null) {

            // Find or create AccountContactRelation
            Contact sfCon = extAcc.visitAddress.sfContact;
            AccountContactRelation relation = relationByContactId.get(sfCon.Id);

            if (relation == null) {
                relation = Rest_UpsertAccountV2.createAccountContactRelation(sfAcc, sfCon);
                relationByContactId.put(sfCon.Id, relation);
            }

            // Update Role
            Rest_UpsertAccountV2.updateAccountContactRelation(relation, extAcc.visitAddress, extAcc.getExternalIdField(), new Set<String> {
                Rest_UpsertAccountV2.Roles.Main.name(),
                Rest_UpsertAccountV2.Roles.Shipping.name()
            });
        }

        // Add billing address
        if (extAcc.billingAddress != null) {

            // Find or create AccountContactRelation
            Contact sfCon = extAcc.billingAddress.sfContact;
            AccountContactRelation relation = relationByContactId.get(sfCon.Id);

            if (relation == null) {
                relation = Rest_UpsertAccountV2.createAccountContactRelation(sfAcc, sfCon);
                relationByContactId.put(sfCon.Id, relation);
            }

            // Update Role
            Rest_UpsertAccountV2.updateAccountContactRelation(relation, extAcc.billingAddress, extAcc.getExternalIdField(), new Set<String> {
                Rest_UpsertAccountV2.Roles.Billing.name()
            });
        }

        return relationByContactId.values();
    }

    private static Map<Id, AccountContactRelation> getAccountContactRelations(Account sfAcc, List<Contact> sfContacts, String extIdField) {
        // Query by acc + con Id
        String sSOQL = 'SELECT Id, AccountId, ContactId, Roles, {0} FROM AccountContactRelation WHERE AccountId = :sfAccId AND ContactId IN :sfContacts';
        sSOQL = String.format(sSOQL, new List<String> { extIdField });
        List<AccountContactRelation> result = (List<AccountContactRelation>) Database.queryWithBinds(sSOQL, new Map<String, Object> {
            'sfAccId' => sfAcc.id,
            'sfContacts' => sfContacts
        }, AccessLevel.SYSTEM_MODE);

        // Return mapped by contact Id
        Map<Id, AccountContactRelation> relations = new Map<Id, AccountContactRelation>();
        for (AccountContactRelation relation : result) {
            relations.put(relation.ContactId, relation);
        }
        return relations;
    }

    private static AccountContactRelation createAccountContactRelation(Account sfAcc, Contact sfCon) {
        System.debug(sfCon);
        // Create  base relation
        AccountContactRelation relation = new AccountContactRelation(
            IsActive = true,
            AccountId = sfAcc.Id,
            ContactId = sfCon.Id,
            StartDate = Date.today()
        );
        return relation;
    }

    private static void updateAccountContactRelation(AccountContactRelation relation, Rest_UpsertAccountV2.ExtContact extCon, String extIdField, Set<String> roles) {
        // Only set ext Id if it was empty OR this contact is the DTO contact, which is always leading
        if (relation.get(extIdField) == null || extCon.isDTO) {
            relation.put(extIdField, extCon.getId());
        }
        // Assign additional role
        for (String role : roles) {
            relation.Roles = Util_System.addMultiPicklistValue(relation.Roles, role);
        }
    }

    private static void removeUnusedAddressContacts(Account sfAcc, Rest_UpsertAccountV2.ExtAccount extAcc) {
        List<AccountContactRelation> addressRelations = [
            SELECT Id, ContactId, Roles
            FROM AccountContactRelation
            WHERE AccountId = :sfAcc.Id
                AND Contact.Is_Address_Contact__c = true
        ];

        for (AccountContactRelation relation : addressRelations) {
            // Validate whether this Contact has to be removed
            Boolean notRelated = relation.ContactId != extAcc.visitAddress?.sfContact.Id
                && relation.ContactId != extAcc.billingAddress?.sfContact.Id;

            if (notRelated && relation.Roles?.contains(Rest_UpsertAccountV2.Roles.Shipping.name())) {
                Database.merge(extAcc.visitAddress.sfContact, relation.ContactId);

            } else if (notRelated && relation.Roles?.contains(Rest_UpsertAccountV2.Roles.Billing.name())) {
                Database.merge(extAcc.billingAddress.sfContact, relation.ContactId);
            }
        }
    }

    private class UpsertResult {
        public Account sfAccount;
        public List<Contact> sfContacts = new List<Contact>();
        public List<AccountContactRelation> sfAccountContactRelations = new List<AccountContactRelation>();
    }

    //these classes are used for deserializing the incoming JSON file.
	public class ExtAccount {
		private String id;
		public String echoesAccountId; // echoes platform id, used when a account is migrated to this plaftorm, used by the Europetrack Platform 
		public Long platformId;
		public String marketId; // 1 Security, 2 Fleet, 3 Internal, Platform 1 -> default security, 2 -> default fleet, 3 default tbd, 4 default n/a, 5 default fleet;
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
		public Long resellerId;
		public String primarySbiCode;
		public String secondarySbiCode1;
		public String secondarySbiCode2;
		public Long personnelCount;
		public Long fulltimePersonnelCount;
		public String directDebitStatus;
		public String directDebitReference;
		public String directDebitLastTakenDate;
		public List<Rest_UpsertAccountV2.ExtContact> contactDTOs;
		// GS 07Dec2023 Added below fields.
		public Integer contractTerm;
		public Integer noticeTerm;
		public Integer renewalTerm;
		public Integer orderOffsetTerm;
		public String invoicePeriod; // values '0' Contract period, '1' Monthly, '3' Quarterly, '12' Yearly and 'Order' (not for subscriptions)
		public String subscriptionType; // values 'Professional', 'Ultimate' and 'Premium'

		public Rest_UpsertAccountV2.ExtContact visitAddress;
		public Rest_UpsertAccountV2.ExtContact billingAddress;

        // Constructors aren't called when using JSON.deserialize, call this method manually instead
        public void init() {
            if (this.visitAddress != null) {
                this.visitAddress.email = Util_System.sanitizeEmail(this.visitAddress.email);
                this.visitAddress.isDTO = false;
            }
            if (this.billingAddress != null) {
                this.billingAddress.email = Util_System.sanitizeEmail(this.billingAddress.email);
                this.billingAddress.isDTO = false;
            }

            for (Rest_UpsertAccountV2.ExtContact contactDTO : this.getContactDTOs()) {
                contactDTO.email = Util_System.sanitizeEmail(contactDTO.email);
                contactDTO.isDTO = true;
            }
        }

        public String getExternalIdField() {
            return Util_System.getPlatformIdField(this.platformId);
        }

        public List<Rest_UpsertAccountV2.ExtContact> getContactDTOs() {
            if (this.contactDTOs == null) {
                return new List<Rest_UpsertAccountV2.ExtContact>();
            }
            return this.contactDTOs;
        }
	}

	public class ExtContact {
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

        // Created contact based on provided data
        public transient Contact sfContact;
        // Found AccountContactRelation for mi contact external ID
        public transient AccountContactRelation relation;
        // Whether contact is a DTO contact or an address contact
        public transient Boolean isDTO = false;

        public String getId() {
            if (this.id == null || this.isDTO) {
                return this.id;
            }
            return this.id + 'a';
        }

        public String getName() {
			String name = String.format('{0} {1} {2}', new List<String> {
				this.firstName ?? '',
				this.insertion ?? '',
				this.surName ?? ''
			});
            return Rest_UpsertAccountV2.normalizeString(name);
        }

		public String getStreet() {
			String street = String.format('{0} {1}', new List<String> {
				this.street ?? '',
				this.houseNumber ?? ''
			});
            return Rest_UpsertAccountV2.normalizeString(street);
		}

        public Boolean matchesContact(Contact sfCon) {
            return this.email != null && this.email == sfCon.Email;
        }

        public Boolean isSameExtContact(Rest_UpsertAccountV2.ExtContact compareTo) {
            return this.email == compareTo?.email;
        }
	}

    private static String normalizeString(String input) {
        if (String.isBlank(input)) {
            // Return blanks as null
            return null;
        }
        // Remove unnecessary whitespace
        input = input.normalizeSpace();
        return input;
    }

    private Enum Roles {
        Main,
        Invoice,
        Digital,
        Reminder,
        Shipping,
        Sales,
        Service,
        ASR,
        Administrator
    }
}