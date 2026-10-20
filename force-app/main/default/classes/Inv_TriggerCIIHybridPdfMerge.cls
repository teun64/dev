/**
 * DEPRECATED (2026-09-21): the Flow this served (rau_Subscription25_Invoice_c_Trigger_CII_Merge)
 * was replaced by the ContentDocumentLink trigger (Trigger_ContentDocumentLink.cls), which catches
 * PDF regenerations that this field-based approach couldn't (Subscription25__PDF_Attachment_Name__c
 * doesn't change on regeneration - see [[project_en16931_einvoicing_rollout]] memory). The old flow
 * couldn't be deleted (blocked by an "insufficient access rights" platform quirk) so this class is
 * kept only so the still-present, deactivated flow version continues to compile. Not invoked by
 * anything live - do not call this directly, use Trigger_ContentDocumentLink's path instead.
 */
public without sharing class Inv_TriggerCIIHybridPdfMerge {
    @InvocableMethod(label='Trigger CII Hybrid PDF Merge (deprecated)' description='Deprecated - see Trigger_ContentDocumentLink.cls' category='Invoicing')
    public static void triggerMerge(List<Id> invoiceIds) {
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        List<Svc_CIIHybridPdfMerge.MergeRequest> requests = new List<Svc_CIIHybridPdfMerge.MergeRequest>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :invoiceIds
        ]) {
            requests.add(new Svc_CIIHybridPdfMerge.MergeRequest(link.LinkedEntityId, link.ContentDocumentId));
        }

        if (!requests.isEmpty()) {
            System.enqueueJob(new Svc_CIIHybridPdfMerge(requests));
        }
    }
}
