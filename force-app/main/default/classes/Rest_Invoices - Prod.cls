@RestResource(UrlMapping='/invoices')
global with sharing class Rest_Invoices {

    private static final Integer MAX_AGE_IN_MONTHS = 24;

    /**
     * Get invoices by platform
     * Example url: /services/invoices?platform-id=1&account-id=some-external-platform-account-id
     */
	@HttpGet
	global static void getInvoices() {

        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, 'RestInvoices', null); 
		Savepoint savePoint = Database.setSavepoint();

        Rest_Invoices.Invoices responseObj = new Rest_Invoices.Invoices();
		try {
            // Verify params
            if (!RestContext.request.params.containsKey('platform-id')) {
                throw new Util_System.CustomException('This request should include a platform-id query parameter');
            }
            if (!RestContext.request.params.containsKey('account-id')) {
                throw new Util_System.CustomException('This request should include an account-id query parameter');
            }

            // Parse params
            String accountId = String.valueOf(RestContext.request.params.get('account-id'));
            Long platformId = Long.valueOf(RestContext.request.params.get('platform-id'));
            logger.setCallingSystem(sessionId, String.valueOf(platformId));
            String platformIdField = Util_System.getPlatformIdField(platformId);

            // Query data and set results
            Account acc = Rest_Invoices.queryAccount(platformIdField, accountId);

            if (acc == null) {
                throw new Util_System.CustomException(String.format('Account was not found for platform {0} with ID {1}', new List<String> {
                    String.valueOf(platformId),
                    accountId
                }));
            }

            List<Subscription25__Invoice__c> invoices = Rest_Invoices.queryInvoices(acc);
            Map<Id, ContentDocument> fileMap = Rest_Invoices.queryInvoiceFiles(invoices);
            responseObj.setInvoices(invoices, fileMap);
            responseObj.success = true;

		} catch (Exception e) {
            // Rollback probably not needed, but just in case
			Database.rollback(savePoint);

            // Set error
			responseObj.messages.add(e.getMessage());
			responseObj.success = false;
		}
        RestContext.response.responseBody = responseObj.getJSONBlob();

        // Finish logging
        Logger.finalizeSession(sessionId, RestContext.response);
        Logger.saveAll();
    }

    private static Account queryAccount(String platformIdField, String accountId) {
        accountId = String.escapeSingleQuotes(accountId);
        String sSOQL = 'SELECT Id'
            + ' FROM Account'
            + ' WHERE {0} = :accountId'
            + ' LIMIT 1';
        sSOQL = String.format(sSOQL, new List<String> { platformIdField});

        List<Account> accounts = Database.query(sSOQL);
        Account acc = !accounts.isEmpty()
            ? accounts.get(0)
            : null;

        return acc;
    }

    private static List<Subscription25__Invoice__c> queryInvoices(Account acc) {
        Date since = Date.today().addMonths(-Rest_Invoices.MAX_AGE_IN_MONTHS);

        List<Subscription25__Invoice__c> invoices = [
            SELECT Id, Name, Subscription25__Invoice_Number__c, Subscription25__Invoice_Date__c, Amount_Gross__c, Financial_Invoice_Is_Paid__c, Subscription25__PDF_Attachment_Name__c
            FROM Subscription25__Invoice__c
            WHERE Subscription25__Account__c = :acc.Id
                AND Subscription25__Invoice_Number__c != null
                AND Subscription25__Status__c = 'Finalized'
                AND Invoice_Printed_In_Exact__c = true
                AND Subscription25__Invoice_Date__c >= :since
        ];
        return invoices;
    }

    public static Map<Id, ContentDocument> queryInvoiceFiles(List<Subscription25__Invoice__c> invoices) {
        if (invoices.isEmpty()) {
            return new Map<Id, ContentDocument>();
        }
        Set<Id> invoiceIds = Util_System.collectIdValues(invoices, 'Id');
        Set<String> fileNames = Util_System.collectStringValues(invoices, 'Subscription25__PDF_Attachment_Name__c');

        Map<Id, ContentDocument> documentByInvoiceId = new Map<Id, ContentDocument>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocument.Id, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :invoiceIds
                AND ContentDocument.LatestPublishedVersion.Title IN :fileNames
        ]) {
            documentByInvoiceId.put(link.LinkedEntityId, link.ContentDocument);
        }
        return documentByInvoiceId;
    }

    @TestVisible
    private class Invoices extends Util_Rest.AbstractRestResult {
        public List<Rest_Invoices.Invoice> invoices;

        public void setInvoices(List<Subscription25__Invoice__c> sub25Invoices, Map<Id, ContentDocument> fileMap) {
            this.invoices = new List<Rest_Invoices.Invoice>();

            for (Subscription25__Invoice__c sub25Invoice : sub25Invoices) {
                Rest_Invoices.Invoice invoice = new Rest_Invoices.Invoice(sub25Invoice);
                invoice.setUrl(fileMap.get(sub25Invoice.Id));
                this.invoices.add(invoice);
            }
        }
    }

    @TestVisible
    private class Invoice {
        public String invoiceNumber;
        public String invoiceUrl;
        public Date invoiceDate;
        public Decimal amountIncVat;
        public Boolean isPaid;

        public Invoice(Subscription25__Invoice__c sub25Invoice) {
            this.invoiceNumber = sub25Invoice.Subscription25__Invoice_Number__c;
            this.invoiceDate = sub25Invoice.Subscription25__Invoice_Date__c;
            this.amountIncVat = sub25Invoice.Amount_Gross__c;
            this.isPaid = sub25Invoice.Financial_Invoice_Is_Paid__c;
        }

        public void setUrl(ContentDocument doc) {
            if (doc?.LatestPublishedVersionId == null) {
                return;
            }
            this.invoiceUrl = String.format('{0}/services/data/v44.0/sobjects/ContentVersion/{1}/VersionData', new List<String> {
                URL.getOrgDomainURL().toExternalForm(),
                doc.LatestPublishedVersionId
            });
        }
    }
}
