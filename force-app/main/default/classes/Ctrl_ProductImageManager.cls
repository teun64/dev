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
    // DML runs in SYSTEM_MODE, which covers CRUD/FLS/sharing (access to this method is already
    // gated by ps_miProducts). It does NOT cover file ownership: Salesforce enforces ownership on
    // ContentVersion/ContentDocument/ContentDocumentLink DML below the CRUD/FLS/sharing layer, so
    // removeOldFile still fails for a non-owner, non-admin user replacing a file someone else
    // uploaded - see the product-image ContentDocuments, which all need to stay owned by whoever
    // last uploaded them rather than accumulating under one admin user.
    @AuraEnabled
    public static String uploadProductImage(Id productId, String base64Data, String filename, Boolean removeOldFile) {
        if (productId == null) throw new AuraHandledException('productId is required.');
        if (String.isBlank(base64Data)) throw new AuraHandledException('No file data received.');
        if (String.isBlank(filename)) filename = 'product-image';

        try {
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
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
