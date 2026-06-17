public without sharing class Util_PriceCalculation {

	public class getPricebookEntryInput {
		//required pricebookEntry or productId, pricebookId and currencyIsoCode
		@InvocableVariable(required=false)
		public PricebookEntry pricebookEntry;
		@InvocableVariable(required=false)
		public Id productId;
		@InvocableVariable(required=false)
		public Id pricebookId;
		@InvocableVariable(required=false)
		public String currencyIsoCode;
		@InvocableVariable(required=true)
		public Id accountId;
		@InvocableVariable(required=true)
		public Integer quantity;
		@InvocableVariable
		public Decimal discount;
	}
	
	public class getPricebookEntryPriceOutput {
		@InvocableVariable(label='Pricebook Entry' description='The pricebook entry')
		public PricebookEntry pricebookEntry;

		public getPricebookEntryPriceOutput(PricebookEntry pricebookEntry){
			this.pricebookEntry = pricebookEntry;
		}
	}

	@InvocableMethod(label='getPricebookEntry' description='Calculates the unit price for the given product, account, pricebook and quantity' category='Prices')
    public static List<getPricebookEntryPriceOutput> getPricebookEntry(List<getPricebookEntryInput> pbeInputs) {
		PricebookEntry pbe;
		List<getPricebookEntryPriceOutput> pbeOutputs = new List<getPricebookEntryPriceOutput>();

		if(pbeInputs.size() == 1) {
			for(getPricebookEntryInput pbeInput : pbeInputs){
				if (pbeInput.pricebookEntry != null) {
					pbe = getPricebookEntry(pbeInput.pricebookEntry, pbeInput.accountId, pbeInput.quantity, pbeInput.discount);
				} else if ((pbeInput.productId != null) && (pbeInput.pricebookId != null)) {
					pbe = getPricebookEntry(pbeInput.productId, pbeInput.pricebookId, pbeInput.currencyIsoCode, pbeInput.accountId, pbeInput.quantity, pbeInput.discount);
				}
			}
		}

		pbeOutputs.add(new getPricebookEntryPriceOutput(pbe));

		return pbeOutputs;		
    }

    Public static PricebookEntry getPricebookEntry(Id productId, Id pricebookId, String currencyIsoCode, Id accountId, integer quantity, decimal discount){

		if ((productId == null) || (pricebookId == null) || (currencyIsoCode == null)) {
			return null;
		}

		List<PricebookEntry> pbeList = [
			SELECT
				FIELDS(STANDARD)
				, AccountPrice__c, Discount__c, Is_Fixed_Price__c
				, Margin__c, No_Discount_Allowed__c, Price_Agreement__c, ProductName__c, ProductRecordType__c, Product_Relation__c, Quantity__c
				, From_Price_1__c , From_Price_2__c, From_Price_3__c, From_Price_4__c
				, From_Quantity_1__c, From_Quantity_2__c, From_Quantity_3__c, From_Quantity_4__c
				, Quantity_Price_1__c, Quantity_Price_2__c, Quantity_Price_3__c, Quantity_Price_4__c
				, Compound_Key__c
			FROM
				PricebookEntry
			WHERE
				Product2Id = :productId AND Pricebook2Id = :pricebookId AND CurrencyIsoCode = :currencyIsoCode  AND IsActive_r__c = true
			LIMIT
				1
		];

		if (pbeList.size() == 1) {
			return getPricebookEntry(pbeList[0], accountId, quantity, discount);
		} else {
			return null;
		}
	}

    Public static PricebookEntry getPricebookEntry(PricebookEntry pbe, Id accId, integer quantity, decimal discount){
        if(pbe == null || !(quantity >= 1)){
            return null;
        }

		if (pbe != null) {
			list<Product_Discount__c> productDiscounts = [
                                        SELECT
                                            FIELDS(STANDARD)
                                            , From_Discount_1__c, From_Discount_2__c, From_Discount_3__c, From_Discount_4__c
                                            , From_Quantity_1__c, From_Quantity_2__c, From_Quantity_3__c, From_Quantity_4__c
                                            , Compound_Key__c
                                        FROM
                                            Product_Discount__c
                                        WHERE
                                            Account__c = :accId AND Product__c = :pbe.Product2Id AND IsActive__c = true
                                        LIMIT
                                            1
                                    ];

			if 	(productDiscounts.size() == 1) {			
            	Product_Discount__c pdi = productDiscounts[0];

                // price agreement found, reset prices
                pbe.Price_Agreement__c = true;
                pbe.From_Price_1__c = ((pdi.From_Discount_1__c == null) || (pdi.From_Quantity_1__c == null)) ? null : (pbe.UnitPrice * (1.00-(pdi.From_Discount_1__c / (((pdi.From_Discount_1__c > 1) || (pdi.From_Discount_1__c < -1)) ? 100 : 1 )))).setScale(2, RoundingMode.HALF_UP);
                pbe.From_Price_2__c = ((pdi.From_Discount_2__c == null) || (pdi.From_Quantity_2__c == null)) ? null : (pbe.UnitPrice * (1.00-(pdi.From_Discount_2__c / (((pdi.From_Discount_2__c > 1) || (pdi.From_Discount_2__c < -1)) ? 100 : 1 )))).setScale(2, RoundingMode.HALF_UP);
                pbe.From_Price_3__c = ((pdi.From_Discount_3__c == null) || (pdi.From_Quantity_3__c == null)) ? null : (pbe.UnitPrice * (1.00-(pdi.From_Discount_3__c / (((pdi.From_Discount_3__c > 1) || (pdi.From_Discount_3__c < -1)) ? 100 : 1 )))).setScale(2, RoundingMode.HALF_UP);
                pbe.From_Price_4__c = ((pdi.From_Discount_4__c == null) || (pdi.From_Quantity_4__c == null)) ? null : (pbe.UnitPrice * (1.00-(pdi.From_Discount_4__c / (((pdi.From_Discount_4__c > 1) || (pdi.From_Discount_4__c < -1)) ? 100 : 1 )))).setScale(2, RoundingMode.HALF_UP);
                pbe.From_Quantity_1__c = ((pdi.From_Discount_1__c == null) || (pdi.From_Quantity_1__c == null)) ? null : pdi.From_Quantity_1__c;
                pbe.From_Quantity_2__c = ((pdi.From_Discount_2__c == null) || (pdi.From_Quantity_2__c == null)) ? null : pdi.From_Quantity_2__c;
                pbe.From_Quantity_3__c = ((pdi.From_Discount_3__c == null) || (pdi.From_Quantity_3__c == null)) ? null : pdi.From_Quantity_3__c;
                pbe.From_Quantity_4__c = ((pdi.From_Discount_4__c == null) || (pdi.From_Quantity_4__c == null)) ? null : pdi.From_Quantity_4__c;
			}
        }

		//Display properties
		string currencySymbol = Util_System.getCurrencySign(pbe.CurrencyIsoCode);
		pbe.Quantity_Price_1__c = ((pbe.From_Quantity_1__c == null) || (pbe.From_Price_1__c == null))? '' : (String.valueOf(pbe.From_Quantity_1__c.format()) + '->(' + currencySymbol + ' ' + Util_System.getCurrencyCents(pbe.From_Price_1__c) + ')');
		pbe.Quantity_Price_2__c = ((pbe.From_Quantity_2__c == null) || (pbe.From_Price_3__c == null))? '' : (String.valueOf(pbe.From_Quantity_2__c.format()) + '->(' + currencySymbol + ' ' + Util_System.getCurrencyCents(pbe.From_Price_2__c) + ')');
		pbe.Quantity_Price_3__c = ((pbe.From_Quantity_3__c == null) || (pbe.From_Price_3__c == null))? '' : (String.valueOf(pbe.From_Quantity_3__c.format()) + '->(' + currencySymbol + ' ' + Util_System.getCurrencyCents(pbe.From_Price_3__c) + ')');
		pbe.Quantity_Price_4__c = ((pbe.From_Quantity_4__c == null) || (pbe.From_Price_4__c == null))? '' : (String.valueOf(pbe.From_Quantity_4__c.format()) + '->(' + currencySymbol + ' ' + Util_System.getCurrencyCents(pbe.From_Price_4__c) + ')');

		//Genral properties
        pbe.Quantity__c = quantity;
		if (discount != null) {
        	pbe.Discount__c = discount;
		}
        pbe.AccountPrice__c = Util_PriceCalculation.getQuantitySalesPrice(pbe);
		pbe.UnitPrice__c = (pbe.AccountPrice__c == null) ? '' : (currencySymbol + ' ' +  Util_System.getCurrencyCents(pbe.AccountPrice__c));
        pbe.SalesPrice__c = (pbe.AccountPrice__c == null) ? 0 : (pbe.AccountPrice__c - ((pbe.Discount__c == null) ? 0 : pbe.Discount__c));

		/*
		system.debug('Quantity : ' + pbe.Quantity__c);
		system.debug('Discount : ' + pbe.Discount__c );
		system.debug('UnitPrice : ' + pbe.UnitPrice);
		system.debug('UnitPrice (c) : ' + pbe.UnitPrice__c);
		system.debug('Sales Price : ' + pbe.SalesPrice__c ); 
		*/

        return pbe;
    }

	private static Decimal getQuantitySalesPrice(PricebookEntry pbe){
		Decimal salesPrice = pbe.UnitPrice;
		if(pbe.From_Quantity_4__c != null && pbe.From_Price_4__c != null && pbe.From_Quantity_4__c >=1 && pbe.From_Quantity_4__c <= pbe.Quantity__c){
			salesPrice = pbe.From_Price_4__c;
		} else if(pbe.From_Quantity_3__c != null && pbe.From_Price_3__c != null && pbe.From_Quantity_3__c >=1 && pbe.From_Quantity_3__c <= pbe.Quantity__c){
			salesPrice = pbe.From_Price_3__c;
		} else if(pbe.From_Quantity_2__c != null && pbe.From_Price_2__c != null && pbe.From_Quantity_2__c >=1 && pbe.From_Quantity_2__c <= pbe.Quantity__c){
			salesPrice = pbe.From_Price_2__c;
		} else if(pbe.From_Quantity_1__c != null && pbe.From_Price_1__c != null && pbe.From_Quantity_1__c >=1 && pbe.From_Quantity_1__c <= pbe.Quantity__c){
			salesPrice = pbe.From_Price_1__c;
		} 
		return salesPrice;
	}
}