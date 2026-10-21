/**
 * Merges the EN16931 CII XML (Svc_CIIInvoiceXmlBuilder) into an invoice's existing plain PDF,
 * producing a ZUGFeRD/Factur-X hybrid PDF/A-3, via an external merge service (nc_CIIMergeService).
 *
 * That Named Credential is currently a PLACEHOLDER - no real merge service exists yet. This class
 * is safe to deploy and unit test (via HttpCalloutMock) but cannot succeed against a real invoice
 * until the Named Credential is pointed at an actual service.
 *
 * Runs as a Queueable because it needs to make a callout, which can't happen in the same
 * transaction as the trigger context that finds a new PDF file linked to the invoice
 * (Trigger_ContentDocumentLink.cls). Each MergeRequest carries the exact ContentDocumentId to
 * merge, rather than re-deriving it from Subscription25__PDF_Attachment_Name__c - confirmed via a
 * real acc invoice that regenerating an existing PDF creates a WHOLE SEPARATE ContentDocument with
 * the same filename (not a new ContentVersion under the original one), so filename-based lookup
 * with no ORDER BY could silently pick the wrong document once more than one shares a name.
 */
public without sharing class Svc_CIIHybridPdfMerge implements Queueable, Database.AllowsCallouts {

    public class MergeRequest {
        public Id invoiceId;
        public Id contentDocumentId;

        public MergeRequest(Id invoiceId, Id contentDocumentId) {
            this.invoiceId = invoiceId;
            this.contentDocumentId = contentDocumentId;
        }
    }

    private List<MergeRequest> requests;

    public Svc_CIIHybridPdfMerge(List<MergeRequest> requests) {
        this.requests = requests;
    }

    public void execute(QueueableContext context) {
        List<Subscription25__Invoice__c> invoicesToUpdate = new List<Subscription25__Invoice__c>();

        for (MergeRequest request : this.requests) {
            Subscription25__Invoice__c invoice = new Subscription25__Invoice__c(Id = request.invoiceId);
            try {
                mergeOne(request.invoiceId, request.contentDocumentId);
                invoice.CII_Merge_Status__c = 'SUCCESS';
                invoice.CII_Merge_Error__c = null;
            } catch (Exception e) {
                invoice.CII_Merge_Status__c = 'ERROR';
                invoice.CII_Merge_Error__c = (e.getMessage() + '\n' + e.getStackTraceString()).left(32768);
            }
            invoicesToUpdate.add(invoice);
        }

        if (!invoicesToUpdate.isEmpty()) {
            Database.update(invoicesToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private void mergeOne(Id invoiceId, Id contentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, PathOnClient, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];

        if (versions.isEmpty()) {
            throw new CIIHybridPdfMergeException('No ContentVersion found for ContentDocument ' + contentDocumentId + ' (invoice ' + invoiceId + ').');
        }

        ContentVersion currentVersion = versions[0];
        String ciiXml = Svc_CIIInvoiceXmlBuilder.buildXml(invoiceId);
        Blob mergedPdf = callMergeService(currentVersion.VersionData, ciiXml);

        ContentVersion newVersion = new ContentVersion();
        newVersion.ContentDocumentId = currentVersion.ContentDocumentId;
        newVersion.PathOnClient = currentVersion.PathOnClient;
        newVersion.VersionData = mergedPdf;
        insert newVersion;
    }

    private Blob callMergeService(Blob pdfBytes, String ciiXml) {
        Map<String, Object> payload = new Map<String, Object>{
            'pdfBase64' => EncodingUtil.base64Encode(pdfBytes),
            'ciiXml' => ciiXml
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:nc_CIIMergeService/merge');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new CIIHybridPdfMergeException('Merge service returned ' + res.getStatusCode() + ': ' + res.getBody());
        }

        return res.getBodyAsBlob();
    }

    public class CIIHybridPdfMergeException extends Exception {}
}
