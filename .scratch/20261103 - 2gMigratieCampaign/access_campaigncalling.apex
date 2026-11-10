// 2G campaign calling (2026-11-10, user's choice): the campaign Ctrl classes go into ps_miAPEXOperationalClasses, and that
// set goes into pg_miSales and pg_miSupport (After Sales). Additive (SetupEntityAccess / PermissionSetGroupComponent DML):
// a permission set deploy would replace the whole set. Run once per org; groups that don't exist in the org are skipped.
Id ps = [SELECT Id FROM PermissionSet WHERE Name = 'ps_miAPEXOperationalClasses'].Id;
List<String> classNames = new List<String>{ 'Ctrl_CampaignMemberCall', 'Ctrl_StagedCampaignOverview' };
Set<Id> has = new Set<Id>();
for (SetupEntityAccess s : [SELECT SetupEntityId FROM SetupEntityAccess WHERE ParentId = :ps]) has.add(s.SetupEntityId);
List<SetupEntityAccess> grants = new List<SetupEntityAccess>();
for (ApexClass c : [SELECT Id, Name FROM ApexClass WHERE Name IN :classNames AND NamespacePrefix = null]) {
  if (!has.contains(c.Id)) grants.add(new SetupEntityAccess(ParentId = ps, SetupEntityId = c.Id));
}
insert grants;
List<String> groupNames = new List<String>{ 'pg_miSales', 'pg_miSupport' };
Set<Id> inGroup = new Set<Id>();
for (PermissionSetGroupComponent c : [SELECT PermissionSetGroupId FROM PermissionSetGroupComponent WHERE PermissionSetId = :ps]) inGroup.add(c.PermissionSetGroupId);
List<PermissionSetGroupComponent> comps = new List<PermissionSetGroupComponent>();
List<String> found = new List<String>();
for (PermissionSetGroup g : [SELECT Id, DeveloperName FROM PermissionSetGroup WHERE DeveloperName IN :groupNames]) {
  found.add(g.DeveloperName);
  if (!inGroup.contains(g.Id)) comps.add(new PermissionSetGroupComponent(PermissionSetGroupId = g.Id, PermissionSetId = ps));
}
insert comps;
System.debug(LoggingLevel.ERROR, 'ACCESSRESULT classes granted ' + grants.size() + ', groups found ' + found + ', added to ' + comps.size() + ' group(s)');
