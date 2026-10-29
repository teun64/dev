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
    // DML runs in SYSTEM_MODE, which covers CRUD/FLS/sharing (access to this method is gated by
    // ps_miProducts / ps_miDealerShopProducts). It does NOT cover file ownership: deleting a
    // ContentDocument someone else uploaded fails for a non-admin user below that layer. So
    // removeOldFile is best effort: when the old file can't be deleted it stays linked, and the new
    // upload still wins because the shop always shows the newest file (Ctrl_DealerShop.getProductImageUrls).
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
                    Database.DeleteResult dr = Database.delete(
                        new ContentDocument(Id = existingLinks[0].ContentDocumentId), false, AccessLevel.SYSTEM_MODE);
                    if (!dr.isSuccess()) {
                        System.debug(LoggingLevel.WARN, 'Old product image kept (not the owner): ' + dr.getErrors());
                    }
                }
            }

            ContentVersion cv = new ContentVersion(
                Title                  = filename,
                PathOnClient           = filename,
                VersionData            = EncodingUtil.base64Decode(base64Data),
                FirstPublishLocationId = productId
            );
            Database.insert(cv, AccessLevel.SYSTEM_MODE);
            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE];

            // The link FirstPublishLocationId creates defaults to InternalUsers visibility, which
            // hides the file from portal users entirely - even Ctrl_DealerShop's SYSTEM_MODE queries
            // then return no ContentDocumentLink/ContentVersion and the shop shows no image.
            List<ContentDocumentLink> newLinks = [
                SELECT Id, Visibility
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :productId
                  AND ContentDocumentId = :cv.ContentDocumentId
                WITH SYSTEM_MODE
            ];
            for (ContentDocumentLink link : newLinks) {
                link.Visibility = 'AllUsers';
            }
            Database.update(newLinks, AccessLevel.SYSTEM_MODE);

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
