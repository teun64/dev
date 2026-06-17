public with sharing class Ctrl_Location {
	private final Asset record;
    public Ctrl_Location.DeviceLocation location {get; private set;}
    public String jsonCoordinates {get; private set;}
    public Boolean displayLocation {get; private set;}

    public Ctrl_Location(ApexPages.StandardController stdC){
		this.record = (Asset)stdC.getRecord();
	}

    public void callLocation() {
        try {
            /*Asset ass = [SELECT Id, Name, extId__c FROM Asset WHERE Id = :stdController.getId()];
            String extID = (ass.extId__c != null) ? ass.extId__c.remove('-in-1') : '<noId>';
            String endpoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Location_Endpoint'].value__c;
            String resBody = Util_RequestButtons.getMiHttpResponse(endpoint, extID);
            system.debug(resbody);*/

            Map<String, String> responses = Util_Platform.getLocation(record.Id);

		
            //if(String.isBlank(resp)){
            if(responses.size() == 0){
                //ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, resp));
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'No Response received'));

            } else {
                if (responses.containsKey('Response')) {
                    String resBody = responses.get('Response');

                    if (String.isNotBlank(resBody)) {
                        this.location = (Ctrl_Location.deviceLocation) JSON.deserialize(resBody, Ctrl_Location.deviceLocation.class);
                        this.generateJsonCoordinates();
                        this.displayLocation = ((this.location != null) && (String.isNotBlank(this.jsonCoordinates)));
                   
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'Succesfully received a Location'));

                    } else {
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'Succesfully received a Location'));
                        this.displayLocation = false;                       
                    }
                } else {
                    if (responses.containsKey('PlatformSyncException')) {
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'PlatformSyncException' ));
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('PlatformSyncException') ));
                    }
                    if (responses.containsKey('CustomException')) {
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'CustomException' ));
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('CustomException') ));
                    }
                    if (responses.containsKey('Exception')) {
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Exception' ));
                        ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('Exception') ));
                    }               
                }  
            }

        } catch (Exception e){
            ApexPages.addMessages(e);
        }
    }

    private void generateJsonCoordinates(){
        this.jsonCoordinates = '{latitude: ' + (Decimal.valueOf(this.location.latitude) / 1000000) + ',' + 'longitude: ' + (Decimal.valueOf(this.location.longitude) / 1000000) + '}';
    }

    public class deviceLocation {
        public String installationId {get; private set;}
        public Long gpsDate {get; private set;}
        public String latitude {get; private set;}
        public String longitude {get; private set;}
        public Integer speed {get; private set;}
        public Integer direction {get; private set;}
        public Integer altitude {get; private set;}
        public String road {get; private set;}
        public String houseNumber {get; private set;}
        public String postalCode {get; private set;}
        public String city {get; private set;}
        public String country {get; private set;}
    
        public DateTime getConvertedGpsDateTime(){
            return DateTime.newInstance(this.gpsDate*1000);
        }
    } 
}