public without sharing class Util_Exact {
	//bit of a weird way to do this, but it's quick and it works well
	//ADMIN_CODE is stored in a custom setting, all endpoints need the admin code in them
	//private static final String ADMIN_CODE = Exact_Settings__c.getAll().get('ADMIN_CODE').String_Value__c;

	private static final String ORDER_ENDPOINT = 'api/v1/{0}/salesorder/SalesOrders';
	private static final String ARTICLE_ENDPOINT = 'api/v1/{0}/logistics/Items';
	private static final String ARTICLE_GET_ENDPOINT = 'api/v1/{0}/bulk/Logistics/Items';

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

	// Account sync moved to Util_FinancialSystemAccount (bulk, flag + Batch_FinancialSystemAccountSync).
	// Kept as forwarders until all callers are moved.
	@future
	public static void syncAccountAsync(Id acctId, String logGUID){
		Util_FinancialSystemAccount.flagAccounts(new Set<Id>{ acctId });
	}

	@future
	public static void syncAccountAsync(Id acctId){
		Util_FinancialSystemAccount.flagAccounts(new Set<Id>{ acctId });
	}

	public static List<String> syncAccount(Id acctId){
		return Util_FinancialSystemAccount.syncAccount(acctId);
	}

	public static List<String> syncAccount(Id acctId, String logGUID){
		return Util_FinancialSystemAccount.syncAccount(acctId);
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

			//the financial system ids live on the Account (FinancialIdAccount__c) and the main contact's
			//AccountContactRelation (FinancialIdContact__c), maintained by Util_FinancialSystemAccount.
			//No account / contact in Exact yet: queue the account for its sync and hold the order until then.
			Account orderAcct = [
				SELECT Id, FinancialIdAccount__c, FinancialDebtorNumber__c, Contact_Person__c
				FROM Account WHERE Id = :curOrder.AccountId WITH SYSTEM_MODE
			];
			String exactContactId;
			if (orderAcct.Contact_Person__c != null) {
				for (AccountContactRelation acr : [
						SELECT FinancialIdContact__c FROM AccountContactRelation
						WHERE AccountId = :orderAcct.Id AND ContactId = :orderAcct.Contact_Person__c WITH SYSTEM_MODE LIMIT 1]) {
					exactContactId = acr.FinancialIdContact__c;
				}
			}
			if (String.isBlank(orderAcct.FinancialIdAccount__c) || String.isBlank(orderAcct.FinancialDebtorNumber__c) || String.isBlank(exactContactId)) {
				Util_FinancialSystemAccount.flagAccounts(new Set<Id>{ orderAcct.Id });
				throw new Util_System.CustomException('The account (' + curOrder.Account.Exact_Account_Name__c + ') is not synchronised with Exact yet (debtor number or contact person missing); it is queued for the account sync, the order waits.');
			}
			Subscription25__Debtor_Number__c curDebNr = new Subscription25__Debtor_Number__c(
				Exact_Id__c = orderAcct.FinancialIdAccount__c,
				Exact_Contact_ID__c = exactContactId
			);
			Boolean saveDebtorNumber = false;

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
	// Invoice finalisation moved to Util_FinancialSystem_Invoice; kept as forwarding wrappers until all callers are moved.
	public static List<String> finalizeInvoice(Id invoiceId){
		return Util_FinancialSystem_Invoice.finalizeInvoice(invoiceId);
	}

	public static List<String> finalizeInvoice(Id invoiceId, String logGUID){
		return Util_FinancialSystem_Invoice.finalizeInvoice(invoiceId, logGUID);
	}

	public static List<String> loadInvoiceNumber(Id invoiceid){
		return Util_FinancialSystem_Invoice.loadInvoiceNumber(invoiceid);
	}

	public static List<String> loadInvoiceNumber(Id invoiceid, String logGUID){
		return Util_FinancialSystem_Invoice.loadInvoiceNumber(invoiceid, logGUID);
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
				this.SalesChannel = Util_FinancialSystem.getExactRelationId(admin.Id, 'SC', ord.Sales_Channel__c);
				warehouseId = Util_FinancialSystem.getExactRelationId(admin.Id, 'WH', ord.Sales_Channel__c);
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
}
