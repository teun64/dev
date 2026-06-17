public without sharing class Ctrl_Invoice {
  private final Subscription25__Invoice__c invoice;
  private final Subscription25__Debtor_Number__c debtorNumber;
  private final Util_Wrappers.AdminWrapper admin;
  private final Boolean invoiceGrouping;
  private final String paymentMethod;
  private final string vatMethod;

  //public Subscription25__Invoice__c invoice {get; private set;}
  //public Subscription25__Debtor_Number__c debtorNumber {get; private set;}
  //public Boolean invoiceGrouping{get; private set;}

  private final Map<String, Ctrl_Invoice.InvoiceItem> itemMap;
  private final Map<String, Ctrl_Invoice.VATItem> vatMap;
  //private Map<Decimal, Ctrl_Invoice.VATItem> vatMap;

  private Boolean wasPaid;

  public Decimal amountNet {get; private set;}
  public Decimal amountGross {get; private set;}
  public Decimal amountVAT {get; private set;}
  public Boolean showPOInDetails {get; private set;}

  //public Ctrl_Invoice(ApexPages.StandardController stdController) {
  public Ctrl_Invoice() {
    //this.invoice = (Subscription25__Invoice__c)stdController.getRecord();

    this.invoice = 
      [
        SELECT
          id, Subscription25__Purchase_Order_Number__c, Subscription25__Total_Amount__c, Subscription25__Invoice_Date__c , Subscription25__Due_Date__c     
          , Subscription25__Account__c, Subscription25__Account__r.Name, Subscription25__Account__r.Sales_Language__c, Subscription25__Account__r.Reseller_Name__c
          , Subscription25__Account__r.RecordType.Developername, Subscription25__Account__r.Invoice_Grouping__c, Subscription25__Account__r.Invoice_Grouping_Option__c, Subscription25__Account__r.Invoice_VAT_Calculation__c
          , Subscription25__Account__r.Invoice_Payment_Remark__c, Subscription25__Account__r.FinancialDebtorNumber__c
          , Account_Contract__r.Invoice_Payment_Remark__c
          , Subscription25__Administration__c
          , Subscription25__VAT_Number__c, Subscription25__Invoice_Number__c
          , Subscription25__Billing_Country__c, Subscription25__Billing_City__c, Subscription25__Billing_Street__c, Subscription25__Billing_Postal_Code__c
          , Subscription25__Contact_Person__c, Subscription25__Contact_Person__r.Name
          , Language__c, Account_Contract__c, Payment_Method_Result__c, Sales_Channel__c, New_Branding__c, Cost_Center_invoicing__c, Invoice_Description__c
          , Percentage_VAT__c, Amount_VAT__c, Amount_Gross__c, IsPrivate__c
        FROM
          Subscription25__Invoice__c
        WHERE
          id = :ApexPages.currentPage().getParameters().get('Id')
        LIMIT 1
      ];

    this.debtorNumber = 
      [
          SELECT
            id, Subscription25__Debtor_Number__c
          FROM
            Subscription25__Debtor_Number__c
          WHERE
            Subscription25__Account__c = :this.invoice.Subscription25__Account__c
            AND Subscription25__Administration__c = :this.invoice.Subscription25__Administration__c
          LIMIT 1
        ];

    this.admin = new Util_Wrappers.AdminWrapper([
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
          Id = :this.invoice.Subscription25__Administration__c
        LIMIT 1
    ]);

    List<OrderItem> orderItems = 
      [
        SELECT 
          Product_Code__c, Quantity, UnitPrice, Description, InvoiceStartDate__c, InvoiceEndDate__c, 
          Invoice_Description__c, Remarks_Customer__c, PoNumber__c, Additional_Installation_Description__c,
          Product_Code_Customer__c, Product_Name__c, Invoice_Grouping__c, 
          Subscription25__Use_ICP__c, Subscription25__VAT_Code__c, Subscription25__VAT_Percentage__c,
          Subscription25__Total_Price__c, Subscription25__Gross_Amount__c, 
          Amount_Net__c, Amount_VAT__c, Amount_Gross__c,
          Order.Name, Order.EffectiveDate, Order.EndDate, Order.Account.Name, Order.BillToContact.Name,
          Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Order_Description__c,
          Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Paid_Until__c,
          Subscription25__Product__r.Name 
        FROM 
          OrderItem
        WHERE 
          Order.Subscription25__Invoice__c = :this.invoice.Id
          // temp solution prevents job from crash
      ];

    this.invoiceGrouping = ((invoice.Subscription25__Account__r.Invoice_Grouping__c) && String.isNotBlank(invoice.Subscription25__Account__r.Invoice_Grouping_Option__c));
    this.vatMethod = invoice.Subscription25__Account__r.Invoice_VAT_Calculation__c;
    this.showPOInDetails = String.isNotBlank(this.invoice.Subscription25__Purchase_Order_Number__c) && this.invoice.Subscription25__Purchase_Order_Number__c.contains(',');
    this.wasPaid = false;
    this.paymentMethod = String.isNotBlank(this.invoice.Payment_Method_Result__c) ? this.invoice.Payment_Method_Result__c.toUpperCase() : 'I8';

    /*
    //get all product ids from the quote lines
    Set<Id> prodIds = Util_System.collectIdValues(orderItems, 'Subscription25__Product__c');
    //load all translations and map them from product id to translation
    List<Data_Translation__c> translations =
      [
        SELECT 
          Name__c, Description__c, Product__c
        FROM 
          Data_Translation__c
        WHERE 
          Product__c IN :prodIds
          AND Language__c = :this.language
       ];

    Map<Id, Data_Translation__c> translationMap = new Map<Id, Data_Translation__c>();
    for(Data_Translation__c translation : translations){
      translationMap.put(translation.Product__c, translation);
    }
    */

    this.itemMap = new Map<String, Ctrl_Invoice.InvoiceItem>();
    //this.vatMap = new Map<Decimal, Ctrl_Invoice.VATItem>();
    this.vatMap = new Map<String, Ctrl_Invoice.VATItem>();

    Decimal vatPerc;
    String vatCode;

    this.amountNet = 0;
    for(OrderItem item : orderItems){
      // 2024 summrieze can be don as wel when doing the data translation
      /*
      Data_Translation__c curTrans = translationMap.get(item.Subscription25__Product__c);
      if((curTrans != null) && (!String.isBlank(curTrans.Name__c))){
        item.Subscription25__Product__r.Name = curTrans.Name__c;
      }
      */

      String aggregateKey = item.Invoice_Grouping__c;
      if(!this.itemMap.containsKey(aggregateKey)){
        Ctrl_Invoice.InvoiceItem invItem = new Ctrl_Invoice.InvoiceItem(this, item);
        this.itemMap.put(aggregateKey, invItem);
      } else {
        this.itemMap.get(aggregateKey).addItem(item);
      }

      this.amountNet += item.Amount_Net__c;

      //add the amount to the proper vat value
      if (!this.invoiceGrouping) {
        vatPerc = item.Subscription25__VAT_Percentage__c;
        vatCode = item.Subscription25__VAT_Code__c;

        if(!this.vatMap.containsKey(vatCode)){
          this.vatMap.put(vatCode, new Ctrl_Invoice.VATItem(vatCode, this.vatMethod, vatPerc));
        }

        this.vatMap.get(vatCode).addAmounts(item.Amount_Net__c, item.Amount_VAT__c, item.Amount_Gross__c);
      }

      //after the current end date
      if(item.Order.Subscription25__Recurring_Order__r.Subscription25__Contract_Product__r.Subscription25__Contract__r.Paid_Until__c > item.Order.EndDate){
          this.wasPaid = true;
      }

    }

    if (this.invoiceGrouping) {
      for (ctrl_invoice.InvoiceItem invoiceItem : itemMap.values()) {
        invoiceItem.setAmounts();

        vatPerc = invoiceItem.vatPercentage;
        vatCode = invoiceItem.vatCode;

        if(!this.vatMap.containsKey(vatCode)){
          this.vatMap.put(vatCode, new Ctrl_Invoice.VATItem(vatCode, this.vatMethod, vatPerc));
        }

        this.vatMap.get(vatCode).addAmounts(invoiceItem.amountNet, invoiceItem.amountVAT, invoiceItem.amountGross);
        system.debug(invoiceItem);

      }

    }

    this.amountVAT = 0;
    this.amountGross = 0;
    for(Ctrl_Invoice.VATItem vatItem : this.vatMap.values()){
      this.amountVAT += vatItem.amountVAT;
      this.amountGross += vatItem.amountGross;
    }

    this.amountGross = Ctrl_Invoice.format(this.amountGross);
    this.amountNet = Ctrl_Invoice.format(this.amountNet);
    this.amountVAT = Ctrl_Invoice.format(this.amountVAT);
  }


  public Util_Wrappers.AdminWrapper getAdmin() {
    return this.admin;
  }

  public Subscription25__Debtor_Number__c getDebtorNumber() {
    return this.debtorNumber;
  }

  public Subscription25__Invoice__c getInvoice() {
    return this.invoice;
  }

  public String getLanguage() {
    String returnValue = 'en';

    if(String.isNotBlank(this.invoice.Language__c)){
        returnValue = this.invoice.Language__c;
    }

    return returnValue.toLowerCase();
  }

  public String getPaymentType() {
    if (string.isBlank(this.paymentMethod)) return '';

    string paymentType = this.wasPaid ? 'V' : this.paymentMethod.isNumeric() ? 'A' : this.paymentMethod.left(1);

    if ((paymentType == 'E') || (paymentType == 'S')) {
      paymentType = 'I';
    } 

    return paymentType;
  }

  private String getPaymentMethod() {
    String returnValue = 'I8';

    if(!String.isBlank(this.invoice.Payment_Method_Result__c)) {
      returnValue = this.invoice.Payment_Method_Result__c;
    }

    return returnValue.toUpperCase();
  }

  public Boolean getShowPaymentRemark(){
    boolean showPaymentRemark;
    showPaymentRemark = ((this.getPaymentType() != 'C') && (this.invoice.Subscription25__Total_Amount__c > 0));
    return showPaymentRemark;
  }

  public String getPaymentRemark(){
    string paymentType = this.getPaymentType();
    string language = this.getLanguage();
    string paymentRemark = (paymentType == 'C') ? '' : System.Label.Get('', 'paymentRemark' + paymentType, language );
    return paymentRemark;
  }

  public Boolean getShowRemarkGeneral() {
    return this.admin.getInvoiceGeneralRemark();
  }

  public String getRemarkGeneral(){
    string language = this.getLanguage();
    string reseller = this.admin.getReseller();
    string remarkGeneral = (this.getShowRemarkGeneral()) ? System.Label.Get('', 'InvoiceRemarkGeneral' + reseller, language) : '';
    return remarkGeneral;
  }

  public Boolean getShowRemarkEU() {
    return ((this.admin.getInvoiceEURemark()) && (this.vatMap.containsKey('7')));
  }

  public String getRemarkEU(){
    string language = this.getLanguage();
    string reseller = this.admin.getReseller();
    string remarkEU = (this.getShowRemarkEU()) ? System.Label.Get('', 'InvoiceRemarkEU' + reseller, language) : '';
    return remarkEU;
  }

  public Boolean getShowRemarkNonEU() {
    return ((this.admin.getInvoiceNonEURemark()) && (this.vatMap.containsKey('6')));
  }

  public String getRemarkNonEU(){
    string language = this.getLanguage();
    string reseller = this.admin.getReseller();
    
    string remarkNonEU = (this.getShowRemarkNonEU()) ? System.Label.Get('', 'InvoiceRemarkNonEU' + reseller, language) : '';
    return remarkNonEU;
  }

  public String getIsPdf(){
    return ApexPages.currentPage().getParameters().containsKey('h') ? 'html' : 'pdf';
  }

  public Boolean getVatMethodTotal(){
    return (this.vatMethod == 'TOTAL');
  }

  public List<List<Ctrl_Invoice.InvoiceItem>> getItems(){
    List<Ctrl_Invoice.InvoiceItem> items = this.itemMap.values();
    items.sort();

    List<List<Ctrl_Invoice.InvoiceItem>> splitItems = new List<List<Ctrl_Invoice.InvoiceItem>>();
    for(Integer i=0; i<items.size(); i++){
      if(Math.mod(i, 900) == 0){
        splitItems.add(new List<Ctrl_Invoice.InvoiceItem>());
      }
      splitItems[splitItems.size()-1].add(items[i]);
    }

    return splitItems;
  }

  public List<Ctrl_Invoice.VATItem> getVATItems(){
    List<Ctrl_Invoice.VATItem> items = this.vatMap.values();
    items.sort();
    return items;
  }

  private static Decimal format(Decimal amount) {
    return amount != null ? amount.setScale(2, RoundingMode.HALF_UP) : 0;
  }

  private static String formatPeriod(OrderItem item){
    String periodString = '';
    if(item.InvoiceStartDate__c != null){
      periodString = DateTime.newInstance(item.InvoiceStartDate__c, Time.newInstance(12, 0, 0, 0)).format('dd-MM-yyyy');
    }
    if(item.InvoiceEndDate__c != null){
      periodString += ' - ' + DateTime.newInstance(item.InvoiceEndDate__c, Time.newInstance(12, 0, 0, 0)).format('dd-MM-yyyy');
    }
    return periodString;
  }

  private class InvoiceItem implements Comparable {
    private Ctrl_Invoice parent;
    public OrderItem item {get; private set;}
    private String guid;
    public String productNumber {get; private set;}
    public String label {get; private set;}
    public Decimal price {get; private set;}
    public Decimal quantity {get; private set;}
    public String vatCode {get; private set;}
    public Decimal vatPercentage {get; private set;}
    public Decimal amountNet {get; private set;}
    public Decimal amountVAT {get; private set;}
    public Decimal amountGross {get; private set;}

    public InvoiceItem(Ctrl_Invoice parent, OrderItem oi) {
      this.parent = parent;
      this.item = oi;
      this.guid = Util_System.generateGUID();
      this.productNumber = oi.Product_Code__c;
      this.quantity = oi.Quantity;
      this.price = oi.UnitPrice;
      this.vatCode = oi.Subscription25__VAT_Code__c;
      this.vatPercentage = oi.Subscription25__VAT_Percentage__c;
      this.amountNet = oi.Amount_Net__c;
      this.amountVAT = oi.Amount_VAT__c;
      this.amountGross = oi.Amount_Gross__c;
      this.label = (oi.Invoice_Description__c != null) ? ((oi.Invoice_Description__c.trim() != ',' ) ?  oi.Invoice_Description__c : '')  : '';

      if (oi.Invoice_Grouping__c.equals(oi.Id)) {
        if(oi.Additional_Installation_Description__c != null) {
          this.label += ((this.label.length() > 0) ? '<br />' : '' )+oi.Additional_Installation_Description__c;
        }

        if(oi.Product_Name__c != null) {
          this.label += ((this.label.length() > 0) ? '<br />' : '' );

          if(oi.Product_Code_Customer__c != null) {
            this.label += oi.Product_Code_Customer__c + ' ';
          }

          this.label += oi.Product_Name__c;
        }

        if(oi.PoNumber__c != null){
            this.label += ((this.label.length() > 0) ? '<br />' : '' ) + 'PO: ' + oi.PoNumber__c;
        }

        if(oi.Remarks_Customer__c != null ){
            this.label += ((this.label.length() > 0) ? '<br />' : '' )+oi.Remarks_Customer__c;
        }
      }
      
    }

    public void addItem(OrderItem oi){
      this.quantity += oi.Quantity;
      this.amountNet += oi.Amount_Net__c;
    }

    private void setAmounts() {
      this.amountVAT = Ctrl_Invoice.format((this.amountNet * (this.vatPercentage/100)));
      this.amountGross = Ctrl_Invoice.format(this.amountNet + this.amountVAT);
    }

    public Decimal getTotal() {
      return this.amountNet;
    }

    public Integer compareTo(Object obj){
      Ctrl_Invoice.InvoiceItem that = (Ctrl_Invoice.InvoiceItem)obj;
      Integer compVal = 0;
      if(this.item.InvoiceStartDate__c != null && that.item.InvoiceStartDate__c != null){
        compVal = that.item.InvoiceStartDate__c.daysBetween(this.item.InvoiceStartDate__c);
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
    this.getInvoice();
    this.getDebtorNumber();
    this.getLanguage();
    this.getIsPdf();
    this.getItems();
    this.getPaymentMethod();
    this.getPaymentRemark();
    this.getShowPaymentRemark();
    this.getShowRemarkGeneral();
    this.getShowRemarkNonEU();
    this.getShowRemarkEU();
    this.getVATItems();
  }

  private class VATItem implements Comparable {
    private Decimal amountVATTotal;
    private Decimal amountVATLine;
    private Decimal amountGrossLine;
    public String code {get; private set;}
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

    public VATItem(String code, String method, Decimal percentage){
      this.code = code;
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
      this.amountVATTotal = (this.amountNet * this.percentage); 
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
      Ctrl_Invoice.VATItem that = (Ctrl_Invoice.VATItem)obj;
      Integer thatCode = Integer.valueOf(that.code);
      Integer thisCode = Integer.valueOf(this.code);
      
      if (thisCode == thatCode) return 0;
      if (thisCode > thatCode) return 1;
      return -1;  
    }
  }
}