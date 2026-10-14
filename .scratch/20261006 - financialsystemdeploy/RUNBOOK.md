# Financial system deploy – acc and prod

Prepared 2026-10-06. **Status 2026-10-14:** dev complete and committed; acc complete (checked file by file against the repo 2026-10-14, see the last section); prod: only the Case – Administration queues + the dispatcher framework (Activate/Dedupe/Stripe steps) – the rebuild itself is NOT deployed.

| Org | State on 2026-10-06 |
|---|---|
| dev | Everything deployed and committed (`3f32641`, `6cbfdbc`, `3cc5dad`, not pushed). Tests: account 23+, order, removal, contact trigger, dispatcher – 65/65 + Test_Batches_FinancialSystem 2/2 |
| acc | Has steps 1-3, backstop, FLS, job dispatcher + Stripe reconcile step. **Missing today's work** (contact update, retire/restore, delete/merge, order line ids, step order 10-50) |
| prod | Has **none** of the rebuild. Only `Batch_ReconcileStripeEvents` (standalone, deployed 2026-10-06 by another session), old `Util_Exact` + `Inv_syncAccountToFinancialSystem` |

What today's work does (see commit `3f32641` for details):
- Contact update step (`Batch_FinancialSystemContactSync`): changed contacts are PUT to Exact without an account sync.
- Role removed / contact deleted / relation removed → Exact contact retired: last name + " (DO NOT USE)", email cleared, `IsMailingExcluded = true`, `EndDate = today`. Role back → restored.
- Contact merge → master takes over the loser's Exact contact + `extId_1..6__c` where its own are empty (roles only when it has none), or gets a new relation on the loser's account; otherwise the loser's Exact contact is retired.
- Invoice address falls back to the establishment address; invoice/shipping addresses are `Main` of their type and kept up to date.
- Order sync stores the Exact SalesOrderLine ids on `OrderItem.FinancialId__c`.
- Minut dispatcher order: 10 AccountSync, 20 ContactSync, 30 ActivateDraftContractProducts, 40 OrderSync, 50 ReconcileStripeEvents.
- Dispatcher steps need **no** `Subscription25__Schedulable_Class__c` record **in dev only** (Sub25 v2.67) – acc/prod (v2.66) DO need one, see the 2026-10-08 gotcha below.

---

## Org check 2026-10-07 (before any deploy)

Method: retrieved every file touched by the rebuild/dispatcher commits (`26378f4^..HEAD`) + the sync buttons from acc and prod into a scratch folder (not the repo), compared each file with HEAD and with every older git version. Nothing was deployed.

### acc – ready for manual testing?
**Not yet.**
- **Blocker: data storage -398 MB (5120 MB quota).** Saving contacts/orders/merges fails → free storage first.
- The 2026-10-06 delta (`acc/package.xml`) is **not** in acc: missing `Batch_FinancialSystemContactSync`, `Svc_FinancialSystemContactRemoval`, `AccountContactRelation` trigger + `Trigger_AccountContactRelation`, `Account.FinancialContactsToRetire__c`, CMDT `Minut_FinancialSystemContactSync`. `Util_FinancialSystemAccount`/`_Order` are on `505c1f8`, `Batch_FinancialSystemAccountSync` on `4a4e3e5`, `Trigger_Contact` on `825d05c`, `rbb_AccountContactRelation` v6 without `fSyncToFinancialSystem`. Minut order in acc is still 10/20/30/40 (Account/Activate/Order/Stripe).
- Everything else of steps 1-3 is in acc and equal to HEAD (apart from `packageVersions`/`30` vs `30.0` noise). Permission sets equal to the repo.
- Running: dispatcher 12× per hour (Account, Activate, Order, Stripe steps all complete); daily rate-limit check 07:30; NL administration = division 10006632, Daily_Limit 200000.
- Tests in acc 2026-10-07: 53/54 (Test_Controllers, Test_Inv_sync*, Test_Util_FinancialSystem*, Test_Exact). Only `Test_Exact.testAccountSync` fails (known, pre-existing).
- One-off `Batch_FinancialSystemOrderSync` failure 06:17 "List has no rows for assignment to SObject" during a manual dispatcher run; all runs since are clean. Code is replaced by the delta – if live check 6 hits it again, read the stack trace from the Apex log.
- **Field visibility while testing**: `pg_Subscription25Admin` is **session-activated** (`hasActivationRequired = true`, acc and prod). Without activation the new fields (`SyncToFinancialSystem__c`, `FinancialSyncState__c`, `FinancialSyncLastError__c`, …) are invisible (UI and API). Also test the buttons as a normal pg_Subscription25User / CCC user.
- acc-only variants (keep, do not overwrite from the repo): `Trigger_Account` = prod + `upsertDebtorNumbers`; `Trigger_Order` = prod + `queueAccountFinancialSync`.

### Prod – what the repo would override (decide before building the package)
| Component | Prod today | Repo HEAD | Use for prod |
|---|---|---|---|
| `Trigger_Account` | go-live P2 variant (09-29) | calls `updateVisitingAddressLabels` → `VisitingAddress_Country__c/_State__c` exist **only in dev** → won't compile | **acc's version** (prod + `upsertDebtorNumbers`) |
| `Trigger_Order` | `610c3cf` | contains the **dev-only Months_In_Advance invoice-date fix** (2026-08-06) + api 62→66 | **HEAD** (user 2026-10-07: fix goes along) |
| `afl_Account_Get_new_debtor_number` | v12 = P2_prod_logic (deletes `Subscription25__Debtor_Number__c` records, historical debtor numbers) | new model: clears Exact ids on Account/ACRs | intended model change (step 2b) – **confirm**; acc already runs the repo variant |
| `rbb_Account` | v66 | only 4 elements differ (`ass_01_Sync_2_Exact`, `dec_01_FinancialSystemSync`, `vEstablishmentAddressSet`, `vFinancialSystemReset`) + api 66→67; start identical | repo version is OK (simpler than assumed above) – still diff once more just before deploy |
| `rbb_AccountContactRelation` | v7 = `02b505d` | + `fSyncToFinancialSystem`, changed `ass_01_RolesStageUpdate` | repo version |
| `Svc_StripeEventProcessor` | `d85d977` | `af49bad` (Stripe reconcile, live webhook path) | **leave out** of this package |
| `Batch_UpdateContractProductPrice` + `Day_UpdateContractProductPrice` | not in prod | in candidate list | **not now** (user 2026-10-07) |
| CMDT `JobDispatcherStep.*` | financial steps `IsActive__c = false` | **all `IsActive__c = true`** | ship with **false** (true = syncing to production Exact within 5 min); OrderSync batch size 10 |
| `ps_miFinancialSystem_Admin` / `ps_miSubscription25_User` | no prod-only entries | + 13 new fields + `Include_CII_Hybrid_PDF__c` | strip `Include_CII_Hybrid_PDF__c` (EN16931 field, **does not exist in prod** → deploy fails) |
| `Test_Exact` | P2 variant (asserts `Exact_Invoice_Address_ID__c`, `syncOrderAsync`) | Account/ACR model | repo version (prod's breaks against the forwarders) |
| `Test_Util_JobDispatcher` | patched copy (no `scheduleEvery5Minutes` test) | full | keep prod's copy |
| `Ctrl_SyncWithExact` (2023), `Inv_syncAccountToFinancialSystem` (2025), `Util_OAuth`, `Util_System`, `Util_Rest`, `Batch_FinalizeInvoices(Limited)`, `Test_Data`, `Util_Exact`, `Inv_syncOrderToFinancialSystem` | older versions, **no prod-only changes** | repo = prod + rebuild changes only | repo version |

Also: `rac_`/`rau_Account_Sync_to_Financial_System` (prod v3/v7, active) fire on the old `FinancialSystemSync__c` flag that prod's `rbb_Account` sets, and call `Util_Exact.syncAccount`. Deploy Apex and the new `rbb_Account` in the **same** step (otherwise the new sync-now code runs from the old flag path); decide whether to deactivate these two flows after go-live.

### User decisions 2026-10-07
- acc delta deployed 2026-10-07 (deploy `0AfG500000Su9ZxKAJ`, 22/22, NoTestRun) incl. **`Trigger_Order` from HEAD** (invoice-date fix goes along, also to prod) and **`scr_Order_SyncToFinancialSystem` v3** (direct sync, see below). Flows active: `rbb_AccountContactRelation` v7, `scr_Order_SyncToFinancialSystem` v3. Minut 10/20/30/40/50 active. Tests: 89/90 (only `Test_Util_JobDispatcher.scheduleEvery5Minutes_creates12Schedules` – live schedule name collision, known) + `Test_Orders` 3/3.
- Prod `Trigger_Order`: use **HEAD** (with the invoice-date fix), not acc's old variant.
- `Batch_UpdateContractProductPrice` / `Day_UpdateContractProductPrice`: **not** in this prod package – goes later with the salesforceLead pricing + Rest_UpsertContract update.
- Buttons: **direct sync** for account and order. Order screen flow now calls `Inv_FinancialSystemOrder` with `syncNow = true` (existing code, no Apex change) → order created in Exact immediately, message shown on the result screen. The batch still picks up flagged orders. Prod: deploy this flow version with the rebuild.

### Gotcha found 2026-10-08: dispatcher steps DO need a Sub25 config record in acc/prod
`Batch_FinancialSystemContactSync` failed on every Minut run in acc after the delta (211×, "List has no rows for assignment to SObject" in start), and because a failed step never reaches `finishBatch`, the chain stopped there – Activate, OrderSync and Stripe did not run from 2026-10-07 12:40 until the fix. Cause: acc/prod run Subscription25 **v2.66**, whose `Job_AbstractBatch2` needs a `Subscription25__Schedulable_Class__c` record (Name + Unique_Name) per class; dev (v2.67) does not – so "dispatcher steps need no record" only holds in dev. Fixed in acc 2026-10-08 08:14 (record `a1YG5000004KtpFMAS`, batch size 25 = class default); the 08:15 chain ran fully.
**Prod**: before activating the steps, create records for `Batch_FinancialSystemAccountSync` (5), `Batch_FinancialSystemContactSync` (25), `Batch_FinancialSystemOrderSync` (10), `Batch_FinancialSystemRateLimitCheck` (10). Prod has only ActivateDraftContractProducts, Dedupe, DataRetentionCleanup, ReconcileStripeEvents, JobDispatcher.

### Manual sync buttons (identical in acc and prod)
- **Account "Send to Exact"** (`Account.Send_to_Exact` → Aura `SyncWithExact` → `Ctrl_SyncWithExact.doSync` → `Util_Exact.syncAccount` → `Util_FinancialSystemAccount.syncAccount`): still syncs **immediately** with the new code. Warnings/postpones are returned as messages → the Aura shows "Something went wrong in synchronisation: …" even when the sync succeeded with a warning (UX only).
- **Order "Sync to Exact"** (`Order.actSyncToFinancialSystem` → `scr_Order_SyncToFinancialSystem` → `Inv_syncOrderToFinancialSystem`): now only **marks** the order (`flagOrders`, SYSTEM_MODE); the Minut OrderSync step sends it within ~5 min and activates it (user decision 2026-10-01). **In prod the button does nothing useful until `Minut_FinancialSystemOrderSync` is active** (~500 orders/week by hand today) → deploy the invocable and activate the step together.
- `Test_Controllers` skips the real account sync under `Test.isRunningTest()` → add a real button click for both buttons to the live checks.

---

## acc

Package: `acc/package.xml` (delta only, 20 components).

Pre-checked 2026-10-06: the acc versions of every class/flow being replaced equal the versions today's changes were built on (no acc-only edits get overwritten). `Test_Batches_FinancialSystem` does not exist in acc yet (new). `OrderItem.FinancialId__c` already exists in acc.

### Pre-checks
1. **Data storage**: acc was over quota (-512MB) on 2026-10-06; saving records failed and the dispatcher runs failed. Check Setup → Storage Usage; free space first if still over (see `project_acc_data_storage_overage` memory for the purge approach).
2. `git status` clean for the files in the package (`sf project retrieve` would overwrite local edits – don't retrieve into the repo).
3. acc Exact = division 10006632 (`Subscription25__Twinfield_Company_Code__c` on the Netherlands administration). Backstop `FinancialSystemProductionDivision__mdt` (NL 1946773 / DE 67822 / UK 112143) is deployed in acc – keep it.

### Deploy
```bash
sf project deploy start -o acc -x ".scratch/20261006 - financialsystemdeploy/acc/package.xml" --test-level NoTestRun --wait 30
```
(RunLocalTests is blocked in acc by unrelated WIP tests – deploy with NoTestRun, then run the tests below.)

Check the flow afterwards: `rbb_AccountContactRelation` new version must be **active** (Tooling: `SELECT ActiveVersion.VersionNumber, LatestVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName = 'rbb_AccountContactRelation'`).

### Tests
```bash
sf apex run test -o acc -n Test_Util_FinancialSystemAccount -n Test_Util_FinancialSystem_Order -n Test_Svc_FinancialSystemContactRemoval -n Test_Trigger_Contact -n Test_Util_JobDispatcher -n Test_Batches_FinancialSystem -n Test_Util_FinancialSystem --result-format human --wait 30
```
Known: `Test_Exact.testAccountSync` failed in acc before today (not part of this list).

### Live checks in acc (Exact division 10006632)
Use your own test records, not Trekhaken B.V.
1. Contact change: change the last name of a contact whose ACR has `FinancialIdContact__c` → after the next Minut round the Exact contact has the new name, ACR flag cleared.
2. Role removed: clear all Roles on such an ACR (contact not the account's Main/Invoice/Shipping) → Exact contact "… (DO NOT USE)", email empty, end date today, excluded from mailings.
3. Role back: give it a role again → Exact contact restored (end date empty, email back).
4. Delete a test contact with an Exact contact → `Account.FinancialContactsToRetire__c` filled, account flagged; after the round the Exact contact is retired and the field is empty.
5. Merge two test contacts on the same account (master without Exact id) → master's ACR has the loser's Exact id; Exact contact shows the master's name after the round.
6. Order sync of a test order → `OrderItem.FinancialId__c` filled on every line.
7. Button "Send to Exact" on a test account → popup closes (success) or shows the message; account state/last error updated.
8. Button "Sync to Exact" on a test order → "queued" message; within ~5 min the order has an Exact id and is Activated.

Probe contacts left in acc Exact on account "test de tester" (12295621):
- "DoNotUse Probe" `750039cf-147a-4c79-be93-6905407651dd` – retired state, for inspection.
- "SF Anonymise Probe" `684257b8-f104-408b-965f-b6146e9b1cbf` – made inactive (end date 2026-10-05) for the **manual anonymise check** (CRM → Accounts → Overview → account → contact → Anonymise; only possible on inactive contacts). Open item for the user.

### Still open in acc (from earlier)
- The Sub25 config record for `Batch_JobDispatcher` could not be created (storage) – AccountSync's 12 schedules were already swapped for the dispatcher's 12 on 2026-10-06, so account sync is effectively off until storage is freed and the dispatcher runs.

---

## prod

**Do not run without an explicit go-ahead from the user, per step.** No test data in prod.

Prod needs the **whole** rebuild, not only today's delta. Candidate file list: `prod/candidate-files.txt` (113 files from the 13 financial-system commits). It is a starting point, **not** a ready package:

### Must be rebuilt from prod, not taken from the repo
| Component | Prod active version (2026-10-06) | How |
|---|---|---|
| `rbb_Account` | v66 | Retrieve prod v66, add only the step-2 changes (sets `SyncToFinancialSystem__c` + reset attempts/next attempt; extra triggers incl. Contact_person/Billing/Shipping and invoice/shipping address changes). Repo flow has platform-status changes that differ from prod. |
| `rbb_AccountContactRelation` | v7 (dev is v41) | Retrieve prod v7, add only formula `fSyncToFinancialSystem` + its assignment to `$Record.Sync_To_Financial_System__c` (see commit `3f32641`). |
| `afl_Account_Get_new_debtor_number` | check | Compare prod with the repo before including. |

Prod deploys flows as **Draft**: activate via Tooling PATCH on FlowDefinition (`Metadata.activeVersionNumber`).

### Also check before building the package
- No destructive changes needed: none of the classes removed during the rebuild exist in prod (checked 2026-10-06).
- Named/External Credentials (`nc_/ec_FinancialSystemNL/DE/UK`): aligned with prod in `4346511` – confirm, don't overwrite secrets.
- Permission sets `ps_miFinancialSystem_Admin` / `ps_miSubscription25_User`: build from prod + the new field entries (prod lacks `Contract_Product.Contractor_Service__c`? – compare). `Acceptance_Environment_Available__c` and `Daily_Limit__c` have no FLS in prod.
- New fields without FLS: `Account.FinancialContactsToRetire__c` (code runs in SYSTEM_MODE; add read FLS if users should see it).
- Prod Apex deploys need **RunSpecifiedTests** (NoTestRun is refused). `sf project deploy report --use-most-recent` can show another org's deploy – verify with a query.
- Scheduled Apex: prod at 67/100. The dispatcher uses 12 slots (every 5 min, hours 1-3,5-23).

### Order (proposal)
1. Fields + custom metadata (incl. `JobDispatcherStep__mdt` type + Minut records, `FinancialSystemProductionDivision__mdt`), credentials check.
2. Apex: `Util_FinancialSystem*`, batches, invocables, `Svc_FinancialSystemContactRemoval`, triggers (`Trigger_Account`, `Trigger_Order`, `Trigger_Contact`, `AccountContactRelation`), `Util_JobDispatcher`, `Batch_JobDispatcher`, `Util_Exact` (forwarders), tests – RunSpecifiedTests with the financial test classes.
3. Flows (rebuilt from prod, see above), then activate.
4. Permission sets (FLS).
5. Daily rate-limit job `Batch_FinancialSystemRateLimitCheck` (07:30).
6. Dispatcher already went live in prod 2026-10-07 for Activate Draft Contract Products, Dedupe Communication Preferences and Reconcile Stripe Events (see the status table below) – their legacy standalone crons are already gone. What's left here is only the 5 financial-system steps: once each class deploys, flip its CMDT `IsActive__c` to `true`, same pattern as the 3 already live.
7. Order sync is currently manual in prod (~500/week): agree with the user when the batch takes over.
8. Once `Minut_FinancialSystemAccountSync` is active and verified against real data: delete `Batch_SyncAccountEuropeTrack` from prod (already deleted from dev/acc 2026-10-07 – it was unscheduled there) and abort its one remaining daily CronTrigger (`0 0 6 * * ?`) – the new account sync covers any account regardless of source, making this EuropeTrack-only backstop fully redundant. Its schedule was already throttled from 12 slots/5 min down to this single daily run on 2026-10-07 as an interim step.

### After go-live
- Exact flag backlog (247 BAG-corrected + 5 restored accounts) – parked by the user 2026-10-01.
- ~~5 accounts permanently stuck by `Batch_SyncAccountEuropeTrack`'s silent-failure bug~~ – RESOLVED 2026-10-07: user removed the 5 accounts directly after investigating (`001bR000001pJD6QAM`, `001bR000000TrAbQAK`, `001bR000001CARGQA4`, `001bR00000RgruwQAB`, `001bR00000retgnQAA` – confirmed deleted from prod).

---

## Job dispatcher in prod – status as of 2026-10-07

The dispatcher framework (`Util_JobDispatcher`, `Batch_JobDispatcher`, `JobDispatcherStep__mdt`) is live in prod, running on the Minut (every 5 min, hours 1-3,5-23) and Day (00:13) schedules. State of each step:

| CMDT record | Class | Dispatcher/Order | Status |
|---|---|---|---|
| `Minut_ActivateDraftContractProducts` | `Batch_ActivateDraftContractProducts` | Minut / – | **Active**. Verified against real data 2026-10-07 (a Draft Contract Product on an Account with a debtor number flipped to Activated; one without a debtor number stayed Draft; 0 errors). Legacy standalone CronTrigger (`0 X * * * ?`, all 24h) aborted. |
| `Day_DedupeCommunicationPreferences` | `Batch_DedupeCommunicationPreferences` | Day / 30 | **Active**. Already ran daily for real in prod via its own native Subscription25 schedule since before this rollout (0 duplicates found in a 2026-10-07 dry-run – evidence it's keeping things clean, not that it's unneeded). Legacy `0 30 6 * * ?` standalone cron aborted; next real run via the dispatcher is tonight at 00:13. |
| `Minut_ReconcileStripeEvents` | `Batch_ReconcileStripeEvents` | Minut / 50 | **Active**. Backfills `Account.PayProv_MandateId__c`/payment method from any Stripe event, covering the gap while a failed trigger-time webhook keeps retrying. Had no standalone legacy cron to kill. |
| `Minut_FinancialSystemAccountSync` | `Batch_FinancialSystemAccountSync` | Minut / – | **Inactive** – class not deployed to prod yet (part of the financial system rebuild, see the acc/prod sections above). |
| `Minut_FinancialSystemContactSync` | `Batch_FinancialSystemContactSync` | Minut / – | **Inactive** – same, not deployed to prod yet. |
| `Minut_FinancialSystemOrderSync` | `Batch_FinancialSystemOrderSync` | Minut / – | **Inactive** – same. Batch size should be set to 10 (not the class default) once enabled – see acc's override, same risk of hitting the 120s Apex callout-time limit against Exact Online. |
| `Day_UpdateContractProductPrice` | `Batch_UpdateContractProductPrice` | Day / 10 | **Inactive** – not deployed to prod yet. |
| `Day_FinancialSystemRateLimitCheck` | `Batch_FinancialSystemRateLimitCheck` | Day / 20 | **Inactive** – not deployed to prod yet; prod currently has its own daily rate-limit job at 07:30 (see "Order (proposal)" step 5 above) which should be retired once this step takes over. |

These 5 go live together with the rest of the financial system rebuild (prod section above) – no separate action needed, just remember to flip `IsActive__c` to `true` once each class is deployed and verified, same pattern as steps 1-3 above.

**Gotcha hit during this rollout**: `Test_Util_JobDispatcher.scheduleEvery5Minutes_creates12Schedules` creates CronTrigger jobs with the exact same names the live Minut schedule now permanently holds in prod (`GoMeddo Subscription - Batch_JobDispatcher - 0 X 1-3,5-23 * * ?`), so it throws `AsyncException: already scheduled for execution` on every future `RunSpecifiedTests` deploy that includes it. Prod runs a patched copy of this test file with that one method removed (kept only in scratch, not committed – see `project_jobdispatcher_prod_cutover_todo` memory). If `scheduleDaily()`/`scheduleHourly()` ever go live for real in prod too, `scheduleDaily_createsOneScheduleAt0013` and `scheduleHourly_createsOneScheduleAtMinute23` will hit the same problem and need the same treatment.

---

## 2026-10-08: new code fully separate from the legacy Exact sync (user decision)

User: the rebuild must **not overwrite existing (prod) code**; the legacy sync stays intact and is retired later as its own step. Record-level overlap (same Account/Debtor Number records) is fine.

**Legacy path restored to the exact prod versions** (repo = prod, so deploying them is a no-op): `Util_Exact`, `Inv_syncAccountToFinancialSystem`, `Inv_syncOrderToFinancialSystem`, `Ctrl_SyncWithExact`, `Util_Rest`, `Batch_FinalizeInvoices`, `Batch_FinalizeInvoicesLimited`, `Test_Exact`, `Test_Inv_sync*`, `Test_Controllers`, flows `afl_Account_Get_new_debtor_number` (prod v12) and `scr_Order_SyncToFinancialSystem` (= prod). `Test_Util_Exact` (not in prod) back to its pre-rebuild version. Dropped with this: dev-only pre-rebuild edits that never reached prod (e.g. the visiting-address check in `Ctrl_SyncWithExact`).

**Trigger hooks moved to their own triggers** (existing `Trigger_Account` / `Trigger_Order` / `Trigger_Contact` = pre-rebuild again):
- `AccountFinancialSystem` (after insert/update) → `Trigger_AccountFinancialSystem` (debtor-number upsert)
- `OrderFinancialSystem` (after insert) → `Trigger_OrderFinancialSystem` (queue account for hardware/opportunity draft orders)
- `ContactFinancialSystem` (before/after delete) → `Trigger_ContactFinancialSystem` (delete/merge capture)
- `AccountContactRelation` trigger was already new.

**Still touching existing components (accepted by the user):** flag logic in `rbb_Account` / `rbb_AccountContactRelation`; `Util_System` (extra Administration fields) and `Util_OAuth` (log fix) as generic improvements; additive permission-set entries.

**Removed from the go-live package** (they move to the switch-over package): `Util_Exact` forwarders, invocable/button/Util_Rest/invoice-batch redirection, `Test_Exact` rewrite.

### Switch-over package (separate, later – retires the legacy sync)
1. Backfill `AccountContactRelation.FinancialIdContact__c` from `Subscription25__Debtor_Number__c.Exact_Contact_Id__c` (ACR of `Account.Contact_person__c`). Prod 2026-10-08: 126,590 debtor numbers have a contact id, 0 ACRs → without this every first sync creates duplicate Exact contacts and orders wait.
2. Deactivate `rac_` / `rau_Account_Sync_to_Financial_System`.
3. Repoint entry points to the new classes: Account "Send to Exact" (`Ctrl_SyncWithExact`), order button (`switchover/scr_Order_SyncToFinancialSystem.flow-meta.xml` = acc v3, direct sync via `Inv_FinancialSystemOrder`), `Util_Rest` (flag instead of `Util_Exact.syncAccountAsync`), `afl_Opportuntity_Create_Order` (`Inv_syncOrderToFinancialSystem` + its `rDebtorNumber.Exact_ID__c` decision), `Batch_FinalizeInvoices(Limited)` → `Util_FinancialSystem_Invoice`.
4. Activate the Minut financial steps.
5. Later: delete `Util_Exact`, `Inv_sync*ToFinancialSystem`, their tests; stop reading `Debtor_Number.Exact_*`.

---

## 2026-10-08: rollout in 4 parts (user decision) – status: built + tested in dev only

### Part 1 – codebase (new components only, no existing component changes)
`Util_FinancialSystem*`, `Batch_FinancialSystem*`, `Inv_FinancialSystemAccount/Order`, `Svc_FinancialSystemContactRemoval`, triggers `OrderFinancialSystem` / `ContactFinancialSystem` / `AccountContactRelation` + handlers, dispatcher steps (inactive), new fields, CMDT, tests. Accepted touches: `Util_System`, `Util_OAuth`, `rbb_Account`, `rbb_AccountContactRelation`, permission sets (additive).
- UK (reseller 6): direct debit does not work in Exact UK → no bank details / Exact mandate required for any direct-debit method (I0 / I3 / I4 / I8 / p0) (`Util_FinancialSystemAccount.requiresBankDetails`). A filled UK bank account is still sent as an Exact bank account.

### Part 2 – debtor number + new buttons
- Flow `rab_Account_Debtor_Number` (replaces the Apex trigger `AccountFinancialSystem`, removed): after update only, when the debtor number is set/changed or the reseller changes (not on create – no reason there, user 2026-10-08); one debtor number per account (composite key Account Id + Administration Id); other administrations deleted; Exact ids taken over from the Account when empty or changed; `Exact_Contact_ID__c` = `FinancialIdContact__c` of the ACR with role Invoice (`isInvoiceContact__c`). Errors → `Account.FinancialSyncLastError__c`.
- Validation rule `vr_FinancialDebtorNumberClear`: debtor number can't be cleared while `FinancialIdAccount__c` is set.
- Buttons: quick actions `Account.actFinancialSystemSync` / `Order.actFinancialSystemSync` ("Sync to Exact (new)") → `scr_Account_FinancialSystemSync` / `scr_Order_FinancialSystemSync`. Still to add to the page layouts / Lightning pages.
- Prod data before activating: account `001bR00000wmFZdQAM` has 2 debtor numbers (Germany a0ZbR00000IM75JUAT, Netherlands a0ZbR00000IUajdUAD) – the flow deletes the one that isn't the reseller's administration on its next run.

### Part 3 – replace the old pointers (existing components)
- `pef_Internal`: `Sync_to_Exact` branch removed (no publisher of that action).
- `Util_Rest.checkDebtorNumber`: no `Util_Exact.syncAccountAsync` any more (non-Exact administrations still get a debtor number).
- `afl_Opportuntity_Create_Order`: order sync removed (`dec_01_BatchSync`, `pa_02_Wait`, `act_01_Sync_Order`, `ass_04_Commit`, `cBatchSync`; was already off in prod). Base = prod v35. **One more adjustment pending (user).**
- `afl_Account_Get_new_debtor_number`: sets `SyncToFinancialSystem__c` (was `FinancialSystemSync__c`) and clears `FinancialIdAccount__c` with the number (new sync POSTs a new Exact account and resets the child ids; needed for `vr_FinancialDebtorNumberClear`).
- Deactivate `rac_` / `rau_Account_Sync_to_Financial_System`; swap the old buttons for the new ones on the layouts; contact-id backfill (see switch-over above).
- Still open: Account `Send to Exact` / Debtor Number `act_Sync_to_Exact` (Aura) → replace on layouts; `Batch_SyncAccountEuropeTrack` stays for now (user).

### Part 4 – remove the old code
`Util_Exact`, `Inv_sync*ToFinancialSystem`, `Ctrl_SyncWithExact` + Aura `SyncWithExact`, old quick actions, `scr_Order_SyncToFinancialSystem`, `rac_`/`rau_Account_Sync_to_Financial_System`, old tests; dead code in `Trigger_Account` / `Trigger_Opportunity` / `Rest_UpsertAccount`; flow `rac_Contract_Product_Activated` (inactive everywhere, replaced by `Batch_ActivateDraftContractProducts`; already deleted in dev – flows need a Tooling API delete per version, a destructive metadata deploy fails with "insufficient access rights on cross-reference id").

## Warehouses: one Exact order per warehouse (built in dev 2026-10-08)

**Status 2026-10-09:** dev committed (`b792413`, not pushed) + data set + live-tested; **acc deployed + data set + live-tested**; prod NOT deployed.

Exact allows one warehouse per sales order; NL has 2 (Moving Intelligence, Europetrack), so an opportunity can now get more than one order (1 Salesforce Order = 1 Exact sales order).

- `pvs_FinancialSystemWarehouse`: readable API names `<reseller>_<code>` (`1_MI`, `1_ET`, `5_MI`, `6_MI`); the GUID is NOT in the value set (it differs per org).
- `FinancialSystemIdWarehouse__c` (picklist, value set) on: Administration ("Warehouse (Default)", dependent on Reseller__c), Administration Product ("Warehouse", vr_FinancialSystemIdWarehouse: prefix must match the administration's reseller), Order ("Warehouse"), Exact_Relation_Setting__c (WH rows: value -> org-specific Exact_ID__c). Not on OrderItem (user: the order is enough).
- Warehouse of a product: Administration Product warehouse, else the administration default. Product warehouse wins over the sales channel (user decision A).
- `Inv_FinancialSystemCreateOrders` (called by afl_Opportuntity_Create_Order): groups the products per warehouse, one Order per warehouse, all-or-nothing (savepoint); Opportunity.Order__c = order of the first product. **Every created order is flagged `SyncToFinancialSystem__c = true`** (user 2026-10-09: the sync belongs in the job dispatcher) -> Minut OrderSync step sends it to Exact (replaces acc's old cBatchSync=false direct sync at creation). In prod nothing is sent until the OrderSync step is active.
- `Util_FinancialSystem_Order`: WarehouseID = Exact GUID of the order's warehouse; order without one takes its products' warehouse (must be one, else error); none at all -> old fallback (channel WH row / Warehouse_Exact_Id__c). Exact Description gets ` (<warehouse api name>)`.
- rau_Opportunity dur_01_Order: payment method / sales channel now updates ALL orders of the opportunity not yet in Exact (was only Order__c); the decision no longer requires Order__r.Exact_Id__c to be empty. NOTE this file also carries the uncommitted Fitting Service change (Rest_UpsertOpportunity work).
- Warehouse_Exact_Id__c stays for the legacy code; retire with Util_Exact (part 4).
- Profiles (user rule 2026-10-09: FLS on System Administrator + every operational mi* profile; all mi* profiles are operational except miAPI(Integration), miNoAccess, miReadOnly and - user 2026-10-09 - miMinimum). Grant follows the profile's object access: Order edit where Order is editable (miAfterSales/DataAdministrator/Finance/Sales/Shareholders/StandardUser), read for miMarketing (Order read-only in prod); Administration read for miAfterSales/DataAdministrator/Sales/Shareholders; Admin Product + Exact Relation Setting edit for miDataAdministrator; System Administrator edit on all 4. Left out: miExperienceCloudSupport (guest licence, never), miCustomerCommunityPlus (community licence), miReadOnly (exists in no org). miShareholders exists in dev/acc only -> drop from the prod package. Minimal profile files: scratchpad `whprofiles` / `accperms`; miMinimum grant revoked again in dev (0Afbd00000Bc16QCAR) + acc (0AfG500000SvvUUKAZ) and its repo file removed; the operational profile files (Admin, miAfterSales, miDataAdministrator, miFinance, miMarketing, miSales, miStandardUser) are committed.
- Perm sets: ps_miFinancialSystem_Admin (Administration + Order edit), ps_miProductPricebookEntry_Admin (Admin Product edit), ps_miOrderManagement (Order edit), ps_miSubscription25_User (read). Deployed to dev as minimal files (repo ps_miSubscription25_User does not deploy to dev: Contractor_Service__c missing there). **⚠ 2026-10-14: a minimal permission-set file REPLACES the whole set** (unlike profiles) – this stripped ps_miOrderManagement and ps_miProductPricebookEntry_Admin in dev + acc; restored from prod, see the 2026-10-14 section.

### Data per org (after deploy) - in THIS order
As soon as an administration default is set, every order without its own warehouse takes it from its products; without a WH mapping row that order fails with "No Exact warehouse id" (retry backoff). So:
1. Exact_Relation_Setting__c WH rows FIRST: set FinancialSystemIdWarehouse__c (WH - Moving Intelligence -> `<adm>_MI`, WH - Europetrack -> `1_ET`) and check Exact_ID__c is filled. prod GUIDs: NL MI 4dab22b0…, NL ET a21af096…, DE 3fb070fb…, UK 07284896…. acc: NL MI d868f85d…, NL ET 96d18dda…, plus "WH - SlimmGPS" = a21af096… (= prod's ET GUID!) - no value; DE/UK rows have NO GUID in acc.
2. Then administration defaults: NL `1_MI`, DE `5_MI`, UK `6_MI` - only where step 1 has a GUID (acc: NOT DE/UK until their rows have one; today those orders go with a blank warehouse, after this they would fail).
3. Then Administration Product warehouses. Rule (user 2026-10-09): products whose platform is only Europetrack -> `1_ET` = NL Administration Products with `Product2.System_Platform__c = '5'` (every product has exactly one platform value; prod: 98 products, 95 active, e.g. 800.313.0130 -> so MI-channel orders with these products now also ship from ET, product wins). Everything else uses the administration default.
   ```apex
   List<Subscription25__Administration_Product__c> aps = [SELECT Id FROM Subscription25__Administration_Product__c
       WHERE Subscription25__Administration__c = :nlAdminId AND Subscription25__Product__r.System_Platform__c = '5'];
   for (Subscription25__Administration_Product__c ap : aps) ap.FinancialSystemIdWarehouse__c = '1_ET';
   update aps;
   ```
4. acc/prod (Sub25 v2.66): `Subscription25__Schedulable_Class__c` Name = Unique_Name = `Batch_FinancialSystemOrderWarehouse`, batch size 20 - BEFORE the repair run / activating step 35 (else "List has no rows" and the whole Minut chain stops).
- The FLS was the reason the fields were invisible to my user (System Administrator had no FLS; pg_Subscription25Admin is session-activated) - fixed by the profile grants.
- dev data 2026-10-09: WH rows MI->1_MI, ET->1_ET, DE->5_MI, UK->6_MI (dev has no Exact GUIDs), NL default 1_MI, 81 NL admin products -> 1_ET.
- afl_Opportuntity_Create_Order is started per interview by pef_Internal (Util_Flows), same as before; the invocable adds ~3 SOQL per opportunity.
- Tests: Test_Util_FinancialSystemWarehouse, Test_Util_FinancialSystem_Order (warehouse tests), Test_afl_Opportuntity_Create_Order (runs the flow + rau_Opportunity).

### Repair / split of existing draft orders
- `Util_FinancialSystemWarehouse.splitOrders` + `Batch_FinancialSystemOrderWarehouse`: draft Hardware/Opportunity orders, not in Exact. Order keeps its own warehouse (or that of its first product) and those products; the products of each other warehouse move to a new draft order (copy of the order, same opportunity, flagged like the original). A move = copy + delete (OrderItem.OrderId can't change); Partner_Code__c moves along. Per order all or nothing.
- Copy uses a fixed list of standard fields + all writable custom fields (not describe isCreateable: that depends on the running user's FLS).
- One-off repair per org, AFTER the data steps: `Database.executeBatch(new Batch_FinancialSystemOrderWarehouse(true), 20);` (prod today: 3 draft Opportunity orders, 0 Hardware).
- Ongoing: dispatcher step `Minut_FinancialSystemOrderWarehouse` (order 35, before the order sync at 40), ships INACTIVE; default mode only splits orders flagged for the sync (no split while someone still edits the order).
- Parent order: Salesforce has OriginalOrderId (standard, reduction orders only, create-only, 0 used in prod) and Subscription25__Parent_Order__c ("the order that this credit (or clone) originated from", used by 205 Contract orders in prod). Exact SalesOrders have no parent/related order field. The split orders are NOT linked by a parent field (only OpportunityId + the same YourRef/Description) - **user 2026-10-09: do not use Subscription25__Parent_Order__c, keep them separate.**

### acc deploy 2026-10-09
- Pre-check: acc versions of everything overwritten = the base of `b792413` (Util_FinancialSystem_Order/Test = 3f32641, rau_Opportunity = 02b505d, perm sets equal apart from format noise: viewAllFields / calculated fields editable). **acc drift: afl_Opportuntity_Create_Order had `cBatchSync = false`** (= direct order sync to Exact at creation via Inv_syncOrderToFinancialSystem); the new flow has no sync step at all (order sync removed, user decision) -> orders created from opportunities in acc are now only sent via the button / flagged batch. Check prod's cBatchSync before the prod deploy.
- `rau_Opportunity` deployed **as committed in b792413** (warehouse part only, WITHOUT the uncommitted Fitting Service elements; user 2026-10-09: leave the Fitting Service out).
- Deploy `0AfG500000SvxKzKAJ`: 16/16 components (value set, 4 fields, VR, 7 classes, CMDT step 35 inactive, 2 flows), RunSpecifiedTests Test_Util_FinancialSystemWarehouse + Test_Util_FinancialSystem_Order + Test_afl_Opportuntity_Create_Order = 25/25 pass. Coverage: Util_FinancialSystemWarehouse 97%, Inv_FinancialSystemCreateOrders 98%, Batch_FinancialSystemOrderWarehouse 82%, Util_FinancialSystem_Order 87%.
- Deploy `0AfG500000SvxT3KAJ`: 4 minimal perm sets + 9 minimal profiles (13/13), FieldPermissions verified. (The minimal ps_miOrderManagement / ps_miProductPricebookEntry_Admin wiped the rest of those sets – restored 2026-10-14.)
- Data: WH rows NL MI (d868f85d) -> 1_MI, NL ET (96d18dda) -> 1_ET, DE -> 5_MI, UK -> 6_MI (no GUID yet = not used), SlimmGPS left blank; NL default 1_MI (DE/UK no default); 81 NL admin products -> 1_ET; Sub25 config record Batch_FinancialSystemOrderWarehouse (20). getExactId check: 1_MI -> d868f85d…, 1_ET -> 96d18dda… OK.
- Live test (anonymous Apex, own opportunity on "E2E Adrestest B.V.", rolled back): opportunity with a platform 1 + platform 5 product -> 2 draft orders (1_MI = Opportunity.Order__c, 1_ET); payment method change -> both orders updated; mixed Hardware draft -> split (original keeps 1_MI, new draft order 1_ET). Same run in dev (opportunity 006bd00000S9pjCAAR, rolled back): same result.
- Repair batch run once (`707G500001XHiCP`): Completed, 0 errors (acc has 0 NL draft Hardware/Opportunity orders not in Exact).
- NOT tested: real send to Exact (acc NL token can reach the prod division - see memory; do it by hand via the order button with a test order if wanted).

- 2026-10-09 follow-up: order flag at creation deployed dev (0Afbd00000Bc309CAB) + acc (0AfG500000SvxBLKAZ), 25/25 tests each, live test repeated in both (rolled back). Flag itself verified by the unit test (SyncToFinancialSystem__c is invisible to my user even in dynamic SOQL).

- 2026-10-09 order type guard (`4a5f320`, user: only Hardware/Opportunity orders may sync): `Util_FinancialSystem_Order.SYNC_ORDER_TYPES = {Hardware, Opportunity}`; Batch_FinancialSystemOrderSync only selects flagged orders of those types; any other flagged order (e.g. Contract via the button) is refused without callouts, flag cleared (no retry), FinancialSyncLastError__c = "Only Hardware and Opportunity orders are sent to the financial system (type: X)." Split step uses the same set. Automatic flagging only happens in Inv_FinancialSystemCreateOrders (Type is always Opportunity there). Prod context: 27,377 Opportunity orders have an Exact order number; Contract orders (~188k in 90 days) are Subscription25 recurring orders and never go to Exact as sales orders. dev 0Afbd00000Bc4dlCAB (27/27 + 40 related tests), acc 0AfG500000Sw0sLKAR (29/29; Test_Util_JobDispatcher left out = known live-schedule collision in acc).

- 2026-10-09 user: the Hardware order type was renamed to Opportunity -> SYNC_ORDER_TYPES / split types = {Opportunity} only (no Hardware orders exist in dev/acc/prod; prod still has 'Hardware' as an active Order.Type picklist value - can be deactivated). Commit after 4a5f320, dev 0Afbd00000Bc5ErCAJ 29/29.

- 2026-10-09 Order.Type value `Hardware` deactivated (user: yes): dev 0Afbd00000Bc5ZpCAJ, acc 0AfG500000Sw1YIKAZ. **prod: not done** (blocked by the auto-mode classifier as a prod deploy) - package in scratchpad `ordertype/deploy` (StandardValueSet OrderType = prod's current values + `<isActive>false</isActive>` on Hardware). Code only compares Type == 'Hardware' (Trigger_Order, Trigger_OrderFinancialSystem, rbb_Order, rbu_Order) - dead branches, clean up later.

### Prod checklist (warehouses) - not run
1. Check prod afl_Opportuntity_Create_Order `cBatchSync` + the versions of everything overwritten.
2. Deploy the b792413 components (rau_Opportunity from the commit, not the working copy) with the 3 test classes; then the **full** repo permission-set files (= prod + the warehouse field, checked 2026-10-14 – NEVER minimal permission-set files, they replace the whole set) + minimal profiles (additive) WITHOUT miShareholders and WITHOUT miMinimum. Re-diff each permission set against prod just before the deploy.
   + Exact_Relation_Setting__c (2026-10-12): validationRules/vr_ERS_Classification_3_and_S_and_W (C3/SC only) + vr_ERS_Classification_WH (warehouse), flows/rbb_Exact_Relation_Setting (WH name/key from the warehouse), layouts/Exact_Relation_Setting__c-Exact Relation Setting Layout (warehouse field), flexipages/rp_ExactRelationSetting (NOT activated in dev/acc - activate by hand or leave). After deploy: Sales Channel stays filled on the WH rows (legacy lookup, by hand), set the warehouse, re-save the 4 WH rows.
   + `Test_Exact` with the WH-fixture fix (2026-10-14) in the same deploy – otherwise vr_ERS_Classification_WH makes `Test_Exact.testOrderSync` fail.
3. Data in order: WH rows (NL MI 4dab22b0…, NL ET a21af096…, DE 3fb070fb…, UK 07284896…), defaults, platform-5 products, Sub25 config record.
4. One-off repair (3 draft Opportunity orders today), check results.
5. Step 35 stays inactive until the order sync steps go live.

## acc deploy of rollout parts 1-3 (DEPLOYED 2026-10-09)
User 2026-10-09: deploy parts 1-3 to acc, **rac_/rau_Account_Sync_to_Financial_System deactivated in the same deploy** (else the legacy Util_Exact sync revives in acc next to the new batch), and the acc data mop-up (`subset/run_cleanup.sh full2`) runs FIRST.
- Package (scratchpad `acc_parts/deploy`, mdapi `acc_parts/mdapi`, 35 components): legacy classes = repo/prod copies (Util_Exact, Inv_sync*, Ctrl_SyncWithExact, Batch_FinalizeInvoices(Limited), tests), Util_Rest + Test_Util_Rest (part 3), Trigger_Contact/Trigger_Order without hooks + new triggers ContactFinancialSystem/OrderFinancialSystem + handlers, Util_FinancialSystemAccount (UK, upsertDebtorNumbers removed) + test, flows rab_Account_Debtor_Number, scr_Account/Order_FinancialSystemSync, afl_Account_Get_new_debtor_number, pef_Internal, quick actions, vr_FinancialDebtorNumberClear, rp_Account/rp_Order (button swap only), FlowDefinitions rac_/rau_ activeVersionNumber 0.
- **Trigger_Account = acc's version minus `upsertDebtorNumbers`** (repo version needs dev-only VisitingAddress_Country/State fields).
- Left out on purpose: rbb_Account (repo has dev-only platform-status changes; acc already flags on Bank_Account_Number__c), rac_/rau_ flow bodies (repo uses other field names), scr_Order_SyncToFinancialSystem (acc v3 stays, off the page), JobDispatcherStep CMDT (Minut financial steps stay off during cleanup).
- Dry run 0AfG500000Sw2e2KAB: 35/35 compile, 87/87 tests pass (only coverage warnings on legacy classes) -> real deploy with NoTestRun.
- acc data cleanup done 2026-10-09 15:49: 1,796 accounts left (the keep subset), DataStorageMB 4,731 free of 5,120. Leftovers created during the run (1 payment, 2 Security Platform contracts) caught by the full2 mop-up.
- Deployed 2026-10-09 (NoTestRun, 35/35): rac_/rau_Account_Sync_to_Financial_System inactive; active: afl_Account_Get_new_debtor_number v11, pef_Internal v2, rab_Account_Debtor_Number v1, scr_Account/Order_FinancialSystemSync v1. Tests after deploy: 116/116 (15 classes incl. Test_Exact, Test_Controllers, Test_rab_Account_Debtor_Number, Test_Orders).
- Minut financial steps Account/Contact/OrderSync active again in acc (repo CMDT, live values otherwise equal); OrderWarehouse (35) stays inactive.
- Open: live button checks with the new "Sync to Exact (new)" actions (account + order); prod not started.

## Manual tests acc 2026-10-12
- Stichting ZorgAccent (12246151): the first new sync (14:11) POSTed a 2nd invoice address (a5d24173) next to the legacy Main one (ffb56b9a, same "Postbus 226"); Exact left the new one Main=false (ffb56b9a was also set Main by hand at 14:15). A PUT with Main=true does make it Main (street change 14:27).
- Fix (user: override the invoice address): on the first sync of an invoice/delivery address of an account already in Exact, GET its Main address of that type (`Type eq N and Main eq true`), store its id and PUT the Salesforce address + invoice/shipping contact + Main=true onto it; POST only when there is none. +1 call in estimateCalls. New test `invoiceAddress_firstSync_takesOverExistingMainAddress`. dev 29/29, acc 0AfG500000SxtWbKAJ 29/29. Committed in `b2add38`.
- Also seen: duplicate Exact contacts (legacy Wibo 762a76d5 + new b9388db4; Willem bf8d4471 + 124af85c) - contacts are not taken over either.
- Cleanup ZorgAccent acc Exact (user 2026-10-12): visit address 25b351ba -> contact 124af85c; deleted invoice addresses ffb56b9a + c4ec9b60. Contacts 762a76d5 (Wibo) + bf8d4471 (Willem) can NOT be deleted: "Gebruikt in: Verkoopfacturen" -> a contact take-over is the only way to avoid these duplicates in prod.
- Contacts 762a76d5 + bf8d4471 renamed "<last name> (TO BE DELETED)" (user 2026-10-12); email/end date unchanged.
- Checked 2026-10-12 (4 acc sales orders + 8 acc sales invoices): InvoiceToContactPerson = contact of the Main Type 3 address whenever there is one (5/5), else the account main contact (7/7); our code never sends InvoiceToContactPerson. Exact docs: Main = "main address for this type". Invoice address itself is not exposed on SalesInvoices via the API - check one invoice PDF.
- Who synced ZorgAccent 2026-10-12: all account syncs (14:11, 14:27, 14:49, 15:02, 15:07 CEST) were the direct "Sync to Exact (new)" button - every Minut AccountSync run 14:10-15:10 processed 0 records. Only the 14:35 contact rename went via the dispatcher (ContactSync, 1 item). Billing contact -> Pieter Herman van den Achterkant at 15:02: new Exact contact 482fe5de on Main invoice address a5d24173, old invoice contact b9388db4 retired "(DO NOT USE)". Scheduled jobs run as Teun Rietman, so CreatedBy does not tell button vs dispatcher apart - use the timing / batch item counts.
- 2026-10-12 Administration Product warehouses re-done from PROD (user: platform exactly 5, prod is the source): prod has 98 Product2 with System_Platform__c = 5 (95 active), none multi-platform. Matched by ProductCode on the NL administration: acc + dev now 98/98 = 1_ET (17 added each; those 17 have a blank or `1;5` platform in acc/dev = Product2 drift vs prod). List: scratchpad wh5/prod_p5.csv. For prod: select by System_Platform__c = '5' directly (prod is the source).
- 2026-10-12 `WH - SlimmGPS` (a1gAO000000Nie2YAC, Exact_ID a21af096 = prod ET GUID) deleted in acc (user); backup scratchpad wh5/acc_slimmgps_backup.json, recoverable from the Recycle Bin. dev never had it. Prod: check for the same row in the prod checklist.
- 2026-10-12 SlimmGPS check: prod has NO `WH - SlimmGPS` row (4 WH rows: NL MI 4dab22b0, NL ET a21af096, DE 3fb070fb, UK 07284896); no SlimmGPS `SC` row in prod/acc/dev; Sales_Channel value set = Moving Intelligence/Europetrack/Echoes in all 3 orgs; Sales_Channel__c on Order/Opportunity/Account/Contract has 0 SlimmGPS records in prod/acc/dev. Nothing left to remove.
- 2026-10-12 Exact_Relation_Setting__c WH rows now keyed on the warehouse (dev 0Afbd00000BdMYbCAN, later acc too; committed in `948bf3b`): vr_ERS_Classification_3_and_S_and_W = C3/SC only (name kept); new vr_ERS_Classification_WH requires FinancialSystemIdWarehouse__c; rbb_Exact_Relation_Setting (api 67): WH Name = "WH - <warehouse label>" (CASE on 1_MI/1_ET/5_MI/6_MI, fallback API name), Composite_Key__c suffix = -<warehouse> (was first letter of the sales channel; max 63 of 64 chars). Sales_Channel__c + Acting_Value__c on WH rows kept: legacy Util_Exact + the new order fallback still look WH up by sales channel - remove with part 4. dev WH rows re-saved; VR probes rolled back. acc/prod: deploy with the warehouse package, then re-save the WH rows.
- 2026-10-12 (later): user: WH rows keep the Sales Channel too -> vr_ERS_Classification_3_and_S_and_W restored to the original formula (C3/SC/WH need Sales Channel), vr_ERS_Classification_WH additionally needs the Warehouse. Deployed dev 0Afbd00000Bd6nDCAR + acc 0AfG500000Sy5j3KAB (2 VRs + rbb flow). dev NL WH rows had their Sales Channel cleared by hand -> restored (MI / Europetrack). WH rows re-saved in dev + acc: names "WH - <warehouse label>", keys -<warehouse>. Probes (rolled back): no channel -> refused, channel without warehouse -> refused, both -> saved. Acting_Value__c -> warehouse: part 4 (with removing the sales-channel fallback in Util_FinancialSystem_Order).
- 2026-10-12 (final): user: warehouse validation on the warehouse only, Sales Channel kept filled by hand for now -> vr_ERS_Classification_3_and_S_and_W = C3/SC again. Layout (warehouse field, user edit in dev) + new record page rp_ExactRelationSetting retrieved into the repo. dev 0Afbd00000BdNG9CAN + acc 0AfG500000Sy641KAB: 2 VRs + rbb flow + layout + record page, 5/5. Probes (rolled back) dev+acc: WH without warehouse refused, WH with warehouse only saved, SC without channel refused. Record page not activated in any org (no org default / app assignment). Added to the prod warehouse checklist step 2.
- 2026-10-12: record page renamed in dev (label typo "Exact Relation Settingm(rp)" -> corrected to "Exact Relation Setting (rp)"); page + layout redeployed dev 0Afbd00000BdN6UCAV + acc 0AfG500000Sy6jxKAB (2/2). Layout name unchanged.
- 2026-10-12 warehouse test acc (anonymous Apex, rolled back, account "test de tester"): NL admin default 1_MI; getExactId NL 1_MI -> d868f85d, 1_ET -> 96d18dda, DE/UK none (no GUID in acc, as expected); product warehouses 1.5001.01.01 (platform 1) -> 1_MI (default), 1.1000.00 (platform 5) -> 1_ET (Administration Product); Inv_FinancialSystemCreateOrders -> "2 orders created (one per warehouse)": 1_MI order with the MI product, 1_ET order with the ET product, each resolving to its Exact GUID. Rollback verified (0 orders left).

## Closed Won check + sync-failure alerts (2026-10-13)

**Closed Won check (option 1, user decision):** `afl_Opportuntity_Create_Order` decision `dec_01_Sync_to_Exact` now requires `Opportunity.Account.FinancialIdAccount__c` (was `Subscription25__Debtor_Number__c.Exact_ID__c`, which only the legacy `Util_Exact` fills → every account synced by the new code was refused "Linked account not Financial ready"). Debtor-number record check kept (ties it to the opportunity's administration). Abort message now says what to do. dev + acc (v39) deployed.
- **Prod**: prod's flow is v35 and differs a lot from the repo (no warehouse split yet) but has the same two `Exact_ID__c` conditions → make the same two-line edit on prod's own version, or ship the repo version with the warehouse package.
- **Prod impact**: 16 debtor-number records have `Exact_ID__c` but the Account has no `FinancialIdAccount__c` → those accounts would be newly blocked at Closed Won. Backfill `Account.FinancialIdAccount__c` from `Exact_ID__c` for those 16 before/with go-live. (155,437 have both.)

**Alerts (`Svc_FinancialSystemSyncAlert`, called from `Util_FinancialSystemAccount.save` after all DML):**

| Category | Raised where | Examples | Who / when |
|---|---|---|---|
| DATA (hard) | `Svc_FinancialSystemSyncAlert.DataException` in `prepare()`/match; or Exact HTTP 400 | not validated by Web Services, establishment address missing, Exact account already linked to another SF account, Exact validation message | account owner at once; once per distinct problem |
| TECHNICAL (soft) | any other `FinancialSyncException`, unhandled exception | 401/403/404 (e.g. wrong-division Exact id), 5xx, callout failure/timeout, unreadable response | retried with back-off (15 min … 24 h); owner only when parked (attempt 8) |
| SILENT | `Util_System.CustomException` | reseller does not sync with Exact; sandbox without acceptance environment | nobody |
| Postponed | rate limit / no capacity | – | nobody, no attempt counted |
Warnings (account in Exact, a part failed: contact / main contact / address / bank / retire) use the same categories.

Recipient: account owner when active and not an integration profile (profile name contains "Integration", miSync, PT1). Otherwise → `routeToCase` (**TODO: case route to be defined**; now only logged in the sync Event_Log). `User.Integration_User__c` is NOT used: it includes System Administrators. Prod 2026-10-13 account owners: ~70,900 integration (Platform Integration 65,437 / Security Platform 5,484), ~69,600 inactive owner, ~43,800 miSales → more than half go to the case route.
Dedupe: key `alert` in `FinancialSyncState__c` (category + first 120 chars); success clears it. Outcome ("Alert sent…" / "case route…" / "not sent: …") appended to the sync Event_Log.
New metadata: CustomNotificationType `FinancialSystemSyncFailed` (deploy with the Apex). `Util_FinancialSystem.lastErrorStatus` added. dev + acc deployed 2026-10-13, 55/55.

**Admin profile FLS**: repo `Admin.profile-meta.xml` got the 10 sync fields (Account 6, Order 4; `FinancialContactsToRetire__c` read-only). Not deployed (classifier blocked); user runs it.

**Bug found 2026-10-13 – duplicate orders on Closed Won (acc opp 006G500000ZaFkLIAV: 4 orders instead of 2)**: `rau_Opportunity` publishes `Internal__e` Create_Order whenever Stage = Closed Won and `Order__c` empty, without requiring a stage change; a second save in the same transaction re-runs it → two events → two parallel `afl_Opportuntity_Create_Order` runs (both 08:21:12). `Inv_FinancialSystemCreateOrders` has no duplicate guard. User deleted the extra pair (03321445/46). **Fixed 2026-10-13 (dev + acc); user acc test OK 2026-10-14 → goes into the prod package (`Inv_FinancialSystemCreateOrders` + `Test_afl_Opportuntity_Create_Order` fixture):** `Inv_FinancialSystemCreateOrders.existingOrders` locks the opportunity (FOR UPDATE) and returns the existing orders of that opportunity + type instead of creating new ones; the parallel second run waits for the first commit. rau_Opportunity not changed. Also fixed `Test_afl_Opportuntity_Create_Order` fixture (needs Account.FinancialIdAccount__c since the Closed Won check change). Tests 13/13 dev + acc.

**Bank account soft (user, 2026-10-13):** a missing bank account on a direct-debit account (was: whole sync refused in `prepare()`) or a bank account refused by Exact no longer blocks the account: account, contacts and addresses go to Exact, the bank/mandate step is skipped as a TECHNICAL (soft) warning; account stays flagged with back-off, owner alerted only when parked; filling in the IBAN re-flags via rbb_Account. Effect: Closed Won is no longer blocked by a missing IBAN. dev + acc 56/56.

## Block after repeated hard failures + case route (2026-10-13, supersedes the alert rules above)

User decisions: block after **3** hard failures; unblock by data change (account) + "Sync to Exact (new)" button/action (account + order); **the block is the only alert moment** (immediate DATA alert and "parked" alert removed); **technical failures never count, never block, never alert or create a case** – they are retried until the technical issue is solved (account and order).

- Fields (Account + Order): `FinancialSyncBlocked__c` (checkbox "Exact Sync Blocked"), `FinancialSyncHardFailures__c` (number). Hard = DATA category (incl. DATA warnings, e.g. a contact Exact refuses with 400). Success → 0 / unblocked.
- Order hard errors (now `Svc_FinancialSystemSyncAlert.DataException`): no account with reseller, no order products, products of several warehouses, no Exact warehouse id, items not in Exact. Silent: reseller without Exact, sandbox block. New: a technical failure while reading Exact items no longer escapes `syncOrders` (was: whole batch run failed) – the orders fail technically and are retried.
- Batches skip blocked records. Account batch still picks a blocked account whose `FinancialSyncAttempts__c` was reset to 0 (rbb_Account re-flag after a data change) → counting restarts. `flagAccounts(ids)` (automatic: order sync, contact step, Trigger_OrderFinancialSystem) keeps a block; `flagAccounts(ids, true)` (Inv_FinancialSystemAccount action) and `flagOrders` (order action) lift it. The button (sync now) always tries, a success lifts the block.
- Alert at the block: active person (UserType Standard, not an integration profile) → bell notification on the record; otherwise (integration profile, inactive, automated process, queue owner) → **Case**: RecordType Default, Origin Automated, AccountId, owner = queue `gqCaseAdministration<reseller>` (2 GR / 3 BE → 1 NL; 5 DE; 6 UK), no second case while one with the same subject is open. Outcome in the sync Event_Log. rbc_Case keeps the queue owner (verified by a real insert in the tests; `CaseTransfer__c` is a restricted platform-queue picklist, not used).
- Queues `gqCaseAdministration1/5/6` ("Case - Administration (NL/DE/UK)", Case) created in dev + acc, **no members yet**. `gqAdministration1` ("Case - Reception - Administration (NL)") is used in 4 flows (ofl_Voice_2_Queue, rbu_Case, rac_EmailMessage, rbc_Case) → NOT renamed.
- **TODO: route the gqCaseAdministration queues via Omni-channel** (until then cases land in an unwatched queue).
- **Prod**: queues created 2026-10-13 (deploy 0AfTx00000138mrKAA, user's go). Fields + list views + Apex + FLS go with the rebuild.
- List views "Exact sync blocked" on Account and Order.
- FLS in repo: `ps_miFinancialSystem_Admin` (edit), `ps_miSubscription25_User` (read), Admin profile (edit). Deploy package in the session scratchpad (`flsdeploy`); `Subscription25__Contract_Product__c.Contractor_Service__c` + object `Contractor_Service__c` (prod: 57,725 records, 57,647 contract products linked → in use) copied from prod to dev and the repo 2026-10-13, so the package now deploys to dev too.
- dev + acc deployed 2026-10-13: 78/78 (Test_Svc_FinancialSystemSyncAlert, Test_Util_FinancialSystemAccount, Test_Util_FinancialSystem_Order, Test_Util_FinancialSystem, Test_Batches_FinancialSystem, Test_Inv_FinancialSystemAccount).

## acc completeness check + test fixture fix (2026-10-14)

**Method:** every file touched by the financial-system commits (`3f32641` … `473ccb2`) plus every repo file matching financial/Exact/JobDispatcher, and `Util_System`, `Util_OAuth`, `pg_Subscription25Admin`, retrieved from acc into the session scratchpad (not the repo) and diffed with HEAD. FLS checked via `FieldPermissions` (5 permission sets + System Administrator and the 6 operational mi* profiles) for every financial field.

**Result: acc has every piece of the rebuild.** Everything else is format noise (`20` vs `20.0`, `&quot;` escaping, `packageVersions`, element order, `trackFeedHistory`/`trackTrending`) or one of the documented divergences:
- `Trigger_Account` = acc's variant (still has the legacy `syncToExact` → `Util_Exact.syncAccountAsync` and the monthly/yearly order logic; repo HEAD is the dev variant). Legacy call goes with part 4.
- `rau_Opportunity`: acc = HEAD without the uncommitted Fitting Service elements – **never deploy the working copy**.
- `scr_Order_SyncToFinancialSystem` = acc v3 (off the page); `rac_`/`rau_Account_Sync_to_Financial_System` inactive, bodies differ on purpose; `rbb_Account` not deployed on purpose.
- `rac_Contract_Product_Activated` still exists in acc (inactive, v3) – delete in part 4 (Tooling API per version).
- `afl_Financial_System_Account/Order_Params` (2026-06, repo only) exist in neither acc nor prod – not part of the rebuild.
- Gone in acc as intended: `AccountFinancialSystem` trigger + `Trigger_AccountFinancialSystem`, `Batch_SyncAccountEuropeTrack`.
- `Account.FinancialIdInvoiceAddress__c` plain text (no external id/unique, `473ccb2`): acc and dev match; prod gets it created as plain text.
- Admin profile FLS (10 sync fields): **present in acc** (the "user runs it" item from 2026-10-13 is done).
- Sub25 config records in acc: AccountSync, ContactSync, OrderSync, RateLimitCheck, OrderWarehouse – all present. Minut Account/Contact/OrderSync active, OrderWarehouse (35) inactive, `Minut_FinancialSystemOrderSync` BatchSize empty (= class/config default).

**Known repo-vs-org drift (not a rebuild gap, left alone):** repo `ps_miOrderManagement` has ~130 Order/OrderItem field entries (incl. `OrderItem.FinancialId__c` / `FinancialStartDate__c` / `FinancialEndDate__c`) that neither dev nor acc has – in both orgs that permission set has no object permissions at all. The rebuild only added `Order.FinancialSystemIdWarehouse__c` (present). Never deploy the full repo file; code runs in SYSTEM_MODE.

**Fix: legacy test fixtures vs `vr_ERS_Classification_WH`.** `Test_Exact.testOrderSync` (and the same fixture in `Test_Util_Exact`) inserted a WH Exact Relation Setting row without a warehouse → refused by the new validation rule (deployed 2026-10-12). Both now set `FinancialSystemIdWarehouse__c = '1_MI'`. dev `0Afbd00000BerTuCAJ` + acc `0AfG500000T0IvVKAV` (2/2, Test_Exact + Test_Util_Exact 10/10).
- **Prod:** `Test_Exact` (fixed version) must ship together with `vr_ERS_Classification_WH` (warehouse package step 2), otherwise every later prod deploy/RunLocalTests that includes `Test_Exact` fails. `Test_Util_Exact` does not exist in prod.

**Tests acc 2026-10-14** (after the fix): 167/167 (`707G500001XowYq`) – Test_Batches_FinancialSystem, Test_Controllers, Test_Exact, Test_Util_Exact, Test_Inv_syncAccount/OrderToFinancialSystem, Test_Orders, Test_Svc_FinancialSystemContactRemoval, Test_Svc_FinancialSystemSyncAlert, Test_Trigger_Contact, Test_Util_FinancialSystem(+Account/Warehouse/_Invoice/_Order), Test_Util_Rest, Test_afl_Opportuntity_Create_Order, Test_rab_Account_Debtor_Number, Test_vr_FinancialEntityChange, Test_Util_JobDispatcher.

**Still open in acc (user, manual):** live clicks on "Sync to Exact (new)" (account + order), ~~the duplicate-order guard test on Closed Won~~ (done, OK – user 2026-10-14), members for the `gqCaseAdministration1/5/6` queues + Omni-channel routing.

### Permission sets aligned with prod (2026-10-14, user)
Found: the 2026-10-09 minimal-file deploy had **replaced** two permission sets in dev + acc (a permission-set deploy is not additive):
| Permission set | prod | dev/acc before |
|---|---|---|
| `ps_miOrderManagement` | 134 fields, Order CRED + viewAllFields, `cp_miOrderActionFinancialSync`, Order tab, ActivateOrder + EditActivatedOrders | ~28 read-only fields, nothing else (users with only this set lost Order access and the order sync action) |
| `ps_miProductPricebookEntry_Admin` | 149 fields, 6 object permissions, 1 tab | 1 field (the warehouse) |
The other two (`ps_miFinancialSystem_Admin`, `ps_miSubscription25_User`) were deployed as full files and match prod + the rebuild fields.

Restored: repo files (= prod + `Order.FinancialSystemIdWarehouse__c` / `Administration_Product__c.FinancialSystemIdWarehouse__c`, verified by diff) deployed to dev `0Afbd00000Bf67yCAB` + acc `0AfG500000T0EruKAF` (dry runs first, 2/2 each). Retrieve-diff after the deploy: dev and acc = prod + the one warehouse field each. No repo change needed.


## Prod package "silent" – code + fields + permissions, nothing active (built 2026-10-14, NOT deployed)

User 2026-10-14: deploy the Apex, fields and permissions to prod **without changing the current situation**; flows not activated, dispatcher steps inactive, only admin-visible buttons for manual tests.

Package: `.scratch/20261014 - financialSystemProdSilent/` – `src/` (source, built from **prod's** files where prod has the component) and `mdapi/` (83 components, deploy this). `.scratch` is in `.forceignore` → convert in a temporary sfdx project (see git history of this section) if `src/` is changed.

**Contents**
- Apex (new): `Util_FinancialSystem`, `Util_FinancialSystemAccount`, `Util_FinancialSystemWarehouse`, `Util_FinancialSystem_Order`, `Batch_FinancialSystemAccountSync/ContactSync/OrderSync/OrderWarehouse/RateLimitCheck`, `Inv_FinancialSystemAccount/Order/CreateOrders`, `Svc_FinancialSystemContactRemoval`, `Svc_FinancialSystemSyncAlert`, `Trigger_AccountContactRelation/ContactFinancialSystem/OrderFinancialSystem` + tests.
- Apex (existing, small): `Util_System` (+ 4 rate-limit fields in the administration query), `Util_OAuth` (logs cleared after save), `Test_Exact` (WH fixture).
- Triggers (new): `AccountContactRelation`, `ContactFinancialSystem`, `OrderFinancialSystem` – **no-op in prod**: they only act once `Minut_FinancialSystemAccountSync` is active (`Util_FinancialSystem.areTriggerHooksEnabled()`, commit `7dc0623`). Without this gate a Contact merge would have copied extId_1..6/Roles onto the master's ACR and an Opportunity/Hardware draft order would have flagged its account.
- Fields: Account 8, Order 7, Administration 5, Administration Product 1, Exact Relation Setting 1 (warehouse); CMDT type `FinancialSystemProductionDivision__mdt` + NL/DE/UK; `pvs_FinancialSystemWarehouse`; list views "Exact sync blocked" (Account, Order); CustomNotificationType `FinancialSystemSyncFailed`.
- Validation rules: `vr_FinancialDebtorNumberClear` **inactive** (155k prod accounts have FinancialIdAccount__c – would block today's debtor-number changes), `vr_ERS_Classification_WH` **inactive**, `vr_FinancialSystemIdWarehouse` active (only fires when the new field is filled).
- CMDT JobDispatcherStep: `Minut_FinancialSystemOrderWarehouse` (new, inactive), `Minut_FinancialSystemOrderSync` = prod + BatchSize 10 (still inactive). The other steps are not in the package.
- Buttons: quick actions `Account/Order.actFinancialSystemSync` + screen flows `scr_Account/Order_FinancialSystemSync`; `rp_Account` / `rp_Order` = **prod's pages** + the new action right after the old button, visible only when `{!$User.isSysAdmin__c}` = true. Old buttons untouched.
- Permission sets = **prod's files** + only the new-field entries: ps_miFinancialSystem_Admin (+19 edit), ps_miSubscription25_User (+20 read), ps_miOrderManagement (+1), ps_miProductPricebookEntry_Admin (+1). Profiles (additive, new-field entries only): Admin 18, miAfterSales 2, miDataAdministrator 4, miFinance 1, miMarketing 1, miSales 2, miStandardUser 1.

**Not in the package (go-live / later):** record-triggered + changed flows (`rab_Account_Debtor_Number`, `rbb_Account`, `rbb_AccountContactRelation`, `afl_Account_Get_new_debtor_number`, `afl_Opportuntity_Create_Order`, `rau_Opportunity`, `pef_Internal`, `rbb_Exact_Relation_Setting`), `Trigger_Account`, `Util_Rest` (part 3), `Util_FinancialSystem_Invoice` (switch-over), ERS layout/record page/`vr_ERS_Classification_3_and_S_and_W`, `Test_Util_JobDispatcher` (prod keeps its patched copy), Sub25 config records, the other dispatcher steps.

**Checks done 2026-10-14:** every custom field the package's Apex uses exists in prod or is in the package; coverage in dev with the test set below: every class ≥ 76% (Util_System 87% via Test_Util_System; ContactSync/AccountSync/OrderSync batches now covered by `setDispatcher`/`getBatchSize` asserts); **acc dry run `0AfG500000T0MxWKAV`: 83/83 components, 105/105 tests, no coverage warnings**.

**Deploy (only on the user's explicit go)** – first a prod validation, then quick-deploy:
```bash
sf project deploy start -o prod --metadata-dir ".scratch/20261014 - financialSystemProdSilent/mdapi" --dry-run \
  --test-level RunSpecifiedTests -t Test_Batches_FinancialSystem -t Test_Svc_FinancialSystemContactRemoval -t Test_Svc_FinancialSystemSyncAlert \
  -t Test_Util_FinancialSystem -t Test_Util_FinancialSystemAccount -t Test_Util_FinancialSystemWarehouse -t Test_Util_FinancialSystem_Order \
  -t Test_Exact -t Test_Util_System --wait 60
sf project deploy quick -o prod --job-id <validation id> --wait 30
```

**After the deploy**
1. Snapshot first (before the deploy): `FlowDefinition` active versions of rbb_Account, rbb_AccountContactRelation, afl_Opportuntity_Create_Order, rau_Opportunity, pef_Internal, afl_Account_Get_new_debtor_number, rac_/rau_Account_Sync_to_Financial_System → must be identical afterwards.
2. `scr_Account_FinancialSystemSync` / `scr_Order_FinancialSystemSync`: prod deploys flows as Draft → activate both (Tooling PATCH FlowDefinition `activeVersionNumber` = 1). Only reachable via the admin-only buttons.
3. Verify: the two VRs inactive; all `Minut_FinancialSystem*` + `Day_FinancialSystemRateLimitCheck` steps `IsActive__c = false`; `Util_FinancialSystem.areTriggerHooksEnabled()` = false (anonymous Apex, read-only).
4. Rollback = redeploy prod's `rp_Account`/`rp_Order` (in `prodpkg` retrieve / git history) and deactivate the two screen flows; the rest is inert.

**Manual tests in prod = real production Exact (NL 1946773 / DE 67822 / UK 112143):**
- Contacts are **not** taken over: prod ACRs have no `FinancialIdContact__c` (backfill = switch-over step 1) → a new-code sync of an existing Exact account POSTs **new** contacts next to the legacy ones (duplicates, can't be deleted once used on invoices). Test with an account that is **not in Exact yet**, or backfill `FinancialIdContact__c` on that one test account first.
- Invoice/delivery address: taken over (Main of its type) – safe.
- Order button: creates a real Exact sales order (with the mapped warehouse; WH rows have no warehouse value yet → old sales-channel fallback) and **activates** the order.
- 3 hard (data) failures block the record and create a Case for `gqCaseAdministration<reseller>` (queues have no members yet) or a bell notification for an active owner.
- The legacy `rac_`/`rau_Account_Sync_to_Financial_System` + `Trigger_Account.syncToExact` stay active; they react to address/VAT/bank changes, not to the fields the new sync writes.

**Extra checks / caveats (2026-10-14)**
- Permission sets compared entry by entry with prod: 0 removed, only the new-field entries added (FinancialSystem_Admin +19, Subscription25_User +20, OrderManagement +1, ProductPricebookEntry_Admin +1), all other elements identical.
- The new screen flows / quick actions / invocables check no custom permission → a System Administrator can run them without extra assignments.
- **Right before the prod validation:** re-retrieve `rp_Account`, `rp_Order`, the 4 permission sets, `Util_System`, `Util_OAuth`, `Test_Exact` and `JobDispatcherStep.Minut_FinancialSystemOrderSync` from prod and diff them with the copies the package was built from (session scratchpad `prodpkg`; prod versions = the `src/` files minus the documented additions). Rebuild if anything changed.
- **acc dry run ≠ prod proof:** prod still has `rac_`/`rau_Account_Sync_to_Financial_System` active, `rbb_AccountContactRelation` v7 without `fSyncToFinancialSystem`, `rbb_Account` v66 without the new flagging. Tests that expect a flow-set flag pass in acc but may fail in prod → the prod `--dry-run` is the real check; a failing first round is possible.
- **Go-live note:** activating `Minut_FinancialSystemAccountSync` also switches on the trigger hooks, incl. the Contact-merge take-over (master ACR gets the loser's `extId_1..6__c` / Roles, or a new ACR). That changes ACRs the platform integrations read → re-run the REBEL/Horizon regression payloads at go-live.

**Prod validation 2026-10-14 (user: go)**
- Re-check before validating: prod `rp_Account`, `rp_Order`, the 4 permission sets, `Util_System`, `Util_OAuth`, `Test_Exact`, `Minut_FinancialSystemOrderSync` identical to the package base.
- Flow snapshot before (active = latest): afl_Account_Get_new_debtor_number 12, afl_Opportuntity_Create_Order 35, pef_Internal 1, rac_Account_Sync_to_Financial_System 3, rau_Account_Sync_to_Financial_System 7, rau_Opportunity 16, rbb_Account 66, rbb_AccountContactRelation 7, scr_Order_SyncToFinancialSystem 2.
- 1st validation `0AfTx0000013FA1KAM`: 83/83 compiled, 99/105 tests – failures were prod differences: 2 rate-limit tests (prod's `Test_Data.createAdministration` sets no Named Credential/company code → administration "not syncing"), 3 tests of flow behaviour (rab_Account_Debtor_Number, rbb_Account, rbb_AccountContactRelation – not in this package), plus the debtor-number assert in the full-sync test (rab flow).
- Fix (dev `0Afbd00000BfBh9CAF` + acc `0AfG500000T0SZtKAN`, 51/51): `Test_Util_FinancialSystem.admin()` sets Named Credential + company code itself; the 3 flow tests moved to the new **`Test_FinancialSystemFlows`** (ships with the flows at go-live – NOT in this package); debtor-number assert removed from the full-sync test (covered by `Test_rab_Account_Debtor_Number`).
- **2nd validation `0AfTx0000013FLJKA2`: Succeeded, 83/83, 102/102, no coverage warnings.** Quick deploy (within 10 days, only on the user's go): `sf project deploy quick -o prod --job-id 0AfTx0000013FLJKA2 --wait 30`, then the "After the deploy" steps above.

**DEPLOYED to prod 2026-10-14 (user: go) – quick deploy `0AfTx0000013Fd3KAE`, 83/83.**
- Flow snapshot after = before (all 9 active versions unchanged).
- `vr_FinancialDebtorNumberClear` + `vr_ERS_Classification_WH` inactive, `vr_FinancialSystemIdWarehouse` active.
- Dispatcher: every financial step inactive (AccountSync 10, ContactSync 20, OrderWarehouse 35, OrderSync 40 with BatchSize 10, Day RateLimitCheck 20); Activate/Dedupe/Stripe/ProcessPayments untouched (active).
- Triggers AccountContactRelation / ContactFinancialSystem / OrderFinancialSystem active but `Util_FinancialSystem.areTriggerHooksEnabled()` = **false** (checked with anonymous Apex) → no-op.
- **Open:** `scr_Account_FinancialSystemSync` (300Tx00000lLe7UIAS) and `scr_Order_FinancialSystemSync` (300Tx00000lLe7VIAS) are Draft v1 – activation was blocked for me (auto-mode classifier, prod) → user activates (Setup → Flows, or the Tooling PATCH below). Until then the admin-only buttons can't run.
  ```bash
  sf api request rest "/services/data/v67.0/tooling/sobjects/FlowDefinition/300Tx00000lLe7UIAS" --method PATCH --body '{"Metadata":{"activeVersionNumber":1}}' -o prod
  sf api request rest "/services/data/v67.0/tooling/sobjects/FlowDefinition/300Tx00000lLe7VIAS" --method PATCH --body '{"Metadata":{"activeVersionNumber":1}}' -o prod
  ```
