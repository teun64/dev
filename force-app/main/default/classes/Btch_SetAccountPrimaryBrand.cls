/**
 * One-time migration: populate Account.PrimaryBrand__c from Reseller_Name__c.
 * Mapping: Reseller_Name__c 1/2/3/5/6 -> 'M' (Moving Intelligence), 4 -> 'E' (Echoes).
 * Runs against ALL accounts regardless of Deactivated__c, to avoid rework if a
 * deactivated account is later reactivated.
 */
public with sharing class Btch_SetAccountPrimaryBrand implements Database.Batchable<SObject>, Database.Stateful {
    private Integer updatedCount = 0;

    private static final Map<String, String> RESELLER_TO_BRAND = new Map<String, String>{
        '1' => 'M', '2' => 'M', '3' => 'M', '5' => 'M', '6' => 'M',
        '4' => 'E'
    };

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Reseller_Name__c, PrimaryBrand__c
            FROM Account
            WHERE Reseller_Name__c IN ('1', '2', '3', '4', '5', '6')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        List<Account> toUpdate = new List<Account>();
        for (Account acc : scope) {
            String brand = RESELLER_TO_BRAND.get(acc.Reseller_Name__c);
            if (brand != null && acc.PrimaryBrand__c != brand) {
                toUpdate.add(new Account(Id = acc.Id, PrimaryBrand__c = brand));
            }
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
            updatedCount += toUpdate.size();
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Btch_SetAccountPrimaryBrand finished, updated ' + updatedCount + ' accounts');
    }
}
