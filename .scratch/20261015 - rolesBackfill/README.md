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

## Prod runs 2026-10-15 (user: go, staged)
Plan `run/prod/20261015-140106` (fresh: 3,476 groups / 3,503 contacts auto, 2,373 review). Script now supports `merge N` / `roles N`
(random sample, before/after snapshot, `check.csv`, `datafix.log`, error-log scan per round); full runs without N skip handled groups.
- **Merge test round 1** (`merge_round_140210_10`): 10/10 OK, 0 Event_Log errors. Losers merged into master, roles unioned, real platform
  ids kept, account lookups repointed to the master, preferences deduped (30 → 15).
- **Replay test** (user's changed plan, `replay_test.py`, `replay_test_140621`): 10 random accounts whose last platform call was before
  the 09:15 UTC fix and none after, nothing changed since that call (guard), a lookup-implied role missing on a relation in the payload.
  Repaired (10/10, mostly Shipping) → replayed the logged body to /UpsertAccount → **repaired roles kept on 10/10**, 0 errors, no other
  relation/account field changes, no new relations, no Exact sync. The replay also added Reminder + Payment (new platformRoles rules) and
  filled `Subscription25__Reminder_Contact__c` on 9 accounts (was empty) – the platform does the same on each account's next call.
- **Round 2** (user: another 10, merge and roles): merge `merge_round_140858_10` 10/10 OK, 0 errors (same checks as round 1, all fine);
  roles `roles_round_140921_10` bulk job `750Tx00000fcgppIAA` 10/10, 0 errors, all as expected (10 relations without roles →
  Main;Invoice;Shipping). Remaining after this round: 3,456 merge groups, ~71,471 relations.
- **Full run (user: go)** – merge: 3,456 groups. First attempt with 20 groups per transaction hit "Too many SOQL queries: 101" (whole
  chunks rolled back, verified 0 contacts deleted) → 5 per transaction + per-group retry. 33 groups failed on DUPLICATE_VALUE
  extId_N__c: the loser's real platform id still collided after clearing it on the loser first → template reordered (merge first,
  which deletes the loser's relation, then the master takes the id; `merge/merge_template.before_reorder.apex` = old version) → the 33
  retried OK (`merge_round_151936_failed`), rest 936/936 OK. **All 3,476 groups merged** (incl. the 20 test-round groups).
- ids: 14 restored, 3 failed (DUPLICATE_VALUE: the platform already re-created those relations with the real id – nothing to do).
- roles: bulk job `750Tx00000fcurCIAQ`: 71,153 processed, **71,152 OK, 1 failed** (07kbR00000aQB81QAG – DUPLICATE_VALUE extId_1__c vs
  07k3W000005RhtuQAC: a pre-existing duplicate platform id on two relations; review). The script logged "bulk job None" because the CLI
  returns a non-zero exit when ≥1 record fails – results fetched with `sf data bulk results`, saved in the round folder.
- recount: accounts + email with ≥2 contacts 2,373 (= exactly the review groups in merge_review.csv); synthetic platform ids left:
  p1 14,709 · p2 811 · p3 1 heal on the next platform call with the contactDTO; p5 4,810 are expected – platform 5 ids are more or less synthetic by nature (user 2026-10-15), not a backlog.
- Event_Log errors during the merge window: 4, all normal legacy sync2Exact traffic (bank account / "Niet gekoppeld: Contactpersoon"),
  not from the data fix.

## Follow-up 2026-10-15 (user) – `run/prod/20261015-140106/followup_162316`
- 07kbR00000aQB81QAG (the 1 failed role row): gone – the user merged duplicate account "Jan Willem  Koppers" (001bR00000RLlhLQAT) into
  Jan-Willem Koppers 0013W000009gIkvQAE at 14:17 UTC; nothing to do.
- Contacts without email where an account lookup implies an email role: 3,933 role cases / 2,245 relations / 2,240 accounts; 3,782 have
  no same-name contact on the account, **131 have a same-name contact WITH email** (likely duplicates), 20 a same-name one without
  email → `noemail_lookup_contacts.csv`. Not changed.
- Duplicate roles (role on 2+ relations of one account, from before the 09:15 role trigger): 15 cases; user rule "lookup decides,
  remove from the other" → 14 role removals on 10 relations (`duplicate_roles_backup.csv`, results 10/10 OK). 1 review case: Manig &
  Palme Invoice (holders Ina Doering + Abteilung Buchhaltung, billing lookup Markus Laessig).
- **Side effect (not foreseen):** Svc_AccountContactRelationRoles treats a changed relation that still holds a role as its owner and
  points the lookup at it. 5 lookups moved to the role holder (Heuvelman Shipping, ENKA Shipping, Ralf Heuel Shipping – all three
  were already "role on one relation, lookup on another" – and Manig & Palme Invoice + Shipping → Ina Doering, Reminder None → Ina;
  Abteilung Buchhaltung lost Invoice there). Prod has 161 such single-holder conflicts in total (Main 54, Invoice 69, Shipping 38).
  Awaiting the user's decision on restoring.
- **Restore (user: follow the proposal):** roles given back to the old lookup contact on Heuvelman / ENKA / Ralf Heuel (Shipping) and Manig &
  Palme (Invoice + Shipping → Markus Laessig), Reminder lookup Manig & Palme cleared again; all lookups back to their pre-change values,
  verified (`restore_plan.json`, `restore_results.txt`).
- **No-email duplicates (user rule: merge only when no platform has two different ids; master takes over all ids, also synthetic):**
  `merge/merge_template_v2.apex`, run `run/prod/20261015-165241-dupnoemail`: 110 groups (97 from the 131 "same name with email" set – master = the contact with
  email – and 13 from the 20 "same name without email" set), **110/110 merged**, 129 contacts. 22 groups not merged (platform ids differ):
  `run/prod/20261015-140106/followup_162316/dupnoemail_not_merged.csv`.
- **The 3,782 "no duplicate" role cases = 2,112 contacts** (`noemail_contacts_2112.csv`): no email at all, so no mail domain to check.
  1,213 have no roles (the role rule strips email roles from contacts without email), 899 have roles. Of the 1,213: **1,120 are the
  only contact of their account** (mostly active: UK B2C 579, NL B2B 342, UK B2B 131, NL B2C 52); account Main and/or Invoice lookup
  points to them; 622 have a phone number; relation direct (1,212); 28 have cases, 13 opportunities. **Not deleted** – deleting would
  leave those accounts without any contact / main / billing contact. Awaiting the user's decision.
- **Lookup conflicts (role on one relation, lookup on another) now 157** (`lookup_conflicts_161.csv`): Main 54 / Invoice 69 / Shipping 34;
  by account platform: p1 125, none 17, p1+p5 8, p5 3, p2 2, p3 2. Lookup contact has an email in 151 of 157. Not changed.
- **User instructions on the 2,112 (2026-10-15), plan `plan_2112.json`:**
  1. Deactivate (active account, no active contract, Subscription_Last_Termindation_Date__c ≥ 90 days ago): **76 accounts → Status__c
     'deactivated', 76/76 OK** (`deactivate_76_results.txt` holds the previous status). Not covered by the rule: 1,759 accounts with no
     contract at all, 11 terminated < 90 days ago, 18 with contracts but no termination date. rau_Account_Status_Sync_to_Platforms is
     inactive in prod (no platform push); rbb_Account only stamps StatusPrevious__c / StatusChangedOn__c.
  2. No roles + only contact (1,120): digital invoicing already off on all; adding Main is impossible – Svc_AccountContactRelationRoles
     strips Main/Invoice/Digital/Reminder/Payment from a contact without email. Needs a decision (rule change or not).
  3. No roles + other contacts (93): delete – 89 are the account's Main lookup; 68 accounts have another contact with email, 25 do not.
     Delete is restricted while Case.ContactId, Order Bill/ShipTo, Contract CustomerSigned, Sub25 Billing attendant / Reminder / UBL
     point to the contact. Not run yet (who becomes main).
  4. With roles + only contact (776): UK 542, NL 184, DE 49, BE 1.
  5. With roles + other contacts (123): none holds Invoice or Digital – nothing to move.
- **PARKED (user 2026-10-15, to continue the financial go-live):** rule change "Main allowed without email" (Svc_AccountContactRelationRoles,
  commit see git log "Roles: Main allowed without an email address") deployed dev `0Afbd00000BgT2TCAV` + acc `0AfG500000T1nikKAB` (78/78),
  NOT prod. Still open: prod deploy + Main role on the 1,120 only contacts; the 93 deletes (who becomes main, 25 without an email
  contact); the 1,759 never-contracted active accounts; the 157 lookup conflicts; the 22 not-merged no-email groups.
  Not needed for the financial go-live: the sync uses the account lookups (Contact_person__c / Billing / Shipping), not the roles.
