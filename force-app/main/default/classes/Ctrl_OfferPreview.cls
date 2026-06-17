public class Ctrl_OfferPreview {
    // Required extension constructor (empty, no-op)
    public Ctrl_OfferPreview(ApexPages.StandardController controller) {}


    //Init the component, check for custom permision to enable signing
    @AuraEnabled
    public static boolean handleInit(Id recordId) {
        Boolean returnValue = String.isBlank(recordId);

        if (!returnValue) {
            // Check User Custom permisson;
            returnValue = !FeatureManagement.checkPermission('cp_miOpportunityEnableSigning');

            if (!returnValue) {
                // Check Opportunity Approval Status
                Opportunity opp = [SELECT Id, Option_Require_Signature__c, Approval_required__c, Approval_Status__c FROM Opportunity WHERE Id =: recordId];

                returnValue = ((!opp.Option_Require_Signature__c) || ((opp.Approval_required__c >= 1) && (opp.Approval_Status__c != 'Approved')));
            }
        }

        return returnValue;
    }

    //save method for saving an id as a Quote PDF
    @AuraEnabled
    public static String handleSave(Id recordId) {
        String returnMsg = '';
        Map<string,String> returnMap;

        returnMap = savePDF(recordId);

        if (returnMap.containsKey('Error')){
            returnMsg = returnMap.get('Error');
        } else {
            returnMsg = returnMap.get('Success');
        }
        
        return returnMsg; 
    }

    @AuraEnabled
    public static String handleSign(Id recordId) {
        String returnMsg = '';
        Map<string,String> returnMap;

        returnMap = savePDF(recordId);

        if (returnMap.containsKey('Error')){
            returnMsg = returnMap.get('Error');
        } else {
            //Do Sign
            returnMsg = returnMap.get('Success');
            returnMsg += Util_Butler.signOpportunityOffer(recordId);
        }
        
        return returnMsg;  
    }

    public static map<string,string> savePDF(Id recordId) {
        PageReference curPage = Page.OfferPDF;
        curPage.getParameters().put('id', recordId);

        Opportunity curOpp = [SELECT
                                    Id
                                    , Name
                                    , OpportunityNumber__c
                                    , OfferVersionId__c
                                    , OfferDocumentId__c
                                    , OfferDocumentTitle__c
                                FROM 
                                    opportunity 
                                WHERE 
                                    Id = :recordId
                                LIMIT 
                                    1];

        Datetime offerDate = Datetime.now();

        String docName = 'O_' + offerDate.format('yyyyMMdd');

        if (curOpp.OpportunityNumber__c != null) {
            docName += '_' + curOpp.OpportunityNumber__c;
        }

        if (curOpp.Name != null) {
            docName += ' - ' + curOpp.Name;
        }

        Map<String,String> returnMap;

        try {
            Blob pdfBody = Test.isRunningTest() ? Blob.valueOf('test') : curPage.getContentAsPDF();
        
            returnMap = Ctrl_OfferPreview.createFile(pdfBody, recordId, docName);

            if (returnMap.containsKey('Success')) {
                curOpp.OfferDocumentId__c = returnMap.containsKey('contentDocumentId') ? returnMap.get('contentDocumentId') : null;
                curOpp.OfferDocumentTitle__c = returnMap.containsKey('contentDocumentTitle') ? returnMap.get('contentDocumentTitle') : null;
                curOpp.OfferVersionId__c = returnMap.containsKey('contentVersionId') ? returnMap.get('contentVersionId') : null;

                Database.update(curopp);
            }

        } catch (Exception e) {
            returnMap = new Map<String,String>();
            returnMap.put('Error', 'Error: ' + e.getMessage());
        }        

        return returnMap;               
    }

    private static map<string, string> createFile(Blob pdfBody, Id parentId, String curName) {
        map<string, string> returnMap = new map<string,string>();

        Savepoint savePnt = Database.setSavePoint();
        try {
            ContentVersion contentVersion = Ctrl_OfferPreview.createContentVersion(Util_System.sanitizeFileName(curName) + '.pdf', pdfBody);
            Database.insert(contentVersion);
            
            ContentVersion newContentVersion = [SELECT ID, ContentDocumentId, Title FROM ContentVersion WHERE ID = :contentVersion.ID];
            
            ContentDocumentLink contentDocumentLink = Ctrl_OfferPreview.createContentDocumentLink(newContentVersion.ContentDocumentId, parentId);
            Database.insert(contentDocumentLink);

            returnMap.put('contentVersionId',newContentVersion.Id);
            returnMap.put('contentDocumentId',newContentVersion.ContentDocumentId);
            returnMap.put('contentDocumentTitle',newContentVersion.Title);
            returnMap.put('contentLinkId',contentDocumentLink.Id);

            //finally add the succes message            
            returnMap.put('Success','Succesfully added a the PDF ' + newContentVersion.Title +  ' with Id: ' + newContentVersion.ContentDocumentId + ' on this opportunity.');

        } catch (Exception e) {
            Database.rollback(savePnt);
            returnMap.put('Error', 'Error: ' + e.getMessage());
        }

        //system.debug(returnMap);
        return returnMap;
    }
    
    private static ContentVersion createContentVersion(String name, Blob body) {
        ContentVersion contentVersion = new ContentVersion(
            ContentLocation = 'S', // S = Stored in Salesforce
            PathOnClient = name,
            Title = name,
            VersionData = body
        );

        return contentVersion;
    }
    
    private static ContentDocumentLink createContentDocumentLink(Id contentDocumentId, Id parentId) {
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = parentId,
            ShareType = 'V',
            Visibility = 'InternalUsers'
        );

        return contentDocumentLink;
    }      
}