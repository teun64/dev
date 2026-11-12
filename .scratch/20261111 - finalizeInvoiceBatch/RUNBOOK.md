# Finalize invoices in the financial system – own credential per Business Entity

Started 2026-11-11. Status: **Phase A BUILT + DEPLOYED to dev 2026-11-11** (53/53 tests). acc/prod not yet. Decisions 1-4 approved (all as recommended).

## Goal
Replace the Subscription25 package job `Job_FinalizeInvoicesInExact` (and the in-repo predecessor `Batch_FinalizeInvoicesLimited`)
with a batch that finalises invoices through its **own Named Credential, stored on the Business Entity**, so its API limit is
separate from the other syncs. In the end there are three separate sync situations to the financial system (Exact):

| # | Sync | Named Credential from | Limit state on |
|---|------|-----------------------|----------------|
| 1 | Custom Apex sync: account, contact, order (`Util_FinancialSystem*`) | Business Entity (`FinSysNamedCredentialSync__c`), fallback Administration | Business Entity (phase B) |
| 2 | Subscription25 package (contracts, orders, invoices) | Administration (`Subscription25__Named_Credential__c`) – untouched, will be pointed back later by config only | Administration (as now) |
| 3 | **Finalize invoices (new)** | Business Entity (`FinSysNamedCredentialFinalize__c`) – no fallback | Business Entity |

## What exists today (checked in the repo)
- `Job_FinalizeInvoicesInExact` is **managed-package code**, not in the repo: cannot be changed, only switched off (Subscription25__Schedulable_Class__c) once every entity is moved.
- `Batch_FinalizeInvoicesLimited` (+ `Batch_FinalizeInvoices`): per reseller, LIMIT 30, batch size 1, 5-minute schedule, calls `Util_Exact.finalizeInvoice` / `loadInvoiceNumber` (legacy, no rate limit awareness). Prod = repo, left untouched until cutover.
- `Util_FinancialSystem_Invoice.finalizeInvoice(Id)` / `loadInvoiceNumber(Id)` already hold the rebuilt logic (GET invoice by order number → PrintedSalesInvoices → GET number again; log + FinSys ids). Not used by a batch yet. 3 Exact calls per invoice.
- `Util_FinancialSystem.doRequest` takes the credential from `admin.Subscription25__Named_Credential__c`; `Limits` (daily limit/remaining/reset, minutely headers, `hasBatchCapacity(n)` = minutely reserve 5 + max % of daily limit) is stored on the **Administration**.
- Dispatcher: `Util_JobDispatcher` + `JobDispatcherStep__mdt` (Dispatchers Minut / Hour / Day). `Batch_JobDispatcher.scheduleHourly()` exists (minute 23) but there are **no Hour steps yet** – first step is to verify whether the Hour dispatcher is scheduled in dev/acc/prod.
- Business Entity ↔ Administration are joined by value: `Business_Entities__c.Reseller__c = Subscription25__Administration__c.Reseller__c` (no lookup, by design).

## Design

### 1. Credential resolver (the only place that decides which credential a call uses)
`Util_FinancialSystem.Purpose { SYNC, FINALIZE }` and `Util_FinancialSystem.namedCredential(admin, purpose)`:
- FINALIZE: `Business_Entities__c.FinSysNamedCredentialFinalize__c`; blank → `null` → the administration is **not eligible** (never silently falls back onto the shared credential/limit).
- SYNC: `FinSysNamedCredentialSync__c`, blank → administration's credential (so deploying changes nothing until a value is filled).
- `doRequest(admin, purpose, ...)` overload; the old signature = SYNC. `Limits(admin, purpose)` reads/stores the limit state on the Business Entity for that purpose (FINALIZE now; SYNC in phase B). Sandbox guard, production-division backstop and `isFinancialSyncAllowed` stay per administration, unchanged.
- `saveLogs` / `Util_OAuth.saveToken` already work per named credential name.

### 2. New fields (Business_Entities__c)
- `FinSysNamedCredentialFinalize__c` (Text 80), `FinSysNamedCredentialSync__c` (Text 80, phase B).
- Limit state for FINALIZE: `FinalizeDailyLimit__c`, `FinalizeRateLimitMaxPercentage__c`, `FinalizeRateLimitRemaining__c`, `FinalizeRateLimitResetOn__c`, `FinalizeRateLimitCheckedOn__c` (same meaning as the Administration fields). SYNC equivalents in phase B.
- On Subscription25__Invoice__c (back-off, so one failing invoice cannot block the head of the queue): `FinSysFinalizeAttempts__c`, `FinSysFinalizeNextAttempt__c`; reuse `Util_FinancialSystem.nextAttempt()` (15 min doubling, parked a week after 8).
- FLS: Admin profile + the existing financial-sync permission sets (`ps/cp_miSyncFinancialSystem`) – new fields have zero FLS by default.

### 3. Batches (all `Subscription25.Job_AbstractBatch2` + `Util_JobDispatcher.Step`, like the other steps)
- **`Batch_FinancialSystemFinalizeInvoices`** – the one generic batch the dispatcher calls (new step `Hour_FinancialSystemFinalizeInvoices`, Dispatcher = Hour). It does no callouts. In `startBatch` it lists Business Entities with a Finalize credential; it then checks per entity/administration **whether there is anything to do**: sync enabled, invoices with `Invoice_Number__c = null AND Exact_Order_Number__c != null AND (FinSysFinalizeNextAttempt__c is due)` for that administration, and `Limits.hasBatchCapacity(3)`. Administrations with nothing to do (or no capacity) start nothing. `finishBatch` starts the first per-administration batch and passes the remaining administrations along.
- **`Batch_FinancialSystemFinalizeInvoicesAdmin`** (one instance per administration, constructor takes the administration + the queue of the others + dispatcher name) – scope = invoices of that administration (query bound to that one administration), batch size small (5). Per invoice: `hasBatchCapacity(3)` against that entity's finalize credential limits → `finalizeInvoice` (or `loadInvoiceNumber` when `Finalized_In_Exact__c`) with the FINALIZE purpose; on a failure back-off fields are set; on a 429/no capacity the rest of the scope is skipped untouched. Callouts first, DML after (limits + logs saved once per execute).
  `finishBatch`: (a) minutely limit hit but work and daily share left → continue after the reset (see decision 2); (b) otherwise start the next administration's batch from the queue; (c) queue empty → `Util_JobDispatcher.startNext(dispatcher, 'Batch_FinancialSystemFinalizeInvoices')`.
- Instances run one after the other (serial), never two for the same administration; a guard in the admin batch aborts when an open `AsyncApexJob` of the same class for that administration exists (a scheduled continuation is not visible in `AsyncApexJob` before it fires, so `Util_JobDispatcher.isRunning` alone is not enough).
- "Not more requests per minute than allowed": Exact answers `X-RateLimit-Minutely-Remaining/-Reset` on every response; `Limits.register` keeps them, `hasBatchCapacity` keeps `MINUTELY_RESERVE` (5) free for manual "sync now". Apex cannot sleep, so pacing = stop at the minutely limit and continue after the reset.
- Daily: stops at `FinalizeRateLimitMaxPercentage__c` (default 90 %) of the entity's finalize daily limit.
- Daily limit refresh: `Batch_FinancialSystemRateLimitCheck` (Day, order 20) also checks every finalize credential (GET current/Me) and stores the result on the Business Entity.

### 4. Cut-over per entity (no big bang)
An entity only moves when its `FinSysNamedCredentialFinalize__c` is filled; entities without it stay on the legacy path. Because `Util_FinancialSystem_Invoice.finalizeInvoice` first looks the invoice up by order number and skips printing when Exact already has a number, a short overlap with `Job_FinalizeInvoicesInExact` does not double-print. When all entities are moved: deactivate `Job_FinalizeInvoicesInExact` (package schedulable class) and abort the `Batch_FinalizeInvoicesLimited - …` schedules.

### 5. Tests
`Test_Batch_FinancialSystemFinalizeInvoices` (nothing to do → no admin batch; chain over 2 administrations; capacity/minutely stop; back-off; no credential → skipped), resolver tests in `Test_Util_FinancialSystem`, `Test_Util_FinancialSystem_Invoice` for the purpose parameter, `Test_Util_JobDispatcher` for the Hour step.

## Phases
- **A (this build)**: resolver + fields + the two batches + Hour step + rate-limit check extension, dev first, then acc. Prod only on explicit command.
- **B (next)**: account/contact/order sync move to `FinSysNamedCredentialSync__c` + their own limit state on the Business Entity.
- Sub25 (2): no code; the Administration credential is simply pointed back by config.

## Manual steps (user)
1. Create the Exact OAuth app + External/Named Credential for finalize per entity (UK first) in dev/acc/prod; give the batch user's permission set the External Credential principal access (otherwise: no access error at runtime).
2. Fill `FinSysNamedCredentialFinalize__c` per Business Entity (data, per org).
3. Verify the Hour dispatcher is scheduled (`Batch_JobDispatcher.scheduleHourly()`) in each org.

## Open decisions (recommendation first)
1. Limit state on Business Entity fields (own set per purpose) – recommended; alternative is a child credential object (more flexible, more build).
2. Continue within the hour after the minutely reset via `System.scheduleBatch(…, 1 min)` – recommended, otherwise ~15 invoices/hour only (the UK backlog is 3,700+ invoices, daily share 9,000 calls = ~3,000 invoices/day).
3. Phase A first, phase B as a separate deploy – recommended.
4. Back-off fields on the invoice (2 new fields) vs. reuse of `FinSysNextAttempt__c` (already used by the invoice-id lookup) – recommended: new fields.

## Build log (2026-11-11, dev)
- Names (40-char Apex limit): generic `Batch_FinancialSystemFinalizeInvoices` (Job_AbstractBatch2 + Step), per administration `Batch_FinancialSystemFinalizeAdmin` (plain Batchable, Stateful, batch size 1: 3 callouts + DML per invoice, no callout after DML; no Schedulable_Class record needed), test `Test_Batch_FinancialSystemFinalize`. Enum is `Util_FinancialSystem.CredentialPurpose` (a type named `Purpose` clashes with `purpose` variables - Apex is case-insensitive).
- Generic batch decides in finishBatch (start query = `SELECT Id FROM Organization`): enabled + own credential + no scheduled continuation + capacity + due invoices. Skips everything while an Admin batch is still open.
- Minutely pacing: the minutely window is carried in batch state; when blocked the Admin batch schedules itself after 1 min (`CronTrigger` name `Finalize invoices continuation - <adminId>`, max 60 rounds) and the dispatcher chain moves on (never waits).
- Fields: Business_Entities__c `FinSysNamedCredentialFinalize__c`, `FinSysNamedCredentialSync__c` (phase B, unused), `FinalizeDailyLimit__c`, `FinalizeRateLimitMaxPercentage__c`, `...Remaining__c`, `...ResetOn__c`, `...CheckedOn__c`; Invoice `FinSysFinalizeAttempts__c`, `FinSysFinalizeNextAttempt__c`.
- FLS dev: Admin profile (partial deploy from outside the repo: `.scratch/.../profile`, copy to scratchpad, sf skips dot folders), FieldPermissions DML for `miModifyAllData` (edit) + `ps_miSubscription25_User` (invoice fields, read) - NOT a permission set deploy. Repo copies of both sets also carry the entries.
- Dispatcher step `Hour_FinancialSystemFinalizeInvoices` (order 10, active). No-op until an entity has a finalize credential AND the Hour dispatcher is scheduled.
- RateLimitCheck (Day) now also checks the finalize credential (log context `RateLimitCheckFinalize`).

## Deploy to acc/prod - checklist
1. Fields + classes + CMDT step + Admin profile grants + FieldPermissions DML (as in dev).
2. acc/prod (Sub25 v2.66): create `Subscription25__Schedulable_Class__c` Name = Unique_Name = `Batch_FinancialSystemFinalizeInvoices` (else "List has no rows" and the chain stops).
3. Verify `Batch_JobDispatcher.scheduleHourly()` is scheduled; the prod `Test_Util_JobDispatcher.scheduleHourly...` test collides with a live schedule (see financialsystemdeploy RUNBOOK gotcha) - deploy with the patched test.
4. Create the Exact app + Named Credential, give the batch user's permission set the External Credential principal access, fill `FinSysNamedCredentialFinalize__c`.
5. Legacy overlap: finalizeInvoice skips printing when Exact already has a number.

## acc 2026-11-11 (DEPLOYED)
- Fields, classes, CMDT step, Admin profile grants, FieldPermissions DML: done; 40/40 tests (Test_Batch_FinancialSystemFinalize, Test_Util_FinancialSystem(_Invoice), Test_Batch_FinalizeInvoicesLimited, Test_Batch_FinancialSystemInvoiceIds).
- `Subscription25__Schedulable_Class__c` `Batch_FinancialSystemFinalizeInvoices` created, **Batch_Size__c = 1**.
- Finding: the Hour dispatcher was NOT scheduled anywhere (acc: Minut only; prod: Minut + Day; dev: none). Scheduled in acc with `Batch_JobDispatcher.scheduleHourly()` (minute 23). Manual Hour run: dispatcher -> Finalize step completed, 0 errors, nothing to do (no finalize credential yet).
- prod: needs scheduleHourly() + Schedulable_Class record (batch size 1) at deploy time. dev: scheduleHourly() not run yet.
- Open: user fills FinSysNamedCredentialFinalize__c in dev/acc/prod.

## Phase B (2026-11-11, dev + acc DEPLOYED, 160/160 tests)
- Field names (user decision): `Business_Entities__c.FinSys_TM__c` = Tailor Made sync credential (account, contact, order, Stripe posting, Odoo); `FinSys_FI__c` = Finalize Invoice credential. Replaced the first-draft `FinSysNamedCredentialSync/Finalize__c` (deleted in dev + acc by destructive deploy).
- `Util_FinancialSystem.namedCredential(admin, SYNC)`: TM credential, else the administration's. FINALIZE: FI only. All saveLogs/OAuth-log credential lookups go through the resolver.
- Limit state: with TM filled the sync state moves to the entity (`SyncDailyLimit__c`, `SyncRateLimitMaxPercentage__c`, `...Remaining__c`, `...ResetOn__c`, `...CheckedOn__c`), else it stays on the administration (blank TM = unchanged behaviour). Finalize: `Finalize*` fields. One entity holds both states. Daily RateLimitCheck covers both credentials.
- Gotcha: every Administration SOQL feeding doRequest/namedCredential must select `Reseller__c` (loud SObjectException otherwise). Field labels max 40 chars.
- Legacy `Util_Exact*` (Sub25-era path) still reads the administration credential - untouched.
- Not yet: prod; Hour dispatcher unscheduled in dev/prod; fill TM/FI per entity (user).

## Git (2026-11-12)
- Committed and pushed to `main` as `ad4195f` (31 files: classes, tests, Hour dispatcher step, Business Entity + invoice fields, `ps_miSubscription25_User` grants, this runbook).
- Deliberately NOT committed: `miModifyAllData.permissionset-meta.xml` (partial set, a deploy would replace the whole set; FLS goes via FieldPermissions DML), unrelated permission-set drafts (`ps_miOLDFinancialSystem`, `ps_miSyncFinancialSystem`, `cp_miSyncFinancialSystem`), and the scratch `profile/` helper folder.
- Gotcha: a first commit with pathspec `-- .` swept in unrelated tracked changes; it was soft-reset (never pushed) and redone with explicit files. Use explicit paths, never `.`.
- Still open: user fills `FinSys_FI__c` / `FinSys_TM__c` per entity (dev/acc/prod); schedule Hour dispatcher in dev + prod; prod deploy only on explicit command (incl. Schedulable_Class record for `Batch_FinancialSystemFinalizeInvoices`, batch size 1).

## dev 2026-11-12
- Hour dispatcher scheduled in dev with `Batch_JobDispatcher.scheduleHourly()` (`GoMeddo Subscription - Batch_JobDispatcher - Hour - 0 23 * * * ?`, WAITING). Hour dispatcher is now scheduled in dev + acc; prod still open.
- Eligibility confirmed (no code change): an administration is only picked when active, `Synchronisation = Exact` and `FinSys_FI__c` is filled on its Business Entity; empty `FinSys_FI__c` = skipped (no fallback to the shared credential). Same check in the Admin batch and the RateLimitCheck.

## Selection aligned with the user's finalized check (2026-11-12, dev + acc DEPLOYED, 29/29 tests)
- User's check: `Sync_State__c = 'COMPLETE' AND Finalized_In_Exact__c = false`. Counts before the change: prod 1154 (UK 1153, NL 1) vs 1149 picked by the old batch filter; acc 2804 vs 2789; dev 1 vs 1 (different invoices).
- `Batch_FinancialSystemFinalizeAdmin` (hasWork + start query) now: `Sync_State__c = 'COMPLETE' AND Exact_Order_Number__c != null AND (Finalized_In_Exact__c = false OR Invoice_Number__c = null)` (second part keeps the "load number" path for flag true / no number).
- Invoice that already has an invoice number (prod 5, acc 15): flag set to true, no Exact call.
- Not handled (prod 1, probably the NL one): COMPLETE, flag false, no Exact order number - nothing to look up; for the user to check.
- Dev findings during the UK test: Schedulable_Class records for `Batch_FinancialSystemFinalizeInvoices` (size 1) and `Batch_FinancialSystemRateLimitCheck` (size 10) were missing in dev (created); principal `np_FinSysFI_UK` was granted to no permission set (granted to `ps_miFinancialSystem` + `ps_miSyncFinancialSystem` in dev - check the same in acc/prod). TM + FI credentials both reach Exact UK in dev (limit 10000). No UK invoice in dev to finalize, real finalize run still untested.
- Test gotcha: the package sets `Sync_State__c` on insert; force 'COMPLETE' with an update afterwards. Invoice number gets a fixture prefix (TTT).

## UK end-to-end test in dev (2026-11-12) - PASSED
- Test invoice `I-2611-00443750` (a1Ubd000002pci1EAA, account "TEST Teun bacs UK", GBP 20) + linked Order `01271086` (administration UK, one line copied from order 801bd00000p4XG9AAM, activated). Left in dev as test data.
- Gotchas to build such an invoice: a header-only invoice cannot go FINALIZED. Flow `rbu_Subscription25_Invoice_c` reads the linked Order (`Order.Subscription25__Invoice__c`) for payment method/paid flag (else "Paid In Advance: value not of required type"); then needs an Order with the same administration, with at least one product, activated ("An invoice with 0 orders cannot become finalized"). After FINALIZED the package sets Sync_State SCHEDULED -> COMPLETE + Exact order number via `Job_Synchronisation`. That package job cannot be started from Apex (class not visible, Type.forName = null) and has no schedule in dev; it was triggered from the UI.
- Finalize batch run: found the invoice, looked up the sales invoice by order number, printed, loaded number -> `GB26700002`, `Finalized_In_Exact__c` = true, `FinSysInvoiceId__c` stored, back-off cleared. First attempt failed with `Invalid reference: Layout` (back-off set as designed).
- Cause of the layout error: `Payment_Setting__mdt.Exact_Invoice_Template__c` held production-division GUIDs; the dev/acc credential points at the UK test division. Fix (dev + acc only): all 12 UK rows (Reseller__c = '6') set to `22803ee5-dea8-45e3-ae64-0475651ca6c3` via `Metadata.Operations.enqueueDeployment` from Apex - repo files deliberately NOT changed (they hold the prod GUIDs; never deploy the test GUID to prod). Old values: `922a4ff1…` (08,14,30,60,I4,I8,pr), `2e5ddea3…` (C,p1,pi), `86e0f81e…` (I0), `aec4f695…` (cr).
- Setup fixes in dev found during the test: Schedulable_Class records for `Batch_FinancialSystemFinalizeInvoices` (1) and `Batch_FinancialSystemRateLimitCheck` (10) missing (created); principal `np_FinSysFI_UK` not granted to any permission set (granted to `ps_miFinancialSystem`, `ps_miSyncFinancialSystem`). Check both in acc/prod.
- Open: acc UK run not done (no UK invoice there), prod deploy only on explicit command.

## acc UK setup + end-to-end test (2026-11-12) - PASSED
- acc credentials mirrored from dev (all UK): auth providers `FinSysTM_UK` (consumer key = the old Exact_UK app) + `FinSysFI_UK` (key to fill), ECs/NCs `ec/nc_FinSysTM_UK`, `ec/nc_FinSysFI_UK`; named principals `np_FinSysTM_UK` / `np_FinSysFI_UK` (TM principal renamed from NamedPrincipalUK, also in dev - re-authenticate after a principal rename), granted to `ps_miFinancialSystem` + `ps_miSyncFinancialSystem` via SetupEntityAccess. Old `nc_FinancialSystemUK`, `ec_FinancialSystemUK`, `Exact_UK` removed from acc (metadata-format deploy `--metadata-dir` with destructiveChangesPost.xml; a source-format `--post-destructive-changes` deploy also deletes the local repo files and rolled back). UK Administration `Named_Credential__c` = `nc_FinSysTM_UK`; Business Entity UK `FinSys_TM__c`/`FinSys_FI__c` filled. Repo/prod still use the old names - do not deploy the repo permission sets to acc unchanged.
- Remote Site Settings acc = dev (added `Owndata_EMEA1_Archive`, `Self_Metadata_API`, `rsCMS_Content_Types` with the acc domain; Self_Metadata_API in repo points at dev).
- Test data acc: account "TEST Teun pr UK" (Market set to Fleet), invoice `I-2611-00566326` + Order `801G500001WEp6RIAT` (product iTrack S5 Monthly DD `UK.ITRACK.S5.01.D`, same as dev), first test invoice `I-2611-00566325` first failed in the package sync (its product `UK.ITRACK.S5P.01.D` does not exist in the UK test division -> "SalesInvoiceLine Not found: Item"), was parked as NOT_APPLICABLE, then synced to Exact by the user (order 7, COMPLETE) and finalized by the batch afterwards: `GB26700004`, `FinSysInvoiceId__c` 8412b1a5-24ed-411c-866a-7ba486aa957a.
- Gotchas found: (1) acc `Exact_Relation_Setting__c` UK rows carry prod-division GUIDs; the UK test division (119572) has one classification group "Relation Type" with only Dealer `1ea6d648-7438-4918-b0e3-4cbaf9ae5e6a` and End User `58f0ca97-cb6c-40d9-a19b-97f86ed35e5d`; C2/C3 do not exist, so account sync failed with "Invalid reference: Account classification". `Composite_Key__c` (admin-class-ExactID) is unique, so only one blank id per classification; account classification fields are formulas (Market/Relation type/Sales channel), Relation_type is restricted per record type. Fix: row `Fleet - End User` (a1gAO000000C2IYYA0) set to the End User GUID, test account Market = Fleet (C2 `Fleet` and C3 blank rows). Old values of the 8 rows: `.../scratchpad/acc_uk_relation_backup.csv` (session only; prod GUIDs are the ones in prod). (2) The package invoice sync (Job_Synchronisation, every 5 min in acc) only starts after Sync_State = RESCHEDULE; a fresh invoice stays PENDING; it needs the account in Exact first.
- Result: invoice COMPLETE (order 6) -> finalize batch -> `GB26700003`, `Finalized_In_Exact__c` true, `FinSysInvoiceId__c` a3ecc2b5-733d-499b-8945-a9a8c1b88002, 0 errors. Layout template = the test GUID set in acc earlier.

## PROD (2026-11-12) - LIVE
- Credentials in prod: ec/nc `FinSysFI_NL/DE/UK` created (TM NL/DE/UK existed), `rs_FinSysGM_NL/DE/UK` remote sites (old `Exact_Online_*` deleted). Principals `np_FinSysFI_*` granted on `ps_miFinancialSystem` + `ps_miSyncFinancialSystem` (by the user in Setup). Secrets entered by the user; all six NCs answer 200 on `current/Me`.
- Fields deployed: `Business_Entities__c` FinSys_TM__c, FinSys_FI__c, FinSysAccountManagerDefault__c (+ NL translation "Relatiebeheerder") and the 10 Sync*/Finalize* limit fields; `Subscription25__Invoice__c` FinSysFinalizeAttempts__c / NextAttempt__c. FLS: Admin profile (edit) + `ps_miSubscription25_User` (read, from prod's own copy). `miModifyAllData` skipped (assigned to nobody).
- Data: Business Entities NL/DE/UK `FinSys_TM__c = nc_FinSysTM_*`, `FinSys_FI__c = nc_FinSysFI_*`. Default account manager left EMPTY on purpose: an account sync therefore sends `AccountManager: null` (clears it in Exact).
- Apex deployed (148 specified tests): Util_FinancialSystem*, Batch_FinancialSystemRateLimitCheck, the two Finalize batches, `Test_Data` (prod copy was older: no named credential on the test administration -> 63 test failures in the first dry run), RunSpecifiedTests needs ~12 FinancialSystem test classes or Util_FinancialSystem_Invoice stays below 75% coverage. `NoTestRun` is refused in prod.
- Live test: NL `I-2611-00786803` -> NL26131320, UK `I-2611-00787180` (GBP) -> GB26760372 (finalize returned the number but left the flag off; set by hand like the batch does for numbered invoices - watch this).
- Switch-on: `Schedulable_Class` `Batch_FinancialSystemFinalizeInvoices` (size 1) created. First as Hour step; then moved: step `Minut_FinancialSystemFinalizeInvoices` (Minut dispatcher, order 70 = after the syncs and ProcessPayments), Hour step deleted in dev/acc/prod, Hour dispatcher schedule aborted in dev/acc/prod (it has no steps). Per-run cap in the Minut round: `Batch_FinancialSystemFinalizeAdmin.minutPerRun` = 50 invoices per administration; the minutely-limit continuation and the daily share still apply; the Minut chain never runs a second admin batch while one is open.
- Legacy `Job_FinalizeInvoicesInExact`: already off in prod (Schedulable__c false, no scheduled job). Cron string kept.
- Backlog at switch-on: UK 1175, NL 348, DE 7.
- Open: watch the first Minut rounds (Event_Log__c errors, `FinSysFinalizeAttempts__c`), the UK flag behaviour above; the credential metadata (auth providers, ec/nc, remote sites) is not in the repo yet.
