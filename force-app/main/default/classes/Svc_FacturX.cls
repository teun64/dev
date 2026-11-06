/**
 * 20261105 TRi Reads the Factur-X (EN16931 CII) invoice XML that Odoo embeds in its invoice PDFs.
 * extractXml: the XML is stored uncompressed in the PDF, so it is cut out of the raw bytes (hex search, no PDF parser).
 * parse: CII XML -> Invoice DTO (header, seller, buyer + contact, lines, totals). Namespace prefixes are ignored.
 * Used by Svc_OdooInvoiceIntake (Odoo invoice e-mails on Email-to-Case).
 */
public with sharing class Svc_FacturX {
	public class FacturXException extends Exception {}

	private static final String XML_START_HEX = EncodingUtil.convertToHex(Blob.valueOf('<?xml'));
	private static final String XML_END = '</rsm:CrossIndustryInvoice>';
	private static final String XML_END_HEX = EncodingUtil.convertToHex(Blob.valueOf(XML_END));

	public class Party {
		public String name;
		public String vatNumber;
		public String legalId;
		public String street;
		public String street2;
		public String postalCode;
		public String city;
		public String countryCode;
		public String contactName;
		public String email;
		public String phone;
	}

	public class Line {
		public String lineId;
		public String code;
		public String name;
		public String description;
		public Decimal quantity;
		public Decimal unitPrice;
		public Decimal lineTotal;
		public Decimal vatPercent;
	}

	public class Invoice {
		public String invoiceNumber;
		public String typeCode;
		public Date issueDate;
		public Date dueDate;
		public String currencyCode;
		public String buyerReference;
		public String buyerOrderReference;
		public Party seller = new Party();
		public Party buyer = new Party();
		public Decimal lineTotal;
		public Decimal taxBasisTotal;
		public Decimal taxTotal;
		public Decimal grandTotal;
		public List<Line> lines = new List<Line>();

		public Boolean isCreditNote() {
			return this.typeCode == '381';
		}
	}

	/** Returns the embedded Factur-X XML of a PDF, or null when the PDF carries none (or only a compressed one). */
	public static String extractXml(Blob pdf) {
		if (pdf == null) {
			return null;
		}
		String hex = EncodingUtil.convertToHex(pdf);
		Integer endIdx = hex.indexOf(XML_END_HEX);
		// a hex match must start on a byte boundary
		while (endIdx >= 0 && Math.mod(endIdx, 2) != 0) {
			endIdx = hex.indexOf(XML_END_HEX, endIdx + 1);
		}
		if (endIdx < 0) {
			return null;
		}
		Integer startIdx = hex.lastIndexOf(XML_START_HEX, endIdx);
		while (startIdx >= 0 && Math.mod(startIdx, 2) != 0) {
			startIdx = startIdx == 0 ? -1 : hex.lastIndexOf(XML_START_HEX, startIdx - 1);
		}
		if (startIdx < 0) {
			return null;
		}
		String xmlHex = hex.substring(startIdx, endIdx + XML_END_HEX.length());
		hex = null;
		return EncodingUtil.convertFromHex(xmlHex).toString();
	}

	public static Invoice parse(String xml) {
		if (String.isBlank(xml)) {
			throw new FacturXException('Empty Factur-X XML');
		}
		Dom.Document doc = new Dom.Document();
		try {
			doc.load(xml);
		} catch (Exception e) {
			throw new FacturXException('Factur-X XML cannot be read: ' + e.getMessage());
		}
		Dom.XmlNode root = doc.getRootElement();
		if (root == null || root.getName() != 'CrossIndustryInvoice') {
			throw new FacturXException('Not a Factur-X (CrossIndustryInvoice) document');
		}

		Invoice inv = new Invoice();
		Dom.XmlNode document = child(root, 'ExchangedDocument');
		inv.invoiceNumber = text(document, 'ID');
		inv.typeCode = text(document, 'TypeCode');
		inv.issueDate = toDate(text(document, 'IssueDateTime/DateTimeString'));

		Dom.XmlNode tx = child(root, 'SupplyChainTradeTransaction');
		Dom.XmlNode agreement = child(tx, 'ApplicableHeaderTradeAgreement');
		inv.buyerReference = text(agreement, 'BuyerReference');
		inv.buyerOrderReference = text(agreement, 'BuyerOrderReferencedDocument/IssuerAssignedID');
		inv.seller = parseParty(child(agreement, 'SellerTradeParty'));
		inv.buyer = parseParty(child(agreement, 'BuyerTradeParty'));

		Dom.XmlNode settlement = child(tx, 'ApplicableHeaderTradeSettlement');
		inv.currencyCode = text(settlement, 'InvoiceCurrencyCode');
		inv.dueDate = toDate(text(settlement, 'SpecifiedTradePaymentTerms/DueDateDateTime/DateTimeString'));
		Dom.XmlNode sums = child(settlement, 'SpecifiedTradeSettlementHeaderMonetarySummation');
		inv.lineTotal = toDecimal(text(sums, 'LineTotalAmount'));
		inv.taxBasisTotal = toDecimal(text(sums, 'TaxBasisTotalAmount'));
		inv.taxTotal = toDecimal(text(sums, 'TaxTotalAmount'));
		inv.grandTotal = toDecimal(text(sums, 'GrandTotalAmount'));

		if (tx != null) {
			for (Dom.XmlNode item : tx.getChildElements()) {
				if (item.getName() == 'IncludedSupplyChainTradeLineItem') {
					inv.lines.add(parseLine(item));
				}
			}
		}

		if (String.isBlank(inv.invoiceNumber)) {
			throw new FacturXException('Factur-X has no invoice number');
		}
		if (inv.issueDate == null) {
			throw new FacturXException('Factur-X ' + inv.invoiceNumber + ' has no invoice date');
		}
		if (inv.lines.isEmpty()) {
			throw new FacturXException('Factur-X ' + inv.invoiceNumber + ' has no invoice lines');
		}
		return inv;
	}

	private static Party parseParty(Dom.XmlNode node) {
		Party p = new Party();
		if (node == null) {
			return p;
		}
		p.name = text(node, 'Name');
		p.legalId = text(node, 'SpecifiedLegalOrganization/ID');
		for (Dom.XmlNode reg : node.getChildElements()) {
			if (reg.getName() == 'SpecifiedTaxRegistration') {
				Dom.XmlNode id = child(reg, 'ID');
				// VA = VAT number, FC = local tax number
				if (id != null && (p.vatNumber == null || id.getAttribute('schemeID', null) == 'VA')) {
					p.vatNumber = id.getText().trim();
				}
			}
		}
		Dom.XmlNode address = child(node, 'PostalTradeAddress');
		p.street = text(address, 'LineOne');
		p.street2 = text(address, 'LineTwo');
		p.postalCode = text(address, 'PostcodeCode');
		p.city = text(address, 'CityName');
		p.countryCode = text(address, 'CountryID');
		Dom.XmlNode contact = child(node, 'DefinedTradeContact');
		p.contactName = text(contact, 'PersonName');
		p.phone = text(contact, 'TelephoneUniversalCommunication/CompleteNumber');
		p.email = text(contact, 'EmailURIUniversalCommunication/URIID');
		if (String.isBlank(p.email)) {
			// the party's own electronic address, only when it is an e-mail address
			String uri = text(node, 'URIUniversalCommunication/URIID');
			if (uri != null && uri.contains('@')) {
				p.email = uri;
			}
		}
		return p;
	}

	private static Line parseLine(Dom.XmlNode item) {
		Line l = new Line();
		l.lineId = text(item, 'AssociatedDocumentLineDocument/LineID');
		Dom.XmlNode product = child(item, 'SpecifiedTradeProduct');
		l.code = text(product, 'SellerAssignedID');
		l.name = text(product, 'Name');
		l.description = text(product, 'Description');
		Dom.XmlNode lineAgreement = child(item, 'SpecifiedLineTradeAgreement');
		Decimal netPrice = toDecimal(text(lineAgreement, 'NetPriceProductTradePrice/ChargeAmount'));
		Decimal basisQty = toDecimal(text(lineAgreement, 'NetPriceProductTradePrice/BasisQuantity'));
		if (netPrice == null) {
			netPrice = toDecimal(text(lineAgreement, 'GrossPriceProductTradePrice/ChargeAmount'));
		}
		l.quantity = toDecimal(text(item, 'SpecifiedLineTradeDelivery/BilledQuantity'));
		Dom.XmlNode lineSettlement = child(item, 'SpecifiedLineTradeSettlement');
		l.vatPercent = toDecimal(text(lineSettlement, 'ApplicableTradeTax/RateApplicablePercent'));
		l.lineTotal = toDecimal(text(lineSettlement, 'SpecifiedTradeSettlementLineMonetarySummation/LineTotalAmount'));
		if (netPrice != null && basisQty != null && basisQty != 0 && basisQty != 1) {
			netPrice = netPrice / basisQty;
		}
		l.unitPrice = netPrice;
		if (l.quantity == null) {
			l.quantity = 1;
		}
		if (l.unitPrice == null && l.lineTotal != null && l.quantity != 0) {
			l.unitPrice = l.lineTotal / l.quantity;
		}
		return l;
	}

	/** First child element by local name, following a '/'-separated path. */
	@TestVisible
	private static Dom.XmlNode child(Dom.XmlNode node, String path) {
		Dom.XmlNode current = node;
		for (String name : path.split('/')) {
			if (current == null) {
				return null;
			}
			Dom.XmlNode found = null;
			for (Dom.XmlNode c : current.getChildElements()) {
				if (c.getName() == name) {
					found = c;
					break;
				}
			}
			current = found;
		}
		return current;
	}

	private static String text(Dom.XmlNode node, String path) {
		Dom.XmlNode n = child(node, path);
		if (n == null) {
			return null;
		}
		String t = n.getText();
		return String.isBlank(t) ? null : t.trim();
	}

	private static Date toDate(String value) {
		if (value == null || value.length() < 8 || !value.left(8).isNumeric()) {
			return null;
		}
		return Date.newInstance(Integer.valueOf(value.substring(0, 4)), Integer.valueOf(value.substring(4, 6)), Integer.valueOf(value.substring(6, 8)));
	}

	private static Decimal toDecimal(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			return Decimal.valueOf(value.trim());
		} catch (TypeException e) {
			return null;
		}
	}
}
