@isTest
private class Test_Trigger_ContentDocumentLink {

    private class MergeServiceMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('fake-merged-pdf-bytes'));
            return res;
        }
    }

    private static Subscription25__Invoice__c createFixture(Boolean includeCIIHybridPdf){
        VAT_Code__c vatCode = new VAT_Code__c(
            Internal_Code__c = 'TESTVAT3',
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
        adm.Include_CII_Hybrid_PDF__c = includeCIIHybridPdf;
        Database.insert(adm);

        Account acc = Test_Data.createAccount('CustomerNL', '98765', 'B2B', true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest3', '12.MiTest3', '1-sv-3', 'Subscription', true);
        prd.QuantityUnitOfMeasure = 'Piece(s)';
        Database.update(prd);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('TestVAT3', 21, true, true);
        Subscription25__Administration_Product__c apr = Test_Data.createAdministrationProduct(adm.Id, prd.Id, vatRate.Id, true);

        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', false);
        inv.Subscription25__VAT_Number__c = 'NL987654321B01';
        inv.Subscription25__PDF_Attachment_Name__c = 'invoice-abc.pdf';
        Database.insert(inv);

        Order ord = Test_Data.createOrder(acc.Id, adm.Id, Date.today().addDays(-14), false);
        ord.Subscription25__Invoice__c = inv.Id;
        Database.insert(ord);

        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, false);
        ori.Product2Id = prd.Id;
        ori.Subscription25__VAT_Code__c = 'TESTVAT3';
        Database.insert(ori);

        return inv;
    }

    private static void linkPdf(Id linkedEntityId, String fileName){
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = Blob.valueOf('fake-plain-pdf-bytes');
        Database.insert(cv);

        ContentVersion insertedCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = insertedCv.ContentDocumentId;
        link.LinkedEntityId = linkedEntityId;
        link.ShareType = 'V';
        Database.insert(link);
    }

    @IsTest
    private static void test_triggersOnMatchingPdfLink(){
        Subscription25__Invoice__c inv = createFixture(true);
        Test.setMock(HttpCalloutMock.class, new MergeServiceMock());

        Test.startTest();
        linkPdf(inv.Id, 'invoice-abc.pdf');
        Test.stopTest();

        Subscription25__Invoice__c result = [SELECT CII_Merge_Status__c FROM Subscription25__Invoice__c WHERE Id = :inv.Id];
        System.assertEquals('SUCCESS', result.CII_Merge_Status__c, 'Expected the trigger to enqueue the merge for a matching PDF link');
    }

    @IsTest
    private static void test_doesNotTriggerWhenFlagOff(){
        Subscription25__Invoice__c inv = createFixture(false);

        Test.startTest();
        linkPdf(inv.Id, 'invoice-abc.pdf');
        Test.stopTest();

        Subscription25__Invoice__c result = [SELECT CII_Merge_Status__c FROM Subscription25__Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(null, result.CII_Merge_Status__c, 'Should not merge when Include_CII_Hybrid_PDF__c is false');
    }

    @IsTest
    private static void test_doesNotTriggerOnFilenameMismatch(){
        Subscription25__Invoice__c inv = createFixture(true);

        Test.startTest();
        linkPdf(inv.Id, 'some-other-file.pdf');
        Test.stopTest();

        Subscription25__Invoice__c result = [SELECT CII_Merge_Status__c FROM Subscription25__Invoice__c WHERE Id = :inv.Id];
        System.assertEquals(null, result.CII_Merge_Status__c, 'Should not merge when the linked file is not the invoice\'s own PDF');
    }

    @IsTest
    private static void test_doesNotTriggerForUnrelatedObject(){
        Account acc = Test_Data.createAccount('UnrelatedAccount', '11111', 'B2B', true);

        Test.startTest();
        ContentVersion cv = new ContentVersion();
        cv.Title = 'random-file.pdf';
        cv.PathOnClient = 'random-file.pdf';
        cv.VersionData = Blob.valueOf('unrelated-bytes');
        Database.insert(cv);

        ContentVersion insertedCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = insertedCv.ContentDocumentId;
        link.LinkedEntityId = acc.Id;
        link.ShareType = 'V';
        Database.insert(link);
        Test.stopTest();

        // No assertion needed beyond "this didn't throw" - the trigger must safely ignore
        // ContentDocumentLinks on objects other than Subscription25__Invoice__c.
        System.assert(true);
    }
}
