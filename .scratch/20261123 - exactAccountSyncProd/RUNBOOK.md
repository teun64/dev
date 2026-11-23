# Exact account sync redesign: prod go-live (commit 5b9b540)

Status 2026-11-23: dev + acc deployed and tested; acc end-to-end Exact check PASSED 2026-11-23 on test division 10006632 (first sync: MainContact = Invoice-role contact, Visit address on that contact, delivery address on the Main-role contact; after role swap + second sync: MainContact moved, Visit address same id re-linked, old contact '(DO NOT USE)', address and Country kept). Acc helper class ZZMk deleted; acc test account 001G500001WuD1UIAV cannot be deleted (association error), harmless. Prod NOT deployed. Deploy only on explicit command.

## What goes live
- `Util_FinancialSystemAccount` + `Test_Util_FinancialSystemAccount` only (package/). No schema, flow or permission changes: `FinancialIdVisitingAddress__c` and `FinSysAccountManagerDefault__c` + `Util_FinancialSystem` already exist in prod.
- Behaviour: account sent without address (POST of a new account still sends the establishment address once, PUT never); Invoice-role contact = Exact MainContact (fallback `Contact_Billing__c`, then `Contact_person__c`); Visit (1) / Invoice (3) / Delivery (4) address per role contact, never deleted; Main-role contact suffix " (m)" instead of " (i)".

## Impact (read-only prod export 2026-11-20, 157,533 synced accounts)
78 accounts change Exact MainContact; 7,695 Invoice-role contact differs from Main-role; 1,530 have no Invoice role (fallback); 7,177 shipping contact differs from main (get a delivery address on next sync); every account does one Visit GET+PUT on its next sync (gradual).

## Before deploy
1. (Done) Acc end-to-end Exact check.
2. User confirms: fallback order, Visit address contact = invoice (main) contact, Main-role contact still synced as normal contact.
3. Explicit user command to deploy prod.

## Deploy
sf CLI skips dot folders (.scratch): first copy `package/` to a non-dot folder, e.g. `cp -R ".scratch/20261123 - exactAccountSyncProd/package" tmp_prod_pkg`, then:
```
sf project deploy start -o prod -d tmp_prod_pkg --dry-run --test-level RunSpecifiedTests --tests Test_Util_FinancialSystemAccount --tests Test_Util_FinancialSystem
```
Real deploy = same without `--dry-run`, only on explicit command. Remove tmp_prod_pkg afterwards.
(Util_FinancialSystem alone is <75% coverage, so keep Test_Util_FinancialSystem in the list.) Run a validate-only first (`--dry-run`).

## After deploy
- Watch the sync log/Logger for the first batch runs; spot-check Jos van Laarhoven (001AO000002ptGfYAI): MainContact, Visit address contact, leftover delivery address 433442b2 should heal on first sync.
- Remove the "production pending" notes from the User & Key-User and Developer/System manuals (Claude Docs) and from memory `project_exact_account_sync_redesign_2026_11`.
