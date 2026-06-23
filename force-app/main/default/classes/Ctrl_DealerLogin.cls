public without sharing class Ctrl_DealerLogin {

    @AuraEnabled
    public static String login(String username, String password, String startUrl) {
        if (String.isBlank(username) || String.isBlank(password)) {
            throw new AuraHandledException('Username and password are required.');
        }

        String target = String.isNotBlank(startUrl) ? startUrl : '/dealer';
        PageReference ref = Site.login(username, password, target);

        if (ref == null) {
            throw new AuraHandledException('Invalid username or password.');
        }
        return ref.getUrl();
    }
}
