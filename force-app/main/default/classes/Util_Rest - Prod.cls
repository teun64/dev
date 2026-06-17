global with sharing class Util_Rest {
    private static final String ACCOUNT_ENDPOINT = 'https://testtesttesttest.nl/';
    private static final String X_MI_USER = 'TEST';
    private static final String X_MI_NONCE = 'TEST';
    private static final String X_MI_TIMESTAMP = 'TEST'; //epoch
    private static final String X_SIGNATURE = 'TEST';
    private static Rest_UpsertAccount.MiAccount miAccount;
    public static Boolean isRestEntry = false; //used by triggers to determine if an upsert came through the rest endpoint
    public static Boolean isNotRecursive = true;

    //function handles the callout.
    //check the type of the object if account : fill in the account fields. If contact leave the account blank and send the contacts.
    //if the callout returns statuscode = 200 -> update the records that the sync is succesfull
    @future (callout=true)
    public static void handleSend(List<Id> objectIds, String type){
        try {
            if (type == 'Account'){
                Account acc = makeAccount(objectIds[0]);
                Map<Id, Boolean> idToIsSuccess = send(objectIds);
                if(idToIsSuccess.get(objectIds[0])){
                    acc.Synced_To_Mi__c = true;

                    Database.update(acc);
                }
            } else if (type == 'Contact'){
                List<Contact> conts = makeContacts(objectIds);
                Map<Id, Boolean> idToIsSuccess = send(objectIds);
                for(Contact cont :conts){
                    if(idToIsSuccess.get(cont.Id)){
                        cont.Synced_To_Mi__c = true;
                    }
                }

                Database.update(conts);
            }
        } catch (Exception e) {
            throw new Util_Rest.UpsertException('Something went wrong while sending a request to MI.');
            //some error logic?
        }
    }

    public static Account makeAccount(Id accId){
        // 20200409 - Gen25/Tri Payment_Method__c replaced by Exact_Payment_Method__c
        Account accRS = [Select ID, Reseller_Name__c FROM Account WHERE Id = :accId];

        Integer resellerId = Integer.valueOf((accRS.Reseller_Name__c != null) ? accRS.Reseller_Name__c : '0');
        Integer platformId = (resellerId <= 4) ? 4 : resellerId;
        platformId -= 3;
        String extIdField = 'extId_' + String.valueOf(platformId) + '__c';

        String sSOQL = 'SELECT Id, ' + extIdField + ', FinancialDebtorNumber__c, Name, isBusiness__c, VAT_Number__c, '
                + 'CoC_number__c, Payment_Method_Contracts__c, Bank_Account__c, Bank_Account_number__c, Bank_BIC__c, Bank_Country__c,  LastModifiedDate '
                + 'FROM Account '
                + 'WHERE Id = \'' + accId + '\'';

        Account acc = Database.Query(sSOQL);

        miAccount = new Rest_UpsertAccount.MiAccount();
        miAccount.id = String.valueOf(acc.get(extIdField));
        miAccount.debtorNumber = acc.FinancialDebtorNumber__c;
        miAccount.name = acc.Name;
        miAccount.isBusiness = acc.isBusiness__c;
        miAccount.vatNumber = acc.VAT_Number__c;
        miAccount.cocNumber = acc.CoC_number__c;
        // 20200409 - Gen25/Tri Payment_Method__c replaced by Exact_Payment_Method__c and assignment changed from paymentMethod to paymentMethodExactCode
        miAccount.paymentMethodExactCode = acc.Payment_Method_Contracts__c;
        miAccount.bankAccountHolder = acc.Bank_Account__c;
        miAccount.bankAccountNumber = acc.Bank_Account_number__c;
        miAccount.bankAccountBIC = acc.Bank_BIC__c;
        //miAccount.lastModificationDate = (acc.LastModifiedDate.getTime() / 1000); //divide by 1000 to get the epoch time
        miAccount.contactDTOs = new List<Rest_UpsertAccount.MiContact>{};

        return acc;
    }


    public static List<Contact> makeContacts(List<Id> contIds){
        miAccount = new Rest_UpsertAccount.MiAccount();
        miAccount.contactDTOs = new List<Rest_UpsertAccount.MiContact>{};
        List<Contact> conts = [
            SELECT Id, extId_1__c, extId_2__c, extId_3__c, extId_4__c,  extId_6__c, AccountId, LastName, MiddleName,
                FirstName, Email, Title, Phone, Language__c, MailingPostalCode,
                MailingCity, MailingCountry, Is_Active__c, Account_Contact__c, Invoice_Contact__c,
                //20220823 TRi Disabled Sales Contact_1__c
                //Sales_Contact_1__c, Rights__c, Password_Emergency_Centre__c,
                //20221216 Disable Viewing Password Emercency centre
                //Password_Emergency_Centre__c, Last_Password_Reset__c,
                Rights__c, LastModifiedDate
            FROM Contact
            WHERE Id IN :contIds
        ];

        miAccount.contactDTOs = new List<Rest_UpsertAccount.MiContact>{};

        for (Contact cont :conts){
            Rest_UpsertAccount.MiContact miCont = new Rest_UpsertAccount.MiContact();
            miCont.id = (cont.extId_1__c != null) ? cont.extId_1__c : cont.extId_2__c;
            miCont.accountId = cont.AccountId;
            miCont.surName = cont.LastName;
            miCont.insertion = cont.MiddleName;
            miCont.firstName = cont.FirstName;
            miCont.email = cont.Email;
            miCont.function = cont.Title;
            miCont.phoneNumber = cont.Phone;
            miCont.language = cont.Language__c;
            miCont.postalCode = cont.MailingPostalCode;
            miCont.city = cont.MailingCity;
            miCont.country = cont.MailingCountry;
            miCont.isActive = cont.Is_Active__c;
            //miCont.hasAccount = cont.Account_Contact__c;
            //miCont.isInvoiceContact = cont.Invoice_Contact__c;
            //miCont.rights = cont.Rights__c;
            //miCont.alarmCode = cont.Password_Emergency_Centre__c;
            //miCont.lastModificationDate = (cont.LastModifiedDate.getTime() / 1000);

            miAccount.contactDTOs.add(miCont);
        }

        return conts;
    }

    public static AddedRecord makeAddedRecord(String type, String miId, String sfId){
        AddedRecord record = new AddedRecord();
        record.type = type;
        record.id = miId;
        record.sfId = sfId;

        return record;
    }

    private static Map<Id, Boolean> send(List<Id> objectIds){
        Map<Id, Boolean> idToIsSuccess = new Map<Id, Boolean>();

        for(Id objId :objectIds){
            HttpRequest req = new HttpRequest();
            req.setEndpoint(ACCOUNT_ENDPOINT);
            req.setMethod('GET');
            req.setHeader('X-Mi-User', X_MI_USER);
            req.setHeader('X-Mi-Nonce', X_MI_NONCE);
            req.setHeader('X-Mi-Timestamp', X_MI_TIMESTAMP);
            req.setHeader('X-Signature', X_SIGNATURE);

            req.setBody(JSON.serialize(miAccount));

            Http http = new Http();
            HttpResponse res = http.send(req);
            Boolean test = true;
            if (res.getStatusCode() == 200){
                idToIsSuccess.put(objId, true);
            } else if(res.getStatusCode() != 200){
                idToIsSuccess.put(objId, false);
            }
        }

        return idToIsSuccess;
    }

    //check if a trigger already fired or not. Prevents recursive triggers.
    public static Boolean isNotRecursive(){
        if(isNotRecursive){
            isNotRecursive = false;

            return true;
        } else {

            return isNotRecursive;
        }
    }

	public static void checkDebtorNumber (String accountId , String platformId) {
		if (String.isBlank(accountId) || String.isBlank(platformId)) {
			return;
		}

		String extIdField = 'extId_' + platformId + '__c';
		String sSOQL = 'SELECT Id, FinancialDebtorNumber__c, Reseller_Name__c,' 
            + ' Contact_Person__c, Contact_Billing__c, Contact_Shipping__c,' 
            + ' Payment_Method_Contracts__c, Payment_Method_Opportunities__c'
			+ ' FROM Account WHERE '
			+ extIdField
			+ ' = \'' + accountId + '\' LIMIT 1';
		Account acc = Database.Query(sSOQL);

		//we also have to insert a Subscription25 debtor number here
		Integer iReseller = (String.isBlank(acc.Reseller_Name__c)) ? 1 :  Integer.valueOf(acc.Reseller_Name__c);
		Integer adminExternalId = Util_System.getAdminExternalId(iReseller);

		Subscription25__Debtor_Number__c debNr;
		Subscription25__Administration__c admin = Util_System.getAdministration(adminExternalId);

		/*if(String.isBlank(admin.Subscription25__Synchronisation__c)){
			debNr = Util_Rest.createDebtorNumber(acc, admin);
            Database.upsert(debNr, Subscription25__Debtor_Number__c.Subscription25__Composite_Key__c);
		} else {*/

        list<Subscription25__Debtor_Number__c> debtorNumbers = [
            SELECT
                Id
                , Subscription25__Account__c
                , Subscription25__Administration__c
                , Subscription25__Composite_Key__c
                , Subscription25__Debtor_Number__c
                , Exact_Id__c
                , Exact_Contact_Id__c
                , Exact_Bank_Account_ID__c
                , Exact_Mandate_Id__c
                , Exact_Billing_Address_ID__c
            FROM
                Subscription25__Debtor_Number__c
            WHERE
                Subscription25__Account__c = :acc.Id and
                Subscription25__Administration__c = :admin.Id
            LIMIT 1
        ];

        debNr = (debtorNumbers.size() == 1) ? debtorNumbers[0] : null;

        system.debug('debiteur -> ' + debNr);

        if ((String.isBlank(admin.Subscription25__Synchronisation__c)) && (debNr == null)) {
			debNr = Util_Rest.createDebtorNumber(acc, admin);
            // upsert the debtor number (for subscription25)
            Database.upsert(debNr, Subscription25__Debtor_Number__c.Subscription25__Composite_Key__c);
            // bring the debtor number on the account
            // Database.update(new Account(Id = acc.Id, FinancialDebtorNumber__c = debNr.Subscription25__Debtor_Number__c));
            acc.FinancialDebtorNumber__c = debNr.Subscription25__Debtor_Number__c;
            Database.update(acc);
        } else if ((String.isNotBlank(admin.Subscription25__Synchronisation__c)) && ((debNr == null) || String.isBlank(debNr.Exact_Id__c) || (String.isBlank(debNr.Exact_Contact_Id__c) && String.isNotBlank(acc.Contact_Person__c)) || (util_system.requireBankDetails.contains(acc.Payment_Method_Contracts__c) && (String.isBlank(debNr.Exact_Bank_Account_ID__c) || String.isBlank(debNr.Exact_Mandate_ID__c))))) {
            Util_Exact.syncAccountAsync(acc.Id);
        }  
        
	}

    public static Subscription25__Debtor_Number__c createDebtorNumber(Account acc, Subscription25__Administration__c admin) {
        if (String.isBlank(acc.Id) || String.isBlank(admin.Id)) {
            return null;
        }

        String tempDebtorNumber = String.valueOf(acc.Id).left(15).right(9);

        Subscription25__Debtor_Number__c debtorNumber = new Subscription25__Debtor_Number__c(
            Subscription25__Account__c = acc.Id,
            Subscription25__Administration__c = admin.Id,
            Subscription25__Composite_Key__c = '' + acc.Id + admin.Id,
            Subscription25__Debtor_Number__c = String.isBlank(acc.FinancialDebtorNumber__c) ? tempDebtorNumber : acc.FinancialDebtorNumber__c
        );
        return debtorNumber;
    }

    global abstract class AbstractRestResult {
	    public Boolean success;
        public List<String> messages;

        public AbstractRestResult(){
            this.messages = new List<String>{};
        }

        public String getJSONString() {
            return JSON.serialize(this, true);
        }

        public Blob getJSONBlob() {
            return Blob.valueOf(this.getJSONString());
        }
    }

    global class RestResult extends  AbstractRestResult {
        public List<AddedRecord> addedRecords;

        public RestResult(){
            super();
            this.addedRecords = new List<AddedRecord>{};
        }

        public void addError(String error) {
            this.success = false;
            this.messages.add(error);
            this.addedRecords.clear();
        }

        public void addAddedRecord(String type, SObject obj, String extIdField) {
            AddedRecord record = Util_Rest.makeAddedRecord(type, String.valueOf(obj.get(extIdField)), obj.Id);
            this.addedRecords.add(record);
        }

        public void addAddedRecords(String type, List<SObject> objects, String extIdField) {
            for (SObject obj : objects) {
                this.addAddedRecord(type, obj, extIdField);
            }
        }
    }

    global class AddedRecord {
        public String type;
        public String id;
        public String sfId;
    }

    public class UpsertException extends Exception {}
}
