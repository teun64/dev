public class Trigger_Contract_Product_c {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_Contract_Product_c.setOrderCreationOverrides();
		Trigger_Contract_Product_c.addAdditionalProducts();
	}

	private static void setOrderCreationOverrides(){
		if(!(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))){
			return;
		}

		List<Subscription25__Contract_Product__c> iterList = Trigger.new;
		Set<Id> contractIds = Util_System.collectIdValues(iterList, 'Subscription25__Contract__c');
		Map<Id, Contract> contractMap = new Map<Id, Contract>([
			SELECT Id, Subscription25__Invoice_Cycle__c, Account.Create_Monthly_Orders_Until__c, Account.Create_Yearly_Orders_Until__c
			FROM Contract
			WHERE Id IN :contractIds
		]);

		for(Subscription25__Contract_Product__c cpNew : iterList){
			Contract curCont = contractMap.get(cpNew.Subscription25__Contract__c);

			//start of by setting everything to the default values
			cpNew.Subscription25__Extrapolate_Orders_Until_Month_End__c = 'INHERIT';
			cpNew.Subscription25__Use_Calendar_Year__c = 'INHERIT';

			//if this is a monthly invoiced contract, check the account settings for monthly orders
			if(curCont.Subscription25__Invoice_Cycle__c == 1 && curCont.Account.Create_Monthly_Orders_Until__c == 'End of month'){
				cpNew.Subscription25__Extrapolate_Orders_Until_Month_End__c = 'YES';
			} else if(curCont.Subscription25__Invoice_Cycle__c == 12){
				//if this is a yearly invoiced contract, check the account settings for yearly orders,
				//here we either extend to the end of the month, or the end of the year
				if(curCont.Account.Create_Yearly_Orders_Until__c == 'End of month'){
					cpNew.Subscription25__Extrapolate_Orders_Until_Month_End__c = 'YES';
				} else if(curCont.Account.Create_Yearly_Orders_Until__c == 'End of year'){
					cpNew.Subscription25__Use_Calendar_Year__c = 'YES';
				}
			}
		}
	}

	//when a contract product is created, check the product to see if the field Additional Product is populated,
	//and if so, add that product as a separate line as well
	private static void addAdditionalProducts(){
		if(!(Trigger.isAfter && Trigger.isInsert)){
			return;
		}

		List<Subscription25__Contract_Product__c> iterList = Trigger.new;
		//we still have to populate the price on the new contract products, to do this, first
		//load the pricebook and the pruchase origin from the related contracts, and then load the pricebook entries for
		//the products that we're creating and map them form pricebook to product to pbe
		Set<Id> contractIds = Util_System.collectIdValues(iterList, 'Subscription25__Contract__c');
		Map<Id, Contract> contractMap = new Map<Id, Contract>([
			SELECT Id, Startdate, Subscription25__First_Invoice_Date__c, Pricebook2Id, Purchase_Origin__c, CurrencyIsoCode, Is_Imported__c, AccountId, Account.FinancialDebtorNumber__c
			FROM Contract
			WHERE Id IN :contractIds
		]);

		//load all product details
		Set<Id> prodIds = Util_System.collectIdValues(iterList, 'Subscription25__Product__c');
		Map<Id, Product2> prodMap = new Map<Id, Product2>([
			SELECT Id, Additional_Product__c, Additional_Product__r.Article_Number_Exact__c, Additional_Product__r.Subscription25__Cost_Type__c  FROM Product2 WHERE Id IN :prodIds
		]);

		List<Subscription25__Contract_Product__c> cpsToInsert = new List<Subscription25__Contract_Product__c>();
		Set<Id> addedProductIds = new Set<Id>();
		for(Subscription25__Contract_Product__c cpNew : iterList){
			if((prodMap.get(cpNew.Subscription25__Product__c).Additional_Product__c == null) || (contractMap.get(cpNew.Subscription25__Contract__c).Purchase_Origin__c != 'NEW') || (cpNew.Subscription25__Price__c < 0.01)){
				continue;
			}
			if((prodMap.get(cpNew.Subscription25__Product__c).Additional_Product__r.Subscription25__Cost_Type__c == 'NON_RECURRING') && ((contractMap.get(cpNew.Subscription25__Contract__c).Is_Imported__c) || 
					((contractMap.get(cpNew.Subscription25__Contract__c).Subscription25__First_Invoice_Date__c != null) && 
					(contractMap.get(cpNew.Subscription25__Contract__c).StartDate != contractMap.get(cpNew.Subscription25__Contract__c).Subscription25__First_Invoice_Date__c)))) {
				continue;
			}
			Subscription25__Contract_Product__c cpToInsert = new Subscription25__Contract_Product__c();
			cpToInsert.Parent__c = cpNew.Id;
			if (String.isNotBlank(cpNew.extId__c)) {
				cpToInsert.extId__c = cpNew.extId__c;
				cpToInsert.extId__c += 'a';
			} 
			cpToInsert.Subscription25__Contract__c = cpNew.Subscription25__Contract__c;
			cpToInsert.Subscription25__Product__c = prodMap.get(cpNew.Subscription25__Product__c).Additional_Product__c;
			cpToInsert.Subscription25__Quantity__c = cpNew.Subscription25__Quantity__c;
			cpToInsert.Subscription25__Start_Date__c = cpNew.Subscription25__Start_Date__c;
			cpToInsert.isPrepaid__c = cpNew.isPrepaid__c;
			cpToInsert.Payment_Method__c = cpNew.Payment_Method__c;
			cpToInsert.Payment_Processor_Reference__c = cpNew.Payment_Processor_Reference__c;
			cpToInsert.Payment_Processor_Amount_Gross__c = cpNew.Payment_Processor_Amount_Gross__c;
			cpToInsert.Subscription25__Status__c = 'Draft';
			cpToInsert.DoActivate__c = true;

			if (prodMap.get(cpNew.Subscription25__Product__c).Additional_Product__r.Subscription25__Cost_Type__c != 'NON_RECURRING') {
				cpToInsert.Service_End_Date__c = cpNew.Service_End_Date__c;
				cpToInsert.Subscription25__Termination_Date__c = cpNew.Subscription25__Termination_Date__c;
			} else {
				// if the product is non-recurring, we need to set the termination date to the last day off the month of the start date
				Date contrProdTerminationDate = cpNew.Subscription25__Start_Date__c.addMonths(1).toStartOfMonth() - 1; 
				contrProdTerminationDate = ((cpNew.Subscription25__Termination_Date__c != null) && (cpNew.Subscription25__Termination_Date__c < contrProdTerminationDate))? cpNew.Subscription25__Termination_Date__c : contrProdTerminationDate;
				//cpToInsert.Service_End_Date__c = contrProdTerminationDate;
				//cpToInsert.Subscription25__Termination_Date__c = contrProdTerminationDate;
				cpToInsert.Service_End_Date__c = cpNew.Service_End_Date__c;
				cpToInsert.Subscription25__Termination_Date__c = cpNew.Subscription25__Termination_Date__c;
			}
			
			cpsToInsert.add(cpToInsert);

			addedProductIds.add(cpToInsert.Subscription25__Product__c);
		}

		if(cpsToInsert.size() == 0){
			return;
		}

		List<PricebookEntry> pbes = [SELECT Id, Product2.Subscription25__Cost_Type__c, Product2.IsBalanceSheet__c, Pricebook2Id, UnitPrice FROM PricebookEntry WHERE Product2Id IN :addedProductIds];
		Map<Id, Map<Id, PricebookEntry>> pbeMap = new Map<Id, Map<Id, PricebookEntry>>();
		for(PricebookEntry pbe : pbes){
			if(!pbeMap.containsKey(pbe.Pricebook2Id)){
				pbeMap.put(pbe.Pricebook2Id, new Map<Id, PricebookEntry>());
			}
			pbeMap.get(pbe.Pricebook2Id).put(pbe.Product2Id, pbe);
		}

		//now go over the lines that we want to create again and populate the prices
		for(Subscription25__Contract_Product__c cp : cpsToInsert){
			Id pricebookId = contractMap.get(cp.Subscription25__Contract__c).Pricebook2Id;
			Id productId = cp.Subscription25__Product__c;
			
			// default pricecaluculation
			PricebookEntry pbe = Util_PriceCalculation.getPricebookEntry(
								productId, 
								pricebookId, 
								contractMap.get(cp.Subscription25__Contract__c).CurrencyIsoCode, 
								contractMap.get(cp.Subscription25__Contract__c).accountId, 
								Integer.valueOf(cp.Subscription25__Quantity__c), 
								0.0);


			//System.debug('pbe :' + pbe);
			Decimal price = (pbe != null) ? pbe.SalesPrice__c : 0;
			//system.debug('price : ' + price);
			price *= (pbeMap.get(pricebookId).get(productId).Product2.IsBalanceSheet__c) ? -1 : 1;

			if(pbeMap.get(pricebookId).get(productId).Product2.Subscription25__Cost_Type__c != 'NON_RECURRING'){
				cp.Subscription25__Setup_Cost__c = 0;
				cp.Subscription25__Price__c =  price;
			} else {
				cp.Subscription25__Setup_Cost__c = price;
				cp.Subscription25__Price__c = 0;
			}
		}

		Database.insert(cpsToInsert);

	}
}
