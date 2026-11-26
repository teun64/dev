/**
 * Catches every Salesforce File linked to a Subscription25__Invoice__c - the first PDF and any
 * regeneration alike. This exists because Subscription25__PDF_Attachment_Name__c doesn't change on
 * regeneration (confirmed on a real acc invoice: the filename stays identical, a whole separate
 * ContentDocument gets created instead), so a field-change-based Flow can only ever catch the very
 * first PDF - see [[project_en16931_einvoicing_rollout]] memory for the full story.
 */
public class Trigger_ContentDocumentLink {
    public static void run(){
        if(!Trigger.isExecuting){
            return;
        }

        Trigger_ContentDocumentLink.triggerCIIHybridPdfMerge();
    }

    private static void triggerCIIHybridPdfMerge(){
        if(!(Trigger.isAfter && Trigger.isInsert)){
            return;
        }

        List<ContentDocumentLink> iterList = Trigger.new;
        // An invoice can get several files linked in one transaction (PDF + the UBL XML of B2B accounts), so keep all of them.
        Map<Id, List<Id>> contentDocumentIdsByInvoiceId = new Map<Id, List<Id>>();
        Set<Id> allDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : iterList) {
            if (link.LinkedEntityId != null && link.LinkedEntityId.getSObjectType() == Subscription25__Invoice__c.SObjectType) {
                if (!contentDocumentIdsByInvoiceId.containsKey(link.LinkedEntityId)) {
                    contentDocumentIdsByInvoiceId.put(link.LinkedEntityId, new List<Id>());
                }
                contentDocumentIdsByInvoiceId.get(link.LinkedEntityId).add(link.ContentDocumentId);
                allDocumentIds.add(link.ContentDocumentId);
            }
        }

        if (contentDocumentIdsByInvoiceId.isEmpty()) {
            return;
        }

        Map<Id, Subscription25__Invoice__c> invoicesById = new Map<Id, Subscription25__Invoice__c>([
            SELECT Id, Subscription25__PDF_Attachment_Name__c, Subscription25__Invoice_Number__c
            FROM Subscription25__Invoice__c
            WHERE Id IN :contentDocumentIdsByInvoiceId.keySet()
              AND Subscription25__Administration__r.Include_CII_Hybrid_PDF__c = true
            WITH SYSTEM_MODE
        ]);

        if (invoicesById.isEmpty()) {
            return;
        }

        Map<Id, ContentDocument> documentsById = new Map<Id, ContentDocument>([
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :allDocumentIds
        ]);

        List<Svc_CIIHybridPdfMerge.MergeRequest> requests = new List<Svc_CIIHybridPdfMerge.MergeRequest>();
        for (Id invoiceId : invoicesById.keySet()) {
            Subscription25__Invoice__c invoice = invoicesById.get(invoiceId);
            // On the very first PDF the package links the file BEFORE it fills PDF_Attachment_Name__c, so
            // fall back to the name it will set: Invoice_<number>.pdf.
            String expectedName = invoice.Subscription25__PDF_Attachment_Name__c;
            if (String.isBlank(expectedName) && !String.isBlank(invoice.Subscription25__Invoice_Number__c)) {
                expectedName = 'Invoice_' + invoice.Subscription25__Invoice_Number__c + '.pdf';
            }
            if (String.isBlank(expectedName)) {
                continue;
            }

            // Only react to the invoice's own PDF - other files (manual attachments, the UBL XML,
            // unrelated automation) can get linked to an invoice record too, and shouldn't trigger a merge.
            for (Id contentDocumentId : contentDocumentIdsByInvoiceId.get(invoiceId)) {
                ContentDocument doc = documentsById.get(contentDocumentId);
                if (doc != null && doc.Title == expectedName) {
                    requests.add(new Svc_CIIHybridPdfMerge.MergeRequest(invoiceId, contentDocumentId));
                    break;
                }
            }
        }

        if (!requests.isEmpty()) {
            System.enqueueJob(new Svc_CIIHybridPdfMerge(requests));
        }
    }
}
