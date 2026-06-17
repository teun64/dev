public class Trigger_Account {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_Account.updateVisitingAddressLabels();
		Trigger_Account.cascadeOrderCreationSettings();
		//Trigger_Account.syncToExact();
	}

	private static void updateVisitingAddressLabels(){
		if(!(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))){
			return;
		}

		List<Account> iterList = Trigger.new;
		for(Account accNew : iterList){
			Boolean addressChanged = true;

            if (Trigger.isUpdate && (Trigger.oldMap != null)) {
                Account accOld = (Account)Trigger.oldMap.get(accNew.Id);

                addressChanged = ((accNew.VisitingAddress__CountryCode__s != accOld.VisitingAddress__CountryCode__s) ||
                    (accNew.VisitingAddress__StateCode__s != accOld.VisitingAddress__StateCode__s) || 
					((String.isNotBlank(accNew.VisitingAddress__CountryCode__s)) && (String.isBlank(accNew.VisitingAddress_Country__c))) || 
					((String.isNotBlank(accNew.VisitingAddress__StateCode__s)) && (String.isBlank(accNew.VisitingAddress_State__c))));

				if (addressChanged) {
					String countryCode = accNew.VisitingAddress__CountryCode__s;
					String stateCode   = accNew.VisitingAddress__StateCode__s;

					accNew.VisitingAddress_Country__c = String.isNotBlank(countryCode) ? Util_AddressLabel.getCountryLabel(countryCode) : null;
					accNew.VisitingAddress_State__c   = String.isNotBlank(stateCode) ? Util_AddressLabel.getStateLabel(stateCode) : null;
				}
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
		Set<Id> monthlyAccIds = new Set<Id>();
		Set<Id> yearlyAccIds = new Set<Id>();
		for(Account accNew : iterList){
			Account accOld = (Account)Trigger.oldMap.get(accNew.Id);

			//collect all account ids where the value of the order creation field has been changed, in two lists
			if(accOld.Create_Monthly_Orders_Until__c != accNew.Create_Monthly_Orders_Until__c){
				monthlyAccIds.add(accNew.Id);
			}
			if(accOld.Create_Yearly_Orders_Until__c != accNew.Create_Yearly_Orders_Until__c){
				yearlyAccIds.add(accNew.Id);
			}
		}

		if(monthlyAccIds.size() == 0 && yearlyAccIds.size() == 0){
			return;
		}

		List<Subscription25__Contract_Product__c> cpsToUpdate = [
			SELECT Id
			FROM Subscription25__Contract_Product__c
			WHERE (Subscription25__Contract__r.AccountId IN :monthlyAccIds AND Subscription25__Contract__r.Subscription25__Invoice_Cycle__c = 1)
				OR (Subscription25__Contract__r.AccountId IN :yearlyAccIds AND Subscription25__Contract__r.Subscription25__Invoice_Cycle__c = 12)
		];
		//save all the products with allOrNone = false so any validation on for instance
		//terminated lines does not block everything
		Database.update(cpsToUpdate, false);
	}

	// private static void syncToExact(){
	// 	if(!(Trigger.isAfter && Trigger.isUpdate)){
	// 		return;
	// 	}

	// 	List<Account> iterList = Trigger.new;
	// 	Set<String> fieldsToCheck = new Set<String>{
	// 		'VAT_Number__c', 'Payment_Method_Opportunities__c',	'Exact_Account_Name__c', 'ShippingStreet',
	// 		'ShippingPostalCode', 'ShippingCity', 'ShippingCountryCode', 'BillingStreet',
	// 		'BillingPostalCode', 'BillingCity',	'BillingCountryCode', 'Billing_Phone__c',
	// 		'Billing_Email__c', 'CoC_Number__c', 'Bank_Account_Number__c', 'Bank_Account__c',
	// 		'Relation_Type__c'
	// 	};
	// 	Set<Id> accsToDo = new Set<Id>();
	// 	for(Account accNew : iterList){
	// 		Account accOld = (Account)Trigger.oldMap.get(accNew.Id);
	// 		if(Util_System.hasFieldChanged(accNew, accOld, fieldsToCheck)){
	// 			accsToDo.add(accNew.Id);
	// 		}
	// 	}

	// 	if(accsToDo.size() == 0){
	// 		return;
	// 	}

	// 	//now, load all the accounts that have a debtor number (because we should just sync updates)
	// 	List<Subscription25__Debtor_Number__c> debtorNumbers = [
	// 		SELECT Id, Subscription25__Account__c
	// 		FROM Subscription25__Debtor_Number__c
	// 		WHERE Subscription25__Account__c IN :accsToDo
	// 	];
	// 	Set<Id> accIds = Util_System.collectIdValues(debtorNumbers, 'Subscription25__Account__c');

	// 	Integer cnt = 0;
	// 	for(Id accId : accIds){
	// 		Util_Exact.syncAccountAsync(accId);
	// 		if(++cnt == 20){
	// 			break; //to prevent limits
	// 		}
	// 	}
	// }
}