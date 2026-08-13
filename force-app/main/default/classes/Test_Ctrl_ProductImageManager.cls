@IsTest(SeeAllData=false)
private class Test_Ctrl_ProductImageManager {

    @TestSetup
    static void makeData() {
        insert new Product2(
            Name                   = 'Test Product Image Upload',
            ProductCode            = 'IMG-TEST-001',
            IsActive               = true,
            Show_In_Dealer_Shop__c = true
        );
    }

    private static String testImageBase64() {
        return EncodingUtil.base64Encode(Blob.valueOf('fake image bytes'));
    }

    @IsTest
    static void testUploadProductImage_createsVersionAndDistribution() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IMG-TEST-001' LIMIT 1];

        String downloadUrl;
        Test.startTest();
        downloadUrl = Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'photo.png', false);
        Test.stopTest();

        System.assertNotEquals(null, downloadUrl, 'A ContentDistribution download URL should be returned');

        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :prod.Id];
        System.assertEquals(1, links.size(), 'FirstPublishLocationId should create exactly one ContentDocumentLink');
    }

    @IsTest
    static void testGetCurrentImageUrl_returnsUploadedUrl() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IMG-TEST-001' LIMIT 1];
        String uploadedUrl = Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'photo.png', false);

        String fetchedUrl;
        Test.startTest();
        fetchedUrl = Ctrl_ProductImageManager.getCurrentImageUrl(prod.Id);
        Test.stopTest();

        System.assertEquals(uploadedUrl, fetchedUrl, 'getCurrentImageUrl should resolve the same distribution URL uploadProductImage returned');
    }

    @IsTest
    static void testUploadProductImage_removeOldFile_replacesInsteadOfAdding() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IMG-TEST-001' LIMIT 1];
        Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'old.png', false);

        Test.startTest();
        Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'new.png', true);
        Test.stopTest();

        List<ContentDocumentLink> links = [SELECT ContentDocument.Title FROM ContentDocumentLink WHERE LinkedEntityId = :prod.Id];
        System.assertEquals(1, links.size(), 'The old file should be removed, leaving only the new one');
        System.assertEquals('new.png', links[0].ContentDocument.Title, 'Remaining file should be the newly uploaded one');
    }

    @IsTest
    static void testUploadProductImage_withoutRemoveOldFile_keepsBoth() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IMG-TEST-001' LIMIT 1];
        Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'first.png', false);

        Test.startTest();
        Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'second.png', false);
        Test.stopTest();

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :prod.Id];
        System.assertEquals(2, linkCount, 'Without removeOldFile, both uploads should stay attached');
    }

    @IsTest
    static void testGetCurrentImageUrl_withTwoLinkedFiles_resolvesToNewest() {
        // Regression: without an explicit order, "first ContentDocumentLink returned" is not
        // reliably the most recently uploaded one - the shop (and this component, after a page
        // refresh) must always resolve to the newest upload, not whichever link the query
        // happens to return first.
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IMG-TEST-001' LIMIT 1];
        Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'old.png', false);
        String newUrl = Ctrl_ProductImageManager.uploadProductImage(prod.Id, testImageBase64(), 'new.png', false);

        String resolvedUrl;
        Test.startTest();
        resolvedUrl = Ctrl_ProductImageManager.getCurrentImageUrl(prod.Id);
        Test.stopTest();

        System.assertEquals(newUrl, resolvedUrl, 'getCurrentImageUrl should resolve to the most recently uploaded image');
    }

    @IsTest
    static void testUploadProductImage_blankBase64_throws() {
        Product2 prod = [SELECT Id FROM Product2 WHERE ProductCode = 'IMG-TEST-001' LIMIT 1];

        Test.startTest();
        try {
            Ctrl_ProductImageManager.uploadProductImage(prod.Id, '', 'photo.png', false);
            System.assert(false, 'Expected an exception for blank file data');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException expected for blank file data');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUploadProductImage_nullProductId_throws() {
        Test.startTest();
        try {
            Ctrl_ProductImageManager.uploadProductImage(null, testImageBase64(), 'photo.png', false);
            System.assert(false, 'Expected an exception for a null productId');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException expected for a null productId');
        }
        Test.stopTest();
    }
}
