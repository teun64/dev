public without sharing class Ctrl_DealerPortal {

    // ── Brand config ──────────────────────────────────────────────────────────

    @AuraEnabled
    public static BrandConfigDTO getBrandConfig() {
        String resellerCode = resolveResellerCode();

        List<BrandThemeConfig__mdt> configs = [
            SELECT Brand__c, BrandName__c, PrimaryColor__c, AccentColor__c,
                   LogoStaticResource__c, TagLine__c, ResellerCodes__c,
                   PortalHomeTitle__c, PortalHomeWelcome__c,
                   PortalShopCtaText__c, PortalSignupTitle__c
            FROM BrandThemeConfig__mdt
        ];

        BrandThemeConfig__mdt matched = null;
        BrandThemeConfig__mdt fallback = null;
        for (BrandThemeConfig__mdt cfg : configs) {
            if (cfg.Brand__c == 'M') fallback = cfg;
            if (String.isNotBlank(cfg.ResellerCodes__c) && String.isNotBlank(resellerCode)) {
                for (String code : cfg.ResellerCodes__c.split(',')) {
                    if (code.trim() == resellerCode) { matched = cfg; break; }
                }
            }
            if (matched != null) break;
        }

        BrandThemeConfig__mdt cfg = matched != null ? matched : (fallback != null ? fallback : configs[0]);

        BrandConfigDTO dto = new BrandConfigDTO();
        dto.brandCode          = cfg.Brand__c;
        dto.brandName          = cfg.BrandName__c;
        dto.primaryColor       = cfg.PrimaryColor__c;
        dto.accentColor        = cfg.AccentColor__c;
        dto.logoPath           = cfg.LogoStaticResource__c;
        dto.homeTitle          = cfg.PortalHomeTitle__c;
        dto.homeWelcome        = cfg.PortalHomeWelcome__c;
        dto.shopCtaText        = cfg.PortalShopCtaText__c;
        dto.signupTitle        = cfg.PortalSignupTitle__c;
        dto.isAuthenticated    = isAuthenticatedUser();
        dto.userName           = isAuthenticatedUser() ? UserInfo.getName() : null;
        return dto;
    }

    // ── Footer info ───────────────────────────────────────────────────────────

    @AuraEnabled
    public static FooterDTO getFooterInfo() {
        String resellerCode = resolveResellerCode();

        List<Subscription25__Administration__c> admins = new List<Subscription25__Administration__c>();
        if (String.isNotBlank(resellerCode)) {
            admins = [
                SELECT Subscription25__Billing_Name__c, Subscription25__Phone__c,
                       Subscription25__Billing_Email_Address__c, Subscription25__Website__c,
                       Subscription25__Billing_Street__c, Subscription25__Billing_City__c,
                       Subscription25__Billing_Country__c
                FROM Subscription25__Administration__c
                WHERE Reseller__c = :resellerCode
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        }

        FooterDTO dto = new FooterDTO();
        if (!admins.isEmpty()) {
            Subscription25__Administration__c admin = admins[0];
            dto.companyName = admin.Subscription25__Billing_Name__c;
            dto.phone       = admin.Subscription25__Phone__c;
            dto.email       = admin.Subscription25__Billing_Email_Address__c;
            dto.website     = admin.Subscription25__Website__c;
            dto.street      = admin.Subscription25__Billing_Street__c;
            dto.city        = admin.Subscription25__Billing_City__c;
            dto.country     = admin.Subscription25__Billing_Country__c;
        } else {
            dto.companyName = 'Moving Intelligence B.V.';
            dto.phone       = '+31 (0)88 990 00 00';
            dto.email       = 'aftersales@movingintelligence.nl';
            dto.website     = 'movingintelligence.nl';
        }
        return dto;
    }

    // ── Signup request ────────────────────────────────────────────────────────

    @AuraEnabled
    public static void submitSignupRequest(
        String companyName,
        String contactName,
        String email,
        String phone,
        String country,
        String message
    ) {
        if (String.isBlank(companyName) || String.isBlank(email)) {
            throw new AuraHandledException('Company name and email are required.');
        }

        Lead lead = new Lead(
            Company    = companyName,
            LastName   = String.isNotBlank(contactName) ? contactName : companyName,
            Email      = email,
            Phone      = phone,
            Country    = country,
            Description = message,
            LeadSource = 'Dealer Portal',
            Status     = 'Open - Not Contacted'
        );
        insert lead;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static String resolveResellerCode() {
        if (!isAuthenticatedUser()) return null;
        List<User> users = [
            SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null) return null;
        List<Contact> contacts = [
            SELECT AccountId FROM Contact WHERE Id = :users[0].ContactId WITH SYSTEM_MODE LIMIT 1
        ];
        if (contacts.isEmpty() || contacts[0].AccountId == null) return null;
        List<Account> accounts = [
            SELECT Reseller_Name__c FROM Account WHERE Id = :contacts[0].AccountId WITH SYSTEM_MODE LIMIT 1
        ];
        return (!accounts.isEmpty()) ? accounts[0].Reseller_Name__c : null;
    }

    private static Boolean isAuthenticatedUser() {
        String userType = UserInfo.getUserType();
        return userType != 'Guest';
    }

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class BrandConfigDTO {
        @AuraEnabled public String  brandCode;
        @AuraEnabled public String  brandName;
        @AuraEnabled public String  primaryColor;
        @AuraEnabled public String  accentColor;
        @AuraEnabled public String  logoPath;
        @AuraEnabled public String  homeTitle;
        @AuraEnabled public String  homeWelcome;
        @AuraEnabled public String  shopCtaText;
        @AuraEnabled public String  signupTitle;
        @AuraEnabled public Boolean isAuthenticated;
        @AuraEnabled public String  userName;
    }

    public class FooterDTO {
        @AuraEnabled public String companyName;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String website;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
    }
}
