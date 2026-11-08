List<String> fields = new List<String>{
  'Campaign.MaxMailAttempts__c','Campaign.MailIntervalDays__c','Campaign.MailCompletedStatus__c',
  'CampaignMember.Priority__c','CampaignMember.MailBatch__c','CampaignMember.MailBatchReleasedOn__c','CampaignMember.MailStage__c',
  'CampaignMember.MailNumber__c','CampaignMember.MailDueOn__c','CampaignMember.Response__c','CampaignMember.ResponseOn__c','CampaignMember.RecontactFrom__c'};
List<PermissionSet> sets = [SELECT Id, Name FROM PermissionSet WHERE Profile.Name = 'System Administrator' OR Name = 'miModifyAllData'];
Set<String> existing = new Set<String>();
for (FieldPermissions fp : [SELECT ParentId, Field FROM FieldPermissions WHERE ParentId IN :sets AND Field IN :fields]) existing.add(fp.ParentId + fp.Field);
List<FieldPermissions> ins = new List<FieldPermissions>();
for (PermissionSet ps : sets) for (String f : fields) if (!existing.contains(ps.Id + f))
  ins.add(new FieldPermissions(ParentId = ps.Id, SobjectType = f.substringBefore('.'), Field = f, PermissionsRead = true, PermissionsEdit = true));
insert ins;
System.debug('FLSRESULT sets=' + sets.size() + ' inserted=' + ins.size());
