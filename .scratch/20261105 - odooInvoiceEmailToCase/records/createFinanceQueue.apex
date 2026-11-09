// Idempotent, per org: queue gqCaseFinanceExcellenceCenter (Case) with Jessica Hak and Floris van Beek as members (when they are active users in this org),
// the permission set ps_miOdooProductMapping for them and for the running user, and the object / field access of the Odoo Product relation for the admin sets.
Group q;
List<Group> existing = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'gqCaseFinanceExcellenceCenter'];
if (existing.isEmpty()) {
	q = new Group(Name = 'Case - Finance Excellence Center', DeveloperName = 'gqCaseFinanceExcellenceCenter', Type = 'Queue');
	insert q;
	insert new QueueSobject(QueueId = q.Id, SobjectType = 'Case');
} else {
	q = existing[0];
}
List<User> people = [SELECT Id, Name FROM User WHERE IsActive = true AND ((FirstName = 'Jessica' AND LastName = 'Hak') OR (FirstName = 'Floris' AND LastName LIKE '%Beek'))];
Set<Id> members = new Set<Id>();
for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :q.Id]) members.add(gm.UserOrGroupId);
List<GroupMember> newMembers = new List<GroupMember>();
Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'ps_miOdooProductMapping'].Id;
Set<Id> assigned = new Set<Id>();
for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :psId]) assigned.add(a.AssigneeId);
List<PermissionSetAssignment> newAssign = new List<PermissionSetAssignment>();
Set<Id> assignees = new Set<Id>{ UserInfo.getUserId() };
for (User u : people) {
	assignees.add(u.Id);
	if (!members.contains(u.Id)) newMembers.add(new GroupMember(GroupId = q.Id, UserOrGroupId = u.Id));
}
for (Id uid : assignees) if (!assigned.contains(uid)) newAssign.add(new PermissionSetAssignment(AssigneeId = uid, PermissionSetId = psId));
insert newMembers;
insert newAssign;
// admin access: object + fields for System Administrator profile set and miModifyAllData
List<PermissionSet> admins = [SELECT Id FROM PermissionSet WHERE Profile.Name = 'System Administrator' OR Name = 'miModifyAllData'];
Set<String> haveObj = new Set<String>();
for (ObjectPermissions o : [SELECT ParentId FROM ObjectPermissions WHERE SobjectType = 'OdooProduct__c']) haveObj.add(String.valueOf(o.ParentId));
Set<String> haveFld = new Set<String>();
for (FieldPermissions f : [SELECT ParentId, Field FROM FieldPermissions WHERE SobjectType = 'OdooProduct__c']) haveFld.add(f.ParentId + f.Field);
List<SObject> perms = new List<SObject>();
for (PermissionSet p : admins) {
	if (!haveObj.contains(String.valueOf(p.Id))) perms.add(new ObjectPermissions(ParentId = p.Id, SobjectType = 'OdooProduct__c', PermissionsRead = true, PermissionsCreate = true, PermissionsEdit = true, PermissionsDelete = true, PermissionsViewAllRecords = true, PermissionsModifyAllRecords = true));
	if (!haveFld.contains(p.Id + 'OdooProduct__c.Mapped__c')) perms.add(new FieldPermissions(ParentId = p.Id, SobjectType = 'OdooProduct__c', Field = 'OdooProduct__c.Mapped__c', PermissionsRead = true, PermissionsEdit = false));
	for (String f : new List<String>{ 'OdooName__c', 'Product__c', 'OdooEntity__c', 'OdooFirstInvoice__c' }) {
		if (!haveFld.contains(p.Id + 'OdooProduct__c.' + f)) perms.add(new FieldPermissions(ParentId = p.Id, SobjectType = 'OdooProduct__c', Field = 'OdooProduct__c.' + f, PermissionsRead = true, PermissionsEdit = true));
	}
}
insert perms;
System.debug('OK queue=' + q.Id + ' members+' + newMembers.size() + ' people=' + people.size() + ' assign+' + newAssign.size() + ' perms+' + perms.size());
