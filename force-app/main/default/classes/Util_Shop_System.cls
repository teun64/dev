public without sharing class Util_Shop_System {

    public class DealerAccountLookup {
        public Id     accountId;
        public Id     contactId;
        public String contactLanguage;
        public String userDefaultLanguage;
    }

    // User -> Contact.AccountId is the primary path (external/community users with a linked
    // Contact); Identity/internal users without a ContactId fall back to an email match on
    // Contact, since that's the only link available to them.
    public static DealerAccountLookup resolveDealerAccountId(Id userId) {
        DealerAccountLookup result = new DealerAccountLookup();

        List<User> users = [
            SELECT ContactId, Email, DefaultLanguage__c
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) return result;
        User usr = users[0];
        result.userDefaultLanguage = usr.DefaultLanguage__c;

        if (usr.ContactId != null) {
            List<Contact> contacts = [
                SELECT AccountId, Language__c
                FROM Contact WHERE Id = :usr.ContactId WITH SYSTEM_MODE LIMIT 1
            ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                result.accountId       = contacts[0].AccountId;
                result.contactId       = usr.ContactId;
                result.contactLanguage = contacts[0].Language__c;
                return result;
            }
        }

        if (String.isNotBlank(usr.Email)) {
            List<Contact> emailCons = [
                SELECT Id, AccountId, Language__c
                FROM Contact WHERE Email = :usr.Email AND AccountId != null
                WITH SYSTEM_MODE LIMIT 1
            ];
            if (!emailCons.isEmpty()) {
                result.accountId       = emailCons[0].AccountId;
                result.contactId       = emailCons[0].Id;
                result.contactLanguage = emailCons[0].Language__c;
            }
        }

        return result;
    }

    // Account.Reseller_Name__c and Administration.Reseller__c are both plain picklist codes
    // ("1".."6") that happen to overlap digit-wise with the unrelated System__c global value
    // set - they are NOT platform codes themselves, just the join key to find the Administration
    // record for a reseller. fieldList is caller-supplied since each caller projects a different
    // shape off Subscription25__Administration__c.
    public static List<Subscription25__Administration__c> getAdministrationsByReseller(String resellerCode, String fieldList) {
        if (String.isBlank(resellerCode)) return new List<Subscription25__Administration__c>();
        String soql = 'SELECT ' + fieldList + ' FROM Subscription25__Administration__c WHERE Reseller__c = :resellerCode';
        return Database.query(soql, AccessLevel.SYSTEM_MODE);
    }
}
