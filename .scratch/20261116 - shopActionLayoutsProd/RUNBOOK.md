# Shop Action layouts + All list view -> prod (PREPARED 2026-11-16, not deployed)
Dev's layouts are placed under prod's layout name "Shop_Action__c-Shop Action Layout" (dev's is called "Shop Action"), so prod's layout is replaced, not duplicated.
Contents: 2 layouts (Shop Action, Shop Action Product: sections, related list, fields) + ListView Shop_Action__c.All.
Dry-run prod: succeeded 3/3 (0AfTx0000015cIbKAI).
Deploy (only on explicit go): sf project deploy start -o prod --manifest "package.xml"
Rollback: retrieve prod layouts first (prod had stripped-down layouts, no related list).
Source files: force-app/main/default/layouts/Shop_Action*, objects/Shop_Action__c/listViews/All (uncommitted).
Deployed prod 2026-11-16.
