// Campaign.OpportunityNamePrefix__c + CampaignOfferProduct__c: object + optional field access for System Administrator + miModifyAllData (Product2 lookups are optional: Product2 cannot have Restrict children; validation rules make them required. Campaign__c is required, no FLS).
// Svc_CampaignOffer reads it in system mode. Additive; run once per org.
List<String> fields = new List<String>{
  'Campaign.OpportunityNamePrefix__c',
  'CampaignOfferProduct__c.Hardware__c','CampaignOfferProduct__c.OfferProduct__c','CampaignOfferProduct__c.AlternativeProduct__c','CampaignOfferProduct__c.FilterField__c',
  'CampaignOfferProduct__c.FilterValue__c','CampaignOfferProduct__c.Active__c','CampaignOfferProduct__c.Priority__c'};
List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Profile.Name = 'System Administrator' OR Name = 'miModifyAllData'];
Set<String> existing = new Set<String>();
for (FieldPermissions fp : [SELECT ParentId, Field FROM FieldPermissions WHERE ParentId IN :sets AND Field IN :fields]) existing.add(fp.ParentId + fp.Field);
List<FieldPermissions> ins = new List<FieldPermissions>();
for (PermissionSet ps : sets) for (String f : fields) if (!existing.contains(ps.Id + f))
  ins.add(new FieldPermissions(ParentId = ps.Id, SobjectType = f.substringBefore('.'), Field = f, PermissionsRead = true, PermissionsEdit = true));
insert ins;
Set<Id> haveObj = new Set<Id>();
for (ObjectPermissions op : [SELECT ParentId FROM ObjectPermissions WHERE ParentId IN :sets AND SobjectType = 'CampaignOfferProduct__c']) haveObj.add(op.ParentId);
List<ObjectPermissions> objs = new List<ObjectPermissions>();
for (PermissionSet ps : sets) if (!haveObj.contains(ps.Id))
  objs.add(new ObjectPermissions(ParentId = ps.Id, SobjectType = 'CampaignOfferProduct__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true, PermissionsViewAllRecords = true, PermissionsModifyAllRecords = true));
insert objs;
System.debug(LoggingLevel.ERROR, 'FLSRESULT fields=' + ins.size() + ' objects=' + objs.size());
