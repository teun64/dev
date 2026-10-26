/**
 * Controller of the dealerPortalContactEmail component, used in the Dealer Portal email templates
 * (welcome / password). Returns the billing email of the dealer's administration (Account
 * Reseller_Name__c → Administration Reseller__c), the same address as in the portal footer and on
 * the login page. Fallback: info@movingintelligence.com (the site's sender).
 */
public without sharing class Ctrl_DealerPortalEmail {
	public static final String FALLBACK_EMAIL = 'info@movingintelligence.com';

	public Id recipientUserId { get; set; }

	public String getContactEmail() {
		return resolveContactEmail(this.recipientUserId);
	}

	// mailto link for the {0} of DealerPortal_EmailQuestions (rendered with escape="false").
	public String getContactEmailHtml() {
		String email = getContactEmail().escapeHtml4();
		return '<a href="mailto:' + email + '" style="color:#1a1a1a;">' + email + '</a>';
	}

	@TestVisible
	private static String resolveContactEmail(Id userId) {
		if (userId == null) return FALLBACK_EMAIL;
		List<User> users = [SELECT Contact.Account.Reseller_Name__c FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
		if (users.isEmpty() || users[0].Contact?.Account?.Reseller_Name__c == null) return FALLBACK_EMAIL;
		List<Subscription25__Administration__c> admins = Util_Shop_System.getAdministrationsByReseller(
			users[0].Contact.Account.Reseller_Name__c, 'Subscription25__Billing_Email_Address__c'
		);
		if (admins.isEmpty() || String.isBlank(admins[0].Subscription25__Billing_Email_Address__c)) return FALLBACK_EMAIL;
		return admins[0].Subscription25__Billing_Email_Address__c;
	}
}
