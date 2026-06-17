public with sharing class Util_OAuth {
	//simpleton stuff
	private static Map<String, Util_OAuth> instances = new Map<String, Util_OAuth>();
	/**
	 * Singleton Constructor. Returns an instance of Util_OAuth, making sure there can be only one instance per context.
	 * @param namedCredential Named Credential that is used for the request
	 * @param eventLogId Id of Event_Log to link the OAuth Log to when created.
	 *
	 * @return The log for the Named Credential Call-out.
	 */
	public static Util_OAuth getInstance(String namedCredential, String eventLogId){
		if(!Util_OAuth.instances.containsKey(namedCredential)){
			Util_OAuth inst = new Util_OAuth(namedCredential);
			Util_OAuth.instances.put(namedCredential, inst);
		}
		Util_OAuth instance = Util_OAuth.instances.get(namedCredential);
		instance.eventLogId = eventLogId; //this will mean that all logs from this call will use the given event log
		return instance;
	}
	/**
	 * Returns any session logs stored as OAuth Log records
	 * @return OAuth_Log__c records logged
	 */
	public List<OAuth_Log__c> getLogs() {
		List<OAuth_Log__c> returnLogs = new List<OAuth_Log__c>();
		for(Util_OAuth.LogWrapper lw : this.logs) {
			returnLogs.add(lw.log);
		}
		return returnLogs;
	}

	private final String executionId;
	private String eventLogId;
	private String namedCredentialName;

	//logging stuff
	private List<Util_OAuth.LogWrapper> logs = new List<Util_OAuth.LogWrapper>();

	//private constructor, because getInstance should be used
	private Util_OAuth(String namedCredential){
		this.executionId = Util_System.generateGUID();
		this.namedCredentialName = namedCredential;
	}
	public void saveToken(){
		//actually only storing logs at this point...
		Map<String, OAuth_Log__c> logsToInsert = new Map<String, OAuth_Log__c>();
		Map<String, List<ContentVersion>> versionsPerLog = new Map<String, List<ContentVersion>>();
		List<ContentVersion> allVersions = new List<ContentVersion>();

		for(Util_OAuth.LogWrapper logWrap : this.logs){
			logsToInsert.put(logWrap.log.GUID__c, logWrap.log);

			List<ContentVersion> versions = logWrap.getContentVersions();
			versionsPerLog.put(logWrap.log.GUID__c, versions);
			allVersions.addAll(versions);
		}

		Database.upsert(logsToInsert.values());
		Database.insert(allVersions);

		//we have to requery the versions to get the contentdocumentids so we can save the contentdocumentlinks
		Map<Id, ContentVersion> versions = new Map<Id, ContentVersion>([SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :allVersions]);
		List<ContentDocumentLink> linksToCreate = new List<ContentDocumentLink>();
		for(String logGuid : versionsPerLog.keySet()){
			for(ContentVersion file : versionsPerLog.get(logGuid)){
				ContentDocumentLink link = new ContentDocumentLink();
				link.LinkedEntityId = logsToInsert.get(logGuid).Id;
				link.ContentDocumentId = versions.get(file.Id).ContentDocumentId;
				link.ShareType = 'I'; //inherit sharing from the linked object
				linksToCreate.add(link);
			}
		}
		Database.insert(linksToCreate);
	}

	//some optional parameters here; addAuth and content, default values are true and null
	public HttpResponse doRequest(String endpoint, Map<String, String> params, String method, String content) {
		return this.doRequest(endpoint, params, method, true, content);
	}

	public HttpResponse doRequest(String endpoint, Map<String, String> params, String method, Boolean addAuth) {
		return this.doRequest(endpoint, params, method, addAuth, null);
	}

	private HttpResponse doRequest(String endpoint, Map<String, String> params, String method, Boolean addAuth, String content) {
		//create the param string, and based on the method append it to the endpoint (GET) or
		//set the param string as the content (POST)
		// Below also adds authentication through Named Credentials
		String paramString = Util_System.getParameterString(params);
		String reqEndpoint = 'callout:' + this.namedCredentialName + '/' + endpoint;
		if (method == 'GET' && !String.isBlank(paramString)) {
			reqEndpoint = reqEndpoint + '?' + paramString;
		}

		reqEndpoint = reqEndpoint.replace(' ', '+');

		//create the request with the appropriate headers, content and endpoint
		HttpRequest request = new HttpRequest();
		request.setTimeout(120000);
		request.setCompressed(false);
		request.setHeader('Cache-Control', 'private');
		request.setHeader('Connection', 'Keep-Alive');
		//if we're sending a payload, set the content length and the request body
		if(!String.isBlank(content)){
			request.setHeader('Content-Length', String.valueOf(content.length()));
			request.setBody(content);
		}

		//set the Accept header and for non-GET requests, also set the content type to JSON.
		request.setHeader('Accept', 'application/json');
		if(method != 'GET'){
			request.setHeader('Content-Type', 'application/json');
			if(!endpoint.contains('DirectDebitMandates')) {
				//20230228 TRi - Addition to retrieve complete posted record back DirectDebitMandates are excluded
				request.setHeader('Prefer', 'return=representation');
			}
		}

		request.setEndpoint(reqEndpoint);
		request.setMethod(method);

		Util_OAuth.LogWrapper log = new Util_OAuth.LogWrapper(this.executionId, this.eventLogId, request);

		// get a response
		HttpResponse response = new Http().send(request);
		//System.debug(response);
		//System.debug(response.getBody());
		log.logResponse(response);
		this.logs.add(log);

		return response;
	}

	private class LogWrapper {
		private OAuth_Log__c log;
		private HttpRequest request;
		private HttpResponse response;

		private LogWrapper(String execId, String eventLogId, HttpRequest req){
			this.log = new OAuth_Log__c(GUID__c = Util_System.generateGUID());
			if(!String.isBlank(eventLogId)){
				this.log.Event_Log__r = new Event_Log__c(GUID__c = eventLogId);
			}
			this.log.Request_Body__c = req.getBody().length() <= OAuth_Log__c.Request_Body__c.getDescribe().length ? req.getBody() : null;
			this.log.Execution_Id__c = execId;
			this.log.Endpoint__c = req.getEndpoint();
			this.log.Method__c = req.getMethod();
			this.request = req;
		}

		private void logResponse(HttpResponse res){
			this.response = res;
			this.log.Response_Body__c = res.getBody().length() <= OAuth_Log__c.Response_Body__c.getDescribe().length ? res.getBody() : null;
			this.log.Status_Code__c = res.getStatusCode();
		}

		private List<ContentVersion> getContentVersions(){
			// GS Only create documents if the relevant body does not fit in the field. This allows for the body to be
			// shown in list views, reports and so on, and this is nice (I think).
			List<ContentVersion> versions = new List<ContentVersion>();
			// Only log in content document if the request size exceeds the field limit
			if(!String.isBlank(this.request.getBody()) && this.request.getBody().length() > OAuth_Log__c.Request_Body__c.getDescribe().length){
				ContentVersion requestFile = new ContentVersion(
						VersionData = Blob.valueOf(this.request.getBody()),
						PathOnClient = 'request-txt',
						Title = 'request.txt'
				);
				versions.add(requestFile);
			}
			// Only log in content document if the response size exceeds the field limit
			if(!String.isBlank(this.response.getBody()) && this.response.getBody().length() > OAuth_Log__c.Response_Body__c.getDescribe().length){
				ContentVersion responseFile = new ContentVersion(
						VersionData = Blob.valueOf(this.response.getBody()),
						PathOnClient = 'response-txt',
						Title = 'response.txt'
				);
				versions.add(responseFile);
			}
			return versions;
		}
	}
}
