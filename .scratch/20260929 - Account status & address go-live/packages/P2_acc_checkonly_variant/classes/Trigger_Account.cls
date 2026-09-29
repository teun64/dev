public class Trigger_Account {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_Account.updateInvoiceAddressLabels();
		Trigger_Account.cascadeOrderCreationSettings();
		//Trigger_Account.syncToExact();
	}

	// country / state labels of the invoice address (custom address fields only have codes), used for the invoice (Subscription25) address
	private static void updateInvoiceAddressLabels(){
		if(!(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))){
			return;
		}

		List<Account> iterList = Trigger.new;
		for(Account accNew : iterList){
			Account accOld = Trigger.isUpdate ? (Account)Trigger.oldMap.get(accNew.Id) : null;
			Boolean addressChanged = (accOld == null) ||
				(accNew.InvoiceAddress__CountryCode__s != accOld.InvoiceAddress__CountryCode__s) ||
				(accNew.InvoiceAddress__StateCode__s != accOld.InvoiceAddress__StateCode__s) ||
				((String.isNotBlank(accNew.InvoiceAddress__CountryCode__s)) && (String.isBlank(accNew.InvoiceAddress_Country__c))) ||
				((String.isNotBlank(accNew.InvoiceAddress__StateCode__s)) && (String.isBlank(accNew.InvoiceAddress_State__c)));

			if (addressChanged) {
				String countryCode = accNew.InvoiceAddress__CountryCode__s;
				String stateCode   = accNew.InvoiceAddress__StateCode__s;

				accNew.InvoiceAddress_Country__c = String.isNotBlank(countryCode) ? Util_AddressLabel.getCountryLabel(countryCode) : null;
				accNew.InvoiceAddress_State__c   = String.isNotBlank(stateCode) ? Util_AddressLabel.getStateLabel(stateCode) : null;
			}
		}
	}

	//when the value of Create Montly Orders Until or Create Yearly Orders Until change, we simply update the contract
	//products of the contracts of the account that have the applicable invoice cycle, so that they will reflect the new value
	private static void cascadeOrderCreationSettings(){
		if(!(Trigger.isAfter && Trigger.isUpdate)){
			return;
		}

		List<Account> iterList = Trigger.new;
		Set<Id> monthlyAcctIds = new Set<Id>();
		Set<Id> yearlyAcctIds = new Set<Id>();
		for(Account acctNew : iterList){
			Account acctOld = (Account)Trigger.oldMap.get(acctNew.Id);

			//collect all account ids where the value of the order creation field has been changed, in two lists
			if(acctOld.Create_Monthly_Orders_Until__c != acctNew.Create_Monthly_Orders_Until__c){
				monthlyAcctIds.add(acctNew.Id);
			}
			if(acctOld.Create_Yearly_Orders_Until__c != acctNew.Create_Yearly_Orders_Until__c){
				yearlyAcctIds.add(acctNew.Id);
			}
		}

		if(monthlyAcctIds.size() == 0 && yearlyAcctIds.size() == 0){
			return;
		}

		List<Subscription25__Contract_Product__c> cpsToUpdate = [
			SELECT Id
			FROM Subscription25__Contract_Product__c
			WHERE (Subscription25__Contract__r.AccountId IN :monthlyAcctIds AND Subscription25__Contract__r.Subscription25__Invoice_Cycle__c = 1)
				OR (Subscription25__Contract__r.AccountId IN :yearlyAcctIds AND Subscription25__Contract__r.Subscription25__Invoice_Cycle__c = 12)
		];
		//save all the products with allOrNone = false so any validation on for instance
		//terminated lines does not block everything
		Database.update(cpsToUpdate, false);
	}

	private static void syncToExact(){
		if(!(Trigger.isAfter && Trigger.isUpdate)){
			return;
		}

		List<Account> iterList = Trigger.new;
		Set<String> fieldsToCheck = new Set<String>{
			'VAT_Number__c', 'Payment_Method_Opportunities__c',	'Exact_Account_Name__c', 'ShippingStreet',
			'ShippingPostalCode', 'ShippingCity', 'ShippingCountryCode', 'BillingStreet',
			'BillingPostalCode', 'BillingCity',	'BillingCountryCode', 'Billing_Phone__c',
			'Billing_Email__c', 'CoC_Number__c', 'Bank_Account_Number__c', 'Bank_Account__c',
			'Relation_Type__c'
		};
		Set<Id> acctsToDo = new Set<Id>();
		for(Account acctNew : iterList){
			Account acctOld = (Account)Trigger.oldMap.get(acctNew.Id);
			if(Util_System.hasFieldChanged(acctNew, acctOld, fieldsToCheck)){
				acctsToDo.add(acctNew.Id);
			}
		}

		if(acctsToDo.size() == 0){
			return;
		}

		//now, load all the accounts that have a debtor number (because we should just sync updates)
		List<Subscription25__Debtor_Number__c> debtorNumbers = [
			SELECT Id, Subscription25__Account__c
			FROM Subscription25__Debtor_Number__c
			WHERE Subscription25__Account__c IN :acctsToDo
		];
		Set<Id> acctIds = Util_System.collectIdValues(debtorNumbers, 'Subscription25__Account__c');

		Integer cnt = 0;
		for(Id acctId : acctIds){
			Util_Exact.syncAccountAsync(acctId);
			if(++cnt == 20){
				break; //to prevent limits
			}
		}
	}
}