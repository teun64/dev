@isTest
public class Test_Svc_FacturX {
	/** Factur-X as Odoo generates it (shape of prod invoice 03251903), with configurable number/buyer/e-mail. */
	public static String sampleXml(String invoiceNumber, String typeCode, String buyerName, String buyerVat, String buyerEmail) {
		return '<?xml version=\'1.0\' encoding=\'UTF-8\'?>\n'
			+ '<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" '
			+ 'xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" '
			+ 'xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">'
			+ '<rsm:ExchangedDocumentContext><ram:GuidelineSpecifiedDocumentContextParameter><ram:ID>urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended</ram:ID></ram:GuidelineSpecifiedDocumentContextParameter></rsm:ExchangedDocumentContext>'
			+ '<rsm:ExchangedDocument><ram:ID>' + invoiceNumber + '</ram:ID><ram:TypeCode>' + typeCode + '</ram:TypeCode>'
			+ '<ram:IssueDateTime><udt:DateTimeString format="102">20260930</udt:DateTimeString></ram:IssueDateTime></rsm:ExchangedDocument>'
			+ '<rsm:SupplyChainTradeTransaction>'
			+ line('1', 'CarFleetDE', 'Monatlich Lizenz CarFleet', '[CarFleetDE] Monatlich Lizenz CarFleet', '35.0', '15.00', '525.00')
			+ line('2', 'CarFleetDE', 'Monatlich Lizenz CarFleet', '[CarFleetDE] Monatlich Lizenz CarFleet', '-6.0', '15.00', '-90.00')
			+ line('3', null, 'Formation', 'Formation', '1.0', '100.00', '100.00')
			+ '<ram:ApplicableHeaderTradeAgreement><ram:BuyerReference>785</ram:BuyerReference>'
			+ '<ram:SellerTradeParty><ram:Name>Echoes</ram:Name><ram:SpecifiedTaxRegistration><ram:ID schemeID="VA">FR79840597819</ram:ID></ram:SpecifiedTaxRegistration></ram:SellerTradeParty>'
			+ '<ram:BuyerTradeParty><ram:Name>' + buyerName + '</ram:Name>'
			+ '<ram:SpecifiedLegalOrganization><ram:ID schemeID="0009">48316123800041</ram:ID></ram:SpecifiedLegalOrganization>'
			+ '<ram:DefinedTradeContact><ram:PersonName>' + buyerName + '</ram:PersonName>'
			+ '<ram:TelephoneUniversalCommunication><ram:CompleteNumber>+33 4 91 29 90 10</ram:CompleteNumber></ram:TelephoneUniversalCommunication>'
			+ (buyerEmail == null ? '' : '<ram:EmailURIUniversalCommunication><ram:URIID schemeID="SMTP">' + buyerEmail + '</ram:URIID></ram:EmailURIUniversalCommunication>')
			+ '</ram:DefinedTradeContact>'
			+ '<ram:PostalTradeAddress><ram:PostcodeCode>13010</ram:PostcodeCode><ram:LineOne>4 BD DES ACIERIES</ram:LineOne><ram:LineTwo>Batiment B</ram:LineTwo>'
			+ '<ram:CityName>MARSEILLE 10</ram:CityName><ram:CountryID>FR</ram:CountryID></ram:PostalTradeAddress>'
			+ (buyerVat == null ? '' : '<ram:SpecifiedTaxRegistration><ram:ID schemeID="VA">' + buyerVat + '</ram:ID></ram:SpecifiedTaxRegistration>')
			+ '</ram:BuyerTradeParty>'
			+ '<ram:BuyerOrderReferencedDocument><ram:IssuerAssignedID>PO-4711</ram:IssuerAssignedID></ram:BuyerOrderReferencedDocument>'
			+ '</ram:ApplicableHeaderTradeAgreement>'
			+ '<ram:ApplicableHeaderTradeDelivery/>'
			+ '<ram:ApplicableHeaderTradeSettlement><ram:PaymentReference>' + invoiceNumber + '</ram:PaymentReference><ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>'
			+ '<ram:BillingSpecifiedPeriod><ram:StartDateTime><udt:DateTimeString format="102">20260930</udt:DateTimeString></ram:StartDateTime>'
			+ '<ram:EndDateTime><udt:DateTimeString format="102">20261030</udt:DateTimeString></ram:EndDateTime></ram:BillingSpecifiedPeriod>'
			+ '<ram:SpecifiedTradePaymentTerms><ram:DueDateDateTime><udt:DateTimeString format="102">20261030</udt:DateTimeString></ram:DueDateDateTime></ram:SpecifiedTradePaymentTerms>'
			+ '<ram:SpecifiedTradeSettlementHeaderMonetarySummation><ram:LineTotalAmount>535.00</ram:LineTotalAmount><ram:TaxBasisTotalAmount>535.00</ram:TaxBasisTotalAmount>'
			+ '<ram:TaxTotalAmount currencyID="EUR">107.00</ram:TaxTotalAmount><ram:GrandTotalAmount>642.00</ram:GrandTotalAmount><ram:DuePayableAmount>642.00</ram:DuePayableAmount>'
			+ '</ram:SpecifiedTradeSettlementHeaderMonetarySummation></ram:ApplicableHeaderTradeSettlement>'
			+ '</rsm:SupplyChainTradeTransaction></rsm:CrossIndustryInvoice>';
	}

	private static String line(String id, String code, String name, String description, String qty, String price, String total) {
		return '<ram:IncludedSupplyChainTradeLineItem><ram:AssociatedDocumentLineDocument><ram:LineID>' + id + '</ram:LineID></ram:AssociatedDocumentLineDocument>'
			+ '<ram:SpecifiedTradeProduct>' + (code == null ? '' : '<ram:SellerAssignedID>' + code + '</ram:SellerAssignedID>')
			+ '<ram:Name>' + name + '</ram:Name><ram:Description>' + description + '</ram:Description></ram:SpecifiedTradeProduct>'
			+ '<ram:SpecifiedLineTradeAgreement><ram:GrossPriceProductTradePrice><ram:ChargeAmount>' + price + '</ram:ChargeAmount></ram:GrossPriceProductTradePrice>'
			+ '<ram:NetPriceProductTradePrice><ram:ChargeAmount>' + price + '</ram:ChargeAmount></ram:NetPriceProductTradePrice></ram:SpecifiedLineTradeAgreement>'
			+ '<ram:SpecifiedLineTradeDelivery><ram:BilledQuantity unitCode="C62">' + qty + '</ram:BilledQuantity></ram:SpecifiedLineTradeDelivery>'
			+ '<ram:SpecifiedLineTradeSettlement><ram:ApplicableTradeTax><ram:TypeCode>VAT</ram:TypeCode><ram:CategoryCode>S</ram:CategoryCode>'
			+ '<ram:RateApplicablePercent>20.0</ram:RateApplicablePercent></ram:ApplicableTradeTax>'
			+ '<ram:SpecifiedTradeSettlementLineMonetarySummation><ram:LineTotalAmount>' + total + '</ram:LineTotalAmount>'
			+ '</ram:SpecifiedTradeSettlementLineMonetarySummation></ram:SpecifiedLineTradeSettlement></ram:IncludedSupplyChainTradeLineItem>';
	}

	/** A "PDF" with the Factur-X embedded uncompressed, like Odoo's (odd-length prefix to test byte alignment). */
	public static Blob samplePdf(String xml) {
		return Blob.valueOf('%PDF-1.7\n%abc\n1 0 obj\n<</Type /EmbeddedFile /Subtype /text#2Fxml /Length 999>>\nstream\n'
			+ xml + '\nendstream\nendobj\n%%EOF');
	}

	@isTest
	static void extractsAndParses() {
		String xml = sampleXml('03251903', '380', 'CanoCar GmbH', 'DE342369057', 'jan.jito@example.com');
		String extracted = Svc_FacturX.extractXml(samplePdf(xml));
		Assert.areEqual(xml, extracted, 'the embedded XML is cut out exactly');

		Svc_FacturX.Invoice inv = Svc_FacturX.parse(extracted);
		Assert.areEqual('03251903', inv.invoiceNumber);
		Assert.areEqual(false, inv.isCreditNote());
		Assert.areEqual(Date.newInstance(2026, 9, 30), inv.issueDate);
		Assert.areEqual(Date.newInstance(2026, 10, 30), inv.dueDate);
		Assert.areEqual('EUR', inv.currencyCode);
		Assert.areEqual('785', inv.buyerReference);
		Assert.areEqual('PO-4711', inv.buyerOrderReference);
		Assert.areEqual('Echoes', inv.seller.name);
		Assert.areEqual('FR79840597819', inv.seller.vatNumber);
		Assert.areEqual('CanoCar GmbH', inv.buyer.name);
		Assert.areEqual('DE342369057', inv.buyer.vatNumber);
		Assert.areEqual('48316123800041', inv.buyer.legalId);
		Assert.areEqual('jan.jito@example.com', inv.buyer.email);
		Assert.areEqual('+33 4 91 29 90 10', inv.buyer.phone);
		Assert.areEqual('4 BD DES ACIERIES', inv.buyer.street);
		Assert.areEqual('Batiment B', inv.buyer.street2);
		Assert.areEqual('13010', inv.buyer.postalCode);
		Assert.areEqual('MARSEILLE 10', inv.buyer.city);
		Assert.areEqual('FR', inv.buyer.countryCode);
		Assert.areEqual(535.00, inv.taxBasisTotal);
		Assert.areEqual(107.00, inv.taxTotal);
		Assert.areEqual(642.00, inv.grandTotal);
		Assert.areEqual(3, inv.lines.size());
		Assert.areEqual('CarFleetDE', inv.lines[0].code);
		Assert.areEqual(35, inv.lines[0].quantity);
		Assert.areEqual(15.00, inv.lines[0].unitPrice);
		Assert.areEqual(20.0, inv.lines[0].vatPercent);
		Assert.areEqual(-6, inv.lines[1].quantity);
		Assert.isNull(inv.lines[2].code);
		Assert.areEqual('Formation', inv.lines[2].name);
	}

	@isTest
	static void handlesMissingOrInvalidXml() {
		Assert.isNull(Svc_FacturX.extractXml(null));
		Assert.isNull(Svc_FacturX.extractXml(Blob.valueOf('%PDF-1.7 no embedded invoice')));
		Assert.isNull(Svc_FacturX.extractXml(Blob.valueOf('</rsm:CrossIndustryInvoice>')), 'end without start');

		for (String bad : new List<String>{ '', '<not xml', '<?xml version="1.0"?><Invoice/>' }) {
			try {
				Svc_FacturX.parse(bad);
				Assert.fail('expected an exception for ' + bad);
			} catch (Svc_FacturX.FacturXException e) {
				Assert.isNotNull(e.getMessage());
			}
		}
		String noLines = '<?xml version="1.0"?><rsm:CrossIndustryInvoice xmlns:rsm="r" xmlns:ram="a" xmlns:udt="u">'
			+ '<rsm:ExchangedDocument><ram:ID>02000001</ram:ID><ram:IssueDateTime><udt:DateTimeString>20260930</udt:DateTimeString></ram:IssueDateTime></rsm:ExchangedDocument>'
			+ '<rsm:SupplyChainTradeTransaction/></rsm:CrossIndustryInvoice>';
		try {
			Svc_FacturX.parse(noLines);
			Assert.fail('expected an exception for an invoice without lines');
		} catch (Svc_FacturX.FacturXException e) {
			Assert.isTrue(e.getMessage().contains('no invoice lines'), e.getMessage());
		}
	}
}
