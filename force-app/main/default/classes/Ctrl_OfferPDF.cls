public without sharing class Ctrl_OfferPDF {
    public Opportunity curOpp {get; private set;}
    //public Map <String, String> labelNameToLabel {get; private set;}
    public Integer longestNameLength {get; private set;}
    public Integer numberOfTerms {get; private set;}
    public Util_Wrappers.AdminWrapper curAdmin {get; private set;}
    public Util_Wrappers.DebtorNumberWrapper curDebtorNumber {get; private set;}
    public QuotePDF__mdt curOfferMDT {get; private set;}
    public Map<String, List<OpportunityLineItem>> lineItemMap {get; private set;}
    public Map<String, String> offerTermsLabel {get; private set;}
    public Map<String, String> offerTermsContent {get; private set;}

    public OpportunityLineItem curOppLines {get; private set;}
    private final Map<String, Ctrl_OfferPDF.OfferSection> sectionMap;
    private final List<String> curTerms;
    private final string vatMethod;
 
    public Ctrl_OfferPDF(ApexPages.StandardController stdController){
        this.curOpp = [
            SELECT ID, Name, Description, Segment__c, LeadSource, CloseDate,  CreatedDate, OpportunityNumber__c, Customer_Reference__c, Direct_Debit_Form_Required__c, New_Branding__c,
                // Sales_Contact__r.Salutation, Sales_Contact__r.FirstName, Sales_Contact__r.LastName, Sales_Contact__r.Name, Sales_Contact__r.Phone, Sales_Contact__r.MobilePhone, Sales_Contact__r.Email,
                // Owner.Name, Owner.Phone, Owner.MobilePhone, Owner.Email, Owner.Title, Owner.FirstName, Owner.LastName,
                SignerId__c, SignerName__c, SignerFirstName__c, SignerLastName__c, SignerSalutation__c, SignerEmail__c, SignerPhone__c, SignerMobile__c, SignerLanguage__c, 
                OwnerId, ReceiverName__c, ReceiverFirstName__c, ReceiverLastName__c, ReceiverTitle__c, ReceiverEmail__c, ReceiverPhone__c, ReceiverMobile__c, ReceiverLanguage__c, 
                AccountId, Account.Name, Account.Reseller_Name__c, Account.RecordType.DeveloperName, Account.Sales_Language__c, Account.Phone, 
                Account.Invoice_VAT_Calculation__c,
                Account.VisitingAddress__Street__s, Account.VisitingAddress__PostalCode__s, Account.VisitingAddress__City__s, Account.VisitingAddress__CountryCode__s,
                Option_Show_Compressed__c, Option_Show_Customer_Product_Code__c, Option_Show_ListPrice__c, Option_Show_UnitPrice__c, Option_Show_Activation_Fee_Remark__c,
                Option_Require_Signature__c, 
                Subscriptions__c, Subscription_Description__c, Subscriptions_StartDate__c, Subscriptions_ContractTerm__c,
                Offer_Description__c, Amount_VAT__c, Amount, Amount_Gross__c,
                Administration__c, 
                    (
                        SELECT Description, Discount,  ListPrice, Product2.ProductCode
                            , Id, PricebookEntryId, Product2Id, Product2.Name, Product2.Offer_Subscription__c, Quantity
                            , UnitPrice, Amount_Net__c, Amount_VAT__c, Amount_Gross__c, VAT_Percentage__c // Services__c, Extra_Subscription__c, LineNumber
                            , OfferSectionCode__c, OfferSectionType__c
                        FROM OpportunityLineItems
                        ORDER BY Order__c
                     )
            FROM Opportunity 
            WHERE Id = :ApexPages.currentPage().getParameters().get('id')
        ];

        this.numberOfTerms = 7;
        this.vatMethod = this.curOpp.Account.Invoice_VAT_Calculation__c;

        //get all product ids from the quote lines
        Set<Id> prodIds = Util_System.collectIdValues(this.curOpp.OpportunityLineItems, 'Product2Id');
        //load all translations and map them from product id to translation
        List<Data_Translation__c> translations = [
            SELECT Name__c, Description__c, Product__c
            FROM Data_Translation__c
            WHERE Product__c IN :prodIds
                AND Language__c = :this.getLanguage()
        ];

        Map<Id, Data_Translation__c> translationMap = new Map<Id, Data_Translation__c>();
        for(Data_Translation__c translation : translations){
            translationMap.put(translation.Product__c, translation);
        }


        List<Subscription25__Administration_Product__c> adminProds = [
            SELECT ID
            FROM Subscription25__Administration_Product__c
            WHERE Subscription25__Product__c IN :prodIds
                AND Subscription25__Administration__c = :this.curOpp.Administration__c 
        ];

        this.curOfferMDT = [SELECT
                                Amount_Label__c
                                , Activation_Fee_Content__c
                                , Approval_Content__c, Approval_Label__c
                                , Article_Number_Label__c
                                , COC_Label__c, Closing_Greeting_Label__c
                                , Date_Label__c, Description_Label__c
                                , Explanation_Label__c
                                , Section0_Label__c, Section1_Label__c, Section3_Label__c, Section12_Label__c
                                , Intro_1_Content__c, Intro_2_Content__c, Intro_3_Content__c
                                , MiApp_Content__c, MiApp_Label__c 
                                , Name_Label__c
                                , Place_and_Date_Label__c, ListPrice_Label__c, UnitPrice_Label__c
                                , Quotation_Label__c, Quote_Number_Label__c
                                , Reference_Label__c
                                , Service_Label__c, Slogan_Content__c, Subtotal_Label__c
                                , Terms_Label__c, Terms_Wind_up_Content__c
                                , Topic_1_Content__c, Topic_1_Label__c, Topic_2_Content__c, Topic_2_Label__c, Topic_3_Content__c, Topic_3_Label__c
                                , Total_excluding_VAT_Label__c, Total_including_VAT_Label__c
                                , Valid_until_Label__c, VAT_Label__c
                                , Your_inquiry_Label__c
                            FROM
                                QuotePDF__mdt
                            WHERE
                                DeveloperName = :getLanguage()
                            LIMIT 1];

        this.lineItemMap = new Map<String, List<OpportunityLineItem>>();
        //this.vatMap = new Map<Decimal, Ctrl_Invoice.VATItem>();
        this.sectionMap = new Map<String, Ctrl_OfferPDF.OfferSection>();
        string sectionLabel;

        //put the actual translations on the qoute line items
        for(OpportunityLineItem oli : this.curOpp.OpportunityLineItems){
            /* if(!translationMap.containsKey(oli.Product2Id)){
                continue;
            }*/
            Data_Translation__c curTrans = translationMap.get(oli.Product2Id);
            if (curTrans != null) {
                if(!String.isBlank(curTrans.Name__c)){
                    oli.Product2.Name = curTrans.Name__c;
                }
                if(!String.isBlank(curTrans.Description__c)){
                    oli.Description = curTrans.Description__c;
                }
            }

            sectionLabel = 'Section' + oli.OfferSectionCode__c + '_Label__c';
            //system.debug('looking for section ' + oli.OfferSectionCode__c + ' - ' + this.curOfferMDT.get(sectionLabel));

            if(!this.sectionMap.containsKey(oli.OfferSectionCode__c)){
                this.sectionMap.put(oli.OfferSectionCode__c, new Ctrl_OfferPDF.OfferSection(oli.OfferSectionCode__c, oli.OfferSectionType__c,String.valueOf(this.curOfferMDT.get(sectionLabel)), this.vatMethod, oli.VAT_Percentage__c));
            }
        
            this.sectionMap.get(oli.OfferSectionCode__c).addAmounts(oli.Amount_Net__c, oli.Amount_VAT__c, oli.Amount_Gross__c);

            if(!this.lineItemMap.containsKey(oli.OfferSectionCode__c)){
                this.lineItemMap.put(oli.OfferSectionCode__c, new list<OpportunityLineItem> {oli});
            } else {
                this.lineItemMap.get(oli.OfferSectionCode__c).add(oli);
            }

            if ((oli.OfferSectionType__c == 'RECURRING') && (String.isNotBlank(oli.Product2.Offer_Subscription__c))) {
                if (String.isNotBlank(curOpp.Subscriptions__c)) {

                    if (!curOpp.Subscriptions__c.contains(oli.Product2.Offer_Subscription__c)) {
                        curOpp.Subscriptions__c = curOpp.Subscriptions__c + ';' + oli.Product2.Offer_Subscription__c;
                    }
                } else {
                    curOpp.Subscriptions__c = oli.Product2.Offer_Subscription__c;
                }

            }
            //system.debug('sctionMap = ' + sectionMap);
            //system.debug('lineItemMap = ' + lineItemMap);
        }

        long resellerId = long.valueOf(String.isNotBlank(this.curOpp.Account.Reseller_Name__c) ? this.curOpp.Account.Reseller_Name__c : '1');
        integer adminId = Util_System.getAdminExternalId(resellerId);

        this.curAdmin = new Util_Wrappers.AdminWrapper([
            SELECT 
                Id, Name, Currency_Symbol__c, Email_Sales__c, Reseller__c, Subscription25__Bank__c,
                Subscription25__BIC__c, Subscription25__Billing_City__c, Subscription25__Billing_Country__c,
                Subscription25__Billing_Email_Address__c, Subscription25__Billing_Name__c, Subscription25__Billing_State__c,
                Subscription25__Billing_Street__c, Subscription25__Billing_Postal_Code__c,
                Subscription25__Chamber_Of_Commerce_Number__c, Subscription25__IBAN__c, Subscription25__Phone__c,
                Subscription25__VAT_Number__c, Subscription25__Website__c,Subscription25__Active__c, Creditor_Identifier_Mandate__c, 
                VAT_Rate_Default__r.Subscription25__VAT_Percentage__c, Bank_6_Account_Number__c, Bank_6_Sort_Code__c, Managing_Directors__c,
                Invoice_General_Remark__c, Invoice_EU_Remark__c, Invoice_NonEU_Remark__c,
                Offer_Term_1__c, Offer_Term_2__c, Offer_Term_3__c, Offer_Term_4__c, Offer_Term_5__c, Offer_Term_6__c, Offer_Term_7__c 
            FROM 
                Subscription25__Administration__c
            WHERE 
                External_ID__c = :adminId
            LIMIT 1
        ]);

        List<Subscription25__Debtor_Number__c> debtorNumbers = [
            SELECT 
                ID
                , Subscription25__Debtor_Number__c
                , Direct_Debit_Form_Reference__c
            FROM
                Subscription25__Debtor_Number__c
            WHERE
                Subscription25__Administration__r.External_ID__c = :adminId
                AND Subscription25__Account__c = :this.curOpp.AccountId
            LIMIT
                1
        ];

        if (debtorNumbers.size() == 0) {
            this.curDebtorNumber = new Util_Wrappers.DebtorNumberWrapper(null);
        } else { 
            this.curDebtorNumber = new Util_Wrappers.DebtorNumberWrapper(debtorNumbers[0]);
        }

        this.offerTermsLabel = new Map<String, String>();
        this.offerTermsContent = new Map<String, String>();
        this.curTerms = new List<String>();
        String curTerm;
        String curTermLabel;
        String curTermContent;
        string language = this.getLanguage();
        string reseller = this.curAdmin.getReseller();

        for (Integer term = 1; term <= this.numberOfTerms; term++) {

            curTerm = String.valueOf(term);
            //System.debug('term = ' + curTerm);

            if (this.curAdmin.getOfferTerm(curTerm)) {
                //this.curTerms.add(curTerm);
                curTermLabel = '';
                curTermContent = '';

                try {
                    curTermContent = System.Label.Get('', 'OfferTerm' + reseller + curTerm + '_Content', language);
                } catch(Exception e) {
                    // Generic exception handling code here.
                    curTermContent = 'OfferTerm' + reseller + curTerm + '_Content custom label not found!';
                }

                if (String.isNotBlank(curTermContent)) {

                    try {
                        curTermLabel = System.Label.Get('', 'OfferTerm' + reseller + curTerm + '_Label', language);
                    } catch(Exception e) {
                        // Generic exception handling code here.
                        // curTermLabel = 'OfferTerm' + reseller + curTerm + '_Label custom label not found!';
                    }

                    this.curTerms.add(curTerm);

                    if(!this.offerTermsContent.containsKey(curTerm)){
                        this.offerTermsContent.put(curTerm, curTermContent);
                    }

                    if(!this.offerTermsLabel.containsKey(curTerm)){
                        this.offerTermsLabel.put(curTerm, curTermLabel);
                    }

                }

            }
        }

        this.detetermineNameLength();
    }

    public List<String> getOfferSubscriptions(){
        if(String.isBlank(curOpp.Subscriptions__c)){
            return null;
        }

        List<String> offerSubscriptions = curOpp.Subscriptions__c.split(';');

        offerSubscriptions.sort();

        return offerSubscriptions;
    }

    public List<String> getOfferTerms() {
        if (this.curTerms.size() >= 0) {
            return this.curTerms;
        } else {
            return null;
        }
    }

    public List<OpportunityLineItem> sectionLines (String section) {
        List<OpportunityLineItem> returnList; 

        if (this.lineItemMap.containsKey(section)) {
            returnList = this.lineItemMap.get(section);
        } else {
            returnList = new List<OpportunityLineItem>();
        }

        return returnList;
    }

    public String getProductName(id productId){
        Product2 curProduct = [Select Name, Description FROM Product2 WHERE id = :productId LIMIT 1];
        Data_Translation__c curTranslation = [SELECT Name__c FROM Data_Translation__c WHERE product__c = :productId AND Language__c = :getLanguage() LIMIT 1];
        String returnValue = curTranslation.Name__c != null ? curTranslation.Name__c : curProduct.Name;
        return returnValue;
    }

    public String getLanguage(){
        String returnValue = 'en';

        if(!String.isBlank(this.curOpp.Account.Sales_Language__c)){
            returnValue = this.curOpp.Account.Sales_Language__c;
        }

        return returnValue.toLowerCase();
    }

    public List<Ctrl_OfferPDF.OfferSection> getOfferSections(){
        List<Ctrl_OfferPDF.OfferSection> offerSections = this.sectionMap.values();
        offerSections.sort();
        return offerSections;
    }

    private void detetermineNameLength(){
        Integer nameLength = String.isNotBlank(this.curOpp.Name) ? this.curOpp.Name.length() : 0;
        Integer accountNameLength = String.isNotBlank(this.curOpp.Account.Name) ? this.curOpp.Account.Name.length() : 0;

        if(nameLength > accountNameLength){
            this.longestNameLength = nameLength;
        } else {
            this.longestNameLength = accountNameLength;
        }
        //length needs to be rounded on a scale of 10. Hence the calculation below.
        this.longestNameLength = Math.round(longestNameLength / 10) * 10;
    }


    private class OfferSection implements Comparable {
        private Decimal amountVATTotal;
        private Decimal amountVATLine;
        private Decimal amountGrossLine;
        public String code {get; private set;}
        public String label {get; private set;}
        public String type {get; private set;}
        public String method {get; private set;}
        public Decimal percentage {get; private set;}
        public Decimal amountNet {get; private set;}
        public Decimal amountVAT {
                get {
                  return this.getAmountVAT();
                }
                private set;}
        public Decimal amountGross {get {
                  return this.getAmountGross();
                }
                private set;}
    
        public OfferSection(String code, String type, String label, String method, Decimal percentage){
          this.code = code;
          this.type = type;
          this.label = label;
          this.method = method;
          Decimal correction = Math.abs(percentage) > 1 ? 100 : 1;
          this.percentage = (percentage / correction);
          this.amountNet = 0;
          this.amountVATLine = 0;
          this.amountGrossLine = 0;
        }
    
        public void addAmounts(Decimal amountNet, Decimal amountVAT, Decimal amountGross){
          this.amountNet += amountNet;
          this.amountVATLine += amountVAT;
          this.amountGrossLine += amountGross;
          decimal percentageCorrection = 
          this.amountVATTotal = this.amountNet * this.percentage;
        }
    
        private Decimal getAmountVAT(){
          Decimal amount = (this.method == 'TOTAL') ? this.amountVATTotal : this.amountVATLine;
          return amount.setScale(2, RoundingMode.HALF_UP);
        }
    
        private Decimal getAmountGross(){
          Decimal amount = (this.method == 'TOTAL') ? (this.amountNet + this.amountVATTotal) : this.amountGrossLine;
          return amount.setScale(2, RoundingMode.HALF_UP);
        }
    
        public Integer compareTo(Object obj){
            Ctrl_OfferPDF.OfferSection that = (Ctrl_OfferPDF.OfferSection)obj;
            Integer thatCode = Integer.valueOf(that.code);
            Integer thisCode = Integer.valueOf(this.code);
            
            if (thisCode == thatCode) return 0;
            if (thisCode > thatCode) return 1;
            return -1;  
          }
      }

    public void getTest(){
        this.curDebtorNumber.getDebtorNumber();
        this.curDebtorNumber.getDirectDebitFormReference();
        this.curAdmin.getBillingName();
        this.curAdmin.getStreet();
        this.curAdmin.getPostalCode();
        this.curAdmin.getCity();
        this.curAdmin.getPhone();
        this.curAdmin.getEmailSales();
        this.curAdmin.getWebsite();
        this.curAdmin.getCoCNumber();
        this.curAdmin.getCurrencySymbol();
        this.curAdmin.getDefaultVatPercentage();
        this.curAdmin.getCreditorIdentifier();
    }
}