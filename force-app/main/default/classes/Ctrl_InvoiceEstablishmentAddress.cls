/**
 * Extension on Invoice.page (Ctrl_Invoice):
 * - shows the customer's establishment address (Account Billing address) in a separate box when the invoice is sent
 *   to a different (invoice) address; tax regulations require the establishment address on the invoice
 *   (custom labels InvoiceEstablishmentTitle / InvoiceEstablishmentNotice).
 * - decides per address whether the country is printed: only when its country code differs from the
 *   administration's country code (Subscription25__Administration__c.Country_Code__c). The establishment address
 *   and the invoice address are checked separately.
 */
public with sharing class Ctrl_InvoiceEstablishmentAddress {
    public Boolean showEstablishmentAddress {get; private set;}
    public String establishmentName {get; private set;}
    public String establishmentStreet {get; private set;}
    public String establishmentPostalCode {get; private set;}
    public String establishmentCity {get; private set;}
    public String establishmentCountry {get; private set;}
    public Boolean showEstablishmentCountry {get; private set;}
    public Boolean showInvoiceCountry {get; private set;}

    public Ctrl_InvoiceEstablishmentAddress(Ctrl_Invoice ctrl) {
        this(loadInvoice(ctrl.getInvoice()), null);
    }

    // adminCountryCode: null = take it from the invoice's administration
    public Ctrl_InvoiceEstablishmentAddress(Subscription25__Invoice__c invoice, String adminCountryCode) {
        this.showEstablishmentAddress = false;
        this.showEstablishmentCountry = false;
        this.showInvoiceCountry = false;
        if (invoice == null) {
            return;
        }

        String adminCode = (adminCountryCode != null) ? adminCountryCode : getAdminCountryCode(invoice.Subscription25__Administration__c);

        // invoice address (address block): the invoice only holds the country name, compare its code
        String invoiceCode = countryCodeFromLabel(invoice.Subscription25__Billing_Country__c);
        this.showInvoiceCountry = String.isNotBlank(invoice.Subscription25__Billing_Country__c) && differs(invoiceCode, adminCode);

        if (invoice.Subscription25__Account__c == null) {
            return;
        }
        List<Account> accs = [
            SELECT Name, BillingStreet, BillingPostalCode, BillingCity, BillingCountry, BillingCountryCode
            FROM Account
            WHERE Id = :invoice.Subscription25__Account__c
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (accs.isEmpty() || String.isBlank(accs[0].BillingStreet)) {
            return;
        }
        Account acc = accs[0];

        // only when the invoice goes to another address than the establishment address
        this.showEstablishmentAddress =
            (normalize(invoice.Subscription25__Billing_Street__c) != normalize(acc.BillingStreet)) ||
            (normalize(invoice.Subscription25__Billing_Postal_Code__c) != normalize(acc.BillingPostalCode)) ||
            (normalize(invoice.Subscription25__Billing_City__c) != normalize(acc.BillingCity));

        this.establishmentName = acc.Name;
        this.establishmentStreet = acc.BillingStreet;
        this.establishmentPostalCode = acc.BillingPostalCode;
        this.establishmentCity = acc.BillingCity;
        this.establishmentCountry = acc.BillingCountry;
        // establishment address: its own country code against the administration's country code
        this.showEstablishmentCountry = String.isNotBlank(acc.BillingCountryCode) && differs(acc.BillingCountryCode, adminCode);
    }

    // re-query the fields this extension needs, independent of the Ctrl_Invoice query
    private static Subscription25__Invoice__c loadInvoice(Subscription25__Invoice__c invoice) {
        if ((invoice == null) || (invoice.Id == null)) {
            return invoice;
        }
        List<Subscription25__Invoice__c> invs = [
            SELECT Id, Subscription25__Account__c, Subscription25__Administration__c,
                Subscription25__Billing_Street__c, Subscription25__Billing_Postal_Code__c, Subscription25__Billing_City__c, Subscription25__Billing_Country__c
            FROM Subscription25__Invoice__c
            WHERE Id = :invoice.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return invs.isEmpty() ? invoice : invs[0];
    }

    private static String getAdminCountryCode(Id adminId) {
        if (adminId == null) {
            return null;
        }
        List<Subscription25__Administration__c> adms = [
            SELECT Country_Code__c, Subscription25__Billing_Country__c
            FROM Subscription25__Administration__c
            WHERE Id = :adminId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (adms.isEmpty()) {
            return null;
        }
        return String.isNotBlank(adms[0].Country_Code__c) ? adms[0].Country_Code__c : countryCodeFromLabel(adms[0].Subscription25__Billing_Country__c);
    }

    // country name (as stored on the invoice) -> ISO code, via the State & Country picklist
    @TestVisible
    private static String countryCodeFromLabel(String label) {
        if (String.isBlank(label)) {
            return null;
        }
        String key = label.trim().toUpperCase();
        for (Schema.PicklistEntry ple : Account.BillingCountryCode.getDescribe().getPicklistValues()) {
            if ((ple.getLabel().toUpperCase() == key) || (ple.getValue().toUpperCase() == key)) {
                return ple.getValue();
            }
        }
        return label.trim();
    }

    // print the country when there's no administration code to compare with, or the codes differ
    private static Boolean differs(String code, String adminCode) {
        return String.isBlank(adminCode) || String.isBlank(code) || (code.toUpperCase() != adminCode.toUpperCase());
    }

    // compare addresses without case, spaces and punctuation ("3500AB" = "3500 ab")
    @TestVisible
    private static String normalize(String value) {
        return (value == null) ? '' : value.toLowerCase().replaceAll('[^a-z0-9]', '');
    }
}
