public with sharing class Ctrl_InvoicePrevious {
    //private final Subscription25__Invoice__c invoice;
   public Subscription25__Invoice__c invoice {get; private set;}
    public Subscription25__Debtor_Number__c debtorNumber {get; private set;}
    public string displayLanguage{get;set;}

    private Map<String, Ctrl_InvoicePrevious.InvoiceItem> itemMap;
    private Map<Decimal, Ctrl_InvoicePrevious.VATItem> vatMap;

    private Boolean wasPaid;

    public Decimal sum {get; private set;}
    public Decimal total {get; private set;}
    public Decimal taxAmount {get; private set;}

    public Boolean showPOInDetails {get; private set;}

    public Ctrl_InvoicePrevious(ApexPages.StandardController stdController) {
       //this.invoice = (Subscription25__Invoice__c)stdController.getRecord();

       this.invoice = [SELECT
                       id, Subscription25__Purchase_Order_Number__c, Subscription25__Total_Amount__c, Subscription25__Invoice_Date__c
                       , Percentage_VAT__c, Amount_VAT__c, Amount_Gross__c, IsPrivate__c
                       , Subscription25__Account__c, Subscription25__Account__r.Sales_Language__c, Subscription25__Account__r.Reseller_Name__c
                       , Subscription25__Account__r.RecordType.Developername, Subscription25__Account__r.Invoice_Payment_Remark__c
                       , Account_Contract__c, Account_Contract__r.Invoice_Payment_Remark__c
                       , Subscription25__Administration__c
                       , Payment_Method_Result__c
                       , Sales_Channel__c
                    FROM
                       Subscription25__Invoice__c
                    WHERE
                       id = :ApexPages.currentPage().getParameters().get('Id')
                    LIMIT 1
                    ];

       this.debtorNumber = [SELECT
                         id, Subscription25__Debtor_Number__c
                       FROM
                         Subscription25__Debtor_Number__c
                       WHERE
                         Subscription25__Account__c = :this.invoice.Subscription25__Account__c
                         AND Subscription25__Administration__c = :this.invoice.Subscription25__Administration__c
                       LIMIT 1
                    ];


        List<OrderItem> orderItems = [
           SELECT Subscription25__Product__r.Name, Subscription25__VAT_Percentage__c, Product_Code__c,
            Quantity, UnitPrice, Description, ServiceDate, EndDate, Subscription25__Use_ICP__c,
            Invoice_Description__c, Remarks_Customer__c, PoNumber__c, Additional_Installation_Description__c,
            Product_Code_Customer__c, Product_Name__c, Invoice_Grouping__c,
            Order.Name, Order.EffectiveDate, Order.EndDate,
            Order.Account.Name,
            Order.BillToContact.Name,
            //Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Description__c,
            //Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Entity__r.Name,
            Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Order_Description__c,
            //Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Subscription25__Purchase_Order_Number__c,
            Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Paid_Until__c
         FROM OrderItem
         WHERE Order.Subscription25__Invoice__c = :this.invoice.Id
         // temp solution prevents job from crash
       ];


       this.displayLanguage = String.isNotBlank(this.invoice.Subscription25__Account__r.Sales_Language__c) ? this.invoice.Subscription25__Account__r.Sales_Language__c : 'en';
       this.displayLanguage = this.displayLanguage.toLowerCase();

       //get all product ids from the quote lines
       Set<Id> prodIds = Util_System.collectIdValues(orderItems, 'Subscription25__Product__c');
       //load all translations and map them from product id to translation
       List<Data_Translation__c> translations = [
           SELECT Name__c, Description__c, Product__c
           FROM Data_Translation__c
           WHERE Product__c IN :prodIds
               AND Language__c = :this.displayLanguage
       ];
       Map<Id, Data_Translation__c> translationMap = new Map<Id, Data_Translation__c>();
       for(Data_Translation__c translation : translations){
           translationMap.put(translation.Product__c, translation);
       }

       this.itemMap = new Map<String, Ctrl_InvoicePrevious.InvoiceItem>();
       this.vatMap = new Map<Decimal, Ctrl_InvoicePrevious.VATItem>();

       this.showPOInDetails = !String.isBlank(this.invoice.Subscription25__Purchase_Order_Number__c) && this.invoice.Subscription25__Purchase_Order_Number__c.contains(',');
       this.wasPaid = false;
       for(OrderItem item : orderItems){
           Data_Translation__c curTrans = translationMap.get(item.Subscription25__Product__c);
           if((curTrans != null) && (!String.isBlank(curTrans.Name__c))){
               item.Subscription25__Product__r.Name = curTrans.Name__c;
           }

           String aggregateKey = item.Invoice_Grouping__c;
           if(!this.itemMap.containsKey(aggregateKey)){
               Ctrl_InvoicePrevious.InvoiceItem invItem = new Ctrl_InvoicePrevious.InvoiceItem(this, item);
               this.itemMap.put(aggregateKey, invItem);
           } else {
               this.itemMap.get(aggregateKey).addItem(item);
           }


           //add the amount to the proper taxt value
           Decimal vatPerc = item.Subscription25__VAT_Percentage__c;
           if(!this.vatMap.containsKey(vatPerc)){
               this.vatMap.put(vatPerc, new Ctrl_InvoicePrevious.VATItem(vatPerc));
           }
           this.vatMap.get(vatPerc).addAmount(item.Quantity * item.UnitPrice);

           //check if the invoice was paid, because the contract's paid until field is on or
           //after the current end date
           if(item.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Paid_Until__c > item.Order.EndDate){
               this.wasPaid = true;
           }
       }

       this.sum = 0;
       for (InvoiceItem item : this.itemMap.values()) {
         this.sum += item.getTotal();
       }

       this.taxAmount = 0;
       for(Ctrl_InvoicePrevious.VATItem vatItem : this.vatMap.values()){
         this.taxAmount += vatItem.getVATAmount();
       }

       this.total = Ctrl_InvoicePrevious.format(this.sum + this.taxAmount);
       this.sum = Ctrl_InvoicePrevious.format(this.sum);
       this.taxAmount = Ctrl_InvoicePrevious.format(this.taxAmount);
    }

    public String getIsPdf(){
        return ApexPages.currentPage().getParameters().containsKey('h') ? 'html' : 'pdf';
    }

    public Boolean getShowPayment(){
        return !String.isBlank(this.getPaymentText());
    }

    private static final Map<String, String> PAYMENT_TEXTS_NL = new Map<String, String>();
    private static final Map<String, String> PAYMENT_TEXTS_DE = new Map<String, String>();
    private static final Map<String, String> PAYMENT_TEXTS_UK = new Map<String, String>();
    private static final Map<String, Integer> PAYMENT_DAYS = new Map<String, Integer>();
   static {
       // 20220702 - TRi added payment Mollie payment, tru webshop, ook voor DE en UK
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('P0', 'Factuur is reeds voldaan via de webshop.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('P1', 'Factuur is reeds voldaan via een kaartbetaling.');

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('08', 'Gelieve het factuurbedrag voor {0} te voldoen.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('14', 'Gelieve het factuurbedrag voor {0} te voldoen.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('30', 'Gelieve het factuurbedrag voor {0} te voldoen.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('60', 'Gelieve het factuurbedrag voor {0} te voldoen.');

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('I0', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //UK Debit
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('I8', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('I4', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('I3', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('E8', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('E4', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('E3', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('S8', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('S4', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.put('S3', 'Het factuurbedrag wordt rond {0} van uw rekening afgeschreven.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('P0', 'Rechnung wurde bereits über den Webshop bezahlt.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('P1', 'Rechnung wurde bereits per Kartenzahlung bezahlt.');

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('08', 'Bitte überweisen Sie den Betrag bis zum {0}.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('14', 'Bitte überweisen Sie den Betrag bis zum {0}.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('30', 'Bitte überweisen Sie den Betrag bis zum {0}.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('60', 'Bitte überweisen Sie den Betrag bis zum {0}.');

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('I0', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //UK Debit
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('I8', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('I4', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('I3', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('E8', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('E4', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('E3', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('S8', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('S4', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.put('S3', 'Der Rechnungsbetrag wird gegen {0} von Ihrem Konto abgebucht.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('P0', 'Invoice has already been paid via the webshop.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('P1', 'Invoice has already been paid via card payment.');

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('08', 'Please pay the invoice amount before {0}.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('14', 'Please pay the invoice amount before {0}.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('30', 'Please pay the invoice amount before {0}.');
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('60', 'Please pay the invoice amount before {0}.');

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('I0', 'The invoice amount will be debited from your account around {0}.'); //UK Debit
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('I8', 'The invoice amount will be debited from your account around {0}.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('I4', 'The invoice amount will be debited from your account around {0}.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('I3', 'The invoice amount will be debited from your account around {0}.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('E8', 'The invoice amount will be debited from your account around {0}.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('E4', 'The invoice amount will be debited from your account around {0}.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('E3', 'The invoice amount will be debited from your account around {0}.'); //30 dagen

       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('S8', 'The invoice amount will be debited from your account around {0}.'); //8 days
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('S4', 'The invoice amount will be debited from your account around {0}.'); //14 dagen
       Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.put('S3', 'The invoice amount will be debited from your account around {0}.'); //30 dagen

       //these shouldn't be shown, so they're not put in the map
       //Ctrl_InvoicePrevious.PAYMENT_TEXTS.put('C', '');
       //Ctrl_InvoicePrevious.PAYMENT_TEXTS.put('p0', '');
       //Ctrl_InvoicePrevious.PAYMENT_TEXTS.put('GR', '');

       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('I0', 12); // UK Card Payment, put on 5 difference between 8th of the month (create invoice) and debit data 15th of the month
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('E8', 8);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('I8', 8);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('S8', 8);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('08', 8);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('14', 14);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('E4', 14);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('I4', 14);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('S4', 14);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('30', 30);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('E3', 30);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('I3', 30);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('S3', 30);
       Ctrl_InvoicePrevious.PAYMENT_DAYS.put('60', 60);
   }

    public String getPaymentText(){
       string paymentText;

       String reseller = this.invoice.Subscription25__Account__r.Reseller_Name__c;

       if (reseller == '6') {
         paymentText = this.getPaymentTextUK();

       } else if (reseller == '5') {
         paymentText = this.getPaymentTextDE();

       } else {
         paymentText = this.getPaymentTextNL();
       }

       return paymentText;
    }

    private String getPaymentMethod() {
       String returnValue = 'I8';

       if(!String.isBlank(this.invoice.Payment_Method_Result__c)) {
           returnValue = this.invoice.Payment_Method_Result__c;
       }

       return returnValue.toUpperCase();
    }

    private String getPaymentTextNL() {
       if(this.invoice.Subscription25__Total_Amount__c <= 0){
           return '';
       }

       if(this.wasPaid){
           return 'Deze factuur is reeds betaald.';
       }

       String paymentMethod = this.getPaymentMethod();
       system.debug(paymentMethod);
       if(!Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.containsKey(paymentMethod)){
           return '';
       }

       String paymentText = Ctrl_InvoicePrevious.PAYMENT_TEXTS_NL.get(paymentMethod);
       Integer numDays = Ctrl_InvoicePrevious.PAYMENT_DAYS.containsKey(paymentMethod) ? Ctrl_InvoicePrevious.PAYMENT_DAYS.get(paymentMethod) : 0;
       Date dt = this.invoice.Subscription25__Invoice_Date__c.addDays(numDays);
       String dtStr = Util_System.formatDate(dt, 'dd-MM-yyyy');
       return 'Betalingsconditie: ' + String.format(paymentText, new List<String>{dtStr});

    }

    private String getPaymentTextDE(){
       if(this.invoice.Subscription25__Total_Amount__c <= 0){
           return '';
       }

       if(this.wasPaid){
           return 'Diese Rechnung wurde bereits bezahlt.';
       }

       String paymentMethod = this.getPaymentMethod();
       if(!Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.containsKey(paymentMethod)){
           return '';
       }

       String paymentText = Ctrl_InvoicePrevious.PAYMENT_TEXTS_DE.get(paymentMethod);
       Integer numDays = Ctrl_InvoicePrevious.PAYMENT_DAYS.containsKey(paymentMethod) ? Ctrl_InvoicePrevious.PAYMENT_DAYS.get(paymentMethod) : 0;
       Date dt = this.invoice.Subscription25__Invoice_Date__c.addDays(numDays);
       String dtStr = Util_System.formatDate(dt, 'dd-MM-yyyy');
       return 'Zahlungsbedingung: ' + String.format(paymentText, new List<String>{dtStr});
    }

    private String getPaymentTextUK(){
       if(this.invoice.Subscription25__Total_Amount__c <= 0){
           return '';
       }

       if(this.wasPaid){
           return 'Paid in full - Thank you';
       }

       String paymentMethod = this.getPaymentMethod();
       if(!Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.containsKey(paymentMethod)){
           return '';
       }

       String paymentText = Ctrl_InvoicePrevious.PAYMENT_TEXTS_UK.get(paymentMethod);
       Integer numDays = Ctrl_InvoicePrevious.PAYMENT_DAYS.containsKey(paymentMethod) ? Ctrl_InvoicePrevious.PAYMENT_DAYS.get(paymentMethod) : 0;
       Date dt = this.invoice.Subscription25__Invoice_Date__c.addDays(numDays);
       String dtStr = Util_System.formatDate(dt, 'dd-MM-yyyy');
       return 'Payment condition: ' + String.format(paymentText, new List<String>{dtStr});
    }

    public List<List<Ctrl_InvoicePrevious.InvoiceItem>> getItems(){
       List<Ctrl_InvoicePrevious.InvoiceItem> items = this.itemMap.values();
       items.sort();

       List<List<Ctrl_InvoicePrevious.InvoiceItem>> splitItems = new List<List<Ctrl_InvoicePrevious.InvoiceItem>>();
       for(Integer i=0; i<items.size(); i++){
           if(Math.mod(i, 900) == 0){
             splitItems.add(new List<Ctrl_InvoicePrevious.InvoiceItem>());
           }
           splitItems[splitItems.size()-1].add(items[i]);
       }

       return splitItems;
    }

    public List<Ctrl_InvoicePrevious.VATItem> getVATItems(){
       List<Ctrl_InvoicePrevious.VATItem> items = this.vatMap.values();
       items.sort();
       return items;
    }

    private static Decimal format(Decimal amount) {
       return amount != null ? amount.setScale(2, RoundingMode.HALF_UP) : 0;
    }

    private static String formatPeriod(OrderItem item){
       String periodString = '';
       if(item.ServiceDate != null){
         periodString = DateTime.newInstance(item.ServiceDate, Time.newInstance(12, 0, 0, 0)).format('dd-MM-yyyy');
       }
       if(item.EndDate != null){
         periodString += ' - ' + DateTime.newInstance(item.EndDate, Time.newInstance(12, 0, 0, 0)).format('dd-MM-yyyy');
       }
       return periodString;
    }

    private class InvoiceItem implements Comparable {
       private Ctrl_InvoicePrevious parent;
       public OrderItem item {get; private set;}
       private String guid;
       public String productNumber {get; private set;}
       public String label {get; private set;}
       public Decimal price {get; private set;}
       public Decimal quantity {get; private set;}
       public Decimal tax {get; private set;}

       public InvoiceItem(Ctrl_InvoicePrevious parent, OrderItem oi) {
         this.parent = parent;
         this.item = oi;
         this.guid = Util_System.generateGUID();
         this.productNumber = oi.Product_Code__c;
         this.quantity = oi.Quantity;
         this.price = oi.UnitPrice;
         this.tax = oi.Subscription25__VAT_Percentage__c;
         /*
         this.label = oi.Subscription25__Product__r.Name;

           if(oi.Order.Subscription25__Recurring_Order__c != null){
               this.label += '<br />'+oi.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Order_Description__c;
            //this.label += '<br />'+oi.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Description__c;
           }
           if(oi.ServiceDate != null && oi.EndDate != null){
               this.label += '<br />'+Util_System.formatDate(oi.ServiceDate, 'dd-MM-yyyy') + ' t/m ' + Util_System.formatDate(oi.EndDate, 'dd-MM-yyyy');
           }
           if(this.parent.showPOInDetails && oi.Order.Subscription25__Recurring_Order__c != null && !String.isBlank(oi.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Subscription25__Purchase_Order_Number__c)){
               this.label += '<br />PO: ' + oi.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Subscription25__Purchase_Order_Number__c;
           }
         */
         this.label = oi.Invoice_Description__c;
         if(oi.Additional_Installation_Description__c != null) {
            this.label += '<br />'+oi.Additional_Installation_Description__c;
         }

        if (oi.Invoice_Grouping__c.equals(oi.Id)) {

            if(oi.Product_Name__c != null) {
            this.label += '<br />';
            if(oi.Product_Code_Customer__c != null) {
                this.label += oi.Product_Code_Customer__c + ' ';
            }
            this.label += oi.Product_Name__c;
            }

            if(oi.PoNumber__c != null){
                this.label += '<br />PO: ' + oi.PoNumber__c;
            }

            if(oi.Remarks_Customer__c != null ){
                this.label += '<br />'+oi.Remarks_Customer__c;
            }
        }

       }

       public void addItem(OrderItem oi){
           this.quantity += oi.Quantity;
       }

       public Decimal getTotal() {
         Decimal total = this.price * this.quantity;
         return Ctrl_InvoicePrevious.format(total);
       }

       public Integer compareTo(Object obj){
         Ctrl_InvoicePrevious.InvoiceItem that = (Ctrl_InvoicePrevious.InvoiceItem)obj;
         Integer compVal = 0;
         if(this.item.ServiceDate != null && that.item.ServiceDate != null){
            compVal = that.item.ServiceDate.daysBetween(this.item.ServiceDate);
         }

         if(compVal == 0 && this.item.Order.Subscription25__Recurring_Order__c != null && that.item.Order.Subscription25__Recurring_Order__c != null){

             String myPlate = this.item.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Order_Description__c;
            //String myPlate = this.item.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Description__c;
            String theirPlate = that.item.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Order_Description__c;
            //String theirPlate = that.item.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Description__c;
            compVal = !String.isBlank(myPlate) && !String.isBlank(theirPlate) ? myPlate.compareTo(theirPlate) : 0;
         }
         return compVal;
       }
    }

    public void getTest(){
       this.getIsPdf();
       this.getItems();
       this.getPaymentText();
       this.getPaymentTextDE();
       this.getPaymentTextNL();
       this.getPaymentTextUK();
       this.getShowPayment();
       this.getVATItems();
    }

    private class VATItem implements Comparable {
       public Decimal percentage {get; private set;}
       public Decimal amount {get; private set;}

       public VATItem(Decimal percentage){
         this.percentage = percentage;
         this.amount = 0;
       }

       public void addAmount(Decimal amt){
         this.amount += amt;
       }

       public Decimal getVATAmount(){
         Decimal vatAmount = this.amount * (this.percentage / 100);
         return vatAmount.setScale(2);
       }

       public Integer compareTo(Object obj){
         Ctrl_InvoicePrevious.VATItem that = (Ctrl_InvoicePrevious.VATItem)obj;
         return (Integer)(this.percentage - that.percentage);
       }
    }
}