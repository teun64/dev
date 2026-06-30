public without sharing class Ctrl_CustomerHub {

    public class AdminInfo {
        @AuraEnabled public String name;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String website;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
        @AuraEnabled public String kvk;
        @AuraEnabled public String vatNumber;
    }

    private static final Map<String, String> BRAND_RESELLER = new Map<String, String>{
        'M' => '1',
        'E' => '4',
        'T' => '6'
    };

    @AuraEnabled(cacheable=true)
    public static AdminInfo getAdminInfo(String contactId, String brand) {
        String resellerCode = null;

        // 1. Try to resolve reseller from contact / authenticated user
        Id resolvedContactId;
        if (String.isNotBlank(contactId)) {
            resolvedContactId = (Id) contactId;
        } else {
            Id uid = UserInfo.getUserId();
            List<User> users = [SELECT ContactId FROM User WHERE Id = :uid WITH SYSTEM_MODE LIMIT 1];
            if (!users.isEmpty()) resolvedContactId = users[0].ContactId;
        }

        if (resolvedContactId != null) {
            List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :resolvedContactId WITH SYSTEM_MODE LIMIT 1];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                List<Account> accounts = [
                    SELECT Reseller_Name__c
                    FROM Account
                    WHERE Id = :contacts[0].AccountId
                    WITH SYSTEM_MODE
                    LIMIT 1
                ];
                if (!accounts.isEmpty()) resellerCode = accounts[0].Reseller_Name__c;
            }
        }

        // 2. Brand fallback when reseller could not be determined; default brand is M
        if (String.isBlank(resellerCode)) {
            resellerCode = BRAND_RESELLER.get(String.isNotBlank(brand) ? brand : 'M');
        }
        if (String.isBlank(resellerCode)) return null;

        List<Subscription25__Administration__c> admins = [
            SELECT Subscription25__Billing_Name__c,
                   Subscription25__Phone__c,
                   email_sales__c,
                   Subscription25__Website__c,
                   Subscription25__Billing_Street__c,
                   Subscription25__Billing_City__c,
                   Subscription25__Billing_Postal_Code__c,
                   Subscription25__Billing_Country__c,
                   Subscription25__Chamber_Of_Commerce_Number__c,
                   Subscription25__VAT_Number__c
            FROM   Subscription25__Administration__c
            WHERE  Reseller__c = :resellerCode
            AND    Subscription25__Active__c = true
            WITH SYSTEM_MODE
            LIMIT  1
        ];
        if (admins.isEmpty()) return null;

        Subscription25__Administration__c a = admins[0];
        String rawWebsite = a.Subscription25__Website__c;
        if (String.isNotBlank(rawWebsite) && !rawWebsite.startsWith('http')) {
            rawWebsite = 'https://' + rawWebsite;
        }

        AdminInfo info      = new AdminInfo();
        info.name           = a.Subscription25__Billing_Name__c;
        info.phone          = a.Subscription25__Phone__c;
        info.email          = a.email_sales__c;
        info.website        = rawWebsite;
        info.street         = a.Subscription25__Billing_Street__c;
        info.city           = a.Subscription25__Billing_City__c;
        info.postalCode     = a.Subscription25__Billing_Postal_Code__c;
        info.country        = a.Subscription25__Billing_Country__c;
        info.kvk            = a.Subscription25__Chamber_Of_Commerce_Number__c;
        info.vatNumber      = a.Subscription25__VAT_Number__c;
        return info;
    }
}
