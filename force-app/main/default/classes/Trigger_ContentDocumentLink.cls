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
        Map<Id, Id> contentDocumentIdByInvoiceId = new Map<Id, Id>();
        for (ContentDocumentLink link : iterList) {
            if (link.LinkedEntityId != null && link.LinkedEntityId.getSObjectType() == Subscription25__Invoice__c.SObjectType) {
                contentDocumentIdByInvoiceId.put(link.LinkedEntityId, link.ContentDocumentId);
            }
        }

        if (contentDocumentIdByInvoiceId.isEmpty()) {
            return;
        }

        Map<Id, Subscription25__Invoice__c> invoicesById = new Map<Id, Subscription25__Invoice__c>([
            SELECT Id, Subscription25__PDF_Attachment_Name__c
            FROM Subscription25__Invoice__c
            WHERE Id IN :contentDocumentIdByInvoiceId.keySet()
              AND Subscription25__Administration__r.Include_CII_Hybrid_PDF__c = true
            WITH SYSTEM_MODE
        ]);

        if (invoicesById.isEmpty()) {
            return;
        }

        Map<Id, ContentDocument> documentsById = new Map<Id, ContentDocument>([
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id IN :contentDocumentIdByInvoiceId.values()
        ]);

        List<Svc_CIIHybridPdfMerge.MergeRequest> requests = new List<Svc_CIIHybridPdfMerge.MergeRequest>();
        for (Id invoiceId : invoicesById.keySet()) {
            Subscription25__Invoice__c invoice = invoicesById.get(invoiceId);
            Id contentDocumentId = contentDocumentIdByInvoiceId.get(invoiceId);
            ContentDocument doc = documentsById.get(contentDocumentId);

            if (doc == null || String.isBlank(invoice.Subscription25__PDF_Attachment_Name__c)) {
                continue;
            }

            // Only react to the invoice's own PDF - other files (manual attachments, unrelated
            // automation) can get linked to an invoice record too, and shouldn't trigger a merge.
            if (doc.Title != invoice.Subscription25__PDF_Attachment_Name__c) {
                continue;
            }

            requests.add(new Svc_CIIHybridPdfMerge.MergeRequest(invoiceId, contentDocumentId));
        }

        if (!requests.isEmpty()) {
            System.enqueueJob(new Svc_CIIHybridPdfMerge(requests));
        }
    }
}
