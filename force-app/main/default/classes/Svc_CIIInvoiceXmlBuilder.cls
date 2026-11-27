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
        // structurally required and must not be empty (PEPPOL-EN16931-R008): deliver-to name (BT-70). The service period
        // (BG-14) goes in the settlement block; no delivery date is claimed since subscriptions bill in advance.
        Dom.XmlNode delivery = ram(tradeTransaction, 'ApplicableHeaderTradeDelivery');
        ramText(ram(delivery, 'ShipToTradeParty'), 'Name', data.buyerName);
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
        if (String.isNotBlank(data.sellerPhone) || String.isNotBlank(data.sellerEmail)) {
            Dom.XmlNode contact = ram(seller, 'DefinedTradeContact');
            // BR-DE-2 asks for a contact name; the department is the seller's name until a real contact exists
            ramText(contact, 'PersonName', data.sellerName);
            if (String.isNotBlank(data.sellerPhone)) {
                ramText(ram(contact, 'TelephoneUniversalCommunication'), 'CompleteNumber', data.sellerPhone);
            }
            if (String.isNotBlank(data.sellerEmail)) {
                ramText(ram(contact, 'EmailURIUniversalCommunication'), 'URIID', data.sellerEmail);
            }
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
        // BT-90 creditor identifier (SEPA direct debit)
        if (String.isNotBlank(data.sellerCreditorId) && data.unclPaymentMeansCode == '59') {
            ramText(settlement, 'CreditorReferenceID', data.sellerCreditorId);
        }
        ramText(settlement, 'InvoiceCurrencyCode', data.currencyCode);

        if (String.isNotBlank(data.unclPaymentMeansCode)) {
            Dom.XmlNode paymentMeans = ram(settlement, 'SpecifiedTradeSettlementPaymentMeans');
            ramText(paymentMeans, 'TypeCode', data.unclPaymentMeansCode);
            // payee account for credit transfers; direct debits (49, 59) carry the buyer's account and mandate instead
            Boolean directDebit = data.unclPaymentMeansCode == '49' || data.unclPaymentMeansCode == '59';
            if (directDebit && String.isNotBlank(data.buyerIban)) {
                ramText(ram(paymentMeans, 'PayerPartyDebtorFinancialAccount'), 'IBANID', data.buyerIban);
            }
            if (!directDebit && String.isNotBlank(data.sellerIban)) {
                ramText(ram(paymentMeans, 'PayeePartyCreditorFinancialAccount'), 'IBANID', data.sellerIban.deleteWhitespace());
                if (String.isNotBlank(data.sellerBic)) {
                    ramText(ram(paymentMeans, 'PayeeSpecifiedCreditorFinancialInstitution'), 'BICID', data.sellerBic.deleteWhitespace());
                }
            }
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

        if (data.periodStart != null && data.periodEnd != null) {
            Dom.XmlNode period = ram(settlement, 'BillingSpecifiedPeriod');
            udtDateTime(ram(period, 'StartDateTime'), data.periodStart);
            udtDateTime(ram(period, 'EndDateTime'), data.periodEnd);
        }

        Boolean debit = data.unclPaymentMeansCode == '59' || data.unclPaymentMeansCode == '49';
        if (data.dueDate != null || (debit && String.isNotBlank(data.mandateReference))) {
            Dom.XmlNode paymentTerms = ram(settlement, 'SpecifiedTradePaymentTerms');
            if (data.dueDate != null) {
                udtDateTime(ram(paymentTerms, 'DueDateDateTime'), data.dueDate);
            }
            if (debit && String.isNotBlank(data.mandateReference)) {
                ramText(paymentTerms, 'DirectDebitMandateID', data.mandateReference);
            }
        }

        Dom.XmlNode summation = ram(settlement, 'SpecifiedTradeSettlementHeaderMonetarySummation');
        ramAmount(summation, 'LineTotalAmount', data.netAmount, null);
        ramAmount(summation, 'TaxBasisTotalAmount', data.netAmount, null);
        ramAmount(summation, 'TaxTotalAmount', data.vatAmount, data.currencyCode);
        ramAmount(summation, 'GrandTotalAmount', data.grossAmount, null);
        ramAmount(summation, 'DuePayableAmount', data.grossAmount, null);

        // BG-3 (after the monetary summation in the CII sequence); only credit notes, only when the original is known
        if (data.invoiceTypeCode == '381' && String.isNotBlank(data.precedingInvoiceNumber)) {
            ramText(ram(settlement, 'InvoiceReferencedDocument'), 'IssuerAssignedID', data.precedingInvoiceNumber);
        }
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
                Subscription25__Account__c, Subscription25__Administration__c, Reseller__c,
                Subscription25__VAT_Number__c,
                Subscription25__Original_Invoice__r.Subscription25__Invoice_Number__c, ParentId__r.Subscription25__Invoice_Number__c,
                Subscription25__Account__r.Name, Subscription25__Account__r.BillingCountryCode,
                Subscription25__Account__r.Invoice_Grouping__c, Subscription25__Account__r.Invoice_Grouping_Option__c,
                Subscription25__Account__r.Invoice_VAT_Calculation__c,
                Subscription25__Account__r.Bank_Account_Number__c, Subscription25__Account__r.PayProv_MandateId__c,
                Subscription25__Account__r.FinancialIdBankMandate__c, Subscription25__Account__r.Cost_Center_invoicing__c,
                Subscription25__Account__r.Invoice_Payment_Remark__c,
                Subscription25__Billing_Street__c, Subscription25__Billing_City__c, Subscription25__Billing_Postal_Code__c,
                Subscription25__Administration__r.Subscription25__Billing_Name__c,
                Subscription25__Administration__r.Subscription25__Billing_Street__c,
                Subscription25__Administration__r.Subscription25__Billing_City__c,
                Subscription25__Administration__r.Subscription25__Billing_Postal_Code__c,
                Subscription25__Administration__r.Country_Code__c,
                Subscription25__Administration__r.CurrencyIsoCode,
                Subscription25__Administration__r.Subscription25__VAT_Number__c,
                Subscription25__Administration__r.Subscription25__Chamber_Of_Commerce_Number__c,
                Subscription25__Administration__r.Subscription25__IBAN__c,
                Subscription25__Administration__r.Subscription25__BIC__c,
                Subscription25__Administration__r.Subscription25__Phone__c,
                Subscription25__Administration__r.Subscription25__Billing_Email_Address__c
            FROM Subscription25__Invoice__c
            WHERE Id = :invoiceId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        // Seller data comes from the Business Entity of the invoice's reseller; the administration only fills gaps
        List<Business_Entities__c> entities = String.isBlank(invoice.Reseller__c) ? new List<Business_Entities__c>() : [
            SELECT Business_Name__c, Address__Street__s, Address__City__s, Address__PostalCode__s, Address__CountryCode__s,
                   VAT_Number__c, CoC_Number__c, Creditor_Identifier__c, IBAN__c, BIC__c, Phone__c,
                   Email_Finance__c, Email_Sales__c
            FROM Business_Entities__c
            WHERE Reseller__c = :invoice.Reseller__c
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Business_Entities__c entity = entities.isEmpty() ? new Business_Entities__c() : entities[0];

        List<OrderItem> orderItems = [
            SELECT
                Invoice_Grouping__c, Product_Code__c, Product_Name__c, Invoice_Description__c, Quantity, UnitPrice,
                Amount_Net__c, Amount_VAT__c, Amount_Gross__c, Subscription25__VAT_Percentage__c,
                Subscription25__VAT_Code__c, Product2.QuantityUnitOfMeasure, Product2.Subscription25__Cost_Type__c, InvoiceStartDate__c, InvoiceEndDate__c
            FROM OrderItem
            WHERE Order.Subscription25__Invoice__c = :invoiceId
            WITH SYSTEM_MODE
        ];

        // UNCL5305 category per package VAT code of this invoice's administration; resolved here rather than
        // through OrderItem.VAT_Code__c, which is only filled once a line is updated (package sets the code after
        // before-save flows on insert)
        Map<String, String> vatCategoryByCode = new Map<String, String>();
        for (Subscription25__VAT_Code__c vatCode : [
            SELECT Subscription25__VAT_Code__c, UNCL5305_Category__c FROM Subscription25__VAT_Code__c
            WHERE Subscription25__Administration__c = :invoice.Subscription25__Administration__c
            WITH SYSTEM_MODE
        ]) {
            vatCategoryByCode.put(vatCode.Subscription25__VAT_Code__c, vatCode.UNCL5305_Category__c);
        }

        // keyed by code, or code|type for a payment provider scheme (pr + sepa_debit / bacs_debit / card)
        Map<String, String> paymentMeansByInternalCode = new Map<String, String>();
        for (Payment_Method_UNCL4461_Mapping__mdt mapping : [
            SELECT Internal_Payment_Code__c, Payment_Method_Type__c, UNCL4461_Code__c FROM Payment_Method_UNCL4461_Mapping__mdt
        ]) {
            String key = String.isBlank(mapping.Payment_Method_Type__c)
                ? mapping.Internal_Payment_Code__c : mapping.Internal_Payment_Code__c + '|' + mapping.Payment_Method_Type__c;
            paymentMeansByInternalCode.put(key, mapping.UNCL4461_Code__c);
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
            input.vatCode = vatCategoryByCode.get(item.Subscription25__VAT_Code__c);
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
        // BT-25 preceding invoice of a credit note: the package link (2.76+) first, then our ParentId__c (UK credits fill that one)
        data.precedingInvoiceNumber = firstNonBlank(invoice.Subscription25__Original_Invoice__r.Subscription25__Invoice_Number__c, invoice.ParentId__r.Subscription25__Invoice_Number__c, null);
        // BT-10: cost center first, then the account's invoice payment remark; empty when neither is filled
        data.buyerReference = firstNonBlank(invoice.Cost_Center_invoicing__c, invoice.Subscription25__Account__r.Cost_Center_invoicing__c,
            invoice.Subscription25__Account__r.Invoice_Payment_Remark__c);
        data.purchaseOrderNumber = invoice.Subscription25__Purchase_Order_Number__c;

        Subscription25__Administration__c adm = invoice.Subscription25__Administration__r;
        data.sellerName = firstNonBlank(entity.Business_Name__c, adm.Subscription25__Billing_Name__c);
        data.sellerStreet = firstNonBlank(entity.Address__Street__s, adm.Subscription25__Billing_Street__c);
        data.sellerCity = firstNonBlank(entity.Address__City__s, adm.Subscription25__Billing_City__c);
        data.sellerPostalCode = firstNonBlank(entity.Address__PostalCode__s, adm.Subscription25__Billing_Postal_Code__c);
        data.sellerCountryCode = firstNonBlank(entity.Address__CountryCode__s, adm.Country_Code__c);
        data.sellerVatNumber = firstNonBlank(entity.VAT_Number__c, adm.Subscription25__VAT_Number__c);
        data.sellerCoCNumber = firstNonBlank(entity.CoC_Number__c, adm.Subscription25__Chamber_Of_Commerce_Number__c);
        data.sellerCreditorId = entity.Creditor_Identifier__c;
        data.sellerPhone = firstNonBlank(entity.Phone__c, adm.Subscription25__Phone__c);
        data.sellerEmail = firstNonBlank(entity.Email_Finance__c, adm.Subscription25__Billing_Email_Address__c, entity.Email_Sales__c);
        data.sellerIban = firstNonBlank(entity.IBAN__c, adm.Subscription25__IBAN__c);
        data.sellerBic = firstNonBlank(entity.BIC__c, adm.Subscription25__BIC__c);
        data.currencyCode = invoice.Subscription25__Administration__r.CurrencyIsoCode;

        data.buyerName = invoice.Subscription25__Account__r.Name;
        data.buyerStreet = invoice.Subscription25__Billing_Street__c;
        data.buyerCity = invoice.Subscription25__Billing_City__c;
        data.buyerPostalCode = invoice.Subscription25__Billing_Postal_Code__c;
        data.buyerCountryCode = invoice.Subscription25__Account__r.BillingCountryCode;
        data.buyerVatNumber = invoice.Subscription25__VAT_Number__c;
        String buyerIban = invoice.Subscription25__Account__r.Bank_Account_Number__c;
        data.buyerIban = String.isBlank(buyerIban) ? null : buyerIban.deleteWhitespace();
        // BT-89: payment provider mandate first, else the Exact mandate id (hyphens dropped, SEPA max 35 characters)
        String exactMandate = invoice.Subscription25__Account__r.FinancialIdBankMandate__c;
        data.mandateReference = firstNonBlank(invoice.Subscription25__Account__r.PayProv_MandateId__c,
            String.isBlank(exactMandate) ? null : exactMandate.remove('-'));
        if (data.mandateReference != null) {
            data.mandateReference = data.mandateReference.left(35);
        }

        String paymentCode = invoice.Payment_Method_Result__c;
        String paymentMethodType = Svc_CIIInvoiceXmlBuilder.paymentMethodType(invoice.Subscription25__Account__c, invoice.Reseller__c);
        data.unclPaymentMeansCode = paymentMeansByInternalCode.containsKey(paymentCode + '|' + paymentMethodType)
            ? paymentMeansByInternalCode.get(paymentCode + '|' + paymentMethodType) : paymentMeansByInternalCode.get(paymentCode);
        // a direct debit needs the buyer's IBAN and a mandate reference (BR-DE-20/25); without both, say "instrument not defined"
        if ((data.unclPaymentMeansCode == '59' || data.unclPaymentMeansCode == '49')
            && (String.isBlank(data.buyerIban) || String.isBlank(data.mandateReference))) {
            data.unclPaymentMeansCode = '1';
        }

        for (OrderItem item : orderItems) {
            if (item.InvoiceStartDate__c != null && (data.periodStart == null || item.InvoiceStartDate__c < data.periodStart)) {
                data.periodStart = item.InvoiceStartDate__c;
            }
            if (item.InvoiceEndDate__c != null && (data.periodEnd == null || item.InvoiceEndDate__c > data.periodEnd)) {
                data.periodEnd = item.InvoiceEndDate__c;
            }
        }

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
            lineData.uneceUnitCode = resolveUneceUnitCode(anchor.Product2.QuantityUnitOfMeasure, anchor.Product2.Subscription25__Cost_Type__c, uneceCodeByInternalUnit);
            data.lines.add(lineData);
        }

        data.vatBreakdown = aggregation.vatBreakdown;
        data.netAmount = aggregation.netAmount;
        data.vatAmount = aggregation.vatAmount;
        data.grossAmount = aggregation.grossAmount;

        return data;
    }

    // ---- Data wrapper classes ------------------------------------------------------------

    /**
     * The payment provider's payment method type for the scheme-specific payment means of a pr invoice: the
     * account's saved method, else the direct debit method of the reseller's business entity. System mode: a
     * payment-provider field the user running the PDF merge need not see.
     */
    @TestVisible
    private static String paymentMethodType(Id accountId, String reseller) {
        List<Account> accounts = [SELECT PayProv_PaymentMethodType__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE];
        if (!accounts.isEmpty() && String.isNotBlank(accounts[0].PayProv_PaymentMethodType__c)) {
            return accounts[0].PayProv_PaymentMethodType__c;
        }
        List<Business_Entities__c> entities = [SELECT PayProv_DirectDebit_PaymentMethod__c FROM Business_Entities__c WHERE Reseller__c = :reseller WITH SYSTEM_MODE LIMIT 1];
        return entities.isEmpty() ? null : entities[0].PayProv_DirectDebit_PaymentMethod__c;
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a.trim() : (String.isNotBlank(b) ? b.trim() : null);
    }

    private static String firstNonBlank(String a, String b, String c) {
        return firstNonBlank(firstNonBlank(a, b), c);
    }

    private class InvoiceData {
        String invoiceNumber;
        Date invoiceDate;
        Date dueDate;
        String invoiceTypeCode;
        String precedingInvoiceNumber;
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
        String sellerCreditorId;
        String sellerPhone;
        String sellerEmail;
        String sellerIban;
        String sellerBic;

        String buyerName;
        String buyerStreet;
        String buyerCity;
        String buyerPostalCode;
        String buyerCountryCode;
        String buyerVatNumber;
        String buyerIban;
        String mandateReference;
        Date periodStart;
        Date periodEnd;

        Decimal netAmount;
        Decimal vatAmount;
        Decimal grossAmount;

        List<LineData> lines;
        List<Util_InvoiceLineAggregator.VatBreakdown> vatBreakdown;
    }

    // BT-130 is mandatory (BR-23). An explicit unit of measure on the product wins; when it is empty or not a picklist
    // value (prod has 369 non-recurring products without unit, and a few recurring ones with 'Month', '12', '24') the
    // cost type decides: recurring = per month, recurring (daily price) = per day, anything else = piece.
    // TODO (decision 2026-11-27): the goal is to use Quantity Unit Of Measure ALONE. Needs a data fix first (set the unit on the
    // ~369 empty non-recurring products, correct 'Month'/'12'/'24' to 'Month(s)'); then drop the cost type fallback.
    @TestVisible
    private static String resolveUneceUnitCode(String unit, String costType, Map<String, String> uneceCodeByInternalUnit) {
        if (String.isNotBlank(unit) && uneceCodeByInternalUnit.containsKey(unit)) {
            return uneceCodeByInternalUnit.get(unit);
        }
        if (costType == 'RECURRING') {
            return uneceCodeByInternalUnit.containsKey('Month(s)') ? uneceCodeByInternalUnit.get('Month(s)') : 'MON';
        }
        if (costType == 'RECURRING_DAILY') {
            return 'DAY';
        }
        return uneceCodeByInternalUnit.containsKey('Piece(s)') ? uneceCodeByInternalUnit.get('Piece(s)') : 'C62';
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
