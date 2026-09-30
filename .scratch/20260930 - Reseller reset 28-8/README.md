# Reseller reset to 1 on 2026-08-28 — investigation & fix

Status 2026-09-30: **fixed in prod** — 1,352 accounts, 0 failures, verified (reseller restored, country in Billing/Visiting/Shipping/Invoice, no Exact sync flag). Run log: `run_prod_20260930_205048.csv`.

## Activity of the fixed accounts (`affected_accounts_activity.csv`)
None has an active contract or contract product.
| Category | Reseller 5 | Reseller 6 | Reseller 3 | With debtor no. |
|---|---|---|---|---|
| Nothing active | 821 | 263 | 8 | 103 |
| Open opportunity (stale: close dates mostly 2022–2025) | 82 | 64 | – | 11 |
| Closed Won, but no contract at all (latest 2026-03) | 96 | 16 | 2 | 104 |

**2026-09-30 deactivated in prod** (`scripts/deactivate_inactive.py`): 1,238 accounts ("nothing active" 1,092 + "open opportunity" 146) active → deactivated, 0 failures; StatusPrevious/StatusChangedOn set by rbb_Account, no Exact sync flag. The 114 "Closed Won, no contract" accounts stay active for investigation. Before-snapshot: `deactivate_before_prod_*.csv`, run log: `deactivate_run_prod_*.csv`.

## Field default on Reseller_Name__c (the real source of "reseller 1" on insert)
`Reseller_Name__c` has default `BLANKVALUE($User.DefaultReseller__c,'1')`, so a new account already has a reseller before rbb_Account runs and the flow's "reseller blank" branch never fires. For platform 1–3 accounts (no recalculation allowed) the user's default / '1' stuck.
**[dev + acc + prod DONE 2026-09-30]** default removed; rbb_Account now derives it (acc: rbb_Account v62). acc's field uses global value set `Reseller` (dev/prod: `BusinessEnitites`) → acc deployed from `packages/acc_prevention` (mdapi), repo file untouched. Verified (rolled back): MI/EuropeTrack → NL/1, Trackpilot → DE/5, Chiron/Nexus → GB/6, Echoes → FR/4, API-supplied reseller kept, nothing → country empty / reseller 1.

## What happened
- 2026-08-28 08:17–10:20 UTC: one-off `Btch_SetAccountPrimaryBrand` updated `PrimaryBrand__c` on ~181K prod accounts (running user Teun Rietman).
- Every update fired `rbb_Account` (prod **v61**, active until 2026-09-29):
  1. `ass_01_Visiting_Country` filled a blank Visiting country with `fVisitingCountryCode` → falls back to the running user's `DefaultCountryCode__c` (**NL**); Billing/Shipping copied from Visiting.
  2. That country change + `fAllowResellerChange` (no extId_1..3) → `ass_02_FinancialEntity` → `CASE(NL)` = **'1'**.
- Hit: every account with **no address at all** and no platform ids → **1,353 accounts** (AccountHistory, all by Teun Rietman):
  5→1: 1,000 · 6→1: 343 · 3→1: 10
- The 2026-09-29 pre-migration backup confirms: all 1,352 already had NL in Billing/Visiting/Shipping with no city.
- Echoes GmbH (5→1) was set back to 5 by Dennis Lorenz on 2026-09-01 12:49 — skipped.

## Was anything sent to the wrong Exact environment? — No evidence of it
| Path | Check | Result |
|---|---|---|
| Account → Exact (debtor) | new `Subscription25__Debtor_Number__c` since 28-8; `FinancialDebtorNumber__c` history; 29-9 sync-flag snapshot | none / none / 0 of these accounts |
| Order → Exact (admin chosen by `Account.Reseller_Name__c`) | orders since 28-8 | only Echoes GmbH (32 orders, from 09-01 12:51, **after** the fix); Exact order nos 29588–30751 = DE range (NL = 906xxx, UK = 217xxx–222xxx) |
| Invoices / Payments | created since 28-8 | none |
| Stripe (reseller change clears PayProv ids / queues delete) | PayProv_* on these accounts | none had a Stripe customer |
| Reseller 3 (BE) | `Util_System.getAdminExternalId(3)` = 1 | Exact admin unchanged (NL) anyway |

Caveat: prod Event_Log__c keeps 8 days, so failed sync attempts between 28-8 and ~22-9 can't be seen; nothing was created in Exact (no debtor records).

## Fix (`scripts/fix_reseller_country.py`)
Target country per account (`affected_accounts.csv`, column Country_Source): contact mailing country → phone prefix → VAT prefix → reseller default (6→GB, 5→DE, 3→BE), only values valid for the old reseller.
Result: DE 974 · GB 343 · AT 15 · CH 10 · BE 10.
- Pass 1: Billing/Visiting/Shipping/Invoice country → v63 derives reseller (DE/AT/CH→5, GB/IE→6).
- Pass 2: reseller explicitly where it differs (BE → flow gives 1, restore 3).
- Chunks of 5 (WSONE_DATA CPU). No Exact sync expected: v63's BillingAddress IsChanged isn't detected, and Util_Exact blocks accounts without an establishment address.
- Order: pilot on King Site Services, Dream Homes Developments Ltd, Woodlands Contracting → verify → rest.

## Prevention

Tests 2026-09-30: platform cases + 28-8 scenario in dev and acc (rolled back); REBEL Lease regression 4 calls in dev OK (roles, billing contact, reseller 1 stable); UK API account reseller 6 kept; dev RunLocalTests 420/458, none of the 38 failures related (integration user, MI connection config, LocalSetting__mdt fields, financial-sync WIP, pre-existing Stripe-id clear on insert in Test_Ctrl_HubPayment).
Still in prod v63 / dev: `ass_01_Billing_Country` runs on **every** save and fills a blank Billing country with the running user's `DefaultCountryCode__c`; that counts as a change, so `fFinancialEntity` recalculates the reseller, falling back to `DefaultReseller__c` or '1'. The running user's profile silently decides a customer's Exact administration.

1. **[dev (v72) + acc (v62) + prod (v64) DONE 2026-09-30]** `fBillingCountryCode` no longer falls back to the user's default country. An empty Billing country is derived from the platform ids: extId_1 (MI) / extId_5 (EuropeTrack) = NL, extId_2 (Trackpilot) = DE, extId_3 (Chiron) / extId_4 (AMI) = GB, extId_6 (Echoes) = FR, otherwise it stays **empty**.
2. **[dev DONE, same version]** `fFinancialEntity`: a blank or unmapped country keeps the current reseller; `DefaultReseller__c` / '1' only when the account has no reseller at all.
   Verified in dev (rolled back): 28-8 scenario (reseller 6, no country, unrelated update) → country stays empty, reseller stays 6; country → DE gives 5; country → US keeps 5; new accounts get the country from their platform id.
   Pre-existing, not changed: on insert with extId_2/extId_3 the reseller stays 1 even with a country (the platform API sends the reseller itself).
3. **Guard the Exact administration** — validation rule: `ISCHANGED(Reseller_Name__c) && NOT(ISBLANK(FinancialDebtorNumber__c)) && NOT($Permission.Change_Reseller)`. A reseller change on an account that exists in Exact moves it to another administration; it must be deliberate. Automation hits the rule too, so a batch fails loudly instead of changing silently.
4. **Mass updates** (one-off batches, data loads):
   - run first in acc on ~200 records and diff *all* fields before/after (not just the target field);
   - after the prod run, check AccountHistory for fields other than the target (`GROUP BY Field` for the run window);
   - optional: a `Bypass_Account_Derivations` custom permission that rbb_Account checks at the start, assigned only for the duration of a technical batch.
5. **Monitoring**: a report subscription / scheduled check on AccountHistory `Reseller_Name__c` changes per day (alert above e.g. 20).

## Prod deploy 2026-09-30
- Package `packages/prod_prevention` = prod v63 (`20260929 .../P2_prod_logic`, verified identical) + only the two formulas; the repo flow also carries the platform-status clear and the new Exact sync rule, which are NOT in prod yet (go-live runbook items 1 and 13).
- Validated with RunSpecifiedTests (Test_Btch_SetAccountPrimaryBrand, Test_Rest_UpsertAccount) 19/19, quick-deployed, rbb_Account v64 activated by hand; Reseller_Name__c default removed. Active v64 verified identical to the package.
- Functional test in prod (`scripts/test_prevention.apex`, everything rolled back) NOT run: blocked by the permission classifier. Same script passed in dev; dev/acc logs show the rolled-back inserts never start the async Exact sync.
