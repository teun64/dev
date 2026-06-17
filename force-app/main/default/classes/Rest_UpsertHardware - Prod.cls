@RestResource(urlMapping='/UpsertHardware')
global class Rest_UpsertHardware {
    private static Asset record;

    @HttpPost
    global static Util_Rest.RestResult handleAction() {
        //result is needed for returning a custom object to the sender
        //this object is used by MI to determine which records have been added succesfully to SF.
        Util_Rest.RestResult result = new Util_Rest.RestResult();
        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, 'RestUpsertHardware', 'S');// TODO: Set calling system?
        //String sessionId = logger.startSession(RestContext.request, null, null); 
        SavePoint savePoint = Database.setSavePoint();

        try {
            Util_Rest.isRestEntry = true;
            //deserialize manually since the incoming installation json does not have a miHardware object wrapper.
            String reqBody = RestContext.request.requestBody.toString();
            MiHardware miHardware = (MiHardware) JSON.deserialize(reqBody, Rest_UpsertHardware.MiHardware.class);
            logger.setSessionRecordExternalId(sessionId, miHardware.id);
            logger.setCallingSystem(sessionId, miHardware.platformId);
            
            //upsert hardware
            result.addedRecords.add(upsertMiHardware(miHardware));

            //if everything went right add the following message and set Success to true.
            result.messages.add('Succes: Hardware has been added with the following ID: ' + miHardware.id + '.');
            result.success = true;

            Util_Rest.isRestEntry = false;

        //when an error occurs: rollback the database and add the error messages to the result object, set success to false and clear the AddedRecords since none have been added.
        } catch (Exception e) {
            Database.rollback(savePoint);
            result.messages.add('Error: ' + e + ' ---STACK-- ' + e.getStackTraceString() + '---LINE----' + e.getLineNumber());
            result.addedRecords.clear();
            result.success = false;

            Util_Rest.isRestEntry = false;
        }

        Logger.setSessionRecord(sessionId, Rest_UpsertHardware.record?.Id, Rest_UpsertHardware.record?.Name);
        String responseBody = JSON.serialize(result);
        Integer statusCode = result.success ? 200 : 400;
        Logger.finalizeSession(sessionId, responseBody, statusCode);
        Logger.saveAll();

        return result;
    }

    //add the hardware as an asset to SF. Add the results to the result object if everything went right.
    private static Util_Rest.AddedRecord upsertMiHardware(MiHardware miHardware){
        Asset hardw;
        String platformId = (miHardware.platformId != null) ? String.valueOf(miHardware.platformId): '';
        String extId = miHardware.id + '-hw-' + platformId;
        String extIdField = 'extId_' + platformId + '__c';
        String sSOQL;
        String hardwareTypeId;
        List<Asset> existingHardware = new List<Asset>();
        Boolean hardwareIsNew = false;

        if(miHardware.id == null){
            throw new Util_Rest.UpsertException('Hardware devices whitout an ID are not allowed.');
        } else {
      sSOQL = 'SELECT Id, Name, Status, AccountId, Dealer_Account__c, Sent_For_Delivery__c, First_Installation__c FROM Asset WHERE extId__c = \'' + extId + '\'';
      system.debug(sSOQL);
      existingHardware = Database.query(sSOQL);

      if(existingHardware.size() == 1){
        //System.debug(curAccts[0].Id);
        hardw = existingHardware[0];
      }
    }

        if(hardw == null){
      hardwareIsNew = true;
      hardw = new Asset();
          hardw.RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByName().get('Hardware').getRecordTypeId();
        hardw.extId__c = extId;
    }

        hardw.Name = String.isNotBlanK(miHardware.serial) ? miHardware.serial : (String.isNotBlanK(miHardware.chassisNumber) ? miHardware.chassisNumber : extId);

        if (String.isNotBlank(miHardware.hardwareTypeId)) {
            hardwareTypeId = miHardware.hardwareTypeId + '-hw-' + platformId;

            sSOQL = 'SELECT Id FROM Product2 WHERE ' + extIdField + ' = \'' + miHardware.hardwareTypeId  + '\'';

            //List<Product2> prods = [SELECT Id FROM Product2 WHERE extId__c = :hardwareTypeId];
            List<Product2> prods = Database.Query(sSOQL);
            system.debug(sSOQL);


            if(prods.size() > 0) {
                hardw.Product2Id = prods[0].Id;
            }

            hardw.Hardware_Type__c = Integer.valueOf(miHardware.hardwareTypeId);
        }

        //hardw.extId__c = extId;
        hardw.System_Platform__c = platformId;
        hardw.SerialNumber = miHardware.serial;
        hardw.SCM_Label__c = miHardware.scmLabel;
        hardw.Accessories__c = miHardware.accessories;
        hardw.Current_Firmware_Version__c = miHardware.currentFirmwareVersion;
        hardw.Sim_State__c = miHardware.simState;
        hardw.Vodafone_Base__c = miHardware.simCoverage;
        hardw.Status = miHardware.hardwareStatusId ?? (hardw.Status ?? '0');
        hardw.Hardware_Status__c = miHardware.hardwareStatus;
        hardw.Activationcode__c = miHardware.activationCode;
        hardw.Activationcode_used_on__c = miHardware.activationCodeUsedDate != null ? Datetime.newInstance(miHardware.activationCodeUsedDate * 1000) : null;
        hardw.Activationcode_send_to__c = miHardware.activationCodeCustomerEmail;
        hardw.Chassis_Number__c = miHardware.chassisNumber;
        hardw.License_Plate__c = (miHardware.licensePlate != null) ? miHardware.licensePlate.replace('-', '') : '';
        hardw.Installation_Date__c = miHardware.installationDate != null ? Datetime.newInstance(miHardware.installationDate * 1000) : null;
        hardw.Delivery_Date__c = miHardware.sentForDeliveryDate != null ? Datetime.newInstance(miHardware.sentForDeliveryDate * 1000) : null;
        hardw.Modem__c = miHardware.modem;
        hardw.PCB__c = miHardware.pcb;
        hardw.Bluetooth__c = (miHardware.bluetooth != null) ? miHardware.bluetooth : false;
        hardw.First_Installation_Date__c = miHardware.firstInstallationDate != null ? Datetime.newInstance(miHardware.firstInstallationDate * 1000) : null;
        hardw.Sent_for_Delivery_Type__c = MiHardware.sentForDeliveryType;


        if(miHardware.dealerAccountId != null){
            sSOQL = 'SELECT Id FROM Account WHERE ' + ExtIdField + ' = \'' +  miHardware.dealerAccountId + '\'';
            List<Account> dealerAcc = Database.Query(sSOQL);

            if(!dealerAcc.isEmpty()){
                hardw.Dealer_Account__c = dealerAcc[0].Id;
            }
        }

        if(miHardware.sentForDeliveryAccountId != null){
            sSOQL = 'SELECT Id FROM Account WHERE ' + ExtIdField + ' = \'' + miHardware.sentForDeliveryAccountId + '\'';
            List<Account> sfdAcc = Database.Query(sSOQL);
            //if (miHardware.platformId == 2) {
            //    sfdAcc = [SELECT Id FROM ACCOUNT WHERE extId_2__c = :miHardware.sentForDeliveryAccountId];
            //} else {
            //    sfdAcc = [SELECT Id FROM ACCOUNT WHERE extId_1__c = :miHardware.sentForDeliveryAccountId];
            //}
            if(!sfdAcc.isEmpty()){
                hardw.Sent_For_Delivery__c = sfdAcc[0].Id;
            }
        }

        //hardw.First_Installation__r = (miHardware.firstInstallationAccountId != null) ? new Account(G25_ExtId_Account__c = miHardware.firstInstallationAccountId) : null;

        if(miHardware.firstInstallationAccountId != null){
            sSOQL = 'SELECT Id FROM Account WHERE ' + ExtIdField + ' = \'' + miHardware.firstInstallationAccountId + '\'';
            List<Account> fiAcc = Database.Query(sSOQL);
            if(!fiAcc.isEmpty()){
                hardw.First_Installation__c = fiAcc[0].Id;
            }
        }

        if(miHardware.accountId != null){
            sSOQL = 'SELECT Id FROM Account WHERE ' + ExtIdField + ' = \'' + miHardware.accountId + '\'';
            List<Account> accts = Database.Query(sSOQL);
            if(!accts.isEmpty()){
                hardw.AccountID = accts[0].Id;
            }
        }

        if(hardw.accountId == null) {
            Rest_UpsertHardware.checkAccount(miHardware, hardw);
        }

        if (hardwareIsNew) {
            Database.insert(hardw);
        } else {
            Database.update(hardw);
        }

        Rest_UpsertHardware.record = hardw;        

        //Database.upsert(hardw, Schema.Asset.Fields.extId__c);

        return Util_Rest.makeAddedRecord('Hardware', String.valueOf(miHardware.id), hardw.Id);
    }

    //check if the hardware already has an account. If not hook the account up to the Technocon account since Account and/or contact are required fields on an asset.
    private static void checkAccount(MiHardware miHardware, Asset hardw){
        // 20200706 - TRi - Replaced by check on extId__c = 0
        String extID = miHardware.id + '-hw-' + String.valueOf(miHardware.platformID);
        String extIdField = 'extId_' + String.valueOf(miHardware.platformID) + '__c';
        String sSOQL;

        List<Asset> hw = [SELECT ID, AccountID FROM Asset WHERE extId__c = :extID];

        if(!hw.isEmpty()){
            if (!String.ISBLANK(hw[0].AccountID) && hw[0].AccountID != null) {
                return;
            }
        }

        sSOQL = 'SELECT Id FROM Account WHERE ' + ExtIdField + ' = \'0\' LIMIT 1';
        List<Account> nnAcc = Database.Query(sSOQL);
        if(nnAcc.isEmpty()){
            Account acc = new Account(Name = 'NO-NAME');

            acc.Put(extIdField, '0');

            Database.insert(acc);
            hardw.AccountId = acc.Id;
        } else {
            hardw.AccountId = nnAcc[0].Id;
        }
    }

    //these class is used for deserializing the incoming JSON file.
    public class MiHardware {
        public String id;
        public Long platformId;
        public String salesforceId;
        public String accountId; // the owner of this device, when platforms are only working with devices and not with entities
        public String serial;
        public String scmLabel;
        public String accessories;
        public String currentFirmwareVersion;
        public String simState;
        public String simCoverage;
        public String hardwareTypeId;
        public String hardwareStatus; // operationele status, naar picklist
        public String hardwareStatusId; // 20211117 picklist status id with english translation.
        public String pcb; //20211117 Printplaat
        public Boolean bluetooth; //20211117 bluetooth functionality
        public String modem; //20211117 modem type
        public String dealerAccountId;
        public String activationCode;
        public Long activationCodeUsedDate;
        public String activationCodeCustomerEmail;
        public Long sentForDeliveryDate;
        public Long installationDate;
        public String licensePlate;
        public String chassisNumber;
        public String sentForDeliveryAccountId;
        public Long firstInstallationDate;
        public String firstInstallationAccountId;
        public String sentForDeliveryType; // eigenlijk <> RMA ipv SALES of ""
        public String firstDeliveryAccountId;
        public Long firstDeliveryDate;
        public String firstDeliveryType;
    }
}