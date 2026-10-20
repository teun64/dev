/**
 * Builds an EN 16931 (UN/CEFACT Cross Industry Invoice, "CII") XML document for a
 * Subscription25__Invoice__c record, for embedding into a ZUGFeRD/Factur-X hybrid PDF/A-3.
 *
 * Assumes the "EN 16931" (Comfort) profile - urn:cen.eu:en16931:2017. Swap GUIDELINE_ID to
 * 'urn:factur-x.eu:1p0:en16931' if the merge service specifically wants the Factur-X spelling.
 *
 * Line grouping and VAT rounding math is shared with Ctrl_Invoice via Util_InvoiceLineAggregator,
 * so the human-readable PDF and this CII XML can never disagree on how lines are merged. Note the
 * VAT breakdown here is grouped by UNCL5305 category+rate (what EN16931 requires), which is a
 * different grouping key than Ctrl_Invoice uses for its own footer (grouped by internal VAT code,
 * for its accounting legend) - both are valid uses of the same shared aggregator.
 */
public with sharing class Svc_CIIInvoiceXmlBuilder {

    private static final String GUIDELINE_ID = 'urn:cen.eu:en16931:2017';
    private static final String NS_RSM = 'urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100';
    private static final String NS_RAM = 'urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100';
    private static final String NS_UDT = 'urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100';
    private static final String DATE_FORMAT_102 = '102';

    public static String buildXml(Id invoiceId) {
        InvoiceData data = loadInvoiceData(invoiceId);

        Dom.Document doc = new Dom.Document();
        Dom.XmlNode root = doc.createRootElement('CrossIndustryInvoice', NS_RSM, 'rsm');
        root.setNamespace('ram', NS_RAM);
        root.setNamespace('udt', NS_UDT);

        buildExchangedDocumentContext(root);
        buildExchangedDocument(root, data);
        buildSupplyChainTradeTransaction(root, data);

        return doc.toXmlString();
    }

    // ---- ExchangedDocumentContext / ExchangedDocument ------------------------------------

    private static void buildExchangedDocumentContext(Dom.XmlNode root) {
        Dom.XmlNode context = rsm(root, 'ExchangedDocumentContext');
        Dom.XmlNode param = ram(context, 'GuidelineSpecifiedDocumentContextParameter');
        ramText(param, 'ID', GUIDELINE_ID);
    }

    private static void buildExchangedDocument(Dom.XmlNode root, InvoiceData data) {
        Dom.XmlNode document = rsm(root, 'ExchangedDocument');
        ramText(document, 'ID', data.invoiceNumber);
        ramText(document, 'TypeCode', data.invoiceTypeCode);

        Dom.XmlNode issueDateTime = ram(document, 'IssueDateTime');
        udtDateTime(issueDateTime, data.invoiceDate);
    }

    // ---- SupplyChainTradeTransaction ------------------------------------------------------

    private static void buildSupplyChainTradeTransaction(Dom.XmlNode root, InvoiceData data) {
        Dom.XmlNode tradeTransaction = rsm(root, 'SupplyChainTradeTransaction');

        Integer lineNumber = 1;
        for (LineData line : data.lines) {
            buildLineItem(tradeTransaction, line, lineNumber, data.currencyCode);
            lineNumber++;
        }

        buildHeaderTradeAgreement(tradeTransaction, data);
        ram(tradeTransaction, 'ApplicableHeaderTradeDelivery'); // structurally required, no content needed here
        buildHeaderTradeSettlement(tradeTransaction, data);
    }

    private static void buildLineItem(Dom.XmlNode tradeTransaction, LineData line, Integer lineNumber, String currencyCode) {
        Dom.XmlNode item = ram(tradeTransaction, 'IncludedSupplyChainTradeLineItem');

        Dom.XmlNode lineDoc = ram(item, 'AssociatedDocumentLineDocument');
        ramText(lineDoc, 'LineID', String.valueOf(lineNumber));

        Dom.XmlNode product = ram(item, 'SpecifiedTradeProduct');
        ramText(product, 'Name', line.name);

        Dom.XmlNode agreement = ram(item, 'SpecifiedLineTradeAgreement');
        Dom.XmlNode netPrice = ram(agreement, 'NetPriceProductTradePrice');
        ramAmount(netPrice, 'ChargeAmount', line.unitPrice, null);

        Dom.XmlNode delivery = ram(item, 'SpecifiedLineTradeDelivery');
        Dom.XmlNode quantity = ramText(delivery, 'BilledQuantity', formatAmount(line.quantity));
        if (String.isNotBlank(line.uneceUnitCode)) {
            quantity.setAttribute('unitCode', line.uneceUnitCode);
        }

        Dom.XmlNode settlement = ram(item, 'SpecifiedLineTradeSettlement');
        Dom.XmlNode tax = ram(settlement, 'ApplicableTradeTax');
        ramText(tax, 'TypeCode', 'VAT');
        ramText(tax, 'CategoryCode', line.vatCategoryCode);
        ramText(tax, 'RateApplicablePercent', formatAmount(line.vatPercent));

        Dom.XmlNode lineSummation = ram(settlement, 'SpecifiedTradeSettlementLineMonetarySummation');
        ramAmount(lineSummation, 'LineTotalAmount', line.netAmount, null);
    }

    private static void buildHeaderTradeAgreement(Dom.XmlNode tradeTransaction, InvoiceData data) {
        Dom.XmlNode agreement = ram(tradeTransaction, 'ApplicableHeaderTradeAgreement');

        if (String.isNotBlank(data.buyerReference)) {
            ramText(agreement, 'BuyerReference', data.buyerReference);
        }

        Dom.XmlNode seller = ram(agreement, 'SellerTradeParty');
        ramText(seller, 'Name', data.sellerName);
        if (String.isNotBlank(data.sellerCoCNumber)) {
            Dom.XmlNode legalOrg = ram(seller, 'SpecifiedLegalOrganization');
            ramText(legalOrg, 'ID', data.sellerCoCNumber);
        }
        Dom.XmlNode sellerAddress = ram(seller, 'PostalTradeAddress');
        ramText(sellerAddress, 'PostcodeCode', data.sellerPostalCode);
        ramText(sellerAddress, 'LineOne', data.sellerStreet);
        ramText(sellerAddress, 'CityName', data.sellerCity);
        ramText(sellerAddress, 'CountryID', data.sellerCountryCode);
        if (String.isNotBlank(data.sellerVatNumber)) {
            Dom.XmlNode sellerTax = ram(seller, 'SpecifiedTaxRegistration');
            Dom.XmlNode sellerTaxId = ramText(sellerTax, 'ID', data.sellerVatNumber);
            sellerTaxId.setAttribute('schemeID', 'VA');
        }

        Dom.XmlNode buyer = ram(agreement, 'BuyerTradeParty');
        ramText(buyer, 'Name', data.buyerName);
        Dom.XmlNode buyerAddress = ram(buyer, 'PostalTradeAddress');
        ramText(buyerAddress, 'PostcodeCode', data.buyerPostalCode);
        ramText(buyerAddress, 'LineOne', data.buyerStreet);
        ramText(buyerAddress, 'CityName', data.buyerCity);
        ramText(buyerAddress, 'CountryID', data.buyerCountryCode);
        if (String.isNotBlank(data.buyerVatNumber)) {
            Dom.XmlNode buyerTax = ram(buyer, 'SpecifiedTaxRegistration');
            Dom.XmlNode buyerTaxId = ramText(buyerTax, 'ID', data.buyerVatNumber);
            buyerTaxId.setAttribute('schemeID', 'VA');
        }

        if (String.isNotBlank(data.purchaseOrderNumber)) {
            Dom.XmlNode poDoc = ram(agreement, 'BuyerOrderReferencedDocument');
            ramText(poDoc, 'IssuerAssignedID', data.purchaseOrderNumber);
        }
    }

    private static void buildHeaderTradeSettlement(Dom.XmlNode tradeTransaction, InvoiceData data) {
        Dom.XmlNode settlement = ram(tradeTransaction, 'ApplicableHeaderTradeSettlement');
        ramText(settlement, 'InvoiceCurrencyCode', data.currencyCode);

        if (String.isNotBlank(data.unclPaymentMeansCode)) {
            Dom.XmlNode paymentMeans = ram(settlement, 'SpecifiedTradeSettlementPaymentMeans');
            ramText(paymentMeans, 'TypeCode', data.unclPaymentMeansCode);
        }

        for (Util_InvoiceLineAggregator.VatBreakdown vat : data.vatBreakdown) {
            Dom.XmlNode tax = ram(settlement, 'ApplicableTradeTax');
            ramAmount(tax, 'CalculatedAmount', vat.vatAmount, null);
            ramText(tax, 'TypeCode', 'VAT');
            ramAmount(tax, 'BasisAmount', vat.netAmount, null);
            ramText(tax, 'CategoryCode', vat.code);
            // Util_InvoiceLineAggregator normalizes percentage to a 0-1 fraction internally
            // (mirrors Ctrl_Invoice's own VATItem) - undo that for the XML, same as Invoice.page does.
            ramText(tax, 'RateApplicablePercent', formatAmount(denormalizePercentage(vat.percentage)));
        }

        if (data.dueDate != null) {
            Dom.XmlNode paymentTerms = ram(settlement, 'SpecifiedTradePaymentTerms');
            Dom.XmlNode dueDateTime = ram(paymentTerms, 'DueDateDateTime');
            udtDateTime(dueDateTime, data.dueDate);
        }

        Dom.XmlNode summation = ram(settlement, 'SpecifiedTradeSettlementHeaderMonetarySummation');
        ramAmount(summation, 'LineTotalAmount', data.netAmount, null);
        ramAmount(summation, 'TaxBasisTotalAmount', data.netAmount, null);
        ramAmount(summation, 'TaxTotalAmount', data.vatAmount, data.currencyCode);
        ramAmount(summation, 'GrandTotalAmount', data.grossAmount, null);
        ramAmount(summation, 'DuePayableAmount', data.grossAmount, null);
    }

    // ---- XML helpers -----------------------------------------------------------------------

    private static Dom.XmlNode rsm(Dom.XmlNode parent, String name) {
        return parent.addChildElement(name, NS_RSM, 'rsm');
    }

    private static Dom.XmlNode ram(Dom.XmlNode parent, String name) {
        return parent.addChildElement(name, NS_RAM, 'ram');
    }

    private static Dom.XmlNode ramText(Dom.XmlNode parent, String name, String text) {
        Dom.XmlNode node = ram(parent, name);
        node.addTextNode(text == null ? '' : text);
        return node;
    }

    private static Dom.XmlNode ramAmount(Dom.XmlNode parent, String name, Decimal amount, String currencyId) {
        Dom.XmlNode node = ramText(parent, name, formatAmount(amount));
        if (String.isNotBlank(currencyId)) {
            node.setAttribute('currencyID', currencyId);
        }
        return node;
    }

    private static void udtDateTime(Dom.XmlNode parent, Date value) {
        Dom.XmlNode dateTimeString = parent.addChildElement('DateTimeString', NS_UDT, 'udt');
        dateTimeString.setAttribute('format', DATE_FORMAT_102);
        dateTimeString.addTextNode(value == null ? '' : formatDate(value));
    }

    private static String formatDate(Date value) {
        return String.valueOf(value.year())
            + String.valueOf(value.month()).leftPad(2, '0')
            + String.valueOf(value.day()).leftPad(2, '0');
    }

    private static String formatAmount(Decimal value) {
        return (value == null ? 0 : value).setScale(2, RoundingMode.HALF_UP).toPlainString();
    }

    private static Decimal denormalizePercentage(Decimal percentage) {
        if (percentage == null) {
            return 0;
        }
        return Math.abs(percentage) > 1 ? percentage : (percentage * 100);
    }

    // ---- Data loading ------------------------------------------------------------------------

    private static InvoiceData loadInvoiceData(Id invoiceId) {
        Subscription25__Invoice__c invoice = [
            SELECT
                Id, Subscription25__Invoice_Number__c, Subscription25__Invoice_Date__c, Subscription25__Due_Date__c,
                Subscription25__Total_Amount__c, Amount_Gross__c, Amount_VAT__c,
                Subscription25__Purchase_Order_Number__c, Cost_Center_invoicing__c, Payment_Method_Result__c,
                Subscription25__VAT_Number__c,
                Subscription25__Account__r.Name, Subscription25__Account__r.BillingCountryCode,
                Subscription25__Account__r.Invoice_Grouping__c, Subscription25__Account__r.Invoice_Grouping_Option__c,
                Subscription25__Account__r.Invoice_VAT_Calculation__c,
                Subscription25__Billing_Street__c, Subscription25__Billing_City__c, Subscription25__Billing_Postal_Code__c,
                Subscription25__Administration__r.Subscription25__Billing_Name__c,
                Subscription25__Administration__r.Subscription25__Billing_Street__c,
                Subscription25__Administration__r.Subscription25__Billing_City__c,
                Subscription25__Administration__r.Subscription25__Billing_Postal_Code__c,
                Subscription25__Administration__r.Country_Code__c,
                Subscription25__Administration__r.CurrencyIsoCode,
                Subscription25__Administration__r.Subscription25__VAT_Number__c,
                Subscription25__Administration__r.Subscription25__Chamber_Of_Commerce_Number__c
            FROM Subscription25__Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];

        List<OrderItem> orderItems = [
            SELECT
                Invoice_Grouping__c, Product_Code__c, Product_Name__c, Invoice_Description__c, Quantity, UnitPrice,
                Amount_Net__c, Amount_VAT__c, Amount_Gross__c, Subscription25__VAT_Percentage__c,
                VAT_Code__r.UNCL5305_Category__c, Product2.QuantityUnitOfMeasure
            FROM OrderItem
            WHERE Order.Subscription25__Invoice__c = :invoiceId
        ];

        Map<String, String> paymentMeansByInternalCode = new Map<String, String>();
        for (Payment_Method_UNCL4461_Mapping__mdt mapping : [
            SELECT Internal_Payment_Code__c, UNCL4461_Code__c FROM Payment_Method_UNCL4461_Mapping__mdt
        ]) {
            paymentMeansByInternalCode.put(mapping.Internal_Payment_Code__c, mapping.UNCL4461_Code__c);
        }

        Map<String, String> uneceCodeByInternalUnit = new Map<String, String>();
        for (Unit_Of_Measure_UNECE_Mapping__mdt mapping : [
            SELECT Internal_Unit__c, UNECE_Code__c FROM Unit_Of_Measure_UNECE_Mapping__mdt
        ]) {
            uneceCodeByInternalUnit.put(mapping.Internal_Unit__c, mapping.UNECE_Code__c);
        }

        Boolean invoiceGrouping = invoice.Subscription25__Account__r.Invoice_Grouping__c
            && String.isNotBlank(invoice.Subscription25__Account__r.Invoice_Grouping_Option__c);
        String vatMethod = invoice.Subscription25__Account__r.Invoice_VAT_Calculation__c;

        List<Util_InvoiceLineAggregator.LineInput> aggregatorInputs = new List<Util_InvoiceLineAggregator.LineInput>();
        for (OrderItem item : orderItems) {
            Util_InvoiceLineAggregator.LineInput input = new Util_InvoiceLineAggregator.LineInput();
            input.groupKey = item.Invoice_Grouping__c;
            input.quantity = item.Quantity;
            input.netAmount = item.Amount_Net__c;
            input.vatAmount = item.Amount_VAT__c;
            input.grossAmount = item.Amount_Gross__c;
            input.vatPercentage = item.Subscription25__VAT_Percentage__c;
            // Grouped by UNCL5305 category here (what EN16931's tax breakdown requires), not the
            // internal VAT code Ctrl_Invoice groups its own footer by - see class comment.
            input.vatCode = item.VAT_Code__r != null ? item.VAT_Code__r.UNCL5305_Category__c : null;
            input.sourceItem = item;
            aggregatorInputs.add(input);
        }

        Util_InvoiceLineAggregator.AggregationResult aggregation =
            Util_InvoiceLineAggregator.aggregate(aggregatorInputs, invoiceGrouping, vatMethod);

        InvoiceData data = new InvoiceData();
        data.invoiceNumber = invoice.Subscription25__Invoice_Number__c;
        data.invoiceDate = invoice.Subscription25__Invoice_Date__c;
        data.dueDate = invoice.Subscription25__Due_Date__c;
        data.invoiceTypeCode = (invoice.Subscription25__Total_Amount__c < 0) ? '381' : '380';
        data.buyerReference = invoice.Cost_Center_invoicing__c;
        data.purchaseOrderNumber = invoice.Subscription25__Purchase_Order_Number__c;

        data.sellerName = invoice.Subscription25__Administration__r.Subscription25__Billing_Name__c;
        data.sellerStreet = invoice.Subscription25__Administration__r.Subscription25__Billing_Street__c;
        data.sellerCity = invoice.Subscription25__Administration__r.Subscription25__Billing_City__c;
        data.sellerPostalCode = invoice.Subscription25__Administration__r.Subscription25__Billing_Postal_Code__c;
        data.sellerCountryCode = invoice.Subscription25__Administration__r.Country_Code__c;
        data.sellerVatNumber = invoice.Subscription25__Administration__r.Subscription25__VAT_Number__c;
        data.sellerCoCNumber = invoice.Subscription25__Administration__r.Subscription25__Chamber_Of_Commerce_Number__c;
        data.currencyCode = invoice.Subscription25__Administration__r.CurrencyIsoCode;

        data.buyerName = invoice.Subscription25__Account__r.Name;
        data.buyerStreet = invoice.Subscription25__Billing_Street__c;
        data.buyerCity = invoice.Subscription25__Billing_City__c;
        data.buyerPostalCode = invoice.Subscription25__Billing_Postal_Code__c;
        data.buyerCountryCode = invoice.Subscription25__Account__r.BillingCountryCode;
        data.buyerVatNumber = invoice.Subscription25__VAT_Number__c;

        data.unclPaymentMeansCode = paymentMeansByInternalCode.get(invoice.Payment_Method_Result__c);

        data.lines = new List<LineData>();
        for (Util_InvoiceLineAggregator.AggregatedLine aggLine : aggregation.lines) {
            OrderItem anchor = (OrderItem) aggLine.anchorItem;
            LineData lineData = new LineData();
            lineData.name = String.isNotBlank(anchor.Invoice_Description__c) ? anchor.Invoice_Description__c : anchor.Product_Name__c;
            lineData.quantity = aggLine.quantity;
            lineData.unitPrice = anchor.UnitPrice;
            lineData.netAmount = aggLine.netAmount;
            lineData.vatPercent = aggLine.vatPercentage;
            lineData.vatCategoryCode = aggLine.vatCode;
            lineData.uneceUnitCode = uneceCodeByInternalUnit.get(anchor.Product2.QuantityUnitOfMeasure);
            data.lines.add(lineData);
        }

        data.vatBreakdown = aggregation.vatBreakdown;
        data.netAmount = aggregation.netAmount;
        data.vatAmount = aggregation.vatAmount;
        data.grossAmount = aggregation.grossAmount;

        return data;
    }

    // ---- Data wrapper classes ------------------------------------------------------------

    private class InvoiceData {
        String invoiceNumber;
        Date invoiceDate;
        Date dueDate;
        String invoiceTypeCode;
        String buyerReference;
        String purchaseOrderNumber;
        String currencyCode;
        String unclPaymentMeansCode;

        String sellerName;
        String sellerStreet;
        String sellerCity;
        String sellerPostalCode;
        String sellerCountryCode;
        String sellerVatNumber;
        String sellerCoCNumber;

        String buyerName;
        String buyerStreet;
        String buyerCity;
        String buyerPostalCode;
        String buyerCountryCode;
        String buyerVatNumber;

        Decimal netAmount;
        Decimal vatAmount;
        Decimal grossAmount;

        List<LineData> lines;
        List<Util_InvoiceLineAggregator.VatBreakdown> vatBreakdown;
    }

    private class LineData {
        String name;
        Decimal quantity;
        Decimal unitPrice;
        Decimal netAmount;
        Decimal vatPercent;
        String vatCategoryCode;
        String uneceUnitCode;
    }
}
