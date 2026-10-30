/**
 * Controller of the orderDeliveryRecipient component, used in the order confirmation email
 * (Opportunity_OrderConfirmation). Shows who the delivery is for, above the delivery address:
 * the attention lines of a different delivery address (Opportunity.ShippingAttention__c, max 2)
 * with line 1 bold, or else the account name in bold. A Visualforce expression cannot split on a
 * line break (FIND/SUBSTITUTE never see the newline), hence this controller.
 */
public without sharing class Ctrl_OrderDeliveryRecipient {
	public static final Integer MAX_LINES = 2;
	public static final Integer MAX_LINE_LENGTH = 100;

	public String attentionText { get; set; }
	public String recipientAccountName { get; set; }

	// The recipient lines, HTML-escaped: the first wrapped in <strong>, joined with <br/>.
	// Rendered with escape="false".
	public String getRecipientHtml() {
		List<String> lines = attentionLines(this.attentionText);
		if (lines.isEmpty() && String.isNotBlank(this.recipientAccountName)) lines.add(this.recipientAccountName);
		if (lines.isEmpty()) return '';
		List<String> html = new List<String>();
		for (Integer i = 0; i < lines.size(); i++) {
			String line = lines[i].escapeHtml4();
			html.add(i == 0 ? '<strong>' + line + '</strong>' : line);
		}
		return String.join(html, '<br/>');
	}

	// Attention text → its non-blank, trimmed lines: at most MAX_LINES of MAX_LINE_LENGTH chars.
	// Also used by Ctrl_DealerShop.placeOrder to store the cart's value in the same shape.
	public static List<String> attentionLines(String value) {
		List<String> lines = new List<String>();
		if (String.isBlank(value)) return lines;
		for (String line : value.split('\r\n|\r|\n')) {
			if (String.isBlank(line)) continue;
			lines.add(line.trim().left(MAX_LINE_LENGTH));
			if (lines.size() == MAX_LINES) break;
		}
		return lines;
	}
}
