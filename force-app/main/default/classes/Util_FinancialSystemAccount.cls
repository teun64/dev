/**
 * Account sync to the financial system (Exact Online), bulkified. Successor of Util_Exact.syncAccount.
 *
 * syncAccounts() handles many accounts in one transaction: all callouts first, then one DML phase
 * (Accounts, AccountContactRelations, logs, rate limits). Per account, per part:
 *  - account     : POST (new) / PUT (changed); duplicate-prevention match GET only for unchecked accounts,
 *                  never links an Exact account that another Salesforce account already uses
 *  - contacts    : main / invoice / shipping contact, one Exact contact per AccountContactRelation
 *                  (ACR.FinancialIdContact__c); Exact account MainContact = the main contact
 *  - addresses   : establishment (Billing) is the Exact account's own address; invoice (type 3) and
 *                  shipping (type 4) are sent separately unless address AND contact equal the establishment
 *  - bank/mandate: an Exact bank account number cannot be changed, so a changed IBAN means GET (exists?) or POST
 * Only parts whose fingerprint (FinancialSyncState__c) changed are sent. Exact ids live on the Account
 * (FinancialId*__c) and the ACR, not on Subscription25__Debtor_Number__c.
 * Failed accounts keep SyncToFinancialSystem__c and are retried with exponential back-off.
 */
public without sharing class Util_FinancialSystemAccount {
	private static final String ACCOUNT_ENDPOINT = 'api/v1/{0}/crm/Accounts';
	private static final String ACCOUNT_GET_ENDPOINT = 'api/v1/{0}/bulk/CRM/Accounts';
	private static final String ADDRESS_ENDPOINT = 'api/v1/{0}/crm/Addresses';
	private static final String BANK_ACCOUNT_ENDPOINT = 'api/v1/{0}/crm/BankAccounts';
	private static final String CONTACT_ENDPOINT = 'api/v1/{0}/crm/Contacts';
	private static final String MANDATE_ENDPOINT = 'api/v1/{0}/cashflow/DirectDebitMandates';

	public static final Integer ADDRESS_TYPE_INVOICE = 3;
	public static final Integer ADDRESS_TYPE_DELIVERY = 4;

	// retry back-off: 15 min, 30 min, 1 h, ... capped at 24 h; parked for a week after MAX_ATTEMPTS
	public static final Integer MAX_ATTEMPTS = 8;
	private static final Integer BACKOFF_BASE_MINUTES = 15;
	private static final Integer BACKOFF_MAX_MINUTES = 24 * 60;

	@TestVisible
	private static final String STATE_ACCOUNT = 'account';
	@TestVisible
	private static final String STATE_INVOICE = 'invoice';
	@TestVisible
	private static final String STATE_SHIPPING = 'shipping';
	@TestVisible
	private static final String STATE_BANK = 'bank';
	@TestVisible
	private static final String STATE_CONTACT = 'contact:';

	public class Result {
		public Id accountId;
		public Boolean success = false;
		/** not attempted (no capacity / not enabled for this org): flag stays, no attempt counted */
		public Boolean postponed = false;
		public Integer calls = 0;
		public List<String> messages = new List<String>();
	}

	// ---------------------------------------------------------------- entry points

	public static List<String> syncAccount(Id accountId) {
		return Util_FinancialSystemAccount.syncAccounts(new Set<Id>{ accountId }, false).get(accountId).messages;
	}

	/**
	 * Syncs the accounts. batchMode = true: stay within the batch budget (FinancialRateLimitMaxPercentage__c),
	 * accounts that do not fit are postponed. batchMode = false ("sync now"): only the hard limit applies.
	 */
	public static Map<Id, Result> syncAccounts(Set<Id> accountIds, Boolean batchMode) {
		Map<Id, Result> results = new Map<Id, Result>();
		List<Util_FinancialSystemAccount.Ctx> contexts = Util_FinancialSystemAccount.load(accountIds);

		Set<Id> limitedAdmins = new Set<Id>();
		for (Util_FinancialSystemAccount.Ctx ctx : contexts) {
			results.put(ctx.acct.Id, ctx.result);
			try {
				Util_FinancialSystemAccount.prepare(ctx);
				if (limitedAdmins.contains(ctx.admin.Id)) {
					ctx.postpone('Rate limit reached for ' + ctx.admin.Name + '; retried in a next run.');
					continue;
				}
				Integer estimate = Util_FinancialSystemAccount.estimateCalls(ctx);
				Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(ctx.admin);
				if (!(batchMode ? lim.hasBatchCapacity(estimate) : lim.hasCapacity(estimate))) {
					ctx.postpone('No financial system capacity left for ' + ctx.admin.Name + ' (' + estimate + ' calls needed); retried in a next run.');
					if (batchMode) {
						limitedAdmins.add(ctx.admin.Id);
					}
					continue;
				}
				Util_FinancialSystemAccount.syncOne(ctx);
			} catch (Util_FinancialSystem.RateLimitException e) {
				// part of the account may have been sent; what succeeded is kept in the state, the rest is retried
				ctx.postpone(e.getMessage());
				if (ctx.admin != null) {
					limitedAdmins.add(ctx.admin.Id);
				}
			} catch (Util_System.CustomException e) {
				ctx.fail(e.getMessage(), Util_Event.LogResultStatus.ERROR);
			} catch (Util_System.FinancialSyncException e) {
				ctx.fail(e.getMessage(), Util_Event.LogResultStatus.ERROR);
			} catch (Exception e) {
				ctx.fail('Unhandled exception occurred: ' + e.getMessage() + ' ' + e.getStackTraceString(), Util_Event.LogResultStatus.UNHANDLED_EXCEPTION);
			}
		}
		Util_FinancialSystemAccount.save(contexts);
		return results;
	}

	/**
	 * Marks the accounts for the next Batch_FinancialSystemAccountSync run (and resets the back-off).
	 */
	public static void flagAccounts(Set<Id> accountIds) {
		List<Account> accounts = new List<Account>();
		for (Id accId : accountIds) {
			accounts.add(new Account(Id = accId, SyncToFinancialSystem__c = true, FinancialSyncAttempts__c = 0, FinancialSyncNextAttempt__c = null));
		}
		Database.update(accounts, false, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * A changed contact (rau_Contact_AccountContactRelation) flags its AccountContactRelations; their accounts
	 * are flagged here so the account batch picks them up.
	 */
	public static void flagAccountsOfChangedContacts() {
		Set<Id> accountIds = new Set<Id>();
		for (AccountContactRelation acr : [
				SELECT AccountId FROM AccountContactRelation
				WHERE Sync_To_Financial_System__c = true AND Account.SyncToFinancialSystem__c = false
				WITH SYSTEM_MODE LIMIT 5000]) {
			accountIds.add(acr.AccountId);
		}
		if (!accountIds.isEmpty()) {
			Util_FinancialSystemAccount.flagAccounts(accountIds);
		}
	}

	/**
	 * Keeps Subscription25__Debtor_Number__c in line with Account.FinancialDebtorNumber__c: upsert on the
	 * composite key (account + administration of the account's reseller). Only the number is stored there;
	 * the financial system ids live on the Account / AccountContactRelation.
	 */
	public static void upsertDebtorNumbers(List<Account> newList, Map<Id, Account> oldMap) {
		Map<Id, Integer> adminExtIdByAccount = new Map<Id, Integer>();
		for (Account acct : newList) {
			Account old = oldMap == null ? null : oldMap.get(acct.Id);
			Boolean changed = old == null
				|| old.FinancialDebtorNumber__c != acct.FinancialDebtorNumber__c
				|| old.Reseller_Name__c != acct.Reseller_Name__c;
			if (String.isBlank(acct.FinancialDebtorNumber__c) || String.isBlank(acct.Reseller_Name__c) || !changed) {
				continue;
			}
			adminExtIdByAccount.put(acct.Id, Util_System.getAdminExternalId(Long.valueOf(acct.Reseller_Name__c)));
		}
		if (adminExtIdByAccount.isEmpty()) {
			return;
		}
		// own query: priming Util_System's administration cache from a trigger would hide administrations
		// created later in the same transaction
		Map<Integer, Id> adminIdByExtId = new Map<Integer, Id>();
		for (Subscription25__Administration__c admin : [
				SELECT Id, External_ID__c FROM Subscription25__Administration__c
				WHERE External_ID__c IN :adminExtIdByAccount.values() WITH SYSTEM_MODE]) {
			adminIdByExtId.put(Integer.valueOf(admin.External_ID__c), admin.Id);
		}
		List<Subscription25__Debtor_Number__c> toUpsert = new List<Subscription25__Debtor_Number__c>();
		for (Account acct : newList) {
			Id adminId = adminExtIdByAccount.containsKey(acct.Id) ? adminIdByExtId.get(adminExtIdByAccount.get(acct.Id)) : null;
			if (adminId == null) {
				continue;
			}
			toUpsert.add(new Subscription25__Debtor_Number__c(
				Subscription25__Account__c = acct.Id,
				Subscription25__Administration__c = adminId,
				Subscription25__Composite_Key__c = '' + acct.Id + adminId,
				Subscription25__Debtor_Number__c = acct.FinancialDebtorNumber__c
			));
		}
		if (!toUpsert.isEmpty()) {
			Database.upsert(toUpsert, Subscription25__Debtor_Number__c.Subscription25__Composite_Key__c, false, AccessLevel.SYSTEM_MODE);
		}
	}

	// ---------------------------------------------------------------- context

	@TestVisible
	private class Ctx {
		Account acct;
		Subscription25__Administration__c admin;
		Event_Log__c log;
		Result result = new Result();
		Map<String, String> state = new Map<String, String>();
		Map<String, String> newState;
		Map<Id, AccountContactRelation> acrByContact = new Map<Id, AccountContactRelation>();
		Map<Id, AccountContactRelation> acrsToUpdate = new Map<Id, AccountContactRelation>();
		Boolean accountDirty = false;
		Boolean isNewExactAccount = false;
		Boolean matched = false;
		String exactMainContact;
		List<String> warnings = new List<String>();
		Boolean failed = false;

		void postpone(String message) {
			this.result.postponed = true;
			this.result.messages.add(message);
			this.log.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
			this.log.Integration_Status__c = Util_Event.LogEventStatus.PENDING.name();
			this.log.Message__c += message + '\n';
		}

		void fail(String message, Util_Event.LogResultStatus status) {
			this.failed = true;
			this.result.messages.add(message);
			this.log.Result_Status__c = status.name();
			this.log.Message__c += message + '\n';
		}

		void warn(String message) {
			this.warnings.add(message);
			this.result.messages.add(message);
			this.log.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
			this.log.Message__c += message + '\n';
		}
	}

	private static List<Util_FinancialSystemAccount.Ctx> load(Set<Id> accountIds) {
		List<Account> accounts = [
			SELECT Id, Name, RecordType.DeveloperName, VAT_Number__c, CoC_Number__c, Reseller_Name__c, Block_Syncing_Exact__c,
				Payment_Method_Contracts__c, Exact_Account_Name__c,
				BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode, Billing_Phone__c, Billing_Email__c,
				InvoiceAddress__Street__s, InvoiceAddress__PostalCode__s, InvoiceAddress__City__s, InvoiceAddress__CountryCode__s,
				ShippingStreet, ShippingPostalCode, ShippingCity, ShippingCountryCode,
				Bank_Account_Number__c, Bank_Account__c,
				FinancialDebtorCheck__c, FinancialNumberOfDebtors__c, FinancialReplaceDebtorNumber__c,
				FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c, FinancialIdAccount__c,
				FinancialIdInvoiceAddress__c, FinancialIdShippingAddress__c, FinancialIdBankAccount__c, FinancialIdBankMandate__c,
				FinancialAccountClassification1__c, FinancialAccountClassification2__c, FinancialAccountClassification3__c,
				SyncToFinancialSystem__c, FinancialSyncState__c, FinancialSyncAttempts__c, FinancialSyncNextAttempt__c, FinancialSyncLastError__c,
				Contact_person__c, Contact_person__r.FirstName, Contact_person__r.MiddleName, Contact_person__r.LastName, Contact_person__r.Email, Contact_person__r.Phone,
				Contact_Billing__c, Contact_Billing__r.FirstName, Contact_Billing__r.MiddleName, Contact_Billing__r.LastName, Contact_Billing__r.Email, Contact_Billing__r.Phone,
				Contact_Shipping__c, Contact_Shipping__r.FirstName, Contact_Shipping__r.MiddleName, Contact_Shipping__r.LastName, Contact_Shipping__r.Email, Contact_Shipping__r.Phone
			FROM Account
			WHERE Id IN :accountIds
			WITH SYSTEM_MODE
			ORDER BY Name
		];

		Set<Id> contactIds = new Set<Id>();
		for (Account acct : accounts) {
			for (Id cid : new List<Id>{ acct.Contact_person__c, acct.Contact_Billing__c, acct.Contact_Shipping__c }) {
				if (cid != null) {
					contactIds.add(cid);
				}
			}
		}
		Map<Id, Map<Id, AccountContactRelation>> acrs = new Map<Id, Map<Id, AccountContactRelation>>();
		for (AccountContactRelation acr : [
				SELECT Id, AccountId, ContactId, FinancialIdContact__c, Sync_To_Financial_System__c
				FROM AccountContactRelation
				WHERE AccountId IN :accountIds AND (ContactId IN :contactIds OR Sync_To_Financial_System__c = true)
				WITH SYSTEM_MODE]) {
			if (!acrs.containsKey(acr.AccountId)) {
				acrs.put(acr.AccountId, new Map<Id, AccountContactRelation>());
			}
			acrs.get(acr.AccountId).put(acr.ContactId, acr);
		}

		List<Util_FinancialSystemAccount.Ctx> contexts = new List<Util_FinancialSystemAccount.Ctx>();
		for (Account acct : accounts) {
			Util_FinancialSystemAccount.Ctx ctx = new Util_FinancialSystemAccount.Ctx();
			ctx.acct = acct;
			ctx.result.accountId = acct.Id;
			ctx.log = Util_Event.getLog(null, 'S', 'E', 'Account', 'sync2Exact', acct.Id, acct.Exact_Account_Name__c, null);
			ctx.state = Util_FinancialSystemAccount.readState(acct.FinancialSyncState__c);
			ctx.newState = ctx.state.clone();
			if (acrs.containsKey(acct.Id)) {
				ctx.acrByContact = acrs.get(acct.Id);
			}
			contexts.add(ctx);
		}
		return contexts;
	}

	// ---------------------------------------------------------------- validation + planning

	/**
	 * Validates the account (same rules as Util_Exact) and resolves the administration.
	 */
	@TestVisible
	private static void prepare(Util_FinancialSystemAccount.Ctx ctx) {
		Account acct = ctx.acct;
		if (!FeatureManagement.checkPermission('cp_miIntegrationSkipDataCheck')) {
			if (acct.Reseller_Name__c == '1' && acct.RecordType.DeveloperName != 'B2C' && acct.BillingCountryCode == 'NL' && acct.Block_Syncing_Exact__c) {
				throw new Util_System.CustomException('This account is not validated by Web Services, this validation has to be completed before this account can be synchronised.');
			} else if (Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c) && (String.isBlank(acct.Bank_Account_Number__c) || String.isBlank(acct.Bank_Account__c))) {
				throw new Util_System.CustomException('This account can not be synchronised because the bank account is not filled in.');
			} else if (String.isBlank(acct.BillingCountryCode) || String.isBlank(acct.BillingStreet) || String.isBlank(acct.BillingPostalCode) || String.isBlank(acct.BillingCity)) {
				throw new Util_System.CustomException('This account can not be synchronised because the establishment / billing address is not filled in.');
			} else if (String.isBlank(acct.InvoiceAddress__CountryCode__s) || String.isBlank(acct.InvoiceAddress__Street__s) || String.isBlank(acct.InvoiceAddress__PostalCode__s) || String.isBlank(acct.InvoiceAddress__City__s)) {
				throw new Util_System.CustomException('This account can not be synchronised because the invoice address is not filled in.');
			}
		}

		Subscription25__Administration__c admin = Util_FinancialSystem.getAdministrationForReseller(acct.Reseller_Name__c);
		if (admin == null || admin.Subscription25__Synchronisation__c != Util_FinancialSystem.SYNC_EXACT || !admin.Subscription25__Active__c) {
			throw new Util_System.CustomException('This accounts reseller does not synchronize with Exact');
		}
		ctx.admin = admin;
		if (!Util_System.isFinancialSyncAllowed(admin)) {
			throw new Util_System.CustomException('This is a sandbox and administration ' + admin.Name + ' has no acceptance environment configured - Exact sync is blocked.');
		}
	}

	/**
	 * Calls this account will (at most) need, given what changed since the last sync.
	 */
	@TestVisible
	private static Integer estimateCalls(Util_FinancialSystemAccount.Ctx ctx) {
		Account acct = ctx.acct;
		Integer calls = 0;
		Boolean isNew = String.isBlank(acct.FinancialIdAccount__c);
		if (Util_FinancialSystemAccount.needsMatch(acct)) {
			calls++;
		}
		calls++; // account POST / PUT (a PUT is skipped when nothing changed)
		for (Id cid : Util_FinancialSystemAccount.contactIds(acct)) {
			calls++;
		}
		calls++; // main contact on the account
		if (Util_FinancialSystemAccount.invoiceAddressDiffers(acct)) {
			calls++;
		}
		if (Util_FinancialSystemAccount.shippingAddressDiffers(acct)) {
			calls++;
		}
		if (String.isNotBlank(acct.Bank_Account_Number__c)) {
			calls += isNew ? 2 : 3; // (GET) + POST/PUT, + mandate
		}
		return calls;
	}

	private static Boolean needsMatch(Account acct) {
		return !acct.FinancialDebtorCheck__c && !acct.FinancialReplaceDebtorNumber__c;
	}

	private static List<Id> contactIds(Account acct) {
		List<Id> ids = new List<Id>();
		for (Id cid : new List<Id>{ acct.Contact_person__c, acct.Contact_Billing__c, acct.Contact_Shipping__c }) {
			if (cid != null && !ids.contains(cid)) {
				ids.add(cid);
			}
		}
		return ids;
	}

	@TestVisible
	private static Boolean invoiceAddressDiffers(Account acct) {
		if (String.isBlank(acct.InvoiceAddress__City__s)) {
			return false;
		}
		Boolean addressDiffers = acct.InvoiceAddress__Street__s != acct.BillingStreet || acct.InvoiceAddress__PostalCode__s != acct.BillingPostalCode
			|| acct.InvoiceAddress__City__s != acct.BillingCity || acct.InvoiceAddress__CountryCode__s != acct.BillingCountryCode;
		Boolean contactDiffers = acct.Contact_Billing__c != null && acct.Contact_Billing__c != acct.Contact_person__c;
		return addressDiffers || contactDiffers;
	}

	@TestVisible
	private static Boolean shippingAddressDiffers(Account acct) {
		if (String.isBlank(acct.ShippingStreet) || String.isBlank(acct.ShippingCity)) {
			return false;
		}
		Boolean addressDiffers = acct.ShippingStreet != acct.BillingStreet || acct.ShippingPostalCode != acct.BillingPostalCode
			|| acct.ShippingCity != acct.BillingCity || acct.ShippingCountryCode != acct.BillingCountryCode;
		Boolean contactDiffers = acct.Contact_Shipping__c != null && acct.Contact_Shipping__c != acct.Contact_person__c;
		return addressDiffers || contactDiffers;
	}

	// ---------------------------------------------------------------- sync of one account

	private static void syncOne(Util_FinancialSystemAccount.Ctx ctx) {
		Account acct = ctx.acct;
		String division = ctx.admin.Subscription25__Twinfield_Company_Code__c;
		String guid = ctx.log.GUID__c;

		// 1. duplicate prevention: look for an existing Exact account (only for unchecked accounts)
		if (Util_FinancialSystemAccount.needsMatch(acct)) {
			Util_FinancialSystemAccount.matchAccount(ctx, division, guid);
		}

		// 2. the account itself
		Util_FinancialSystemAccount.syncAccountRecord(ctx, division, guid);

		// 3. contacts (main / invoice / shipping), each as its own Exact contact
		for (Id cid : Util_FinancialSystemAccount.contactIds(acct)) {
			try {
				Util_FinancialSystemAccount.syncContact(ctx, cid, division, guid);
			} catch (Util_System.FinancialSyncException e) {
				ctx.warn('Contact: ' + e.getMessage());
			}
		}

		// 4. main contact on the Exact account
		String mainExactId = Util_FinancialSystemAccount.exactContactId(ctx, acct.Contact_person__c);
		if (String.isNotBlank(mainExactId) && mainExactId != ctx.exactMainContact) {
			try {
				Map<String, Object> body = new Map<String, Object>{ 'MainContact' => mainExactId };
				Util_FinancialSystem.doRequest(ctx.admin, String.format(ACCOUNT_ENDPOINT, new List<String>{ division }) + '(guid\'' + acct.FinancialIdAccount__c + '\')',
					null, 'PUT', JSON.serialize(body), guid);
				ctx.result.calls++;
				ctx.exactMainContact = mainExactId;
			} catch (Util_System.FinancialSyncException e) {
				ctx.warn('Main contact: ' + e.getMessage());
			}
		}
		ctx.newState.put(STATE_ACCOUNT, Util_FinancialSystemAccount.hash(new Util_FinancialSystemAccount.ExactAccount(acct, ctx.exactMainContact)));

		// 5. invoice and shipping address (only when they differ from the establishment address or its contact)
		try {
			Util_FinancialSystemAccount.syncAddress(ctx, ADDRESS_TYPE_INVOICE, division, guid);
			Util_FinancialSystemAccount.syncAddress(ctx, ADDRESS_TYPE_DELIVERY, division, guid);
		} catch (Util_System.FinancialSyncException e) {
			ctx.warn('Address: ' + e.getMessage());
		}

		// 6. bank account and mandate
		if (String.isNotBlank(acct.Bank_Account_Number__c)) {
			try {
				Util_FinancialSystemAccount.syncBank(ctx, division, guid);
			} catch (Util_System.FinancialSyncException e) {
				ctx.warn('Bank account / mandate: ' + e.getMessage());
			}
		}
	}

	private static void matchAccount(Util_FinancialSystemAccount.Ctx ctx, String division, String guid) {
		Account acct = ctx.acct;
		Util_FinancialSystemAccount.ExactAccount exactAcct = new Util_FinancialSystemAccount.ExactAccount(acct, null);
		List<String> filters = new List<String>();
		if (String.isNotBlank(acct.FinancialIdAccount__c)) {
			filters.add('(ID eq guid\'' + acct.FinancialIdAccount__c + '\')');
		}
		if (String.isNotBlank(exactAcct.Code)) {
			filters.add('(Code eq \'' + ('                  ' + exactAcct.Code).right(18) + '\')');
		}
		String name = Util_FinancialSystem.odataString(exactAcct.Name);
		String line1 = Util_FinancialSystem.odataString(exactAcct.AddressLine1);
		if (String.isNotBlank(name) && String.isNotBlank(line1)) {
			List<String> nameFilter = new List<String>{ '(Name eq \'' + name + '\')', '(AddressLine1 eq \'' + line1 + '\')' };
			String postcode = Util_FinancialSystem.odataString(exactAcct.Postcode);
			String city = Util_FinancialSystem.odataString(exactAcct.City);
			if (String.isNotBlank(postcode)) {
				nameFilter.add('(Postcode eq \'' + postcode + '\')');
			}
			if (String.isNotBlank(city)) {
				nameFilter.add('(City eq \'' + city + '\')');
			}
			if (String.isNotBlank(postcode) || String.isNotBlank(city)) {
				filters.add('(' + String.join(nameFilter, ' and ') + ')');
			}
		}
		if (filters.isEmpty()) {
			return;
		}

		Map<String, String> params = new Map<String, String>{
			'$select' => 'ID,Code,Name,AddressLine1,Postcode,City,MainContact',
			'$filter' => String.join(filters, ' or '),
			'$orderby' => 'Code desc'
		};
		String response = Util_FinancialSystem.doRequest(ctx.admin, String.format(ACCOUNT_ENDPOINT, new List<String>{ division }), params, 'GET', null, guid);
		ctx.result.calls++;
		acct.FinancialDebtorCheck__c = true;
		acct.FinancialReplaceDebtorNumber__c = false;
		ctx.accountDirty = true;
		if (String.isBlank(response)) {
			return;
		}
		Util_FinancialSystemAccount.ExactGetAccounts found = (Util_FinancialSystemAccount.ExactGetAccounts) JSON.deserialize(response, Util_FinancialSystemAccount.ExactGetAccounts.class);
		if (found == null || found.results == null || found.results.isEmpty()) {
			return;
		}
		Util_FinancialSystemAccount.ExactGetAccount hit = found.results[0];

		// one Exact account may never be linked to more than one Salesforce account
		List<Account> others = [
			SELECT Id, Name FROM Account
			WHERE FinancialIdAccount__c = :hit.ID AND Id != :acct.Id
			WITH SYSTEM_MODE LIMIT 1
		];
		if (!others.isEmpty()) {
			throw new Util_System.CustomException('Exact account ' + hit.Code + ' (' + hit.Name + ') is already linked to Salesforce account '
				+ others[0].Name + ' (' + others[0].Id + '); check for a duplicate account before syncing.');
		}

		acct.FinancialNumberOfDebtors__c = found.results.size();
		if (acct.FinancialIdAccount__c != hit.ID) {
			acct.FinancialIdAccount__c = hit.ID;
			Util_FinancialSystemAccount.resetChildIds(ctx);
		}
		if (String.isNotBlank(hit.Code) && acct.FinancialDebtorNumber__c != hit.Code) {
			acct.FinancialDebtorNumber__c = hit.Code;
		}
		ctx.exactMainContact = hit.MainContact;
		ctx.matched = true;
	}

	/** The Exact account changed: all ids and fingerprints of its children are void. */
	private static void resetChildIds(Util_FinancialSystemAccount.Ctx ctx) {
		Account acct = ctx.acct;
		acct.FinancialIdInvoiceAddress__c = null;
		acct.FinancialIdShippingAddress__c = null;
		acct.FinancialIdBankAccount__c = null;
		acct.FinancialIdBankMandate__c = null;
		for (AccountContactRelation acr : ctx.acrByContact.values()) {
			if (String.isNotBlank(acr.FinancialIdContact__c)) {
				acr.FinancialIdContact__c = null;
				ctx.acrsToUpdate.put(acr.Id, acr);
			}
		}
		ctx.newState = new Map<String, String>();
		ctx.accountDirty = true;
	}

	private static void syncAccountRecord(Util_FinancialSystemAccount.Ctx ctx, String division, String guid) {
		Account acct = ctx.acct;
		String endpoint = String.format(ACCOUNT_ENDPOINT, new List<String>{ division });
		if (String.isBlank(acct.FinancialIdAccount__c)) {
			Util_FinancialSystemAccount.ExactAccount body = new Util_FinancialSystemAccount.ExactAccount(acct, null);
			String response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), guid);
			ctx.result.calls++;
			Util_FinancialSystemAccount.ExactGetAccount created = (Util_FinancialSystemAccount.ExactGetAccount) JSON.deserialize(response, Util_FinancialSystemAccount.ExactGetAccount.class);
			acct.FinancialIdAccount__c = created.ID;
			acct.FinancialDebtorCheck__c = true;
			acct.FinancialReplaceDebtorNumber__c = false;
			acct.FinancialNumberOfDebtors__c = 1;
			ctx.isNewExactAccount = true;
			Util_FinancialSystemAccount.resetChildIds(ctx);
			String code = created.Code;
			if (String.isBlank(code)) {
				code = Util_FinancialSystemAccount.getDebtorNumber(ctx, created.ID, division, guid);
			}
			acct.FinancialDebtorNumber__c = code == null ? null : code.trim();
			ctx.exactMainContact = created.MainContact;
			return;
		}
		Util_FinancialSystemAccount.ExactAccount body = new Util_FinancialSystemAccount.ExactAccount(acct, ctx.exactMainContact != null ? ctx.exactMainContact : Util_FinancialSystemAccount.exactContactId(ctx, acct.Contact_person__c));
		if (!ctx.matched && Util_FinancialSystemAccount.hash(body) == ctx.state.get(STATE_ACCOUNT)) {
			// unchanged since the last sync
			ctx.exactMainContact = body.MainContact;
			return;
		}
		Util_FinancialSystem.doRequest(ctx.admin, endpoint + '(guid\'' + acct.FinancialIdAccount__c + '\')', null, 'PUT', JSON.serialize(body), guid);
		ctx.result.calls++;
		ctx.exactMainContact = body.MainContact;
	}

	private static String getDebtorNumber(Util_FinancialSystemAccount.Ctx ctx, String exactId, String division, String guid) {
		Map<String, String> params = new Map<String, String>{
			'$filter' => 'ID eq guid\'' + exactId + '\'',
			'$select' => 'Code'
		};
		String response = Util_FinancialSystem.doRequest(ctx.admin, String.format(ACCOUNT_GET_ENDPOINT, new List<String>{ division }), params, 'GET', null, guid);
		ctx.result.calls++;
		Util_FinancialSystemAccount.ExactGetAccounts found = (Util_FinancialSystemAccount.ExactGetAccounts) JSON.deserialize(response, Util_FinancialSystemAccount.ExactGetAccounts.class);
		return (found == null || found.results == null || found.results.isEmpty()) ? null : found.results[0].Code;
	}

	private static String exactContactId(Util_FinancialSystemAccount.Ctx ctx, Id contactId) {
		if (contactId == null || !ctx.acrByContact.containsKey(contactId)) {
			return null;
		}
		return ctx.acrByContact.get(contactId).FinancialIdContact__c;
	}

	private static Contact contactOf(Account acct, Id contactId) {
		if (contactId == acct.Contact_person__c) {
			return acct.Contact_person__r;
		} else if (contactId == acct.Contact_Billing__c) {
			return acct.Contact_Billing__r;
		}
		return acct.Contact_Shipping__r;
	}

	private static void syncContact(Util_FinancialSystemAccount.Ctx ctx, Id contactId, String division, String guid) {
		AccountContactRelation acr = ctx.acrByContact.get(contactId);
		if (acr == null) {
			ctx.warn('Contact ' + contactId + ' has no relation with this account and is not synced.');
			return;
		}
		Util_FinancialSystemAccount.ExactContact body = new Util_FinancialSystemAccount.ExactContact(ctx.acct.FinancialIdAccount__c, Util_FinancialSystemAccount.contactOf(ctx.acct, contactId));
		String stateKey = STATE_CONTACT + contactId;
		String fingerprint = Util_FinancialSystemAccount.hash(body);
		String endpoint = String.format(CONTACT_ENDPOINT, new List<String>{ division });
		if (String.isBlank(acr.FinancialIdContact__c)) {
			String response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), guid);
			ctx.result.calls++;
			Util_FinancialSystemAccount.ExactContact created = (Util_FinancialSystemAccount.ExactContact) JSON.deserialize(response, Util_FinancialSystemAccount.ExactContact.class);
			acr.FinancialIdContact__c = created.ID;
			acr.Sync_To_Financial_System__c = false;
			ctx.acrsToUpdate.put(acr.Id, acr);
		} else if (fingerprint != ctx.state.get(stateKey)) {
			Util_FinancialSystem.doRequest(ctx.admin, endpoint + '(guid\'' + acr.FinancialIdContact__c + '\')', null, 'PUT', JSON.serialize(body), guid);
			ctx.result.calls++;
			if (acr.Sync_To_Financial_System__c == true) {
				acr.Sync_To_Financial_System__c = false;
				ctx.acrsToUpdate.put(acr.Id, acr);
			}
		} else if (acr.Sync_To_Financial_System__c == true) {
			acr.Sync_To_Financial_System__c = false;
			ctx.acrsToUpdate.put(acr.Id, acr);
		}
		ctx.newState.put(stateKey, fingerprint);
	}

	private static void syncAddress(Util_FinancialSystemAccount.Ctx ctx, Integer addressType, String division, String guid) {
		Account acct = ctx.acct;
		Boolean isInvoice = addressType == ADDRESS_TYPE_INVOICE;
		if (!(isInvoice ? Util_FinancialSystemAccount.invoiceAddressDiffers(acct) : Util_FinancialSystemAccount.shippingAddressDiffers(acct))) {
			return;
		}
		Id contactId = isInvoice ? acct.Contact_Billing__c : acct.Contact_Shipping__c;
		String exactContact = Util_FinancialSystemAccount.exactContactId(ctx, contactId != null ? contactId : acct.Contact_person__c);
		if (String.isBlank(exactContact)) {
			exactContact = Util_FinancialSystemAccount.exactContactId(ctx, acct.Contact_person__c);
		}
		Util_FinancialSystemAccount.ExactAddress body = new Util_FinancialSystemAccount.ExactAddress(acct, addressType, exactContact);
		String stateKey = isInvoice ? STATE_INVOICE : STATE_SHIPPING;
		String fingerprint = Util_FinancialSystemAccount.hash(body);
		String existingId = isInvoice ? acct.FinancialIdInvoiceAddress__c : acct.FinancialIdShippingAddress__c;
		String endpoint = String.format(ADDRESS_ENDPOINT, new List<String>{ division });
		if (String.isBlank(existingId)) {
			String response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), guid);
			ctx.result.calls++;
			Util_FinancialSystemAccount.ExactAddress created = (Util_FinancialSystemAccount.ExactAddress) JSON.deserialize(response, Util_FinancialSystemAccount.ExactAddress.class);
			if (isInvoice) {
				acct.FinancialIdInvoiceAddress__c = created.ID;
			} else {
				acct.FinancialIdShippingAddress__c = created.ID;
			}
			ctx.accountDirty = true;
		} else if (fingerprint != ctx.state.get(stateKey)) {
			Util_FinancialSystem.doRequest(ctx.admin, endpoint + '(guid\'' + existingId + '\')', null, 'PUT', JSON.serialize(body), guid);
			ctx.result.calls++;
		}
		ctx.newState.put(stateKey, fingerprint);
	}

	private static void syncBank(Util_FinancialSystemAccount.Ctx ctx, String division, String guid) {
		Account acct = ctx.acct;
		Util_FinancialSystemAccount.ExactBankAccount body = new Util_FinancialSystemAccount.ExactBankAccount(acct);
		String fingerprint = Util_FinancialSystemAccount.hash(body);
		String endpoint = String.format(BANK_ACCOUNT_ENDPOINT, new List<String>{ division });
		String previousBankId = acct.FinancialIdBankAccount__c;
		Boolean bankChanged = String.isBlank(previousBankId) || fingerprint != ctx.state.get(STATE_BANK);

		if (bankChanged) {
			String bankId;
			Boolean resetMandate = false;
			String response;
			if (ctx.isNewExactAccount) {
				response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), guid);
				ctx.result.calls++;
				if (response != '500') {
					bankId = ((Util_FinancialSystemAccount.ExactBankAccount) JSON.deserialize(response, Util_FinancialSystemAccount.ExactBankAccount.class)).ID;
					resetMandate = true;
				}
			}
			if (bankId == null) {
				// an Exact bank account number cannot be changed: look it up for this account, else create it
				Map<String, String> params = new Map<String, String>{
					'$select' => 'ID,BICCode,BankAccountHolderName,Main,BankAccount',
					'$filter' => 'Account eq guid\'' + acct.FinancialIdAccount__c + '\' and BankAccount eq \'' + body.BankAccount + '\''
				};
				response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, params, 'GET', null, guid);
				ctx.result.calls++;
				Util_FinancialSystemAccount.ExactBankAccounts found = (Util_FinancialSystemAccount.ExactBankAccounts) JSON.deserialize(response, Util_FinancialSystemAccount.ExactBankAccounts.class);
				if (found != null && found.results != null && !found.results.isEmpty()) {
					Util_FinancialSystemAccount.ExactBankAccount existing = found.results[0];
					bankId = existing.ID;
					if (existing.Main != true || (String.isNotBlank(acct.Bank_Account__c) && existing.BankAccountHolderName != acct.Bank_Account__c)) {
						Util_FinancialSystem.doRequest(ctx.admin, endpoint + '(guid\'' + bankId + '\')', null, 'PUT', JSON.serialize(body), guid);
						ctx.result.calls++;
						resetMandate = existing.Main != true;
					}
				} else {
					response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), guid);
					ctx.result.calls++;
					if (response == '500') {
						throw new Util_System.FinancialSyncException('The bank account (' + acct.Bank_Account_Number__c + ') is not accepted by the financial system, please check!');
					}
					bankId = ((Util_FinancialSystemAccount.ExactBankAccount) JSON.deserialize(response, Util_FinancialSystemAccount.ExactBankAccount.class)).ID;
					resetMandate = true;
				}
			}
			if (bankId != previousBankId || resetMandate) {
				// a new / re-activated bank account needs a new mandate
				acct.FinancialIdBankAccount__c = bankId;
				acct.FinancialIdBankMandate__c = null;
				ctx.accountDirty = true;
			}
			ctx.newState.put(STATE_BANK, fingerprint);
		}

		// mandate: for a new / changed bank account, when the payment method needs one
		if (String.isBlank(acct.FinancialIdBankMandate__c) && String.isNotBlank(acct.FinancialIdBankAccount__c)
				&& Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c)) {
			Util_FinancialSystemAccount.ExactMandate mandate = new Util_FinancialSystemAccount.ExactMandate(acct);
			String response = Util_FinancialSystem.doRequest(ctx.admin, String.format(MANDATE_ENDPOINT, new List<String>{ division }), null, 'POST', JSON.serialize(mandate), guid);
			ctx.result.calls++;
			Util_FinancialSystemAccount.ExactMandate created = (Util_FinancialSystemAccount.ExactMandate) JSON.deserialize(response, Util_FinancialSystemAccount.ExactMandate.class);
			acct.FinancialIdBankMandate__c = created?.ID;
			ctx.accountDirty = true;
		}
	}

	// ---------------------------------------------------------------- DML phase

	private static void save(List<Util_FinancialSystemAccount.Ctx> contexts) {
		List<Account> accounts = new List<Account>();
		List<AccountContactRelation> acrs = new List<AccountContactRelation>();
		List<Event_Log__c> logs = new List<Event_Log__c>();
		Set<String> namedCredentials = new Set<String>();

		for (Util_FinancialSystemAccount.Ctx ctx : contexts) {
			Account acct = ctx.acct;
			Account upd = new Account(Id = acct.Id);
			if (ctx.admin != null) {
				namedCredentials.add(ctx.admin.Subscription25__Named_Credential__c);
			}
			// ids / debtor number / matching bookkeeping found during the callouts
			upd.FinancialIdAccount__c = acct.FinancialIdAccount__c;
			upd.FinancialDebtorNumber__c = acct.FinancialDebtorNumber__c;
			upd.FinancialIdInvoiceAddress__c = acct.FinancialIdInvoiceAddress__c;
			upd.FinancialIdShippingAddress__c = acct.FinancialIdShippingAddress__c;
			upd.FinancialIdBankAccount__c = acct.FinancialIdBankAccount__c;
			upd.FinancialIdBankMandate__c = acct.FinancialIdBankMandate__c;
			upd.FinancialDebtorCheck__c = acct.FinancialDebtorCheck__c;
			upd.FinancialReplaceDebtorNumber__c = acct.FinancialReplaceDebtorNumber__c;
			upd.FinancialNumberOfDebtors__c = acct.FinancialNumberOfDebtors__c;
			upd.FinancialSyncState__c = JSON.serialize(ctx.newState);

			if (ctx.result.postponed && !ctx.failed) {
				// nothing failed: try again in a next run, no attempt counted
			} else if (ctx.failed || !ctx.warnings.isEmpty()) {
				Integer attempts = (acct.FinancialSyncAttempts__c == null ? 0 : acct.FinancialSyncAttempts__c.intValue()) + 1;
				upd.FinancialSyncAttempts__c = attempts;
				upd.FinancialSyncNextAttempt__c = Util_FinancialSystemAccount.nextAttempt(attempts);
				upd.FinancialSyncLastError__c = String.join(ctx.result.messages, ' | ').left(255);
				upd.SyncToFinancialSystem__c = true;
			} else {
				ctx.result.success = true;
				upd.SyncToFinancialSystem__c = false;
				// contact changes are handled with the account: no relation of it stays flagged
				for (AccountContactRelation acr : ctx.acrByContact.values()) {
					if (acr.Sync_To_Financial_System__c == true) {
						acr.Sync_To_Financial_System__c = false;
						ctx.acrsToUpdate.put(acr.Id, acr);
					}
				}
				upd.FinancialSyncAttempts__c = 0;
				upd.FinancialSyncNextAttempt__c = null;
				upd.FinancialSyncLastError__c = null;
				ctx.log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
			}
			if (ctx.failed) {
				ctx.log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
			}
			ctx.log.extId__c = acct.FinancialIdAccount__c;
			ctx.log.Message__c = (ctx.log.Message__c + 'Calls: ' + ctx.result.calls).left(131072);
			accounts.add(upd);
			acrs.addAll(ctx.acrsToUpdate.values());
			logs.add(ctx.log);
		}

		List<Database.SaveResult> srs = Database.update(accounts, false, AccessLevel.SYSTEM_MODE);
		for (Integer i = 0; i < srs.size(); i++) {
			if (!srs[i].isSuccess()) {
				Util_FinancialSystemAccount.Ctx ctx = contexts[i];
				ctx.result.success = false;
				String msg = 'Saving the account failed: ' + srs[i].getErrors()[0].getMessage();
				ctx.result.messages.add(msg);
				ctx.log.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
				ctx.log.Message__c += '\n' + msg;
			}
		}
		if (!acrs.isEmpty()) {
			Database.update(acrs, false, AccessLevel.SYSTEM_MODE);
		}
		Util_FinancialSystem.saveLimits();
		Util_FinancialSystem.saveLogs(logs, namedCredentials, null);
	}

	@TestVisible
	private static Datetime nextAttempt(Integer attempts) {
		if (attempts >= MAX_ATTEMPTS) {
			return System.now().addDays(7);
		}
		Integer minutes = Math.min(BACKOFF_MAX_MINUTES, BACKOFF_BASE_MINUTES * (Integer) Math.pow(2, attempts - 1));
		return System.now().addMinutes(minutes);
	}

	// ---------------------------------------------------------------- fingerprints

	@TestVisible
	private static Map<String, String> readState(String raw) {
		Map<String, String> state = new Map<String, String>();
		if (String.isBlank(raw)) {
			return state;
		}
		try {
			Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);
			for (String key : parsed.keySet()) {
				state.put(key, String.valueOf(parsed.get(key)));
			}
		} catch (Exception e) {
			// unreadable state: everything is sent again
		}
		return state;
	}

	@TestVisible
	private static String hash(Object payload) {
		Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(payload)));
		return EncodingUtil.convertToHex(digest).left(24);
	}

	// ---------------------------------------------------------------- Exact payloads

	@TestVisible
	private class ExactAccount {
		String Code;
		String Name;
		String AddressLine1;
		String Postcode;
		String City;
		String Country;
		String Phone;
		String Email;
		String ChamberOfCommerce;
		String VATNumber;
		String SearchCode;
		String Status;
		String PaymentConditionSales;
		String Classification1;
		String Classification2;
		String Classification3;
		String MainContact;

		ExactAccount(Account acct, String mainContact) {
			this.Code = String.isBlank(acct.FinancialDebtorNumber__c) ? null : acct.FinancialDebtorNumber__c;
			this.Name = acct.Exact_Account_Name__c;
			this.AddressLine1 = acct.BillingStreet; // establishment / billing address = main address
			this.Postcode = acct.BillingPostalCode;
			this.City = acct.BillingCity;
			this.Country = acct.BillingCountryCode;
			this.Phone = acct.Billing_Phone__c;
			this.Email = acct.Billing_Email__c;
			this.ChamberOfCommerce = (acct.CoC_Number__c != '-') ? acct.CoC_Number__c : '';
			this.VATNumber = (acct.VAT_Number__c != '-') ? acct.VAT_Number__c : '';
			this.SearchCode = String.isBlank(acct.FinancialDebtorNumberPrevious__c) ? null : acct.FinancialDebtorNumberPrevious__c;
			this.Status = 'C'; // customer
			this.PaymentConditionSales = acct.Payment_Method_Contracts__c;
			this.MainContact = String.isBlank(mainContact) ? null : mainContact;
			try {
				Subscription25__Administration__c admin = Util_FinancialSystem.getAdministrationForReseller(String.isBlank(acct.Reseller_Name__c) ? '1' : acct.Reseller_Name__c);
				this.Classification1 = Util_FinancialSystem.getExactRelationId(admin.Id, 'C1', acct.FinancialAccountClassification1__c);
				this.Classification2 = Util_FinancialSystem.getExactRelationId(admin.Id, 'C2', acct.FinancialAccountClassification2__c);
				this.Classification3 = Util_FinancialSystem.getExactRelationId(admin.Id, 'C3', acct.FinancialAccountClassification3__c);
			} catch (Exception e) {
				// classifications are optional
			}
		}
	}

	private class ExactGetAccount {
		String ID;
		String Code;
		String Name;
		String MainContact;
	}

	private class ExactGetAccounts {
		List<Util_FinancialSystemAccount.ExactGetAccount> results;
	}

	@TestVisible
	private class ExactAddress {
		String ID;
		String Account;
		String AddressLine1;
		String Postcode;
		String City;
		String Country;
		String Contact;
		Integer Type; // Visit=1, Postal=2, Invoice=3, Delivery=4

		ExactAddress(Account acct, Integer addressType, String exactContact) {
			Boolean isInvoice = addressType == ADDRESS_TYPE_INVOICE;
			this.Account = acct.FinancialIdAccount__c;
			this.AddressLine1 = isInvoice ? acct.InvoiceAddress__Street__s : acct.ShippingStreet;
			this.Postcode = isInvoice ? acct.InvoiceAddress__PostalCode__s : acct.ShippingPostalCode;
			this.City = isInvoice ? acct.InvoiceAddress__City__s : acct.ShippingCity;
			this.Country = isInvoice ? acct.InvoiceAddress__CountryCode__s : acct.ShippingCountryCode;
			this.Contact = String.isBlank(exactContact) ? null : exactContact;
			this.Type = addressType;
		}
	}

	private class ExactBankAccounts {
		List<Util_FinancialSystemAccount.ExactBankAccount> results;
	}

	@TestVisible
	private class ExactBankAccount {
		String ID;
		String Account;
		String BankAccount;
		String BankAccountHolderName;
		Boolean Main;

		ExactBankAccount(Account acct) {
			this.Account = acct.FinancialIdAccount__c;
			this.BankAccount = acct.Bank_Account_Number__c;
			this.BankAccountHolderName = acct.Bank_Account__c;
			this.Main = true; // the Salesforce bank account is always the main bank account
		}
	}

	private class ExactMandate {
		String ID;
		String Account;
		String BankAccount;
		Boolean Main;
		Date SignatureDate;
		Boolean FirstSend;
		Integer Type;
		Integer PaymentType;

		ExactMandate(Account acct) {
			this.Account = acct.FinancialIdAccount__c;
			this.BankAccount = acct.FinancialIdBankAccount__c;
			this.Main = true;
			this.SignatureDate = Date.today();
			this.FirstSend = true;
			this.Type = 0; // core
			this.PaymentType = 1; // recurring
		}
	}

	@TestVisible
	private class ExactContact {
		String ID;
		String Account;
		String FirstName;
		String MiddleName;
		String LastName;
		String Email;
		String Phone;

		ExactContact(String exactAccountId, Contact con) {
			this.Account = exactAccountId;
			this.FirstName = con?.FirstName;
			this.MiddleName = con?.MiddleName;
			this.LastName = con?.LastName;
			this.Email = con?.Email;
			this.Phone = con?.Phone;
		}
	}
}
