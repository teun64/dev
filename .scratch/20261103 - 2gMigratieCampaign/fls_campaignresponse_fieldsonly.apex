// Campaign response fields (apply answer + response link) + Product2.MigrationProduct__c (offer lines) + Source job fields: read/edit for System Administrator + miModifyAllData, read-only for miSales, miFinance, miMarketing, miAfterSales
// Fields part only (stage A of the prod rollout: the guest class does not exist yet). The guest class grant follows after the Apex deploy.
List<String> fields = new List<String>{
  'Campaign.CampaignRole__c', 'Campaign.MailScheduleDays__c', 'CampaignMember.ResponseToken__c', 'CampaignMember.ResponseUrl__c',
  'Product2.MigrationProduct__c', 'Product2.MigrationPriority__c', 'Campaign.SourceSelection__c', 'Campaign.SourceCountryCodes__c',
  'CampaignMember.Account__c', 'CampaignMember.UnitCount__c', 'CampaignMember.Dealer__c', 'CampaignMember.LargeAccount__c'};
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
// guest page class (a permission set deploy would replace the whole set)
