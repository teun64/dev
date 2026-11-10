// FLS for the dunning fields: System Administrator profile + miModifyAllData (read/edit), ps_miSubscription25_User (read)
Map<String, Boolean> editable = new Map<String, Boolean>{
    'Payment__c.Dunning_Step__c' => true, 'Payment__c.Dunning_Action__c' => true, 'Payment__c.Retry_Date__c' => true,
    'Payment__c.Suspension_Date__c' => true, 'Payment__c.Failure_Code__c' => true, 'Payment__c.Card_Renewal_Requested__c' => true,
    'Payment__c.Card_Expires_Before_Collection__c' => false,
    'Account.PayProv_CardExpiry__c' => true, 'Account.PayProv_CardWallet__c' => true
};
Map<Id, Boolean> setsEdit = new Map<Id, Boolean>();
for (PermissionSet ps : [SELECT Id, Name, Profile.Name FROM PermissionSet WHERE Profile.Name = 'System Administrator' OR Name IN ('miModifyAllData', 'ps_miSubscription25_User')]) {
    setsEdit.put(ps.Id, ps.Name != 'ps_miSubscription25_User');
}
Set<String> existing = new Set<String>();
for (FieldPermissions fp : [SELECT ParentId, Field FROM FieldPermissions WHERE ParentId IN :setsEdit.keySet() AND Field IN :editable.keySet()]) existing.add(fp.ParentId + fp.Field);
List<FieldPermissions> rows = new List<FieldPermissions>();
for (Id psId : setsEdit.keySet()) for (String f : editable.keySet()) {
    if (existing.contains(psId + f)) continue;
    rows.add(new FieldPermissions(ParentId = psId, SobjectType = f.substringBefore('.'), Field = f, PermissionsRead = true,
        PermissionsEdit = setsEdit.get(psId) && editable.get(f)));
}
insert rows;
System.debug('FLS rows inserted: ' + rows.size() + ' on ' + setsEdit.size() + ' sets');
