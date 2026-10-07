# Financial system deploy – acc and prod

Prepared 2026-10-06. Nothing in this runbook has been run yet.

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
- Dispatcher steps need **no** `Subscription25__Schedulable_Class__c` record.

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
6. Dispatcher go-live: `Batch_JobDispatcher.scheduleEvery5Minutes()`; then abort prod's **12 standalone `Batch_ActivateDraftContractProducts` CronTriggers** (by explicit Id) and the standalone Stripe reconcile schedule if any – only once the dispatcher actually runs.
7. Order sync is currently manual in prod (~500/week): agree with the user when the batch takes over.

### After go-live
- Exact flag backlog (247 BAG-corrected + 5 restored accounts) – parked by the user 2026-10-01.
- `Batch_SyncAccountEuropeTrack` (12 slots, 0 items in 30 days) – phase out candidate.

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
