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
                LIMIT 1
            ];
            if (!existingLinks.isEmpty()) {
                delete new ContentDocument(Id = existingLinks[0].ContentDocumentId);
            }
        }

        ContentVersion cv = new ContentVersion(
            Title                  = filename,
            PathOnClient           = filename,
            VersionData            = EncodingUtil.base64Decode(base64Data),
            FirstPublishLocationId = productId
        );
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];

        ContentDistribution cd = new ContentDistribution(
            Name                              = filename,
            ContentVersionId                  = cv.Id,
            PreferencesAllowViewInBrowser     = true,
            PreferencesAllowOriginalDownload  = true,
            PreferencesNotifyOnVisit          = false
        );
        insert cd;

        cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id];
        return cd.ContentDownloadUrl;
    }
}
