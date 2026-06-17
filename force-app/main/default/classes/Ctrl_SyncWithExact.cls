public with sharing class Ctrl_SyncWithExact {
	@AuraEnabled
	public static String getSyncInformation(Id contextId){
		String msg = 'No account found to sync to exact';

		Id syncId = Ctrl_SyncWithExact.getAccountId(contextId);
		//return a string containing information about what will happen when te button gets clicked

		if ((syncId != null) && (syncId.getSObjectType() == Account.getSObjectType())) {
			msg = 'This action creates/updates a Relation in Exact!';
			Account acct = [
				SELECT Id, Exact_Account_Name__c, RecordType.DeveloperName
					, ShippingStreet, ShippingPostalCode, ShippingCity, ShippingCountryCode
					, BillingStreet, BillingPostalCode, BillingCity, BillingCountryCode
					, VisitingAddress__Street__s, VisitingAddress__PostalCode__s, VisitingAddress__City__s, VisitingAddress__CountryCode__s
					, Bank_Account_Number__c, Bank_Account__c
					, Reseller_Name__c, Block_Syncing_Exact__c
					, Payment_Method_Opportunities__c, Payment_Method_Contracts__c
				FROM Account
				WHERE Id = :syncId
			];

			if(acct.Reseller_Name__c == '1' && acct.RecordType.DeveloperName != 'B2C' && acct.VisitingAddress__CountryCode__s == 'NL' && acct.Block_Syncing_Exact__c){
				msg += '<br/>This account was not validated by Web Services, this validation has to be completed before this account can be synchronised.';
			} else if ((Util_System.requireBankDetails.contains(acct.Payment_Method_Opportunities__c) || Util_System.requireBankDetails.contains(acct.Payment_Method_Contracts__c))   && (String.isBlank(acct.Bank_Account_Number__c) || String.isBlank(acct.Bank_Account__c))){
				msg +='<br/>This account can not be synchronised because the bank account was not filled in.';
			} else if (String.isBlank(acct.VisitingAddress__CountryCode__s) || String.isBlank(acct.VisitingAddress__Street__s) || String.isBlank(acct.VisitingAddress__PostalCode__s) || String.isBlank(acct.VisitingAddress__City__s)){
				msg += '<br>This account can not be synchronised because the visiting address was not filled in.';
			} else if (String.isBlank(acct.ShippingCountryCode) || String.isBlank(acct.ShippingStreet) || String.isBlank(acct.ShippingPostalCode) || String.isBlank(acct.ShippingCity)){
				msg += '<br>This account can not be synchronised because the shipping address was not filled in.';
			} else if (String.isBlank(acct.BillingCountryCode) || String.isBlank(acct.BillingStreet) || String.isBlank(acct.BillingPostalCode) || String.isBlank(acct.BillingCity)){
				msg += '<br>This account can not be synchronised because the billing address was not filled in.';
			} else {
				msg += '<br/><br/>When you want to continue, press "Synchronise".';
			}
		} else if ((syncId != null) && (syncId.getSObjectType() == Order.getSObjectType())) {
			Order ord = [
				SELECT Id, Exact_Id__c, AccountId, Subscription25__Administration__c, Payment_Method__c
				FROM Order
				WHERE Id = :syncId
			];

			list<Subscription25__Debtor_Number__c> debtorNumbers = new list<Subscription25__Debtor_Number__c>([
				SELECT
					id
					, Exact_Id__c
					, exact_Contact_Id__c
					, Exact_Bank_Account_Id__c
					, Exact_Mandate_Id__c
				FROM 
					Subscription25__Debtor_Number__c
				WHERE
					Subscription25__Account__c = :ord.AccountId
					and Subscription25__Administration__c = :ord.Subscription25__Administration__c
				LIMIT
					1					
			]);

			Subscription25__Debtor_Number__c debNr = (debtorNumbers.size() == 0) ? null : debtorNumbers[0]; 
			boolean bSync = true;

			msg = 'This action creates an Order in Exact!';
			if (String.isNotBlank(ord.Exact_Id__c)) {
				msg += '<br/>This Order is already synchronized.';
				bsync = false;
			} else if (debNr == null) {
				msg +='<br/>This Order can not be synchronised because Account has no Debtor Number.';
				bsync = false;
			} else {
				if (String.isBlank(debNr.Exact_Contact_Id__c)) {
					msg += '<br>This order can not be synchronised because main (contact) on the account is missing or not synced to Exact';
					bsync = false;
				} 
				if (Util_System.requireBankDetails.contains(ord.Payment_Method__c) && (String.isBlank(debNr.Exact_Bank_Account_Id__c) || String.isBlank(debNr.Exact_Mandate_Id__c))) {
					msg += '<br>This order can not be synchronised because the bank account was not filled in on the Acoount or not sync to Exact.';
					bsync = false;
				} 
			} 
			if (bsync) {
				msg += '<br/><br/>When you want to continue, press "Synchronise".';
			}			
		}

		return msg;
	}

	@AuraEnabled
	public static List<String> doSync(Id contextId){
		Id syncId = Ctrl_SyncWithExact.getAccountId(contextId);
		List<String> msgs = new List<String>();

		if (syncId == null) {
			msgs.add('No Account/Order found to sync to exact');
			return msgs;
		}

		//based off of the context id, determine which sync to cal
		if (syncId.getSObjectType() == Account.getSObjectType()) {
			try {			
				if (!Test.isRunningTest()) {
					msgs = Util_Exact.syncAccount(syncId);
				} else {
					msgs.add('syncAccount');
				}
			} catch(Exception ex){
				msgs.add(ex.getMessage());
			}
		} else if (syncId.getSObjectType() == Order.getSObjectType()) {
			try {			
				if (!Test.isRunningTest()) {
					msgs = Util_Exact.syncOrder(syncId);
				} else {
					msgs.add('syncOrder');
				}
			} catch(Exception ex){
				msgs.add(ex.getMessage());
			}		
		}

		return msgs;
	}


	private static id getAccountId( Id contextId) {
		Id syncId;

		if (contextId.getSObjectType() == Account.getSObjectType()) {
			syncId = contextId;
		} else if (contextId.getSObjectType() == Subscription25__Debtor_Number__c.getSObjectType()) {
			list<Subscription25__Debtor_Number__c> debtorNumbers = new List<Subscription25__Debtor_Number__c>(
				[select 
					Id
					, Subscription25__Account__c 
				from 
					Subscription25__Debtor_Number__c 
				where 
					Id = :contextId]);

			if (debtorNumbers.size() >= 1) {
				syncId = debtorNumbers[0].Subscription25__Account__c;
			}

		} else if (contextId.getSObjectType() == Order.getSObjectType()) {
			syncId = contextId;
		}

		return syncId;

	}
}