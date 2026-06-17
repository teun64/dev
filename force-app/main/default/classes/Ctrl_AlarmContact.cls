public with sharing class Ctrl_AlarmContact {
    public List<Ctrl_AlarmContact.AlarmContact> miAlarmCont {get; set;}
    private static Map<String, Asset> extIdToinstallation;
    private static Map<String, Contact> extIdToContact;

    
    public Ctrl_AlarmContact (ApexPages.StandardController stdController) {
        try {
            Asset ass = [SELECT Id, Name, extId__c FROM Asset WHERE Id = :stdController.getId()];
            String extID = (ass.extId__c != null) ? ass.extId__c.remove('-in-1') : '<noId>';
            String endpoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Alarmcontact_Endpoint'].value__c;
            String resBody = Util_RequestButtons.getMiHttpResponse(endpoint, extID);

            this.miAlarmCont = (List<Ctrl_AlarmContact.AlarmContact>) JSON.deserialize(resBody, List<Ctrl_AlarmContact.AlarmContact>.class);
            this.getRelatedInformation();

        } catch (Exception e){
            ApexPages.addMessages(e);
        }
    }

    private void getRelatedInformation(){
        Set<String> extIdinstallation = new Set<String>();
        Set<String> extIdContact = new Set<String>();
        for(Ctrl_AlarmContact.AlarmContact aCont :this.miAlarmCont){
            if(String.isNotBlank(aCont.installationId)){
                extIdinstallation.add(aCont.installationId);
            }
            if(String.isNotBlank(aCont.contactId)){
                extIdContact.add(aCont.contactId);
            }
        }

        this.getinstallationMap(extIdinstallation);
        this.getContactMap(extIdContact);
    }

    private void getinstallationMap(Set<String> extIdinstallation){
        Ctrl_AlarmContact.extIdToinstallation = new Map<String, Asset>();
        for(Asset ass :[SELECT Id, Name, extId__c FROM Asset WHERE extId__c IN :extIdinstallation]){
            Ctrl_AlarmContact.extIdToinstallation.put(ass.extId__c, ass);
        }
    }

    private void getContactMap(Set<String> extIdContact){
        Ctrl_AlarmContact.extIdToContact = new Map<String, Contact>();
        for(Contact cont :[SELECT Id, Name, extId_1__c FROM Contact WHERE extId_1__c IN :extIdContact]){
            Ctrl_AlarmContact.extIdToContact.put(cont.extId_1__c, cont);
        }
    }

    public class AlarmContact {
        public String id {get; private set;}
        public String installationId {get; private set;}
        public String contactId {get; private set;}
        public String firstName {get; private set;}
        public String insertion {get; private set;}
        public String surName {get; private set;}
        public String phoneNumber1 {get; private set;}
        public String phoneNumber2 {get; private set;}
        public String alarmCode {get; private set;}
        public String alarmCodeHint {get; private set;}
        public String sortOrder {get; private set;} 
        public Long lastModificationDate {get; private set;}


        public Asset getinstallationSFId(){
            if(Ctrl_AlarmContact.extIdToinstallation.containsKey(this.installationId)){
                return Ctrl_AlarmContact.extIdToinstallation.get(this.installationId);
            } 

            return new Asset();
        }


        public Contact getContactSFId(){
            if(Ctrl_AlarmContact.extIdToContact.containsKey(this.contactId)){
                return Ctrl_AlarmContact.extIdToContact.get(this.contactId);
            } 

            return new Contact();
        }

        public String getConvertedDate(){
            return this.lastModificationDate != null ? DateTime.newInstance(this.lastModificationDate*1000).format('EEE dd-MM-YYYY HH:mm:ss') : null;
        }
    }
}