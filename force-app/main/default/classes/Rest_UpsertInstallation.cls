@RestResource(urlMapping='/UpsertInstallation')
global class Rest_UpsertInstallation {
    private static Asset record;

    @HttpPost
    global static Util_Rest.RestResult handleAction() {
        Util_Rest.RestResult result = new Util_Rest.RestResult();
        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, 'RestUpsertInstallation', 'S');// TODO: Set calling system?
        SavePoint savePoint = Database.setSavePoint();

        try {
            Util_Rest.isRestEntry = true;
            //deserialize manually since the incoming installation json does not have a MiInstallation object wrapper.
            String requestBody = RestContext.request.requestBody.toString();
            MiInstallation miInstal = (MiInstallation) JSON.deserialize(requestBody, Rest_UpsertInstallation.MiInstallation.class);
            logger.setSessionRecordExternalId(sessionId, miInstal.id);
            logger.setCallingSystem(sessionId, miInstal.platformId);

            //upsert installation. The Old function adds a installation__c object to SF. This is the old and (still) current way of adding the installations to SF.
            //This will be replaced by Assets. For now both functions are active. The old one should be commented out when it is no longer needed.
            result.addedRecords.add(Rest_UpsertInstallation.upsertMiInstallation(miInstal));

            //if everything went right add the following message and set Success to true.
            result.success = true;
            result.messages.add('Succes: Installation(s) have been added with the following ID: ' + miInstal.id + '.');
        } catch (Exception e) {
            //when an error occurs: rollback the database and add the error messages to the result object, set success to false and clear the AddedRecords since none have been added.
            Database.rollback(savePoint);

            result.success = false;
            result.messages.add('Error: ' + e);
            result.addedRecords.clear();
        }

        Logger.setSessionRecord(sessionId, Rest_UpsertInstallation.record?.Id, Rest_UpsertInstallation.record?.Name);        
        String responseBody = JSON.serialize(result);
        Integer statusCode = result.success ? 200 : 400;
        Logger.finalizeSession(sessionId, responseBody, statusCode);
        Logger.saveAll();

        Util_Rest.isRestEntry = false;

        return result;
    }

    //add a entity as an asset. If everything went right add the record to the result object
    private static Util_Rest.AddedRecord upsertMiInstallation(MiInstallation miInstal){
        if (miInstal.id == null){
            throw new Util_Rest.UpsertException('Installations whitout ID are not allowed.');
        }

        String platformId = (miInstal.platformID != null) ? String.valueOf(miInstal.platformID) : '';
        String extId = miInstal.id + '-in-' + platformId;
        String extIdField = 'extId_' + platformId + '__c';
        String sSOQL;

        Asset inst = new Asset();
        inst.extId__c = extId;
        inst.System_Platform__c = platformId;

        sSOQL = 'SELECT Id FROM Account WHERE ' + extIdField + ' = \'' + miInstal.accountId + '\'';
        List<Account> accs = Database.Query(sSOQL);
        //List<Account> accs = [SELECT Id FROM Account WHERE G25_ExtID_Account__c = :miInstal.accountId];
        if(accs.isEmpty()){
            throw new Util_Rest.UpsertException('No Account found for Installation with ID: ' + miInstal.id);
        }

        inst.AccountId = accs[0].Id;
        inst.RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByName().get('Entity').getRecordTypeId();
        inst.Start_Date__c = miInstal.startDate != null ? DateTime.newInstance(miInstal.startDate * 1000).date() : null;
        inst.End_Date__c = miInstal.endDate != null ? DateTime.newInstance(miInstal.endDate * 1000).date() : null;
        inst.Remarks__c = miInstal.remarks;


        if(miInstal.driverContactId != null){
            sSOQL = 'SELECT Id FROM Contact WHERE ' + extIdField + ' = \'' + miInstal.driverContactId + '\'';
            List<Contact> driver = Database.Query(sSOQL);
            if(!driver.isEmpty()){
                inst.Driver__c = driver[0].Id;
            }
        }

        inst.License_Plate__c = (miInstal.licensePlate != null) ? miInstal.licensePlate.replace('-', '') : '';
        inst.Brand__c = (miInstal.brand != null) ? miInstal.brand : '';
        inst.Model__c = (miInstal.model != null) ? miInstal.model : '';
        inst.Insurance_Company__c = (miInstal.insurerName != null) ? miInstal.insurerName : null;
        inst.Object_Year_of_Manufacture__c = (miInstal.yearOfManufacture != null) ? miInstal.yearOfManufacture : '';
        inst.Chassis_Number__c = (miInstal.chassisNumber != null) ? miInstal.chassisNumber : '';
        inst.Object_Type__c = miInstal.objectTypeID;
        inst.Name = (inst.License_Plate__c != null) ? inst.License_Plate__c : ((inst.Chassis_Number__c != null) ? inst.Chassis_Number__c : (inst.Object_Type__c + ' - Empty License Plate / VIN' ));

        inst.SCM_Certificate__c = miInstal.scmCertificate;
        inst.Hardware_Id__c = miInstal.hardwareId;
        inst.Installation_Date__c = miInstal.installationDate != null ? DateTime.newInstance(miInstal.installationDate * 1000).date() : null;
        inst.Has_Active_Incident__c = miInstal.hasActiveIncident != null ? miInstal.hasActiveIncident : false;



        if(miInstal.dealerContactId != null){
            sSOQL = 'SELECT Id FROM Contact WHERE ' + extIdField + ' = \'' + miInstal.dealerContactId + '\'';
            List<Contact> dealer = Database.Query(sSOQL);
            //List<Contact> dealer = [SELECT Id FROM Contact WHERE G25_ExtId_Contact__c = :miInstal.dealerContactId];
            if(!dealer.isEmpty()){
                inst.Dealer_Contact__c = dealer[0].Id;
            }
        }

        if(miInstal.dealerAccountId != null){
            sSOQL = 'SELECT Id FROM Account WHERE ' + extIdField + ' = \'' + miInstal.dealerAccountId + '\'';
            List<Account> dealerAcc = Database.Query(sSOQL);
            //List<Account> dealerAcc = [SELECT Id FROM Account WHERE G25_ExtID_Account__c = :miInstal.dealerAccountId];
            if(!dealerAcc.isEmpty()){
                inst.Dealer_Account__c = dealerAcc[0].Id;
            }
        }

        inst.Alarm_Contact_Required__c =  miInstal.isAlarmcontactRequired != null ? Boolean.valueOf(miInstal.isAlarmContactRequired) : false;
        //inst.Mi_LastModificationDate__c = miInstal.lastModificationDate != null ? DateTime.newInstance(miInstal.lastModificationDate * 1000) : null;
        inst.Installation_Location_Id__c = miInstal.installationLocationId;
        inst.Remark__c = miInstal.installationRemark;
        // 20211229/Gen25/TRi/ Object-type changed to objecttypeid
        inst.Incident_Detection_Date__c = miInstal.onlineIncidentDetectionDate!= null ? DateTime.newInstance(miInstal.onlineIncidentDetectionDate* 1000).date() : null;
        Rest_UpsertInstallation.setParentAsset(miInstal, inst);
        Rest_UpsertInstallation.setParentContacts(miInstal);


        Database.upsert(inst, Schema.Asset.Fields.extId__c);

        Rest_UpsertInstallation.record = inst;
        
        return Util_Rest.makeAddedRecord('Entity', miInstal.id, inst.Id);
    }

    //account and contact details need to be updated on the related hardware since this information comes with the installation/entity object.
    private static void setParentContacts(MiInstallation miInstal){

        String platformId = (miInstal.platformId != null) ? String.valueOf(miInstal.platformId): '';
        String extId = miInstal.id + '-in-' + platformId;
        String extIdField = 'extId_' + platformId + '__c';
        String extIdHW = miInstal.hardwareId + '-hw-' + platformId;
        String sSOQL;


        Asset hardw = [
            SELECT Id, Name
            FROM Asset
            WHERE extId__c = :extIdHw
            LIMIT 1
        ];

        if(hardw == null){
            throw new Util_Rest.UpsertException('Error: no hardware found with External Id: ' + miInstal.hardwareId);
        }

        if(miInstal.accountId != null){
            sSOQL = 'SELECT Id FROM Account WHERE ' + extIdField + ' = \'' +  miInstal.accountId + '\'';
            List<Account> accs = Database.Query(sSOQL);
            //List<Account> accs = [
            //    SELECT Id
            //    FROM Account
            //    WHERE G25_ExtID_Account__c = :miInstal.accountId
            //];
            if(!accs.isEmpty()){
                hardw.AccountId = accs[0].Id;
            }
        }

        if(miInstal.driverContactId != null){
            sSOQL = 'SELECT Id FROM Contact WHERE ' + extIdField + ' = \'' + miInstal.driverContactId + '\'';
            List<Contact> conts = Database.Query(sSOQL);
            //List<Contact> conts = [SELECT Id FROM Contact WHERE G25_ExtId_Contact__c = :miInstal.driverContactId];
            if(!conts.isEmpty()){
                hardw.ContactId = conts[0].Id;
            }
        }

        Database.update(hardw);
    }

    private static void setParentAsset(MiInstallation miInstal, Asset inst){
        if(String.isNotBlank(miInstal.hardwareId)){
            String extIdHW = miInstal.hardwareId + '-hw-' + inst.System_Platform__c;
            List<Asset> parentAssets = [
                SELECT Id, ExtId_Hardware__c
                FROM Asset
                WHERE extID__c = :extIdHW
            ];
            if (parentAssets.size() == 1){
                inst.ParentId = parentAssets[0].Id;
            }
        }
    }

    //these classes are used for deserializing the incoming JSON file.
    public class MiInstallation {
        public String id;
        public Long platformId;
        public String salesforceId;
        public String accountId;
        public Long startDate;
        public Long endDate;
        public String remarks;
        public String driverContactId;
        public String licensePlate;
        public String brand;
        public String model;
        public String yearOfManufacture;
        public String chassisNumber;
        public String scmCertificate;
        public String hardwareId;
        public Long installationDate;
        public String dealerContactId;
        public String dealerAccountId;
        public String isAlarmContactRequired;
        public Boolean hasActiveIncident;
        public String installationLocationId;
        public String installationRemark;
        public Long onlineIncidentDetectionDate;
        public String objectTypeId;  // replaces objecttype
        public String  insurerName; // Optional name of the insurance company where this vehicle is insured
    }
}