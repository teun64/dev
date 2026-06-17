/**
 * Created by Gerbrand Spaans (Gen25) on 08/12/2023.
 * Allows the getContractProducts LWV to get GoMeddo Subscription25 Contract Products and show these to users that have
 * no license to see these objects.
 * Works from the Account and Contact record.
 */

public without sharing class Ctrl_GetContractProducts {
    @AuraEnabled(Cacheable=true)
    public static List<Object> getContractProducts(String recordId, String contractProductFields) {

        // Input Validation
        if(String.isBlank(recordId)) {
            throw new AuraHandledException('Record Id is required');
        }
        Id rId;
        try{
            rId = (Id)recordId;
        } catch (Exception e) {
            throw new AuraHandledException('A valid record id is required');
        }

        // Build the Query based on the SObject type of the recordId;
        String query = 'SELECT {0} FROM Subscription25__Contract_Product__c ';
        if(rId.getSobjectType() == Account.getSObjectType()) {
            query += 'WHERE Subscription25__Contract__r.AccountId = :recordId';
        } else if(rId.getSobjectType() == Contract.getSObjectType()) {
            query += 'WHERE Subscription25__Contract__c = :recordId';
        } else if(rId.getSobjectType() == Contact.getSObjectType()) {
            List<Contact> contactAccountIds = [SELECT AccountId FROM Contact WHERE Id = :recordId LIMIT 1];
            recordId = contactAccountIds[0].AccountId;
            query += 'WHERE Subscription25__Contract__r.AccountId = :recordId';
        } else {
            throw new AuraHandledException('SObject for the provided record id is not supported.');
        }

        String orderBy = ' ORDER BY Subscription25__Start_Date__c DESC';
        query += orderBy;

        String sSoql = String.format(
                query,
                new List<String>{contractProductFields}
        );

        List<Subscription25__Contract_Product__c> contractProducts;
        try {
            contractProducts = Database.query(sSoql);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to get contract product records');
        }

        // Build the Response Map
        List<Map<String, Object>> contractProductObjects = new List<Map<String, Object>>();
        for(Subscription25__Contract_Product__c cp : contractProducts) {
            Map<String, Object> cpMap = new Map<String, Object>();
            for(String cpField : contractProductFields.split(',')) {
                // Use the full name to populate the map
                String fullName = cpField;
                SObject currentSobject = cp;
                // if the field is a lookup, the sobjects need to be followed. for this it needs to get each lookup and finally lookup the field.
                while(cpField.contains('.')) {
                    // One level deeper. Get the SObject Name, replace the relation postfix if present
                    String sobjectName = cpField.substring(0, cpField.indexOf('.'));
                    // Get the SObject
                    currentSobject = currentSobject.getSObject(sobjectName);
                    // pop the object
                    cpField = cpField.substring(cpField.indexOf('.') + 1);
                }
                cpMap.put(fullName, currentSobject.get(cpField));
            }
            contractProductObjects.add(cpMap);
        }
        return contractProductObjects;
    }
}