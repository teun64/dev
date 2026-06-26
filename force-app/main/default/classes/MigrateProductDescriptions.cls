/**
 * One-time data migration:
 *   Product2.Description          → Product2.shortDescription__c
 *   Data_Translation__c.Description__c   → Data_Translation__c.longDescription__c
 *   Data_Translation__c.Short_Description__c → Data_Translation__c.shortDescription__c
 *
 * Run once via: Ctrl_DealerShop.migrateDescriptions() or execute the methods directly.
 * Delete this class after migration is confirmed.
 */
public without sharing class MigrateProductDescriptions {

    public static void run() {
        migrateProducts();
        migrateTranslations();
        System.debug('MigrateProductDescriptions: done');
    }

    private static void migrateProducts() {
        List<Product2> toUpdate = new List<Product2>();
        for (Product2 p : [
            SELECT Id, Description, shortDescription__c
            FROM Product2
            WHERE Description != null
              AND (shortDescription__c = null OR shortDescription__c = '')
            WITH SYSTEM_MODE
        ]) {
            p.shortDescription__c = p.Description;
            toUpdate.add(p);
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
            System.debug('Products migrated: ' + toUpdate.size());
        }
    }

    private static void migrateTranslations() {
        List<Data_Translation__c> toUpdate = new List<Data_Translation__c>();
        for (Data_Translation__c t : Database.query(
            'SELECT Id, Description__c, Short_Description__c, shortDescription__c, longDescription__c ' +
            'FROM Data_Translation__c ' +
            'WITH SYSTEM_MODE',
            AccessLevel.SYSTEM_MODE
        )) {
            Boolean changed = false;
            if (String.isNotBlank((String) t.get('Description__c'))
                && String.isBlank((String) t.get('longDescription__c'))) {
                t.put('longDescription__c', t.get('Description__c'));
                changed = true;
            }
            if (String.isNotBlank((String) t.get('Short_Description__c'))
                && String.isBlank((String) t.get('shortDescription__c'))) {
                t.put('shortDescription__c', t.get('Short_Description__c'));
                changed = true;
            }
            if (changed) toUpdate.add(t);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
            System.debug('Translations migrated: ' + toUpdate.size());
        }
    }
}
