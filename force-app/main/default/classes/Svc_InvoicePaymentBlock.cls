/**
 * Direct debit block in the invoice email: the package's invoice email (InvoiceNL/UK/DE) merges
 * Subscription25__Invoice__c.Payment_Setup_Block__c, so a customer whose invoice is emailed gets the mandate
 * request in that one email instead of a separate setup email.
 *   - fill:  renders paymentDirectDebitInvoiceBlock_<LANG> for the payment into its invoice. Called by
 *            afl_Payment_Direct_Debit_Setup while the invoice email is still PENDING (payment → Awaiting Invoice Email).
 *   - clear: empties the block again once the separate setup email went out after all (invoice email failed,
 *            safety net) or the customer completed the mandate before the invoice email was sent.
 * The block language follows the Administration's invoice template (InvoiceNL → NL, InvoiceDE → DE, otherwise EN),
 * so it always matches the email it sits in; Contact.Language__c could put an NL block into an English invoice.
 */
public without sharing class Svc_InvoicePaymentBlock {

    public static final String FILL  = 'fill';
    public static final String CLEAR = 'clear';
    @TestVisible private static final String TEMPLATE_PREFIX = 'paymentDirectDebitInvoiceBlock_';

    public class Request {
        @InvocableVariable(label='Payment Id' required=true)
        public Id paymentId;
        @InvocableVariable(label='Action' description='fill or clear' required=true)
        public String action;
    }

    public class Result {
        @InvocableVariable(label='Done' description='fill: the block is on the invoice; clear: the block is empty')
        public Boolean done = false;
    }

    @InvocableMethod(label='Invoice Payment Block' description='Fills or clears the direct debit block on the invoice of each payment.' category='Payment')
    public static List<Result> run(List<Request> requests) {
        Map<Id, String> actionByPayment = new Map<Id, String>();
        for (Request r : requests) {
            if (r?.paymentId != null) actionByPayment.put(r.paymentId, r.action == FILL ? FILL : CLEAR);
        }

        Map<Id, Payment__c> payments = new Map<Id, Payment__c>([
            SELECT Id, Name, Invoice__c, Contact__c, Setup_URL__c,
                   Invoice__r.Subscription25__Administration__r.Subscription25__Invoice_Email_Template__c
            FROM Payment__c
            WHERE Id IN :actionByPayment.keySet()
            WITH SYSTEM_MODE
        ]);
        Map<String, Id> templates = templateIds();

        Map<Id, Subscription25__Invoice__c> updates = new Map<Id, Subscription25__Invoice__c>();
        Map<Id, Id> invoiceByPayment = new Map<Id, Id>();
        for (Payment__c p : payments.values()) {
            if (p.Invoice__c == null) continue;
            String block = null;
            if (actionByPayment.get(p.Id) == FILL) {
                if (String.isBlank(p.Setup_URL__c)) continue;   // no token or no Customer Hub URL: no usable link
                Id templateId = templates.get(language(p.Invoice__r?.Subscription25__Administration__r?.Subscription25__Invoice_Email_Template__c));
                if (templateId == null) templateId = templates.get('EN');
                if (templateId == null) continue;
                try {
                    block = render(templateId, p);
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Svc_InvoicePaymentBlock ' + p.Name + ': ' + e.getMessage());
                    continue;
                }
                if (String.isBlank(block)) continue;
            }
            updates.put(p.Invoice__c, new Subscription25__Invoice__c(Id = p.Invoice__c, Payment_Setup_Block__c = block));
            invoiceByPayment.put(p.Id, p.Invoice__c);
        }

        Set<Id> saved = new Set<Id>();
        if (!updates.isEmpty()) {
            List<Subscription25__Invoice__c> rows = updates.values();
            List<Database.SaveResult> srs = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < srs.size(); i++) {
                if (srs[i].isSuccess()) saved.add(rows[i].Id);
                else System.debug(LoggingLevel.ERROR, 'Svc_InvoicePaymentBlock ' + rows[i].Id + ': ' + srs[i].getErrors());
            }
        }

        List<Result> results = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            Id invoiceId = r?.paymentId == null ? null : invoiceByPayment.get(r.paymentId);
            res.done = invoiceId != null && saved.contains(invoiceId);
            results.add(res);
        }
        return results;
    }

    /** InvoiceNL → NL, InvoiceDE → DE, anything else (InvoiceUK, blank) → EN. */
    @TestVisible
    static String language(String invoiceTemplate) {
        String code = String.isBlank(invoiceTemplate) ? '' : invoiceTemplate.right(2).toUpperCase();
        return (code == 'NL' || code == 'DE') ? code : 'EN';
    }

    private static Map<String, Id> templateIds() {
        Map<String, Id> ids = new Map<String, Id>();
        String pattern = TEMPLATE_PREFIX + '%';
        for (EmailTemplate t : [SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName LIKE :pattern WITH SYSTEM_MODE]) {
            ids.put(t.DeveloperName.removeStart(TEMPLATE_PREFIX).toUpperCase(), t.Id);
        }
        return ids;
    }

    /** Rendered template body without the html/head/body wrapper, ready to sit inside the invoice email. */
    @TestVisible
    static String render(Id templateId, Payment__c p) {
        String html = Messaging.renderStoredEmailTemplate(templateId, p.Contact__c, p.Id).getHtmlBody();
        if (html == null) return null;
        String content = html.substringAfter('<body');
        content = String.isBlank(content) ? html : content.substringAfter('>');
        return content.contains('</body>') ? content.substringBeforeLast('</body>').trim() : content.trim();
    }
}
