public with sharing class Ctrl_Incident {
    public List<Ctrl_Incident.Incident> miIncs {get;set;}
    private static Map<String, Asset> extIdToAsset;

    public Ctrl_Incident(ApexPages.StandardController stdController) {
        try {
            Asset ass = [SELECT Id, Name, extId__c FROM Asset WHERE Id = :stdController.getId()];
            String extID = (ass.extId__c != null) ? ass.extId__c.left(ass.extId__c.indexOf('-')) : '<noId>';
            String endpoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Incident_Endpoint'].value__c;
            String resBody = Util_RequestButtons.getMiHttpResponse(endpoint, extID);
        
            this.miIncs = (List<Ctrl_Incident.Incident>) JSON.deserialize(resBody, List<Ctrl_Incident.Incident>.class);
            this.getRelatedInformation();
        } catch (Exception e){
            ApexPages.addMessages(e);
        }
    }

    private void getRelatedInformation(){
        Set<String> assetExtIds = new Set<String>();
        String assetExtId;

        for(Ctrl_Incident.Incident inc :this.miIncs){
            if(inc.installationId != null){
                assetExtId = String.valueOf(inc.installationId)+'-in-1';
                assetExtIds.add(assetExtId);
            } 
            if(inc.hardwareId != null){
                assetExtId = String.valueOf(inc.hardwareId)+'-hw-1';
                assetExtIds.add(assetExtId);
            }
        }

        this.getAssetsMap(assetExtIds);
    }
    
    private void getAssetsMap(Set<String> assetExtIds){
        Ctrl_Incident.extIdToAsset = new Map<String, Asset>();
        for(Asset ass :[SELECT Id, Name, extId__c FROM Asset WHERE extId__c IN :assetExtIds]){
            Ctrl_Incident.extIdToAsset.put(ass.extId__c, ass);
        }
    } 

    public class Incident {
        public Long id {get; private set;}
        public String test {get; private set;}
        public Long hardwareId {get; private set;}
        public Long endDate {get; private set;}
        public String descriptionDetected {get; private set;}
        public String descriptionSolved {get; private set;}
        public Long installationId {get; private set;}
        public Long startDate {get; private set;}


        public Asset getInstallationSFId(){
            String extId = String.valueOf(this.installationId)+'-in-1';
            if(Ctrl_Incident.extIdToAsset.containsKey(extId)){
                return Ctrl_Incident.extIdToAsset.get(extId);
            } 

            return new Asset();
        }

        public Asset getHardwareSFId(){
            String extId = String.valueOf(this.hardwareId)+'-hw-1';
            if(Ctrl_Incident.extIdToAsset.containsKey(extId)){
                return Ctrl_Incident.extIdToAsset.get(extId);
            } 

            return new Asset();
        }

        public String getConvertedStartDate(){
            return this.startDate != null ? DateTime.newInstance(this.startDate*1000).format('EEE dd-MM-YYYY HH:mm:ss') : null;
        }

        public String getConvertedEndDate(){
            return this.endDate != null ? DateTime.newInstance(this.endDate*1000).format('EEE dd-MM-YYYY HH:mm:ss') : null;
        }
    }
}