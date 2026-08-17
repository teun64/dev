/**
 * Determines whether Contacts should be excluded from marketing/communication-preference
 * touchpoints based on AccountContactRelation.Marketing__c.
 *
 * A Contact is excluded only when they have at least one AccountContactRelation and NONE of
 * them are marketable — a Contact with no relations at all, or at least one marketable
 * relation, is not excluded. "No relations yet" (e.g. a Contact just before insert, before any
 * AccountContactRelation exists) is treated the same as "no disqualifying evidence."
 */
public without sharing class Util_ContactMarketing {

    public static Set<Id> getExcludedContactIds(Set<Id> contactIds) {
        Set<Id> excluded = new Set<Id>();
        if (contactIds == null || contactIds.isEmpty()) return excluded;

        Set<Id> hasAnyRelation        = new Set<Id>();
        Set<Id> hasMarketableRelation = new Set<Id>();

        for (AccountContactRelation acr : [
            SELECT ContactId, Marketing__c
            FROM   AccountContactRelation
            WHERE  ContactId IN :contactIds
            WITH   SYSTEM_MODE
        ]) {
            hasAnyRelation.add(acr.ContactId);
            if (acr.Marketing__c) hasMarketableRelation.add(acr.ContactId);
        }

        for (Id contactId : hasAnyRelation) {
            if (!hasMarketableRelation.contains(contactId)) {
                excluded.add(contactId);
            }
        }
        return excluded;
    }
}
