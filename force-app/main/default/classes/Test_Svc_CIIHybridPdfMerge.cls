@isTest
private class Test_Svc_CIIHybridPdfMerge {

    private class MergeServiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req){
            System.assertEquals('callout:nc_CIIMergeService/merge', req.getEndpoint());
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('fake-merged-pdf-bytes'));
            return res;
        }
    }

    private class MergeServiceErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('merge service exploded');
            return res;
        }
    }

    private static Subscription25__Invoice__c createFixture(){
        VAT_Code__c vatCode = new VAT_Code__c(
            Internal_Code__c = 'TESTVAT2',
            UNCL5305_Category__c = 'S',
            Percentage__c = 21
        );
        Database.insert(vatCode);

        Subscription25__Administration__c adm = Test_Data.createAdministration(false);
        adm.Subscription25__Billing_Name__c = 'Test Administration BV';
        adm.Subscription25__Billing_Street__c = 'Teststraat 1';
        adm.Subscription25__Billing_City__c = 'Amsterdam';
        adm.Subscription25__Billing_Postal_Code__c = '1000 AA';
        adm.Country_Code__c = 'NL';
        adm.CurrencyIsoCode = 'EUR';
        adm.Subscription25__VAT_Number__c = 'NL123456789B01';
        adm.Subscription25__Chamber_Of_Commerce_Number__c = '12345678';
        Database.insert(adm);

        Account acc = Test_Data.createAccount('CustomerNL', '54321', 'B2B', true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest2', '12.MiTest2', '1-sv-2', 'Subscription', true);
        prd.QuantityUnitOfMeasure = 'Piece(s)';
        Database.update(prd);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('TestVAT2', 21, true, true);
        Subscription25__Administration_Product__c apr = Test_Data.createAdministrationProduct(adm.Id, prd.Id, vatRate.Id, true);

        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', false);
        inv.Subscription25__VAT_Number__c = 'NL987654321B01';
        inv.Subscription25__PDF_Attachment_Name__c = 'invoice-123.pdf';
        Database.insert(inv);

        Order ord = Test_Data.createOrder(acc.Id, adm.Id, Date.today().addDays(-14), false);
        ord.Subscription25__Invoice__c = inv.Id;
        Database.insert(ord);

        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, false);
        ori.Product2Id = prd.Id;
        ori.Subscription25__VAT_Code__c = 'TESTVAT2';
        Database.insert(ori);

        return inv;
    }

    private static Id createPdfContentDocument(Id invoiceId, String fileName){
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = Blob.valueOf('fake-plain-pdf-bytes');
        Database.insert(cv);

        ContentVersion insertedCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = insertedCv.ContentDocumentId;
        link.LinkedEntityId = invoiceId;
        link.ShareType = 'V';
        Database.insert(link);

        return insertedCv.ContentDocumentId;
    }

    @IsTest
    private static void test_mergeSuccess(){
        Subscription25__Invoice__c inv = createFixture();
        Id contentDocumentId = createPdfContentDocument(inv.Id, 'invoice-123.pdf');
        Test.setMock(HttpCalloutMock.class, new MergeServiceMock());

        Test.startTest();
        System.enqueueJob(new Svc_CIIHybridPdfMerge(new List<Svc_CIIHybridPdfMerge.MergeRequest>{
            new Svc_CIIHybridPdfMerge.MergeRequest(inv.Id, contentDocumentId)
        }));
        Test.stopTest();

        Subscription25__Invoice__c result = [SELECT CII_Merge_Status__c, CII_Merge_Error__c FROM Subscription25__Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('SUCCESS', result.CII_Merge_Status__c);
        System.assertEquals(null, result.CII_Merge_Error__c);

        List<ContentVersion> versions = [SELECT Id, VersionData FROM ContentVersion WHERE ContentDocumentId = :contentDocumentId];
        System.assertEquals(2, versions.size(), 'Expected the original plain PDF plus the merged hybrid version');

        // CreatedDate can tie within the same test transaction, so resolve "current" the same way
        // Svc_CIIHybridPdfMerge itself does - via ContentDocument.LatestPublishedVersionId - rather
        // than trusting insertion/query order.
        ContentDocument doc = [SELECT LatestPublishedVersion.VersionData FROM ContentDocument WHERE Id = :contentDocumentId];
        System.assertEquals('fake-merged-pdf-bytes', doc.LatestPublishedVersion.VersionData.toString());
    }

    @IsTest
    private static void test_mergeFailure_setsErrorStatus(){
        Subscription25__Invoice__c inv = createFixture();
        Id contentDocumentId = createPdfContentDocument(inv.Id, 'invoice-123.pdf');
        Test.setMock(HttpCalloutMock.class, new MergeServiceErrorMock());

        Test.startTest();
        System.enqueueJob(new Svc_CIIHybridPdfMerge(new List<Svc_CIIHybridPdfMerge.MergeRequest>{
            new Svc_CIIHybridPdfMerge.MergeRequest(inv.Id, contentDocumentId)
        }));
        Test.stopTest();

        Subscription25__Invoice__c result = [SELECT CII_Merge_Status__c, CII_Merge_Error__c FROM Subscription25__Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('ERROR', result.CII_Merge_Status__c);
        System.assert(result.CII_Merge_Error__c.contains('500'), 'Expected the error detail to mention the failing status code');
    }
}
