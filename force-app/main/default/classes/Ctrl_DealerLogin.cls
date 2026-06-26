public without sharing class Ctrl_DealerLogin {

    @AuraEnabled
    public static String login(String email, String password, String startUrl) {
        if (String.isBlank(email) || String.isBlank(password)) {
            throw new AuraHandledException('E-mailadres en wachtwoord zijn verplicht.');
        }

        String username = buildUsername(email.trim().toLowerCase());
        String target   = String.isNotBlank(startUrl) ? startUrl : '/dealer';
        PageReference ref = Site.login(username, password, target);

        if (ref == null) {
            throw new AuraHandledException('Ongeldig e-mailadres of wachtwoord.');
        }
        return ref.getUrl();
    }

    // Same convention as Svc_DealerUserSetup.buildUsername:
    //   production : <email>.miDealer
    //   sandbox    : <email>.miDealer.<sandboxName>
    private static String buildUsername(String email) {
        // Sandbox org domain: orgname--sandboxname.sandbox.my.salesforce.com
        // Production:         orgname.my.salesforce.com
        String host = System.URL.getOrgDomainUrl().getHost();
        String username = email + '.miDealer';
        if (host.contains('--')) {
            username += '.' + host.substringBetween('--', '.');
        }
        return username;
    }
}
