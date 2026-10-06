/**
 * Account sync to the financial system (Exact Online), bulkified. Successor of Util_Exact.syncAccount.
 *
 * syncAccounts() handles many accounts in one transaction: all callouts first, then one DML phase
 * (Accounts, AccountContactRelations, logs, rate limits). Per account, per part:
 *  - account     : POST (new) / PUT (changed); duplicate-prevention match GET only for unchecked accounts,
 *                  never links an Exact account that another Salesforce account already uses
 *  - contacts    : main / invoice / shipping contact, one Exact contact per AccountContactRelation
 *                  (ACR.FinancialIdContact__c); Exact account MainContact = the main contact. Any other relation
 *                  with an Exact id that is flagged (changed contact) is maintained as well.
 *  - addresses   : establishment (Billing) is the Exact account's own address; invoice (type 3) = invoice
 *                  address when supplied, otherwise the establishment address, + invoice contact; shipping
 *                  (type 4) likewise. Created only when address or contact differs from the establishment + main
 *                  contact; once created it is kept up to date. Both are the Main address of their type.
 *  - bank/mandate: an Exact bank account number cannot be changed, so a changed IBAN means GET (exists?) or POST
 * Only parts whose fingerprint (FinancialSyncState__c) changed are sent. Exact ids live on the Account
 * (FinancialId*__c) and the ACR, not on Subscription25__Debtor_Number__c.
 * Failed accounts keep SyncToFinancialSystem__c and are retried with exponential back-off.
 *
 * syncFlaggedContacts() (Batch_FinancialSystemContactSync) handles changed contacts without an account sync: a
 * flagged relation with an Exact id is PUT directly; one without an Exact id but with a Main / Invoice / Shipping
 * role flags its account (the account sync creates the contact and links it to the address).
 * A relation with an Exact contact but no role left (and not the account's main / invoice / shipping contact) is
 * retired in Exact: last name + " (DO NOT USE)", email cleared, excluded from mailings, EndDate = today (inactive).
 * When it gets a role again, the contact is restored (EndDate cleared).
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

	// retry back-off: Util_FinancialSystem.nextAttempt
	public static final Integer MAX_ATTEMPTS = Util_FinancialSystem.MAX_ATTEMPTS;

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
	@TestVisible
	private static final String STATE_RETIRED = 'retired:';
	@TestVisible
	private static final String DO_NOT_USE = ' (DO NOT USE)';

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
	 * Contact update: handles relations flagged by rau_Contact_AccountContactRelation (name / email / phone changed)
	 * without a full account sync. Relations of accounts that are flagged themselves are left to the account sync.
	 *  - account not in Exact yet         : flag cleared (the first account sync creates the contacts it needs)
	 *  - relation has an Exact contact id : PUT when its fingerprint changed, flag cleared
	 *  - no Exact id, Main/Invoice/Shipping role : account flagged (POST contact + address link in the account sync)
	 *  - no Exact id, other role          : flag cleared
	 * A failed PUT flags the account, so the account sync retries it with back-off.
	 */
	public static void syncFlaggedContacts(Set<Id> relationIds, Boolean batchMode) {
		Map<Id, List<AccountContactRelation>> toSendByAccount = new Map<Id, List<AccountContactRelation>>();
		Map<Id, Account> accounts = new Map<Id, Account>();
		List<AccountContactRelation> toClear = new List<AccountContactRelation>();
		Set<Id> accountsToFlag = new Set<Id>();
		for (AccountContactRelation acr : [
				SELECT Id, AccountId, ContactId, FinancialIdContact__c, Roles, isMainContact__c, isInvoiceContact__c, isShippingContact__c,
					Account.Contact_person__c, Account.Contact_Billing__c, Account.Contact_Shipping__c,
					Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone,
					Account.Name, Account.Exact_Account_Name__c, Account.Reseller_Name__c, Account.FinancialIdAccount__c,
					Account.SyncToFinancialSystem__c, Account.FinancialSyncState__c
				FROM AccountContactRelation
				WHERE Id IN :relationIds AND Sync_To_Financial_System__c = true
				WITH SYSTEM_MODE]) {
			if (acr.Account.SyncToFinancialSystem__c) {
				continue;
			}
			if (String.isBlank(acr.Account.FinancialIdAccount__c)) {
				toClear.add(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = false));
			} else if (String.isNotBlank(acr.FinancialIdContact__c)) {
				if (!toSendByAccount.containsKey(acr.AccountId)) {
					toSendByAccount.put(acr.AccountId, new List<AccountContactRelation>());
					accounts.put(acr.AccountId, acr.Account);
				}
				toSendByAccount.get(acr.AccountId).add(acr);
			} else if (acr.isMainContact__c || acr.isInvoiceContact__c || acr.isShippingContact__c) {
				accountsToFlag.add(acr.AccountId);
			} else {
				toClear.add(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = false));
			}
		}

		List<Account> stateUpdates = new List<Account>();
		List<Event_Log__c> logs = new List<Event_Log__c>();
		Set<String> namedCredentials = new Set<String>();
		Set<Id> limitedAdmins = new Set<Id>();
		for (Id accountId : toSendByAccount.keySet()) {
			Account acct = accounts.get(accountId);
			List<AccountContactRelation> acrs = toSendByAccount.get(accountId);
			Subscription25__Administration__c admin = Util_FinancialSystem.getAdministrationForReseller(acct.Reseller_Name__c);
			if (admin == null || admin.Subscription25__Synchronisation__c != Util_FinancialSystem.SYNC_EXACT || !admin.Subscription25__Active__c
					|| !Util_System.isFinancialSyncAllowed(admin)) {
				// the account sync reports why this account cannot be synchronised
				accountsToFlag.add(accountId);
				continue;
			}
			Util_FinancialSystem.Limits lim = Util_FinancialSystem.getLimits(admin);
			if (limitedAdmins.contains(admin.Id) || !(batchMode ? lim.hasBatchCapacity(acrs.size()) : lim.hasCapacity(acrs.size()))) {
				// no capacity: stays flagged for a next run
				limitedAdmins.add(admin.Id);
				continue;
			}
			namedCredentials.add(admin.Subscription25__Named_Credential__c);
			Event_Log__c log = Util_Event.getLog(null, 'S', 'E', 'Account', 'contact2Exact', accountId, acct.Exact_Account_Name__c, null);
			log.Message__c = '';
			Map<String, String> state = Util_FinancialSystemAccount.readState(acct.FinancialSyncState__c);
			String endpoint = String.format(CONTACT_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
			Integer calls = 0;
			Boolean failed = false;
			for (AccountContactRelation acr : acrs) {
				String stateKey = STATE_CONTACT + acr.ContactId;
				Util_FinancialSystemAccount.ContactRequest req = new Util_FinancialSystemAccount.ContactRequest(acct.FinancialIdAccount__c, acr,
					Util_FinancialSystemAccount.isRetired(acr, acct), state.get(stateKey));
				try {
					if (req.fingerprint != state.get(stateKey)) {
						Util_FinancialSystem.doRequest(admin, endpoint + '(guid\'' + acr.FinancialIdContact__c + '\')', null, 'PUT', req.body, log.GUID__c);
						calls++;
					}
					state.put(stateKey, req.fingerprint);
					toClear.add(new AccountContactRelation(Id = acr.Id, Sync_To_Financial_System__c = false));
				} catch (Util_FinancialSystem.RateLimitException e) {
					// the rest stays flagged for a next run
					limitedAdmins.add(admin.Id);
					log.Message__c += e.getMessage() + '\n';
					break;
				} catch (Util_System.FinancialSyncException e) {
					failed = true;
					accountsToFlag.add(accountId);
					log.Message__c += 'Contact ' + acr.ContactId + ': ' + e.getMessage() + '\n';
				}
			}
			if (calls > 0) {
				stateUpdates.add(new Account(Id = accountId, FinancialSyncState__c = JSON.serialize(state)));
			}
			if (calls > 0 || failed) {
				log.Result_Status__c = failed ? Util_Event.LogResultStatus.ERROR.name() : log.Result_Status__c;
				log.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
				log.extId__c = acct.FinancialIdAccount__c;
				log.Message__c = (log.Message__c + 'Calls: ' + calls).left(131072);
				logs.add(log);
			}
		}

		if (!toClear.isEmpty()) {
			Database.update(toClear, false, AccessLevel.SYSTEM_MODE);
		}
		if (!stateUpdates.isEmpty()) {
			Database.update(stateUpdates, false, AccessLevel.SYSTEM_MODE);
		}
		if (!accountsToFlag.isEmpty()) {
			Util_FinancialSystemAccount.flagAccounts(accountsToFlag);
		}
		Util_FinancialSystem.saveLimits();
		if (!logs.isEmpty()) {
			Util_FinancialSystem.saveLogs(logs, namedCredentials, null);
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
		// Exact contacts retired in this run (Account.FinancialContactsToRetire__c)
		Set<String> retiredIds = new Set<String>();
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
				FinancialContactsToRetire__c,
				Contact_person__c, Contact_Billing__c, Contact_Shipping__c
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
				SELECT Id, AccountId, ContactId, FinancialIdContact__c, Sync_To_Financial_System__c, Roles,
					Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone
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
		calls += Util_FinancialSystemAccount.contactsToSync(ctx).size();
		calls += Svc_FinancialSystemContactRemoval.readEntries(acct.FinancialContactsToRetire__c).size();
		calls++; // main contact on the account
		if (Util_FinancialSystemAccount.invoiceAddressDiffers(acct) || String.isNotBlank(acct.FinancialIdInvoiceAddress__c)) {
			calls++;
		}
		if (Util_FinancialSystemAccount.shippingAddressDiffers(acct) || String.isNotBlank(acct.FinancialIdShippingAddress__c)) {
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

	/** The main / invoice / shipping contact, plus any other flagged relation that has an Exact contact. */
	private static List<Id> contactsToSync(Util_FinancialSystemAccount.Ctx ctx) {
		List<Id> ids = Util_FinancialSystemAccount.contactIds(ctx.acct);
		for (AccountContactRelation acr : ctx.acrByContact.values()) {
			if (acr.Sync_To_Financial_System__c == true && String.isNotBlank(acr.FinancialIdContact__c) && !ids.contains(acr.ContactId)) {
				ids.add(acr.ContactId);
			}
		}
		return ids;
	}

	@TestVisible
	private static Boolean hasInvoiceAddress(Account acct) {
		return String.isNotBlank(acct.InvoiceAddress__Street__s) && String.isNotBlank(acct.InvoiceAddress__City__s);
	}

	@TestVisible
	private static Boolean hasShippingAddress(Account acct) {
		return String.isNotBlank(acct.ShippingStreet) && String.isNotBlank(acct.ShippingCity);
	}

	/**
	 * The invoice address (invoice address when supplied, otherwise the establishment address) or its contact
	 * differs from the establishment address + main contact.
	 */
	@TestVisible
	private static Boolean invoiceAddressDiffers(Account acct) {
		Boolean addressDiffers = Util_FinancialSystemAccount.hasInvoiceAddress(acct) && (acct.InvoiceAddress__Street__s != acct.BillingStreet
			|| acct.InvoiceAddress__PostalCode__s != acct.BillingPostalCode || acct.InvoiceAddress__City__s != acct.BillingCity
			|| acct.InvoiceAddress__CountryCode__s != acct.BillingCountryCode);
		Boolean contactDiffers = acct.Contact_Billing__c != null && acct.Contact_Billing__c != acct.Contact_person__c;
		return addressDiffers || contactDiffers;
	}

	/** Same as invoiceAddressDiffers, for the shipping address and contact. */
	@TestVisible
	private static Boolean shippingAddressDiffers(Account acct) {
		Boolean addressDiffers = Util_FinancialSystemAccount.hasShippingAddress(acct) && (acct.ShippingStreet != acct.BillingStreet
			|| acct.ShippingPostalCode != acct.BillingPostalCode || acct.ShippingCity != acct.BillingCity
			|| acct.ShippingCountryCode != acct.BillingCountryCode);
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

		// 3. contacts (main / invoice / shipping + changed ones with an Exact id), each as its own Exact contact
		for (Id cid : Util_FinancialSystemAccount.contactsToSync(ctx)) {
			try {
				Util_FinancialSystemAccount.syncContact(ctx, cid, division, guid);
			} catch (Util_System.FinancialSyncException e) {
				ctx.warn('Contact: ' + e.getMessage());
			}
		}

		// 3b. Exact contacts of deleted relations (deleted / merged contact, removed relation)
		Util_FinancialSystemAccount.retireRemovedContacts(ctx, division, guid);

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

		// 5. invoice and shipping address (when they differ from the establishment address or its contact, or already exist)
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

	private static void syncContact(Util_FinancialSystemAccount.Ctx ctx, Id contactId, String division, String guid) {
		AccountContactRelation acr = ctx.acrByContact.get(contactId);
		if (acr == null) {
			ctx.warn('Contact ' + contactId + ' has no relation with this account and is not synced.');
			return;
		}
		Util_FinancialSystemAccount.ExactContact body = new Util_FinancialSystemAccount.ExactContact(ctx.acct.FinancialIdAccount__c, acr.Contact);
		String stateKey = STATE_CONTACT + contactId;
		Util_FinancialSystemAccount.ContactRequest req = new Util_FinancialSystemAccount.ContactRequest(ctx.acct.FinancialIdAccount__c, acr,
			String.isNotBlank(acr.FinancialIdContact__c) && Util_FinancialSystemAccount.isRetired(acr, ctx.acct), ctx.state.get(stateKey));
		String fingerprint = req.fingerprint;
		String endpoint = String.format(CONTACT_ENDPOINT, new List<String>{ division });
		if (String.isBlank(acr.FinancialIdContact__c)) {
			String response = Util_FinancialSystem.doRequest(ctx.admin, endpoint, null, 'POST', JSON.serialize(body), guid);
			ctx.result.calls++;
			Util_FinancialSystemAccount.ExactContact created = (Util_FinancialSystemAccount.ExactContact) JSON.deserialize(response, Util_FinancialSystemAccount.ExactContact.class);
			acr.FinancialIdContact__c = created.ID;
			acr.Sync_To_Financial_System__c = false;
			ctx.acrsToUpdate.put(acr.Id, acr);
		} else if (fingerprint != ctx.state.get(stateKey)) {
			Util_FinancialSystem.doRequest(ctx.admin, endpoint + '(guid\'' + acr.FinancialIdContact__c + '\')', null, 'PUT', req.body, guid);
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

	private static void retireRemovedContacts(Util_FinancialSystemAccount.Ctx ctx, String division, String guid) {
		String endpoint = String.format(CONTACT_ENDPOINT, new List<String>{ division });
		for (Svc_FinancialSystemContactRemoval.RetireEntry entry : Svc_FinancialSystemContactRemoval.readEntries(ctx.acct.FinancialContactsToRetire__c)) {
			AccountContactRelation acr = new AccountContactRelation();
			acr.Contact = new Contact(FirstName = entry.firstName, MiddleName = entry.middleName, LastName = entry.lastName);
			Util_FinancialSystemAccount.ContactRequest req = new Util_FinancialSystemAccount.ContactRequest(ctx.acct.FinancialIdAccount__c, acr, true, null);
			try {
				Util_FinancialSystem.doRequest(ctx.admin, endpoint + '(guid\'' + entry.id + '\')', null, 'PUT', req.body, guid);
				ctx.result.calls++;
				ctx.retiredIds.add(entry.id);
			} catch (Util_System.FinancialSyncException e) {
				ctx.warn('Retiring contact ' + entry.id + ': ' + e.getMessage());
			}
		}
	}

	/** No role left and not the account's main / invoice / shipping contact: the Exact contact is retired. */
	@TestVisible
	private static Boolean isRetired(AccountContactRelation acr, Account acct) {
		return String.isBlank(acr.Roles)
			&& acr.ContactId != acct.Contact_person__c && acr.ContactId != acct.Contact_Billing__c && acr.ContactId != acct.Contact_Shipping__c;
	}

	/**
	 * PUT body + fingerprint of an Exact contact. Active: the plain contact (same fingerprint as before retiring
	 * existed); after a retirement EndDate is cleared and mailing allowed again. Retired: " (DO NOT USE)" after the
	 * last name, email cleared, excluded from mailings, EndDate = today (only when it is retired now, not on a
	 * later change of a retired contact).
	 */
	@TestVisible
	private class ContactRequest {
		@TestVisible
		String fingerprint;
		@TestVisible
		String body;

		@TestVisible
		ContactRequest(String exactAccountId, AccountContactRelation acr, Boolean retired, String previousFingerprint) {
			Util_FinancialSystemAccount.ExactContact contact = new Util_FinancialSystemAccount.ExactContact(exactAccountId, acr.Contact);
			String plain = Util_FinancialSystemAccount.hash(contact);
			Boolean wasRetired = previousFingerprint != null && previousFingerprint.startsWith(STATE_RETIRED);
			if (!retired) {
				this.fingerprint = plain;
				if (!wasRetired) {
					this.body = JSON.serialize(contact);
					return;
				}
				Map<String, Object> restore = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(contact));
				restore.put('EndDate', null);
				restore.put('IsMailingExcluded', false);
				this.body = JSON.serialize(restore);
				return;
			}
			this.fingerprint = STATE_RETIRED + plain;
			Map<String, Object> retire = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(contact));
			retire.put('LastName', (String.isBlank(acr.Contact?.LastName) ? '' : acr.Contact.LastName) + DO_NOT_USE);
			retire.put('Email', '');
			retire.put('IsMailingExcluded', true);
			if (!wasRetired) {
				retire.put('EndDate', Datetime.now().formatGmt('yyyy-MM-dd') + 'T00:00:00');
			}
			this.body = JSON.serialize(retire);
		}
	}

	private static void syncAddress(Util_FinancialSystemAccount.Ctx ctx, Integer addressType, String division, String guid) {
		Account acct = ctx.acct;
		Boolean isInvoice = addressType == ADDRESS_TYPE_INVOICE;
		String existingId = isInvoice ? acct.FinancialIdInvoiceAddress__c : acct.FinancialIdShippingAddress__c;
		// a created address is kept up to date, also when it equals the establishment address again
		if (String.isBlank(existingId) && !(isInvoice ? Util_FinancialSystemAccount.invoiceAddressDiffers(acct) : Util_FinancialSystemAccount.shippingAddressDiffers(acct))) {
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
				upd.FinancialSyncNextAttempt__c = Util_FinancialSystem.nextAttempt(attempts);
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

		Map<Id, Set<String>> retiredByAccount = new Map<Id, Set<String>>();
		for (Util_FinancialSystemAccount.Ctx ctx : contexts) {
			if (!ctx.retiredIds.isEmpty()) {
				retiredByAccount.put(ctx.acct.Id, ctx.retiredIds);
			}
		}
		if (!retiredByAccount.isEmpty()) {
			Map<Id, Account> current = new Map<Id, Account>([
				SELECT Id, FinancialContactsToRetire__c FROM Account WHERE Id IN :retiredByAccount.keySet() WITH SYSTEM_MODE
			]);
			for (Account upd : accounts) {
				if (!retiredByAccount.containsKey(upd.Id)) {
					continue;
				}
				List<Svc_FinancialSystemContactRemoval.RetireEntry> remaining = new List<Svc_FinancialSystemContactRemoval.RetireEntry>();
				for (Svc_FinancialSystemContactRemoval.RetireEntry e : Svc_FinancialSystemContactRemoval.readEntries(current.get(upd.Id)?.FinancialContactsToRetire__c)) {
					if (!retiredByAccount.get(upd.Id).contains(e.id)) {
						remaining.add(e);
					}
				}
				upd.FinancialContactsToRetire__c = remaining.isEmpty() ? null : JSON.serialize(remaining);
			}
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
		Boolean Main;

		ExactAddress(Account acct, Integer addressType, String exactContact) {
			Boolean isInvoice = addressType == ADDRESS_TYPE_INVOICE;
			// invoice / shipping address when supplied, otherwise the establishment address
			Boolean own = isInvoice ? Util_FinancialSystemAccount.hasInvoiceAddress(acct) : Util_FinancialSystemAccount.hasShippingAddress(acct);
			this.Account = acct.FinancialIdAccount__c;
			if (!own) {
				this.AddressLine1 = acct.BillingStreet;
				this.Postcode = acct.BillingPostalCode;
				this.City = acct.BillingCity;
				this.Country = acct.BillingCountryCode;
			} else if (isInvoice) {
				this.AddressLine1 = acct.InvoiceAddress__Street__s;
				this.Postcode = acct.InvoiceAddress__PostalCode__s;
				this.City = acct.InvoiceAddress__City__s;
				this.Country = acct.InvoiceAddress__CountryCode__s;
			} else {
				this.AddressLine1 = acct.ShippingStreet;
				this.Postcode = acct.ShippingPostalCode;
				this.City = acct.ShippingCity;
				this.Country = acct.ShippingCountryCode;
			}
			this.Contact = String.isBlank(exactContact) ? null : exactContact;
			this.Type = addressType;
			this.Main = true; // the Salesforce invoice / shipping address is the default of its type
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
