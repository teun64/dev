public with sharing class Ctrl_Voucher {

    public List<Ctrl_Voucher.Voucher> voucherList {get; private set;}
    private static Map<String, Contact> extIdToCreatedByCont;
    private static Map<String, Contact> extIdToRequestedByCont;
    private static Map<String, Account> extIdToAccount;
    private static Map<String, Asset> extIdToEntity;
    private static Map<String, Asset> extIdToHardware;

    public Ctrl_Voucher(ApexPages.StandardController stdController) {
        Account acc = [SELECT Id, Name, extId_1__c FROM Account WHERE Id = :stdController.getId()];
        
        try {
            String endpoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Voucher_Endpoint'].value__c;
            String resBody = Util_RequestButtons.getMiHttpResponse(endpoint, acc.extId_1__c);
            
            List<Ctrl_Voucher.Voucher> miVouchers = (List<Ctrl_Voucher.Voucher>) JSON.deserialize(resBody, List<Ctrl_Voucher.Voucher>.class);
            this.voucherList = miVouchers;
            this.voucherList.sort(); //sort the vouchers by createdate; new first.
            this.getRelatedInformation();
        } catch (Exception e){
            ApexPages.addMessages(e);
        }
    }

    private void getRelatedInformation(){
        Set<String> createdByContsExtIds = new Set<String>();
        Set<String> requestedByContsExtIds = new Set<String>();
        Set<String> parentAccountsExtIds = new Set<String>();
        Set<String> entityExtIds = new Set<String>();
        Set<String> hardwareExtIds = new Set<String>();

        for(Ctrl_Voucher.Voucher vouch :this.voucherList){
            if(vouch.createdByContactId != null){
                createdByContsExtIds.add(vouch.createdByContactId);
            }
            if(vouch.requestedByContactId != null){
                requestedByContsExtIds.add(vouch.requestedByContactId);
            }
            if(vouch.accountId != null){
                parentAccountsExtIds.add(vouch.accountId);
            }
            if(vouch.installationId != null){
                entityExtIds.add(vouch.installationId);
            }
            if(vouch.hardwareId != null){
                hardwareExtIds.add(vouch.hardwareId);
            }
        }

        this.getCreatedByContsMap(createdByContsExtIds);
        this.getRequestedByContsMap(requestedByContsExtIds);
        this.getAccountsMap(parentAccountsExtIds);
        this.getEntityMap(entityExtIds);
        this.getHardwareMap(hardwareExtIds);
    }

    private void getCreatedByContsMap(Set<String> createdByContsExtIds){
        List<Contact> createdByConts = [
            SELECT Id, Name, extId_1__c 
            FROM Contact 
            WHERE extId_1__c IN :createdByContsExtIds
        ];
        
        Ctrl_Voucher.extIdToCreatedByCont = new Map<String, Contact>();
        for (Contact cont :createdByConts){
            Ctrl_Voucher.extIdToCreatedByCont.put(cont.extId_1__c, cont);
        }
    }

    private void getRequestedByContsMap(Set<String> requestedByContsExtIds){
        List<Contact> requestedByConts = [
            SELECT Id, Name, extId_1__c 
            FROM Contact 
            WHERE extId_1__c IN :requestedByContsExtIds
        ];
        
        Ctrl_Voucher.extIdToRequestedByCont = new Map<String, Contact>();
        for (Contact cont :requestedByConts){
            Ctrl_Voucher.extIdToCreatedByCont.put(cont.extId_1__c, cont);
        }
    }

    private void getAccountsMap(Set<String> parentAccountsExtIds){
        List<Account> parentAccs = [
            SELECT Id, Name, extId_1__c 
            FROM Account 
            WHERE extId_1__c IN :parentAccountsExtIds
        ];

        Ctrl_Voucher.extIdToAccount = new Map<String, Account>();
        for (Account acc :parentAccs){
            Ctrl_Voucher.extIdToAccount.put(acc.extId_1__c, acc);
        }
    }

    private void getEntityMap(Set<String> entityExtIds){
        List<Asset> entities = [
            SELECT Id, Name, extId__c 
            FROM Asset 
            WHERE extId__c IN :entityExtIds
        ];

        Ctrl_Voucher.extIdToEntity = new Map<String, Asset>();
        for(Asset ass :entities){
            Ctrl_Voucher.extIdToEntity.put(ass.extId__c, ass);
        }
    }

    private void getHardwareMap(Set<String> hardwareExtIds){
        List<Asset> hardware = [
            SELECT Id, Name, extId__c 
            FROM Asset 
            WHERE extId__c IN :hardwareExtIds
        ];

        Ctrl_Voucher.extIdToHardware = new Map<String, Asset>();
        for(Asset ass :hardware){
            Ctrl_Voucher.extIdToHardware.put(ass.extId__c, ass);
        }
    }

    public class Voucher implements Comparable {
        public String id {get; private set;}
        public String voucherCode {get; private set;}
        public Long createDate {get; private set;}
        public Long endDate {get; private set;}
        public String createdByContactId {get; private set;}
        public String requestedByContactId {get; private set;}
        public Double value {get; private set;}
        public Double spent {get; private set;}
        public String accountId {get; private set;}
        public String installationId {get; private set;}
        public String hardwareId {get; private set;}
        public String dealerTaskType {get; private set;}
        public String reason {get; private set;}
        public String status {get; private set;}

        public String getConvertedCreatedDate(){
            return this.createDate != null ? DateTime.newInstance(this.createDate*1000).format('EEE dd-MM-YYYY HH:mm:ss') : null;
        }

        public String getConvertedEndDate(){
            return this.endDate*1000 != null ? DateTime.newInstance(this.endDate*1000).format('EEE dd-MM-YYYY HH:mm:ss') : null;
        }

        public Contact getCreatedByContactSFId(){
            if(Ctrl_Voucher.extIdToCreatedByCont.containsKey(this.createdByContactId)){
                return Ctrl_Voucher.extIdToCreatedByCont.get(this.createdByContactId);
            } 
            
            return new Contact();
        }

        public Contact getRequestedByContactSFId(){
            if(Ctrl_Voucher.extIdToCreatedByCont.containsKey(this.requestedByContactId)){
                return Ctrl_Voucher.extIdToCreatedByCont.get(this.requestedByContactId);
            } 
            
            return new Contact();
        }

        public Account getAccountSFId(){
            String value = this.accountId;
            if(Ctrl_Voucher.extIdToAccount.containsKey(value)){
                return Ctrl_Voucher.extIdToAccount.get(value);
            } 

            return new Account();
        } 

        public Asset getInstallationSFId(){
            String value = this.installationId;
            if(Ctrl_Voucher.extIdToEntity.containsKey(value)){
                return Ctrl_Voucher.extIdToEntity.get(value);
            }

            return new Asset();
        }

        public Asset getHardwareSFId(){
            String value = this.hardwareId;
            if(Ctrl_Voucher.extIdToHardware.containsKey(value)){
                return Ctrl_Voucher.extIdToHardware.get(value);
            }

            return new Asset();
        }

        public Integer compareTo(Object compareTo){
            Ctrl_Voucher.Voucher compareToVoucher = (Ctrl_Voucher.Voucher) compareTo;

            return this.createDate < compareToVoucher.createDate ? 1 : -1;
        }
    }
}