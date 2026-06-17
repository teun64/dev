/**
 * Created by Gerbrand Spaans (Gen25) on 19/11/2023.
 * This Queueable is called by Batch_FinancialSystemAccountSync, which is managed by Subs25 Jobs.
 */

 public with sharing class Queue_FinancialSystemAccountSync implements Queueable, Database.AllowsCallouts {
    private static final String FINANCIAL_SYSTEM_SETTING_TIMESTAMP = 'ACCOUNT_SYNC_TIMESTAMP'; // Name of the FinancialSystem Custom Setting to store the timestamp

    private final String paginatedLink; // used for paginated runs
    private final String eventLogGuid; // GUID (External Id) for the main log record
    private final Subscription25__Administration__c admin; // Administration record. Contains config info for the call out.

    // Any keys are added to the select statement sent to FinancialSystem.
    // Any values are then also mapped the account.
    private final Map<String, String> financialSystemFieldNameMapping = new Map<String, String>{
            'Timestamp' => null,
            'Blocked' => 'Is_Blocked__c',
            'ID' => 'FinancialIdAccount__c'
    };

    public Queue_FinancialSystemAccountSync(Subscription25__Administration__c admin, String nextPageUri, String eventGuid) {
        this.admin = admin;
        this.paginatedLink = nextPageUri;
        this.eventLogGuid = eventGuid;
    }

    /**
     * Queueable Execution. Requests a page and re-queues if a next page is present.,
     * @param context Queueable Context provided by the platform
     */
    public void execute(QueueableContext context) {
        if(String.isBlank(this.admin.Subscription25__Twinfield_Company_Code__c)) {
            // No FinancialSystem division code on admin record so no way to perform call-out
            return;
            // throw new Util_System.FinancialSyncException('No exact division code on admin record');
        }

        // prepare logging
        Logger2 log = Logger2.getInstance(this.eventLogGuid);

        String endpointURI = 'callout:' + this.admin.Subscription25__Named_Credential__c;
        Map<String, String> params = new Map<String, String>();

        // Set endpoint. If this is the first callout (nextUrl is blank) than start a new sync. Otherwise, follow the
        // pagination instructions.
        if(String.isBlank(this.paginatedLink)) {
            // append the Account Sync Endpoint to the named credential.
            endpointURI += String.format(Util_FinancialSystem.ACCOUNT_SYNC_ENDPOINT, new List<String>{this.admin.Subscription25__Twinfield_Company_Code__c});
            // only send the params on the first request. After that the pagination contains all needed params already.
            Integer accountTimestamp = Queue_FinancialSystemAccountSync.getAccountSyncTimestamp(this.admin);
            params.put('$select', String.join(this.FinancialSystemFieldNameMapping.keySet(), ','));
            params.put('$filter', 'Timestamp gt ' + accountTimestamp);
            // Add the Query parameters to the endpoint
        } else {
            // strip of the first bit that is already in the Named Credential. //
            endpointURI = this.paginatedLink.substring(this.paginatedLink.indexOf('/api/'));
        }

        // Do the call out
        HttpResponse response = new HttpResponse();
        HttpRequest request = Util_FinancialSystem.getFinancialRequest(endpointURI, null, 'GET', params);
        String sessionGuid = log.startSession(request, 'Sync Accounts for Administration ' + this.admin.Name, 'FinancialSystem');
        try {
            response = Util_FinancialSystem.doFinancialRequest(request, this.admin);
            log.finalizeSession(sessionGuid, response);
        } catch (Exception e) {
            // do exception logging
            log.finalizeSession(sessionGuid, e);
            log.saveAll();
            return;
        }

        String processGuid = log.startProcess('Process Accounts for ' + this.admin.Name, 'S', this.admin);
        try {
            // get the results in a map. Skip the initial container object 'd' altogether.
            Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
            responseMap = (Map<String, Object>)responseMap.get('d');
            List<Object> financialSystemResults = (List<Object>)responseMap.get('results');

            // loop over response items and create Accounts based on the provided field mapping.
            Map<String, Account> financialSystemAccounts = Queue_FinancialSystemAccountSync.getAccountUpdates(financialSystemResults, financialSystemFieldNameMapping);

            // get existing accounts and remove any mapped accounts that do not exist. this is update only
            Queue_FinancialSystemAccountSync.mapToSalesforceAccountsAndRemoveUnknowns(financialSystemAccounts);
            Database.update(financialSystemAccounts.values());

            // store the last timestamp for quicker syncs later.
            if(!financialSystemResults.isEmpty()) {
                Map<String, Object> lastResult = (Map<String, Object>)financialSystemResults[financialSystemResults.size() -1];
                Queue_FinancialSystemAccountSync.saveAccountSyncTimestamp(this.admin, (String)lastResult.get('Timestamp'));
            }
            // check rescheduling
            this.reschedule(responseMap);

            log.finalizeProcess(processGuid, 'All records processed succesfully');
        } catch (Exception e) {
            log.finalizeProcess(processGuid, e);
        }

        // create the logs
        log.saveAll();
    }
    /**
     * Perform Rescheduling check and enqueue the new job if necessary
     * @param responseMap The Full FinancialSystem Response map
     */
    @TestVisible
    private void reschedule(Map<String, Object> responseMap) {
        if (responseMap.containsKey('__next')) {
            Queue_FinancialSystemAccountSync queue = new Queue_FinancialSystemAccountSync(this.admin, (String) responseMap.get('__next'), this.eventLogGuid);
            System.enqueueJob(queue);
        }
    }
    /**
     * Removes all the FinancialSystem Accounts that do not exist in Salesforce (so no inserts) and adds the SF Id for faster
     * updating. Matching is done based on the FinancialSystem Id. The further mapping has already been done so the result is ready for updating.
     * @param accountUpdates Accounts returned from FinancialSystem by ExactId.
     */
    @TestVisible
    private static void mapToSalesforceAccountsAndRemoveUnknowns(Map<String, Account> accountUpdates) {
        Map<String, Id> existingGuidsToSFId = new Map<String, Id>();
        for (Account a : [SELECT Id, FinancialIdAccount__c FROM Account WHERE FinancialIdAccount__c IN :accountUpdates.keySet()]) {
            existingGuidsToSFId.put(a.FinancialIdAccount__c, a.Id);
        }
        for (String financialSystemId : accountUpdates.keySet()) {
            // If FinancialSystemId found in Salesforce, get the account from accountUpdates and set the Id. Then add it to the
            // return list.
            if (existingGuidsToSFId.containsKey(financialSystemId)) {
                // add the account id to the sobject for update speed
                accountUpdates.get(financialSystemId).put('Id', existingGuidsToSFId.get(financialSystemId));
            } else {
                // does not exist in SF, no update please
                accountUpdates.remove(financialSystemId);
            }
        }
    }
    /**
     * Set the values received from FinancialSystem to SF Account records. Takes a list of FinancialSystem Accounts and a mapping object
     * and moves fields from the FinancialSystem result to the Salesforce Account.
     * @param financialSystemResults Filtered list of FinancialSystem Accounts. These records exist in Salesforce and FinancialSystem
     * @param mapping Mapping Object. Contains Key Value pairs {FinancialSystem Source Field -> Salesforce Desitination Field}
     *
     * @return Populated Salesforce Account records for update.
     */
    @TestVisible
    private static Map<String, Account> getAccountUpdates(List<Object> financialSystemResults, Map<String, String> mapping) {
        Map<String, Account> financialSystemAccountValues = new Map<String, Account>();
        for(Object o : financialSystemResults) {
            Map<String, Object> financialSystemObject = (Map<String, Object>)o;
            Account updateAccount = new Account();
            for(String key : mapping.keySet()) {
                if(String.isNotBlank(mapping.get(key))) {
                    updateAccount.put(mapping.get(key), financialSystemObject.get(key));
                }
            }
            financialSystemAccountValues.put((String)financialSystemObject.get('ID'), updateAccount);
        }
        return financialSystemAccountValues;
    }
    /**
     * @param admin The Subscription25 Administration requesting the setting.
     * Get the Exact_Setting__c record that stores the last Account Sync Timestamp. This is used for later syncs to
     * minimize the number of requests.
     * @return The last stored Account Timestamp. Use this for the Exact Account Sync.
     */
    @TestVisible
    private static Integer getAccountSyncTimestamp(Subscription25__Administration__c admin) {
        Exact_Settings__c syncSetting = Queue_FinancialSystemAccountSync.getSetting(admin.Subscription25__Twinfield_Company_Code__c + '_' + Queue_FinancialSystemAccountSync.FINANCIAL_SYSTEM_SETTING_TIMESTAMP);
        return Integer.valueOf(syncSetting.String_Value__c);
    }
    /**
     * @param admin The Subscription25 Administration requesting the setting.
     * Store the time stamp to custom setting for easy retrieval. This is not stored in cache as this is a persistent
     * value.
     * @param timestampValue Value of the timestamp of the last retrieved record.
     */
    @TestVisible
    private static void saveAccountSyncTimestamp(Subscription25__Administration__c admin, String timestampValue) {
        Exact_Settings__c syncSetting = Queue_FinancialSystemAccountSync.getSetting(admin.Subscription25__Twinfield_Company_Code__c + '_' + Queue_FinancialSystemAccountSync.FINANCIAL_SYSTEM_SETTING_TIMESTAMP);
        syncSetting.String_Value__c = timestampValue;
        if(String.isBlank(syncSetting.Id)) {
            Database.insert(syncSetting);
        } else {
            Database.update(syncSetting);
        }
    }
    /**
     * Get Exact_Setting__c Custom setting by name
     * @param settingName Name of the setting
     *
     * @return FinancialSystem Custom Setting Record
     */
    private static Exact_Settings__c getSetting(String settingName) {
        Exact_Settings__c syncSetting = Exact_Settings__c.getInstance(settingName);
        if(syncSetting == null) {
            syncSetting = new Exact_Settings__c(
                    Name = settingName,
                    String_Value__c = '1'
            );
        }
        return syncSetting;
    }
}