# Backfill of account-contact roles from the account lookups (prepared 2026-10-15, NOT run)

Variant A (user: prepare the backfill; A chosen as the neutral variant): a relation gets Main / Invoice / Shipping /
Reminder / Digital only where the account lookup already points to that contact (Contact_person__c,
Contact_Billing__c, Contact_Shipping__c, Subscription25__Reminder_Contact__c, Subscription25__UBL_Billing_Attendant_To__c).
Existing roles are kept, new ones appended. Prod export 2026-10-15 (229,090 relations):

| | |
| --- | --- |
| Relations to update | 71,487 (active accounts 69,414, deactivated 1,670, blocked 315, bankrupt 88) |
| Roles added | Shipping 70,002 · Main 57,971 · Invoice 57,748 · Reminder 1,555 · Digital 1,054 |
| Account fields changed | none: the lookups already point to these contacts (Billing Attendant change: 0 of 57,748) |
| Skipped (review_skipped.csv) | 3,934 no email address · 222 role held by another contact · 21 lookup contact not related |

Not chosen – variant B (also Payment/Shipping with Main, Reminder/Digital with Invoice): 187,707 relations and it would
move the Reminder contact and UBL billing attendant on many accounts. The platform adds those roles itself on its next
call for accounts that are still active.

What runs on each update in prod: rbb_AccountContactRelation (before save; only sets default roles on new direct
relations) and Svc_AccountContactRelationRoles (one owner per role, lookups; synchronous, no callouts). The roles
flow is off since 2026-10-15 09:15. No platform / Exact callouts.

Files (sorted by AccountId, so an account's relations sit in the same batch):
- `backup_roles_before.csv` – Id, Roles as they are now (all 71,487) = rollback file
- `update_pilot_100.csv` – 100 random relations
- `update_rest.csv` – the other 71,387

Steps (each only on the user's explicit go; prod):
1. Pilot: `sf data update bulk -o prod --sobject AccountContactRelation --file "update_pilot_100.csv" --wait 30`
   Check: the 100 relations have the new roles; no Event_Log__c with Action RolesSync / Result ERROR; the accounts'
   five lookups unchanged (compare with the export); 0 failed rows.
2. Rest: same command with `update_rest.csv` (off-peak). Bulk API 2.0 runs batches in parallel: rerun the failed-rows
   file once (row locks on a busy account are retried fine).
3. Re-run the export count: relations missing a lookup-implied role should drop from 71,487 to ~the skipped list.
Rollback: `sf data update bulk -o prod --sobject AccountContactRelation --file "backup_roles_before.csv" --wait 60`
(roles back; removing roles makes no owner changes).
