public without sharing class Util_Butler {
    public static String signOpportunityOffer(String recordId) {
        if (string.isBlank(recordId)) return null;
        String returnMsg;

        Opportunity curOpp = [SELECT
            Id
            , Name
            , OpportunityNumber__c
            , OfferVersionId__c
            , OfferDocumentId__c
            , OfferDocumentTitle__c
            , OfferSignReady__c
            , Sales_Channel__c
        FROM 
            opportunity 
        WHERE 
            Id = :recordId
        LIMIT 
            1];

        //system.debug(curOpp);

        if (curOpp.OfferSignReady__c) {
            String srtDevName;
            
            if (curOpp.Sales_Channel__c == 'Echoes') {
                srtDevName = 'echoes_Opportunity_1_Signer_Owner_As_Receiver';
            } else {
                srtDevName = 'mi_Opportunity_1_Signer_Owner_As_Receiver';
            }

            list<cadmus_sign2__Sign_request_template__c> signTemplates = new list<cadmus_sign2__Sign_request_template__c> (
                [SELECT
                    Id
                FROM 
                    cadmus_sign2__Sign_request_template__c 
                WHERE 
                    DeveloperName__c = :srtDevName
                LIMIT 
                    1]
            );

            if (signTemplates.size() > 0) {
                try {
                    cadmus_core.DocGenerationWrapper wrapper = new cadmus_core.DocGenerationWrapper(); 
                    wrapper.contentVersionId = curOpp.OfferVersionId__c;
                    wrapper.contentDocumentId = curOpp.OfferDocumentId__c; 
                    wrapper.response = new cadmus_core.CadmusHttpResponse(); 
                    wrapper.response.metadata = new cadmus_core.MetadataWrapper(); 
                    wrapper.response.metadata.targetName = curOpp.OfferDocumentTitle__c; 
                    //Set "wrapper.response.additionaldocs" with a list of other documents you want to add 
                    
                    if (!Test.isRunningTest()) {
                        //system.debug(signTemplates[0].Id);
                        cadmus_sign2.SignButlerClientApi.createAndLaunchSignRequestAsync(signTemplates[0].Id, recordId, wrapper);
                    }

                    returnMsg = 'Success: ' + curOpp.OfferDocumentTitle__c + ' has been successfully added to the signing queue.';
                    
                } catch (Exception e) {
                    returnMsg = 'Error: ' + e.getMessage();
                } 
            } else {
                returnMsg = 'Error: Template ' + srtDevName + ' not found, signing not possible.';
            }

        } else {
            returnMsg = 'Error: This opportunity ' + curOpp.Name + ' is not ready to be signed.';
        }

        returnMsg += ' (' + recordId + ')'; 

        //system.debug(returnMsg);
        return returnMsg;
    }    
    
}