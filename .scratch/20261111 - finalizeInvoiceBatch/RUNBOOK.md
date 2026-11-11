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
