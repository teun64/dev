/**
 * Dealer Portal login and forgot password (guest, dealerLogin LWC).
 *
 * Dealers type their email address; the username is derived with Svc_DealerUserSetup.buildUsername
 * (<email>.miDealer[.<sandbox>], +tag dropped). A full dealer username is accepted as is; any other
 * username is refused, so this guest endpoint can't be used to try internal credentials.
 *
 * Every failure gives the same LOGIN_FAILED code (the LWC shows a generic message with the contact
 * email), so the page never tells whether an account exists or is disabled. The real reason stays
 * in the Login History. forgotPassword never reports a result either.
 */
public without sharing class Ctrl_DealerPortalLogin {
	public static final String LOGIN_FAILED = 'LOGIN_FAILED';

	@AuraEnabled
	public static String login(String identifier, String password, String startUrl) {
		String username = resolveUsername(identifier);
		if (username == null || String.isBlank(password)) {
			throw newFailure();
		}
		PageReference result;
		try {
			result = Site.login(username, password, safeStartUrl(startUrl));
		} catch (Exception e) {
			throw newFailure();
		}
		if (result == null) {
			throw newFailure();
		}
		return result.getUrl();
	}

	@AuraEnabled
	public static void forgotPassword(String identifier) {
		String username = resolveUsername(identifier);
		if (username == null) return;
		try {
			Site.forgotPassword(username);
		} catch (Exception e) {
			System.debug(LoggingLevel.WARN, 'Ctrl_DealerPortalLogin.forgotPassword: ' + e.getMessage());
		}
	}

	@TestVisible
	private static String resolveUsername(String identifier) {
		if (String.isBlank(identifier)) return null;
		String value = identifier.deleteWhitespace().toLowerCase();
		if (!value.contains('@')) return null;
		String suffix = Svc_DealerUserSetup.usernameSuffix().toLowerCase();
		if (value.endsWith(suffix)) return value;
		// A username of another kind (internal user, other portal) is never passed on.
		if (value.substringAfterLast('@').contains('.midealer')) return null;
		return Svc_DealerUserSetup.buildUsername(value).toLowerCase();
	}

	// Only a relative path on this site: no open redirect to another host.
	@TestVisible
	private static String safeStartUrl(String startUrl) {
		if (String.isBlank(startUrl)) return null;
		String value = startUrl.trim();
		if (!value.startsWith('/') || value.startsWith('//') || value.contains('\\') || value.contains(':')) return null;
		return value;
	}

	private static AuraHandledException newFailure() {
		AuraHandledException e = new AuraHandledException(LOGIN_FAILED);
		e.setMessage(LOGIN_FAILED);
		return e;
	}
}
