/**
 * Controller of the emailLetterheadPreferences component (footer part): company data of the
 * Business Entity that belongs to the email language. Visualforce email templates cannot merge
 * across objects the way Lightning templates do, and the Dealer Portal mails are also sent for
 * guests, so the entity is resolved from the language (same mapping as the Dealer Portal footer:
 * nl = reseller 1, fr = 4, de = 5, anything else = 6).
 */
public without sharing class Ctrl_EmailLetterheadFooter {

    public String emailLanguage { get; set; }

    public Business_Entities__c entity {
        get {
            if (entity == null) {
                List<Business_Entities__c> found = [
                    SELECT Business_Name__c, Address__Street__s, Address__PostalCode__s, Address__City__s,
                           Address__CountryCode__s, CoC_Number__c, VAT_Number__c, Managing_directors__c,
                           Terms_Conditions_URL__c, Privacy_Policy_URL__c
                    FROM Business_Entities__c
                    WHERE Reseller__c = :resellerCode()
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                entity = found.isEmpty() ? new Business_Entities__c() : found[0];
            }
            return entity;
        }
        private set;
    }

    public String addressLine {
        get {
            Business_Entities__c e = entity;
            List<String> parts = new List<String>();
            if (String.isNotBlank((String) e.get('Address__Street__s'))) parts.add((String) e.get('Address__Street__s'));
            String cityLine = ((String.isBlank((String) e.get('Address__PostalCode__s')) ? '' : (String) e.get('Address__PostalCode__s') + ' ')
                + (String.isBlank((String) e.get('Address__City__s')) ? '' : (String) e.get('Address__City__s'))).trim();
            if (String.isNotBlank(cityLine)) parts.add(cityLine);
            String country = COUNTRIES.get((String) e.get('Address__CountryCode__s'));
            if (country != null) parts.add(country);
            return String.join(parts, ', ');
        }
    }

    private static final Map<String, String> COUNTRIES = new Map<String, String>{
        'NL' => 'Netherlands', 'DE' => 'Germany', 'GB' => 'United Kingdom',
        'BE' => 'Belgium', 'FR' => 'France', 'GR' => 'Greece'
    };

    private String resellerCode() {
        String lang = String.isBlank(emailLanguage) ? '' : emailLanguage.left(2).toLowerCase();
        return lang == 'nl' ? '1' : lang == 'fr' ? '4' : lang == 'de' ? '5' : '6';
    }
}
