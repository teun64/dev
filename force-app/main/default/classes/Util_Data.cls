public with sharing class Util_Data {
    //GET
    public static Opportunity getOpportunityForExactSyncById(Id oppId){
        if(oppId == null){
            throw new DataException('Error: an empty id is passed to Util_Data.getOpportunityForExactSyncById(Id oppId) method. Make sure a valid Id is passed to this method.');
        }

        return [
            SELECT Name
            FROM Opportunity
            WHERE Id = :oppId
        ];
    }

    public static ContentVersion createContentVersion(String name, Blob body) {
        ContentVersion cv = new ContentVersion(
            ContentLocation = 'S', // S = Stored in Salesforce
            PathOnClient = name,
            Title = name,
            VersionData = body
        );
        return cv;
    }
    
    public static ContentDocumentLink createContentDocumentLink(ID contentDocumentID, ID parentID) {
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink(
            ContentDocumentId = contentDocumentID,
            LinkedEntityId = parentID,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        return contentDocumentLink;
    }
    
    private class DataException extends Exception{}
}