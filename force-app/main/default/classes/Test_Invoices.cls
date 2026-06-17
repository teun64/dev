@IsTest
public with sharing class Test_Invoices {

    @IsTest
    static void testGetInvoiceWithFileSuccess() {
        // Create test invoice
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Product2 prod = Test_Data.createProduct('name', 'code.P', '1-in-1', 'SubscriptionP', true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 10, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vr.Id, true);
        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        opp.Installation_Notes__c = 'installation notes';
        opp.Sales_Contact__c = cont.Id;
        Database.insert(opp);

		Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
		ord.OpportunityId = opp.Id;
        ord.Payment_Method__c = 'I8';
		Database.insert(ord);

		OrderItem oi = Test_Data.createOrderItem(ord.Id, pbe.Id, 100, false);
        oi.Partner_Code__c = '1A2B3C4D5E6F7';
        Database.insert(oi);

        Subscription25__Invoice__c inv = Test_data.createInvoice(admin.Id, acct.Id, 'Draft', true);
        ord.subscription25__invoice__c = inv.id;
        Database.update(ord);

        inv.Subscription25__Status__c = 'Finalized';
        inv.Subscription25__Exact_Order_Number__c = '55';
        inv.Subscription25__Finalized_In_Exact__c = true;
        inv.Subscription25__PDF_Attachment_Name__c = 'Invoice.pdf';
        Database.update(inv);

        // Create file
        ContentVersion ver = new ContentVersion(
            Title          = inv.Subscription25__PDF_Attachment_Name__c,
            PathOnClient   = inv.Subscription25__PDF_Attachment_Name__c,
            VersionData    = Blob.valueOf('Test Content'),
            IsMajorVersion = true
        );
        Database.insert(ver);

        ContentDocument doc = [
            SELECT Id, LatestPublishedVersion.VersionDataUrl
            FROM ContentDocument
            WHERE LatestPublishedVersionId = :ver.Id
        ];
        ContentDocumentLink link = new ContentDocumentLink(
            LinkedEntityId = inv.Id,
            ContentDocumentId = doc.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        Database.insert(link);

        // Set Rest context
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestURI = '/services/apexrest/invoices';
        RestContext.request.httpMethod = 'GET';
        RestContext.request.params.put('platform-id', '1');
        RestContext.request.params.put('account-id', '12');

        Test.startTest();
        Rest_Invoices.getInvoices();
        RestResponse response = RestContext.response;
        Test.stopTest();

        // Assert invoices wrapper
        Assert.isNotNull(response?.responseBody);
        Rest_Invoices.Invoices invoices = (Rest_Invoices.Invoices) JSON.deserialize(response.responseBody.toString(), Rest_Invoices.Invoices.class);
        Assert.isNotNull(invoices);
        String message = invoices.messages.isEmpty() ? 'No message' : invoices.messages.get(0);
        Assert.isNotNull(invoices.success); //isTrue throws internal-server-error when null
        Assert.isTrue(invoices.success, message);
        Assert.areEqual(1, invoices.invoices.size());

        // Assert invoice
        inv = [
            SELECT Id, Amount_Gross__c, Financial_Invoice_Is_Paid__c, Subscription25__Invoice_Number__c, Subscription25__Invoice_Date__c
            FROM Subscription25__Invoice__c
            WHERE Id = :inv.Id
        ];
        Rest_Invoices.Invoice invoice = invoices.invoices.get(0);
        // Assert field mapping done correctly
        Assert.areEqual(inv.Amount_Gross__c, invoice.amountIncVat);
        Assert.areEqual(inv.Financial_Invoice_Is_Paid__c, invoice.isPaid);
        Assert.areEqual(inv.Subscription25__Invoice_Number__c, invoice.invoiceNumber);
        Assert.areEqual(inv.Subscription25__Invoice_Date__c, invoice.invoiceDate);
        //Assert.areEqual(doc.LatestPublishedVersion.VersionDataUrl, invoice.invoiceUrl);
        // Assert test data was correct
        Assert.isNotNull(invoice.amountIncVat);
        Assert.isNotNull(invoice.isPaid);
        Assert.isNotNull(invoice.invoiceNumber);
        Assert.isNotNull(invoice.invoiceDate);
        Assert.isNotNull(invoice.invoiceUrl);
    }

    @IsTest
    static void testGetInvoiceWithoutFileSuccess() {

        // Create test invoice
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Product2 prod = Test_Data.createProduct('name', 'code.P', '1-in-1', 'SubscriptionP', true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prod.Id, 10, true);
        Test_Data.createAdministrationProduct(admin.Id, prod.Id, vr.Id, true);
        Test_Data.createDebtorNumber(admin.Id, acct.Id, true);

        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        opp.Installation_Notes__c = 'installation notes';
        opp.Sales_Contact__c = cont.Id;
        Database.insert(opp);

		Order ord = Test_Data.createOrder(acct.Id, admin.Id, Date.today(), false);
		ord.OpportunityId = opp.Id;
        ord.Payment_Method__c = 'I8';
		Database.insert(ord);

		OrderItem oi = Test_Data.createOrderItem(ord.Id, pbe.Id, 100, false);
        oi.Partner_Code__c = '1A2B3C4D5E6F7';
        Database.insert(oi);

        Subscription25__Invoice__c inv = Test_data.createInvoice(admin.Id, acct.Id, 'Draft', true);
        ord.subscription25__invoice__c = inv.id;
        Database.update(ord);

        inv.Subscription25__Status__c = 'Finalized';
        inv.Subscription25__Exact_Order_Number__c = '55';
        inv.Subscription25__Finalized_In_Exact__c = true;
        inv.Subscription25__PDF_Attachment_Name__c = 'Invoice.pdf';
        Database.update(inv);

        // Set Rest context
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestURI = '/services/apexrest/invoices';
        RestContext.request.httpMethod = 'GET';
        RestContext.request.params.put('platform-id', '1');
        RestContext.request.params.put('account-id', '12');

        Test.startTest();
        Rest_Invoices.getInvoices();
        RestResponse response = RestContext.response;
        Test.stopTest();

        // Assert invoices wrapper
        Rest_Invoices.Invoices invoices = (Rest_Invoices.Invoices) JSON.deserialize(response.responseBody.toString(), Rest_Invoices.Invoices.class);
        Assert.isNotNull(invoices);
        String message = invoices.messages.isEmpty() ? 'No message' : invoices.messages.get(0);
        Assert.isNotNull(invoices.success); //isTrue throws internal-server-error when null
        Assert.isTrue(invoices.success, message);
        Assert.areEqual(1, invoices.invoices.size());

        // Assert invoice
        inv = [
            SELECT Id, Amount_Gross__c, Financial_Invoice_Is_Paid__c, Subscription25__Invoice_Number__c, Subscription25__Invoice_Date__c
            FROM Subscription25__Invoice__c
            WHERE Id = :inv.Id
        ];
        Rest_Invoices.Invoice invoice = invoices.invoices.get(0);
        // Assert field mapping done correctly
        Assert.areEqual(inv.Amount_Gross__c, invoice.amountIncVat);
        Assert.areEqual(inv.Financial_Invoice_Is_Paid__c, invoice.isPaid);
        Assert.areEqual(inv.Subscription25__Invoice_Number__c, invoice.invoiceNumber);
        Assert.areEqual(inv.Subscription25__Invoice_Date__c, invoice.invoiceDate);
        Assert.isNull(invoice.invoiceUrl);
        // Assert test data was correct
        Assert.isNotNull(invoice.amountIncVat);
        Assert.isNotNull(invoice.isPaid);
        Assert.isNotNull(invoice.invoiceNumber);
        Assert.isNotNull(invoice.invoiceDate);
    }

    @IsTest
    static void testGetInvoiceInvalidPlatform() {

        // Set Rest context
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestURI = '/services/apexrest/invoices';
        RestContext.request.httpMethod = 'GET';
        RestContext.request.params.put('account-id', '12');

        Test.startTest();
        Rest_Invoices.getInvoices();
        Test.stopTest();

        // Assert invoices wrapper
        Rest_Invoices.Invoices invoices = (Rest_Invoices.Invoices) JSON.deserialize(RestContext.response.responseBody.toString(), Rest_Invoices.Invoices.class);
        Assert.isNotNull(invoices);
        Assert.isNotNull(invoices.messages);
        Assert.areEqual(1, invoices.messages.size());
        Assert.areEqual('This request should include a platform-id query parameter', invoices.messages.get(0));
        Assert.isNotNull(invoices.success); //isTrue throws internal-server-error when null
        Assert.isFalse(invoices.success);
    }

    @IsTest
    static void testGetInvoiceInvalidAccountId() {

        // Set Rest context
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestURI = '/services/apexrest/invoices';
        RestContext.request.httpMethod = 'GET';
        RestContext.request.params.put('platform-id', '1');

        Test.startTest();
        Rest_Invoices.getInvoices();
        Test.stopTest();

        // Assert invoices wrapper
        Rest_Invoices.Invoices invoices = (Rest_Invoices.Invoices) JSON.deserialize(RestContext.response.responseBody.toString(), Rest_Invoices.Invoices.class);
        Assert.isNotNull(invoices);
        Assert.isNotNull(invoices.messages);
        Assert.areEqual(1, invoices.messages.size());
        Assert.areEqual('This request should include an account-id query parameter', invoices.messages.get(0));
        Assert.isNotNull(invoices.success); //isTrue throws internal-server-error when null
        Assert.isFalse(invoices.success);
    }

    @IsTest
    static void testGetInvoiceInvalidAccount() {
        // Set Rest context
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        RestContext.request.requestURI = '/services/apexrest/invoices';
        RestContext.request.httpMethod = 'GET';
        RestContext.request.params.put('platform-id', '1');
        RestContext.request.params.put('account-id', '12');

        Test.startTest();
        Rest_Invoices.getInvoices();
        Test.stopTest();

        // Assert invoices wrapper
        Rest_Invoices.Invoices invoices = (Rest_Invoices.Invoices) JSON.deserialize(RestContext.response.responseBody.toString(), Rest_Invoices.Invoices.class);
        Assert.isNotNull(invoices);
        Assert.isNotNull(invoices.messages);
        Assert.areEqual(1, invoices.messages.size());
        Assert.areEqual('Account was not found for platform 1 with ID 12', invoices.messages.get(0));
        Assert.isNotNull(invoices.success); //isTrue throws internal-server-error when null
        Assert.isFalse(invoices.success);
    }
}
