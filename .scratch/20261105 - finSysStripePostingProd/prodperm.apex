List<String> fields = new List<String>();
for (Schema.SObjectType t : new List<Schema.SObjectType>{ FinSysPosting__c.SObjectType, FinSysPostingLine__c.SObjectType }) {
    for (Schema.SObjectField f : t.getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.isCustom() && d.getName() != 'Posting__c') fields.add(t + '.' + d.getName());
    }
}
for (String f : new List<String>{ 'FinSysStripeFeeGLCode__c','FinSysStripeFeeVATCode__c','FinSysStripeJournalCode__c','FinSysStripePostingFrom__c','FinSysStripeSuspenseGLCode__c','FinSysStripeTransitGLCode__c' }) fields.add('Business_Entities__c.' + f);
for (String f : new List<String>{ 'FinSysInvoiceId__c','FinSysInvoiceNumber__c','FinSysNextAttempt__c' }) fields.add('Subscription25__Invoice__c.' + f);
fields.sort();
Map<String, Boolean> sets = new Map<String, Boolean>{ 'ps_miSubscription25_User' => false, 'miModifyAllData' => true };
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN :sets.keySet()]) {
    Boolean edit = sets.get(ps.Name);
    Set<String> have = new Set<String>();
    for (FieldPermissions fp : [SELECT Field FROM FieldPermissions WHERE ParentId = :ps.Id AND SobjectType IN ('FinSysPosting__c','FinSysPostingLine__c','Business_Entities__c','Subscription25__Invoice__c')]) have.add(fp.Field);
    List<ObjectPermissions> ops = new List<ObjectPermissions>();
    Set<String> haveObj = new Set<String>();
    for (ObjectPermissions op : [SELECT SobjectType FROM ObjectPermissions WHERE ParentId = :ps.Id AND SobjectType IN ('FinSysPosting__c','FinSysPostingLine__c')]) haveObj.add(op.SobjectType);
    for (String o : new List<String>{ 'FinSysPosting__c','FinSysPostingLine__c' }) if (!haveObj.contains(o))
        ops.add(new ObjectPermissions(ParentId = ps.Id, SobjectType = o, PermissionsRead = true, PermissionsCreate = edit, PermissionsEdit = edit, PermissionsDelete = edit));
    Database.SaveResult[] r1 = Database.insert(ops, false);
    List<FieldPermissions> fps = new List<FieldPermissions>();
    for (String f : fields) if (!have.contains(f)) fps.add(new FieldPermissions(ParentId = ps.Id, SobjectType = f.substringBefore('.'), Field = f, PermissionsRead = true, PermissionsEdit = edit));
    Database.SaveResult[] r2 = Database.insert(fps, false);
    Integer ok = 0; for (Database.SaveResult r : r1) if (r.isSuccess()) ok++; else System.debug('OBJERR ' + ps.Name + ' ' + r.getErrors()[0].getMessage());
    Integer okf = 0; for (Database.SaveResult r : r2) if (r.isSuccess()) okf++; else System.debug('FLDERR ' + ps.Name + ' ' + r.getErrors()[0].getMessage());
    System.debug('PS ' + ps.Name + ' objects ' + ok + '/' + ops.size() + ' fields ' + okf + '/' + fps.size());
}
