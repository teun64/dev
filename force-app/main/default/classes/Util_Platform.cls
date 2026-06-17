public with sharing class Util_Platform {
	private static final String ACCOUNT_ENDPOINT = 'v1/upsertContractor';
	private static final String ALARMCONTACT_ENDPOINT = 'v1/getAlarmContactsByEntityId';
	private static final String EMAIL_ENDPOINT = 'v1/getMailsByPersonId';
	private static final String INCIDENT_ENDPOINT = 'v1/getIncidentsByEntityId';
	private static final String LOCATION_ENDPOINT = 'v1/getLocationByEntityId';
	private static final String VOUCHER_ENDPOINT = 'v1/getVouchersByContractorId';
	private static AccessLevel runningMode = AccessLevel.SYSTEM_MODE;

	@future(callout=true)
	public static void syncAccountAsync(Id acctId, String platformId){
		Util_Platform.syncAccount(acctId, platformId);
	}	

    public static Map<String, String> syncAccount(Id acctId, String platformId){
		return Util_Platform.syncAccount(acctId, platformId, null);
	}

	public static Map<String, String> syncAccount(Id acctId, String platformId, String logGUID){
		String extIdField = 'extId_' + platformId + '__c';
		String extIdFieldContact = 'extId_' + platformId + '__c';
		String adminFieldContact = 'isAdministrator_' + platformId + '__c';
		String hasDealerTasksFieldContact = 'hasDealerTasks_' + platformId + '__c';
		String deletedFieldContact = 'isDeleted_' + platformId + '__c';
		String visibleFieldContact = 'isVisible_' + platformId + '__c';

		String sSOQL = 'SELECT Id, Name, Exact_Account_Name__c, Short_Name__c, isBusiness__c, isPrivacyMode__c, VAT_Number__c, CoC_Number__c, Payment_Method_Contracts__c'
			+ ', Bank_Account__c, Bank_BIC__c, Bank_Account_Number__c, Bank_Country__c' 
			+ ', FinancialDebtorNumber__c, FinancialDebtorNumberPrevious__c'
			+ ', Reseller_Name__c, Market__c, Sales_Channel__c, Sales_Language__c'
			+ ', FinancialAccountClassification1__c, FinancialAccountClassification2__c, FinancialAccountClassification3__c'
            + ', SBI_Primary_Code__c, SBI_Secondary_Code_1__c, SBI_Secondary_Code_2__c, NumberOfEmployees, NumberOfFulltimeEmployees__c, Is_Blocked__c, IsBankrupt__c'
			+ ', ShippingPostalCode, ShippingCity, ShippingStreet, ShippingCountryCode, Shipping_Email__c, Shipping_Phone__c, Shipping_Name__c'
			+ ', BillingPostalCode, BillingCity, BillingStreet, BillingCountryCode, Billing_Email__c, Billing_Phone__c, Billing_Name__c' 
			+ ',' + extIdField
			+ ', Contact_person__r.FirstName, Contact_person__r.MiddleName, Contact_person__r.LastName, Contact_person__r.Language__c'
			+ ', Contact_person__r.Email, Contact_person__r.Phone, Contact_person__r.MobilePhone, Contact_person__r.OtherPhone'
			+ ', Contact_person__r.Has_Dealertask_access__c, Contact_person__r.Newsletter__c, Contact_person__r.Is_Active__c'
			+ ', Contact_Person__r.' + extIdField
			+ ', Contact_Billing__r.FirstName, Contact_Billing__r.MiddleName, Contact_Billing__r.LastName, Contact_Billing__r.Language__c' 
			+ ', Contact_Billing__r.Email, Contact_Billing__r.Phone, Contact_Billing__r.MobilePhone, Contact_Billing__r.OtherPhone'			
			+ ', Contact_Billing__r.Has_Dealertask_access__c, Contact_Billing__r.Newsletter__c, Contact_Billing__r.Is_Active__c'
			+ ', Contact_Billing__r.' + extIdField			
			+ ', Contact_Shipping__r.FirstName, Contact_Shipping__r.MiddleName, Contact_Shipping__r.LastName, Contact_Shipping__r.Language__c' 
			+ ', Contact_Shipping__r.Email, Contact_Shipping__r.Phone, Contact_Shipping__r.MobilePhone, Contact_Shipping__r.OtherPhone'			
			+ ', Contact_Shipping__r.Has_Dealertask_access__c, Contact_Shipping__r.Newsletter__c, Contact_Shipping__r.Is_Active__c'
			+ ', Contact_Shipping__r.' + extIdField
			+ ', (SELECT Id, ContactId, Roles, Contact.FirstName, Contact.MiddleName, Contact.LastName, Contact.Email, Contact.Phone, Contact.MobilePhone, Contact.OtherPhone, Contact.Language__c, Contact.Newsletter__c, Contact.Has_Dealertask_access__c, Contact.Is_Active__c ' 
			+ ', ' + extIdFieldContact + ', ' + adminFieldContact + ', ' + hasDealerTasksFieldContact + ', ' + deletedFieldContact + ', ' + visibleFieldContact 
			+ ' FROM AccountContactRelations ' 
			+ ' WHERE ((IsActive = true) AND ((isShippingContact__c = true) OR (isInvoiceContact__c = true) OR (isMainContact__c = true))) ORDER BY isMainContact__c DESC, isInvoiceContact__c DESC, isShippingContact__c DESC  LIMIT 1)'
            + ', (SELECT Id, Subscription25__Debtor_Number__c FROM Subscription25__Debtor_Numbers__r)'
			+ ' FROM Account WHERE Id = \'' + acctId + '\' LIMIT 1';

		//System.debug(sSOQL);

        Account syncAcct = Database.Query(sSOQL, Util_Platform.runningMode); 

		//System.debug('Util_Platform.syncAccount - syncAcct : ' + syncAcct);
 		String namedCredential = 'Platform' + platformId;

		Util_Rest.RestResult result;

		Map<String,String> msgs = new Map<String,String>();
		Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', platformId, 'Account', 'sync2Platform', acctId, syncAcct.Exact_Account_Name__c, syncAcct.extId_1__c);
		//Subscription25__Debtor_Number__c curDebNr;

		try {
			//System.debug('Util_Platform.syncAccount - try 1 ' );

			if ((syncAcct.Subscription25__Debtor_Numbers__r.isEmpty()) && (String.isBlank(syncAcct.FinancialDebtorNumber__c))) {
				throw new Util_System.CustomException('Make sure the account has been synced to Exact before synchronising it to MI.');
			}
			if(syncAcct.Contact_person__c == null){
				throw new Util_System.CustomException('Make sure an \'Main (Contact)\' is selected.');
			}
			if(syncAcct.Contact_Billing__c == null){
				throw new Util_System.CustomException('Make sure an \'Billing (Contact)\' Contact is selected.');
			}


			//String endpoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Account_Endpoint'].value__c;
            String endpoint = Util_Platform.ACCOUNT_ENDPOINT;
            String method = 'POST';
			//Rest_UpsertAccount.MiAccount miAcct = new Rest_UpsertAccount.MiAccount(syncAcct, );
					//System.debug('Util_Platform.syncAccount - try 4 ' );
			//System.debug('Util_Platform.syncAccount - syncAcct : ' + syncAcct);
			Rest_UpsertAccount.MiAccount miAcct = new Rest_UpsertAccount.MiAccount(syncAcct);
			//System.debug('Util_Platform.syncAccount - miAcct : ' + miAcct);

			String response = Util_Platform.dorequest(namedCredential, endpoint, null, method, JSON.serialize(miAcct), mainLog.GUID__c, platformId);
			//System.debug('response = ' + response);
			result = (Util_Rest.RestResult)JSON.deserialize(response, Util_Rest.RestResult.class);

			if (result != null) {
				if(syncAcct.get(extIdField) == null){
					syncAcct.put(extIdField, result.addedRecords[0].id);
					Database.update(syncAcct, Util_Platform.runningMode);
				}

				if (result.addedRecords.size() == 1) {
					mainlog.extId__c = result.addedRecords[0].id;
				}
			}

		} catch(Util_Platform.PlatformSyncException e){
			//PlatformSyncException is thrown by Util_Platform.doRequest, happens when The platfrom(s) returns an error (validation or something, platform side)
			//when this happens, this function should continue (so for instance, only address creation fails). The
			//actual error will be logged in the OAuth log, status of the exact log should be WARNING or something
			//the messages should be relayed on to the user
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.put('PlatformSyncException',e.getMessage());
		} catch(Util_System.CustomException e){
			//custom exceptions are thrown by some custom validation (account already synced, etc)
			//should be logged and shown to the user, should stop execution of this function altogether
			//status of the exact log should be ERROR
			//System.debug('Util_Platform.syncAccount - CustomException : ' + e.getMessage() );
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.put('CustomException',e.getMessage());
		} catch(Exception e){
			//all other exceptions are caught and the function does not continue. message to the user should be a generic
			//error message
			mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.put('Exception','Unhandled exception occurred.');
		}
			
		//now save the logs and the tokens
		mainlog.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
		Database.upsert(mainLog, Event_Log__c.GUID__c, Util_Platform.runningMode);

		if (platformId == '1') {
			Util_ConnectionMi.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		} else {
			Util_OAuth.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		}
		
		return msgs;
	}

    public static Map<String, String> getLocation(Id objectId){
		return Util_Platform.getLocation(objectId, null);
	}

	public static Map<String, String> getLocation(Id objectId, String logGUID){
		Map<String,String> msgs = new Map<String,String>();
		Event_Log__c mainLog;
		Util_Rest.RestResult result;
		String extID;
		String platformId = '1';
		String namedCredential;
		String endpoint = Util_Platform.LOCATION_ENDPOINT;
		String method = 'GET';
		String response;

		try {
			Asset ass = [SELECT Id, Name, extId__c FROM Asset WHERE Id = :objectId WITH SYSTEM_MODE];

			if (ass == null) {
				throw new Util_System.CustomException('No Valid Asset found.');
			}

			if (String.isNotBlank(ass.extId__c)) {
				platformId = ass.extId__c.right(1);
				//extID = ass.extId__c.remove('-in-'+platformId);
				extID = (ass.extId__c != null) ? ass.extId__c.left(ass.extId__c.indexOf('-')) : '<noId>';

			} else {
				throw new Util_System.CustomException('No External id fount for asset ('+ass.id+ ').');
			}

			namedCredential = 'Platform' + platformId;
			Map<String, String> params = new Map<String, String>();

			params.put('objectId', extID); 

			mainLog = Util_Event.getLog(logGUID, platformId, 'S', 'Asset', 'getLocation', ass.id, ass.Name, ass.extId__c);

			response = Util_Platform.dorequest(namedCredential, endpoint, params, method, null, mainLog.GUID__c, platformId);
			//System.debug('Util_Platform.getLocation - response : ' + response);

			if (String.isNotBlank(response)) {				
				msgs.put('Response', response);
			}

		} catch(Util_Platform.PlatformSyncException e){
			//PlatformSyncException is thrown by Util_Platform.doRequest, happens when The platfrom(s) returns an error (validation or something, platform side)
			//when this happens, this function should continue (so for instance, only address creation fails). The
			//actual error will be logged in the OAuth log, status of the exact log should be WARNING or something
			//the messages should be relayed on to the user
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.put('PlatformSyncException',e.getMessage());
		} catch(Util_System.CustomException e){
			//custom exceptions are thrown by some custom validation (account already synced, etc)
			//should be logged and shown to the user, should stop execution of this function altogether
			//status of the exact log should be ERROR
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.put('CustomException',e.getMessage());
		} catch(Exception e){
			//all other exceptions are caught and the function does not continue. message to the user should be a generic
			//error message
			mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.put('Exception','Unhandled exception occurred.');
		}
			
		//now save the logs and the tokens
		mainlog.Integration_Status__c = Util_Event.LogEventStatus.PROCESSED.name();
		Database.upsert(mainLog, Event_Log__c.GUID__c, Util_Platform.runningMode);
		if (platformId == '1') {
			Util_ConnectionMi.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		} else {
			Util_OAuth.getInstance(namedCredential, mainLog.GUID__c).saveToken();
		}

		return msgs;
	}

	private static String doRequest(String namedCredential, String endpoint, Map<String, String> params, String method, String requestBody, String logGuid, String platformId) {
		String response = '';
		Boolean wasException = false;

		try {
			HttpResponse res;
			
			if (platformId == '1') {
				Util_ConnectionMi sesMi = Util_ConnectionMi.getInstance(namedCredential, logGuid);
				res = sesMi.doRequest(endpoint, params, method, requestBody);
			} else {
				Util_OAuth sesOAuth = Util_OAuth.getInstance(namedCredential, logGuid);
				res = sesOAuth.doRequest(endpoint, params, method, requestBody);				
			}

			//if the response has status code 204, that means that a PUT was successful, in which case
			//no response body is given. We shouldn't try to actually get the response in that case
			//System.debug('Util_Platform.doRequest - res : ' + res );
			if(res.getStatusCode() == 204){
				return response;
			} else if(res.getStatusCode() != 200){
				throw new PlatformSyncException('Error: ' + res.getBody());
			} else if(String.isBlank(res.getBody().replace('[]',''))){
				throw new PlatformSyncException('Error: ' + 'Received an empty response from MI. No data available.');
			}

			Map<String, Object> dirtyResponse = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
			//System.debug('Util_Platform.doRequest - dirtyResponse : ' + dirtyResponse );
			
			if(dirtyResponse.containsKey('error')){
				//System.debug('Util_Platform.doRequest - dirtyResponse error : ' + dirtyResponse.get('error') );
				Map<String, Object> errMap = (Map<String, Object>)dirtyResponse.get('error');
				Map<String, Object> msgMap = (Map<String, Object>)errMap.get('message');
				throw new PlatformSyncException((String)msgMap.get('value'));
			} else {
				//response = JSON.serialize(dirtyResponse.get('addedRecords'));

				if (JSON.serialize(dirtyResponse.get('success'))=='false') {
					//System.debug('Util_Platform.doRequest - dirtyResponse - success : ' + JSON.serialize(dirtyResponse.get('success')));
					throw new PlatformSyncException(JSON.serialize(dirtyResponse.get('messages')));
				} else {
					response = res.getBody();
				}
			}
			
		} catch(PlatformSyncException platEx){
			//rethrow custom exceptions (these are the errors given by exact), make sure these are handled
			//at some point in the stack, otherwise finally will not execute, refresh tokens will be invalid
			//and general unpleasantness occurs
			wasException = true;
			throw platEx;
		} catch(Util_System.ConnectionException conEx) {
			wasException = true;
			throw conEx;
		} catch(Util_System.CustomException cusEx){
			//rethrow custom exceptions (these are the errors given by exact), make sure these are handled
			//at some point in the stack, otherwise finally will not execute, refresh tokens will be invalid
			//and general unpleasantness occurs
			wasException = true;
			throw cusEx;
		} catch(Exception sysEx){
			wasException = true;
			throw sysEx;
		}
		//System.debug('Util_Platform.doRequest -> response : ' + response );		
		return response;
	}

	public class PlatformSyncException extends Exception {}

}