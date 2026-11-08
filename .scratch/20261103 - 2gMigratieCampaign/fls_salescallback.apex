// Sales call-back fields: read/edit for System Administrator + miModifyAllData, read-only for the profiles of the sales role group (miSales, miFinance, miMarketing, miAfterSales)
// (Svc_SalesCallback writes them in system mode). Additive: skips grants that already exist. Run once per org.
List<String> fields = new List<String>{
  'Campaign.CallbackLabel__c',
  'Case.Campaign__c','Case.CampaignMemberId__c','Case.CallbackSource__c','Case.CallbackAttempts__c',
  'Case.CallbackDueOn__c','Case.CallbackLastAgent__c'};
List<PermissionSet> adminSets = [SELECT Id FROM PermissionSet WHERE Profile.Name = 'System Administrator' OR Name = 'miModifyAllData'];
List<PermissionSet> salesSets = [SELECT Id FROM PermissionSet WHERE Profile.Name IN ('miSales','miFinance','miMarketing','miAfterSales')];
Map<Id, Boolean> editBySet = new Map<Id, Boolean>();
for (PermissionSet ps : adminSets) editBySet.put(ps.Id, true);
for (PermissionSet ps : salesSets) editBySet.put(ps.Id, false);
Set<String> existing = new Set<String>();
for (FieldPermissions fp : [SELECT ParentId, Field FROM FieldPermissions WHERE ParentId IN :editBySet.keySet() AND Field IN :fields]) existing.add(fp.ParentId + fp.Field);
List<FieldPermissions> ins = new List<FieldPermissions>();
for (Id psId : editBySet.keySet()) for (String f : fields) if (!existing.contains(psId + f))
  ins.add(new FieldPermissions(ParentId = psId, SobjectType = f.substringBefore('.'), Field = f, PermissionsRead = true, PermissionsEdit = editBySet.get(psId)));
insert ins;
System.debug(LoggingLevel.ERROR, 'FLSRESULT sets=' + editBySet.size() + ' inserted=' + ins.size());
