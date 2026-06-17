public without sharing class Util_Wrappers {
    public class DebtorNumberWrapper {
        private Subscription25__Debtor_Number__c debNr;
        public DebtorNumberWrapper(Subscription25__Debtor_Number__c debNr){
            this.debNr = (debNr != null) ? debNr : null;
        }
        public String getDebtorNumber(){
            return (this.debNr != null) ? this.debNr.Subscription25__Debtor_Number__c : '';
        }
        public String getDirectDebitFormReference(){
            return (this.debNr != null) ? this.debNr.Direct_Debit_Form_Reference__c : '';
        }		
    }

    public class AdminWrapper {
        private Subscription25__Administration__c admin;
        public AdminWrapper(Subscription25__Administration__c admin){
            this.admin = admin;
        }
        public String getReseller() {
            return this.admin.Reseller__c;
        }
        public String getBillingName(){
            return this.admin.Subscription25__Billing_Name__c;
        }
        public String getStreet(){
            return this.admin.Subscription25__Billing_Street__c;
        }
        public String getPostalCode(){
            return this.admin.Subscription25__Billing_Postal_Code__c;
        }
        public String getCity(){
            return this.admin.Subscription25__Billing_City__c;
        }
        public String getCountry(){
            return this.admin.Subscription25__Billing_Country__c;
        }
        public String getEmail(){
            return this.admin.Subscription25__Billing_Email_Address__c;
        }
        public String getPhone(){
            return this.admin.Subscription25__Phone__c;
        }
        public String getEmailSales(){
            return this.admin.Email_Sales__c;
        }
        public String getWebsite(){
            return this.admin.Subscription25__Website__c;
        }
        public String getCoCNumber(){
            return this.admin.Subscription25__Chamber_Of_Commerce_Number__c;
        }
        public String getVATNumber(){
            return this.admin.Subscription25__VAT_Number__c;
        }
        public String getIBAN(){
            return this.admin.Subscription25__IBAN__c;
        }
        public String getBIC(){
            return this.admin.Subscription25__BIC__c;
        }
        public String getBankAccountNumber(){
            return this.admin.Bank_6_Account_Number__c;
        }
        public String getBankSortCode(){
            return this.admin.Bank_6_Sort_Code__c;
        }
        public String getCurrencySymbol(){
            return this.admin.Currency_Symbol__c;
        }
        public Decimal getDefaultVatPercentage(){
            return this.admin.VAT_Rate_Default__r.Subscription25__VAT_Percentage__c;
        }
        public String getCreditorIdentifier(){
            return this.admin.Creditor_Identifier_Mandate__c;
        }
        public String getManagingDirectors(){
            return this.admin.Managing_Directors__c;
        }
        public Boolean getInvoiceGeneralRemark() {
            return this.admin.Invoice_General_Remark__c;            
        }
        public Boolean getInvoiceEURemark() {
            return this.admin.Invoice_EU_Remark__c;            
        }
        public Boolean getInvoiceNonEURemark() {
            return this.admin.Invoice_NonEU_Remark__c;            
        }
        public Boolean getOfferTerm(String term) {
        if (String.isBlank(term)) {
                return false;
            }
            string termField = 'Offer_Term_' + term + '__c';
            
            return this.admin.get(termField) != null ? (Boolean)this.admin.get(termField) : false;
        }
    }
}