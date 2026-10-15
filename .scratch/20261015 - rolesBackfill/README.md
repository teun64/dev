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

## The data fix in one go – `run_datafix.py` (supersedes the CSV steps below; 2026-10-15)

Prerequisite: the code fix live in prod – `Rest_UpsertAccount` 64f920c (visit / billing contact keeps the real platform id,
name match), validated `0AfTx0000013IkbKAE` (2/2, 30/30); quick deploy on the go. Otherwise visit-only calls keep creating
duplicates / overwriting ids while the fix runs.

Steps (each re-reads prod; output in `run/prod/<timestamp>/`, git-ignored because it holds e-mail addresses):
1. `python3 run_datafix.py plan` – exports + plans. Today: **3,476 duplicate groups merge automatically (3,503 contacts)**:
   same account + email + name, at most one real platform id per platform. Master = the contact with a real platform id,
   then the most roles, then the oldest. **2,373 groups → `merge_review.csv`** (1,181 two real platform ids = two platform
   users, 1,005 different names, 187 both) – not touched.
2. `python3 run_datafix.py merge` – per group (chunks of 20, anonymous Apex `merge/merge_template.apex`): re-read, master gets
   the union of the roles and – when it has none – the loser's real platform id + administrator / visible checkboxes, then
   `Database.merge`. Group fails → rolled back, logged, next group; stops after 50 failures. Merged contacts sit in the
   Recycle Bin for 15 days (an undelete does not move children back).
3. `python3 run_datafix.py ids` – real platform ids from the request logs (kept since 2026-10-06): 18 relations today.
   The other ~21,800 synthetic ids are only known to the platform; with the fix live they repair themselves on the next
   platform call that carries the contact as a contactDTO.
4. `python3 run_datafix.py roles` – variant A backfill, recomputed after the merges (~71,500 relations), bulk update
   (comma / LF), backup CSV first.
5. `python3 run_datafix.py recount`.

Rehearsal in acc (`DATAFIX_ORG=acc`, 2026-10-15): plan 13 groups + 1 review → merge 13/13 OK → ids 0 → roles 1,791/1,791
(a second run: 0 left) → no RolesSync errors → 1 duplicate group left (the review one). It caught two CSV problems that would
have failed in prod: CRLF line endings and the locale's column delimiter – both fixed in the script.

## Earlier preparation (kept for reference)

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
