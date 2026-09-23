public with sharing class Ctrl_ProductImageManager {

    @AuraEnabled(cacheable=true)
    public static String getCurrentImageUrl(Id productId) {
        if (productId == null) return null;
        Map<Id, String> urls = Ctrl_DealerShop.getProductImageUrls(new Set<Id>{ productId });
        return urls.get(productId);
    }

    // Uploads a new image for a product with the same settings the Dealer Shop relies on to
    // display it: FirstPublishLocationId links the ContentVersion to the product directly (no
    // separate ContentDocumentLink insert needed), and the ContentDistribution is what makes the
    // file downloadable by guest/portal users - see Ctrl_DealerShop.getProductImageUrls.
    //
    // DML runs in SYSTEM_MODE: access to this method is already gated by ps_miProducts (class
    // access + Product2 CRUD), so it shouldn't additionally require the running user to own or
    // have explicit CRUD/sharing on the underlying ContentVersion/ContentDocument/
    // ContentDistribution records - e.g. replacing an image someone else originally uploaded
    // otherwise fails with INSUFFICIENT_ACCESS_OR_READONLY for any non-admin user.
    @AuraEnabled
    public static String uploadProductImage(Id productId, String base64Data, String filename, Boolean removeOldFile) {
        if (productId == null) throw new AuraHandledException('productId is required.');
        if (String.isBlank(base64Data)) throw new AuraHandledException('No file data received.');
        if (String.isBlank(filename)) filename = 'product-image';

        if (removeOldFile == true) {
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :productId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!existingLinks.isEmpty()) {
                Database.delete(new ContentDocument(Id = existingLinks[0].ContentDocumentId), AccessLevel.SYSTEM_MODE);
            }
        }

        ContentVersion cv = new ContentVersion(
            Title                  = filename,
            PathOnClient           = filename,
            VersionData            = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = productId
        );
        Database.insert(cv, AccessLevel.SYSTEM_MODE);
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE];

        ContentDistribution cd = new ContentDistribution(
            Name                              = filename,
            ContentVersionId                  = cv.Id,
            PreferencesAllowViewInBrowser     = true,
            PreferencesAllowOriginalDownload  = true,
            PreferencesNotifyOnVisit          = false
        );
        Database.insert(cd, AccessLevel.SYSTEM_MODE);

        cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id WITH SYSTEM_MODE];
        return cd.ContentDownloadUrl;
    }
}
