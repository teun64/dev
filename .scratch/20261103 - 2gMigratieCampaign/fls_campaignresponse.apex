// Campaign response fields (apply answer + response link) + Product2.MigrationProduct__c (offer lines) + Source job fields: read/edit for System Administrator + miModifyAllData, read-only for miSales, miFinance, miMarketing, miAfterSales
// (Svc_CampaignResponse writes them in system mode), plus the guest class Ctrl_CampaignResponseGuest on ps_miCustomerHub_Guest. Additive. Run once per org.
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
Id guestPs = [SELECT Id FROM PermissionSet WHERE Name = 'ps_miCustomerHub_Guest'].Id;
Id cls = [SELECT Id FROM ApexClass WHERE Name = 'Ctrl_CampaignResponseGuest' AND NamespacePrefix = null].Id;
if ([SELECT COUNT() FROM SetupEntityAccess WHERE ParentId = :guestPs AND SetupEntityId = :cls] == 0) {
  insert new SetupEntityAccess(ParentId = guestPs, SetupEntityId = cls);
  System.debug(LoggingLevel.ERROR, 'FLSRESULT guest class granted');
}
