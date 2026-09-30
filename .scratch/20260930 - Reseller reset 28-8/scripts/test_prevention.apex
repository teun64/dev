// Rolled-back check of the reseller/country prevention (rbb_Account + Reseller_Name__c without default).
// Nothing is kept: every insert/update is rolled back at the end.
Savepoint sp = Database.setSavepoint();
try {
    Id b2b = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId();
    List<Account> accs = new List<Account>{
        new Account(Name='RRTEST ext1 MI',            RecordTypeId=b2b, extId_1__c='RRTEST1'),
        new Account(Name='RRTEST ext2 Trackpilot',    RecordTypeId=b2b, extId_2__c='RRTEST2'),
        new Account(Name='RRTEST ext3 Chiron',        RecordTypeId=b2b, extId_3__c='RRTEST3'),
        new Account(Name='RRTEST ext4 Nexus',         RecordTypeId=b2b, extId_4__c='RRTEST4'),
        new Account(Name='RRTEST ext5 EuropeTrack',   RecordTypeId=b2b, extId_5__c='RRTEST5'),
        new Account(Name='RRTEST ext6 Echoes',        RecordTypeId=b2b, extId_6__c='RRTEST6'),
        new Account(Name='RRTEST ext3 API reseller 3',RecordTypeId=b2b, extId_3__c='RRTEST3b', Reseller_Name__c='3'),
        new Account(Name='RRTEST nothing',            RecordTypeId=b2b)
    };
    insert accs;
    for (Account a : [SELECT Name, BillingCountryCode, Reseller_Name__c, FinancialSystemSync__c, FinancialSystemSyncBank__c, FinancialSystemSyncMandate__c
                      FROM Account WHERE Id IN :accs ORDER BY Name]) {
        System.debug('R INSERT ' + a.Name + ' | country=' + a.BillingCountryCode + ' | reseller=' + a.Reseller_Name__c
            + ' | syncflags=' + a.FinancialSystemSync__c + '/' + a.FinancialSystemSyncBank__c + '/' + a.FinancialSystemSyncMandate__c);
    }
    // 28-8 scenario: reseller 6, no country, no platform ids, unrelated update
    Account t = accs[7];
    update new Account(Id = t.Id, Reseller_Name__c = '6');
    update new Account(Id = t.Id, PrimaryBrand__c = 'E');
    Account r = [SELECT BillingCountryCode, Reseller_Name__c FROM Account WHERE Id = :t.Id];
    System.debug('R UPDATE 28-8 scenario | country=' + r.BillingCountryCode + ' | reseller=' + r.Reseller_Name__c);
    update new Account(Id = t.Id, BillingCountryCode = 'DE');
    r = [SELECT BillingCountryCode, Reseller_Name__c FROM Account WHERE Id = :t.Id];
    System.debug('R UPDATE country->DE | country=' + r.BillingCountryCode + ' | reseller=' + r.Reseller_Name__c);
    update new Account(Id = t.Id, BillingCountryCode = 'US');
    r = [SELECT BillingCountryCode, Reseller_Name__c FROM Account WHERE Id = :t.Id];
    System.debug('R UPDATE country->US | country=' + r.BillingCountryCode + ' | reseller=' + r.Reseller_Name__c);
} finally {
    Database.rollback(sp);
    System.debug('R ROLLED BACK');
}
