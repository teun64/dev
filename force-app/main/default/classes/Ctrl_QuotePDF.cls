public without sharing class Ctrl_QuotePDF {
	/*
	public Quote curQuote {get; private set;}
	public Map <String, String> labelNameToLabel {get; private set;}
	public Integer longestNameLength {get; private set;}
	public Ctrl_QuotePDF.AdminWrapper curAdmin {get; private set;}
	public Ctrl_QuotePDF.DebtorNumberWrapper curDebtorNumber {get; private set;}
	public QuotePDF__mdt curQuotePDF {get; private set;}
	//public list<QuoteLineItem> curQuoteLines {get; private set;}

	public Ctrl_QuotePDF(ApexPages.StandardController stdController){
		this.curQuote = Util_Data.getQuoteAndLineItemsForPdfByQuoteId(ApexPages.currentPage().getParameters().get('id'));
		//get all product ids from the quote lines
		Set<Id> prodIds = Util_System.collectIdValues(this.curQuote.QuoteLineItems, 'Product2Id');
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

		//put the actual translations on the qoute line items
		for(QuoteLineItem qli : this.curQuote.QuoteLineItems){
			if(!translationMap.containsKey(qli.Product2Id)){
				continue;
			}
			Data_Translation__c curTrans = translationMap.get(qli.Product2Id);
			if (curTrans != null) {
				if(!String.isBlank(curTrans.Name__c)){
					qli.Product2.Name = curTrans.Name__c;
				}
				if(!String.isBlank(curTrans.Description__c)){
					qli.Description = curTrans.Description__c;
				}
			}
		}

		this.curQuotePDF = [SELECT
								Amount_Label__c
								, Activation_Fee_Content__c
								, Approval_Content__c, Approval_Label__c
								, Article_Number_Label__c
								, COC_Label__c, Closing_Greeting_Label__c
								, Date_Label__c, Description_Label__c
								, Explanation_Label__c
								, Hardware_Label__c
								, Intro_1_Content__c, Intro_2_Content__c, Intro_3_Content__c
								, MiApp_Content__c, MiApp_Label__c, MiAzure_Content__c, MiAzure_Label__c, MiBlack_Content__c, MiBlack_Label__c, MiBlue_Content__c, MiBlue_Label__c, MiGreen_Content__c, MiGreen_Label__c, MiGrey_Content__c , MiGrey_Label__c
								, MiOrange_Content__c , MiOrange_Label__c, MiRed_Content__c, MiRed_Label__c, MiRoyalBlue_Content__c, MiRoyalBlue_Label__c, MiYellow_Content__c, MiYellow_Label__c, MiWhite_Content__c, MiWhite_Label__c
								, tpBasic_Content__c, tpBasic_Label__c, tpEnterprise_Content__c, tpEnterprise_Label__c, tpPremium_Content__c, tpPremium_Label__c, tpProfessional_Content__c, tpProfessional_Label__c
								, tpRemoteSpeedometerDownload_Content__c, tpRemoteSpeedometerDownload_Label__c, tpTemperatureModule_Content__c, tpTemperatureModule_Label__c, tpTourPlanning_Content__c, tpTourPlanning_Label__c
								, tpTrackPilotApp_Content__c, tpTrackPilotApp_Label__c
								, Name_Label__c
								, Place_and_Date_Label__c, Price_Label__c
								, Quotation_Label__c, Quote_Number_Label__c
								, Reference_Label__c
								, Service_Label__c, Slogan_Content__c, Subtotal_Label__c
								, Terms_Label__c, Terms_1_Content__c, Terms_2_Content__c, Terms_3_Content__c
								, Topic_1_Content__c, Topic_1_Label__c, Topic_2_Content__c, Topic_2_Label__c, Topic_3_Content__c, Topic_3_Label__c
								, Total_excluding_VAT_Label__c, Total_including_VAT_Label__c
								, Valid_until_Label__c, VAT_Label__c
								, Your_inquiry_Label__c
                            	, Mandate_Account_Holder_Label__c, Mandate_Account_Number_Label__c, Mandate_Address_Label__c
                            	, Mandate_BIC_Label__c, Mandate_Company_Label__c, Mandate_Contact_Person_Label__c
                            	, Mandate_Creditor_Identifier_Label__c, Mandate_Email_Label__c, Mandate_IBAN_Label__c
                            	, Mandate_1_Content__c, Mandate_Name_of_the_Bank_Label__c, Mandate_Phone_Label__c
                            	, Mandate_Postal_Code_City_Label__c, Mandate_Reference_Number_Label__c, Mandate_Sort_Code_Label__c
                            	, Mandate_Street_Label__c, Mandate_Type__c, Mandate_Client_Number_Label__c, Signature_Stamp_of_the_Client_Label__c
							 FROM
								QuotePDF__mdt
							 WHERE
								DeveloperName = :getLanguage()];

		long resellerId = long.valueOf(String.isNotBlank(this.curQuote.Account.Reseller_Name__c) ? this.curQuote.Account.Reseller_Name__c : '1');
		integer adminId = Util_System.getAdminExternalId(resellerId);


		this.curAdmin = new Ctrl_QuotePDF.AdminWrapper([
			SELECT Id, Name, Currency_Symbol__c, Email_Sales__c, Reseller__c, Subscription25__Bank__c,
				Subscription25__BIC__c, Subscription25__Billing_City__c, Subscription25__Billing_Country__c,
				Subscription25__Billing_Email_Address__c, Subscription25__Billing_Name__c, Subscription25__Billing_State__c,
				Subscription25__Billing_Street__c, Subscription25__Billing_Postal_Code__c,
				Subscription25__Chamber_Of_Commerce_Number__c, Subscription25__IBAN__c, Subscription25__Phone__c,
				Subscription25__VAT_Number__c, Subscription25__Website__c,Subscription25__Active__c, Creditor_Identifier_Mandate__c, 
				VAT_Rate_Default__r.Subscription25__VAT_Percentage__c 
			FROM Subscription25__Administration__c
			WHERE External_ID__c = :adminId
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
				AND Subscription25__Account__c = :this.curQuote.AccountId
			LIMIT
				1
		];

		if (debtorNumbers.size() == 0) {
			this.curDebtorNumber = new Ctrl_QuotePDF.DebtorNumberWrapper(null);
		} else { 
			this.curDebtorNumber = new Ctrl_QuotePDF.DebtorNumberWrapper(debtorNumbers[0]);
		}


		this.detetermineNameLength();
	}

	public List<String> getQuoteServices(){
		if(String.isBlank(curQuote.Service__c)){
			return null;
		}

		return curQuote.Service__c.split(';');
	}

	public String getProductName(id productId){
		Product2 curProduct = [Select Name, Description FROM Product2 WHERE id = :productId LIMIT 1];
		Data_Translation__c curTranslation = [SELECT Name__c FROM Data_Translation__c WHERE product__c = :productId AND Language__c = :getLanguage() LIMIT 1];
		String returnValue = curTranslation.Name__c != null ? curTranslation.Name__c : curProduct.Name;
		return returnValue;
	}

	public String getLanguage(){
		String returnValue = 'nl';

		if(!String.isBlank(this.curQuote.Account.Sales_Language__c)){
			returnValue = this.curQuote.Account.Sales_Language__c;
		}

		return returnValue.toLowerCase();
	}

	private void detetermineNameLength(){
		Integer nameLength = String.isNotBlank(this.curQuote.Name) ? this.curQuote.Name.length() : 0;
		Integer accountNameLength = String.isNotBlank(this.curQuote.Account.Name) ? this.curQuote.Account.Name.length() : 0;

		if(nameLength > accountNameLength){
			this.longestNameLength = nameLength;
		} else {
			this.longestNameLength = accountNameLength;
		}
		//length needs to be rounded on a scale of 10. Hence the calculation below.
		this.longestNameLength = Math.round(longestNameLength / 10) * 10;
	}

	private class DebtorNumberWrapper {
		private Subscription25__Debtor_Number__c debNr;
		private DebtorNumberWrapper(Subscription25__Debtor_Number__c debNr){
			this.debNr = (debNr != null) ? debNr : null;
		}
		public String getDebtorNumber(){
			return (this.debNr != null) ? this.debNr.Subscription25__Debtor_Number__c : '';
		}
		public String getDirectDebitFormReference(){
			return (this.debNr != null) ? this.debNr.Direct_Debit_Form_Reference__c : '';
		}		
	}

	private class AdminWrapper {
		private Subscription25__Administration__c admin;
		private AdminWrapper(Subscription25__Administration__c admin){
			this.admin = admin;
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
		public String getCurrencySymbol(){
			return this.admin.Currency_Symbol__c;
		}
		public Decimal getDefaultVatPercentage(){
			return this.admin.VAT_Rate_Default__r.Subscription25__VAT_Percentage__c;
		}
		public String getCreditorIdentifier(){
			return this.admin.Creditor_Identifier_Mandate__c;
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
 */
}