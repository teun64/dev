// Customer Hub URL on every Administration (prod). Sync_Administration_to_Business_Entity copies it to the Business Entity,
// where Payment__c.Setup_URL__c (direct debit link in all DD emails + the invoice email block) reads it.
List<Subscription25__Administration__c> admins = [SELECT Id, Name, CustomerHub_URL__c FROM Subscription25__Administration__c];
for (Subscription25__Administration__c a : admins) {
    System.debug('HUBFILL|' + a.Name + '|before=' + a.CustomerHub_URL__c);
    a.CustomerHub_URL__c = 'https://customer.movingintelligence.com';
}
update admins;
