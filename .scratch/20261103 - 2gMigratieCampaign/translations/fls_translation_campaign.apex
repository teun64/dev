// Additive FLS for Data_Translation__c.Campaign__c: every permission set / profile that can read Data_Translation__c.Product__c
// gets the same access on Campaign__c. Run per org after the field deploy (a permission set deploy would replace the whole set).
List<FieldPermissions> src = [SELECT ParentId, SobjectType, PermissionsRead, PermissionsEdit FROM FieldPermissions
	WHERE SobjectType = 'Data_Translation__c' AND Field = 'Data_Translation__c.Product__c'];
Set<Id> have = new Set<Id>();
for (FieldPermissions f : [SELECT ParentId FROM FieldPermissions WHERE Field = 'Data_Translation__c.Campaign__c']) have.add(f.ParentId);
List<FieldPermissions> add = new List<FieldPermissions>();
for (FieldPermissions f : src) {
	if (have.contains(f.ParentId)) continue;
	add.add(new FieldPermissions(ParentId = f.ParentId, SobjectType = 'Data_Translation__c', Field = 'Data_Translation__c.Campaign__c',
		PermissionsRead = f.PermissionsRead, PermissionsEdit = f.PermissionsEdit));
}
Database.SaveResult[] res = Database.insert(add, false);
Integer ok = 0;
for (Integer i = 0; i < res.size(); i++) {
	if (res[i].isSuccess()) ok++; else System.debug('FLS fail ' + add[i].ParentId + ': ' + res[i].getErrors()[0].getMessage());
}
System.debug('FLS Campaign__c inserted ' + ok + ' of ' + add.size());
