# Rest_UpsertContract deploy – prod

Prepared 2026-10-09. Nothing in this runbook has been run in prod yet. Every prod step needs an explicit go from Teun.

Manual (developer + key user, process flow): https://claude.ai/code/artifact/83d7b01c-0d5a-48cb-bb3c-3457eb3b9e0e

| Org | State on 2026-10-09 |
|---|---|
| dev | Everything committed (`841146a`, `f87361e`, `43d4aad`, not pushed). Tests: v1 26/26, v2 30/30 |
| acc | Same as dev (verified file by file against HEAD). `Rest_UpsertContractV2` added to `ps_miAPEXRestPointClasses`, reaches Platform Integration + Security Platform via `pg_miAPIPlatformIntegration` (verified). All test methods green after the deploy |
| prod | Original `Rest_UpsertContract` (pre-split), no v2, no `Batch_UpdateContractProductPrice`. CMDT `JobDispatcherStep.Day_UpdateContractProductPrice` already exists, **inactive** |

Two stages:
- **Stage 1 – v1** (`/UpsertContract`): may go on Teun's go.
- **Stage 2 – v2** (`/v2/UpsertContract`): **blocked** until the price data change in prod is done (user, 2026-10-08).

What v1 brings to prod (both termination processes, all platforms):
- terminationDate process derives `Termination_Method__c` from the dates; dates that fit no method → No Credit on `Subscription25__Current_End_Date__c` (never a credit).
- A call without dates clears the termination as before; it is **not** a revert (only `terminationId` `0` / Undo Termination reverse credits).
- Multiple base services: another **Activated** base service keeps the contract running (only this contract product is terminated/credited); the last one ends the contract on the **latest** base service date.
- Credit correction moved to `correctAndTerminate`; with a single base service the behaviour is unchanged.

---

## Org check 2026-10-09 (read-only, nothing deployed)

Retrieved from prod into the session scratchpad (not the repo) and compared with HEAD:

| Component | Prod vs HEAD | In this deploy |
|---|---|---|
| `Rest_UpsertContract` | prod = the pre-split original (HEAD adds the rules above) | stage 1 |
| `Test_Rest_UpsertContract` | prod is older (no generic termination/base service tests, no `testFirstOrderNegativeAdvanceScenario`) | stage 1 |
| `Util_PriceCalculation` | HEAD only adds `PRICE_CALCULATED_PLATFORMS = {'1','5'}` | stage 2 |
| `Rest_UpsertContractV2`, `Test_Rest_UpsertContractV2`, `Batch_UpdateContractProductPrice` | not in prod | stage 2 |
| `ps_miAPEXRestPointClasses` | repo file also lists `Rest_UpsertOpportunity` (dev only) → **do not deploy the repo file** | stage 2, from a retrieved prod copy |
| `Util_Rest`, `Util_System`, `Test_Data` | differ, but only by financial-system work | **not** in this deploy (v1/v2 only use methods prod already has) |
| `Trigger_Order` | prod lacks the 2026-08-06 Months_In_Advance invoice-date fix; HEAD = prod + only that fix (meta identical), in acc since 2026-10-07 | stage 1 (user 2026-10-09) |

### Resolved: `testFirstOrderNegativeAdvanceScenario`
Both test classes contain this test (added 2026-08-06). It asserts the `Trigger_Order` invoice-date fix, which prod did not have. Decision 2026-10-09: **`Trigger_Order` from HEAD goes along in stage 1** (it only adds that fix), with `Test_Orders` in the test run.

---

## Stage 1 – v1 (`/UpsertContract`)

### 1. Validate (check-only, nothing is changed; still needs a go: runs tests in prod)
```
sf project deploy validate --target-org prod \
  --manifest ".scratch/20261009 - deployRestUpsertContract/prod-v1/package.xml" \
  --test-level RunSpecifiedTests --tests Test_Rest_UpsertContract --tests Test_Orders
```
Expect: all methods pass, coverage `Rest_UpsertContract` ≥ 75% (dev 82%) and `Trigger_Order` ≥ 75%. Note the validation id.

### 2. Deploy (go from Teun)
Quick deploy of the validated id, or:
```
sf project deploy start --target-org prod \
  --manifest ".scratch/20261009 - deployRestUpsertContract/prod-v1/package.xml" \
  --test-level RunSpecifiedTests --tests Test_Rest_UpsertContract --tests Test_Orders
```
Multi-file deploys roll back completely when one file fails – check the result, not the "Changed" list.

### 3. Live checks (read-only, no test data in prod)
- Next platform calls succeed: `IntegrationAttempt__c`/log for `RestUpsertContract` shows no new errors (compare with the hour before).
- New terminations through the terminationDate process get a `Termination_Method__c` (Contract history, Platform Integration / Security Platform).
- New orders get the expected `Subscription25__Invoice_Date__c` (first order of a contract with a negative Months_In_Advance no longer shifts an extra month).
- No unexpected credit orders: compare the number of credit orders created by the integration users the day after with the 30-day average.

### Rollback
`prod-rollback/` holds the prod versions retrieved 2026-10-09 (metadata format: `Rest_UpsertContract`, `Test_Rest_UpsertContract`, `Trigger_Order`, `Util_PriceCalculation`):
```
sf project deploy start --target-org prod \
  --metadata-dir ".scratch/20261009 - deployRestUpsertContract/prod-rollback" \
  --test-level RunSpecifiedTests --tests Test_Rest_UpsertContract --tests Test_Orders
```
Stage 2 rollback: switch platforms 1/5 back to `/UpsertContract`, deactivate `Day_UpdateContractProductPrice`, redeploy `Util_PriceCalculation` from `prod-rollback/` (v2 classes can stay, nothing calls them).

---

## Stage 2 – v2 (`/v2/UpsertContract`) – BLOCKED until the price data change

Prerequisites:
- [ ] Price data change in prod done (Teun).
- [ ] Stage 1 deployed.
- [ ] Platform team ready to switch platforms 1 and 5 to `/services/apexrest/v2/UpsertContract`.

### 1. Validate
```
sf project deploy validate --target-org prod \
  --manifest ".scratch/20261009 - deployRestUpsertContract/prod-v2/package.xml" \
  --test-level RunSpecifiedTests --tests Test_Rest_UpsertContractV2 --tests Test_Util_PriceCalculation
```
Coverage in dev: `Rest_UpsertContractV2` 83%, `Batch_UpdateContractProductPrice` 97%, `Util_PriceCalculation` 90%.

### 2. Deploy classes (go from Teun) – same command with `deploy start`.

### 3. Permission set (same method as acc 2026-10-09)
Do **not** deploy the repo file (it lists `Rest_UpsertOpportunity`, not in prod). Retrieve prod's copy, add only `Rest_UpsertContractV2`, deploy that:
```
sf project retrieve start --target-org prod --metadata PermissionSet:ps_miAPEXRestPointClasses --target-metadata-dir <scratch>/psprod --unzip
# add <classAccesses><apexClass>Rest_UpsertContractV2</apexClass><enabled>true</enabled></classAccesses> after Rest_UpsertContract
sf project deploy start --target-org prod --metadata-dir <scratch>/psprod/unpackaged/unpackaged --test-level NoTestRun
```
Verify: `SetupEntityAccess` for `Rest_UpsertContractV2` shows `ps_miAPEXRestPointClasses` **and** `pg_miAPIPlatformIntegration` (group recalculation takes a minute). In prod the group is assigned to miFleet Platform, Platform Integration, Security Platform.

### 4. Platforms switch (platform team)
Platforms 1 and 5 call `/v2/UpsertContract`. Other platforms stay on v1. Watch the first calls: v2 adds `Skipped: no-op sync call …` for nightly no-op pings.

### 5. Nightly price refresh
Activate `JobDispatcherStep.Day_UpdateContractProductPrice` (`IsActive__c = true`; exists in prod, Day dispatcher, order 10). Only after platforms 1/5 are on v2 – v1 also sets `Update_Price_before_Renewal__c`, so the batch would otherwise reprice v1 contract products of platforms 1/5 too.
Check the first run: contract products with `Update_Price_before_Renewal__c = true`, renewing that day, platforms 1/5 → `Subscription25__Price__c` updated, no errors.

---

## Open / decisions
- [x] `testFirstOrderNegativeAdvanceScenario`: `Trigger_Order` HEAD goes along in stage 1 (2026-10-09).
- [ ] Go for stage 1.
- [ ] Stage 2 after the price data change.
- After a prod deploy: update the deployment status table in the manual.
