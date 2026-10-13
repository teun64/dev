# Batch_ProcessPayments + rbb_Payment fix — deploy runbook (2026-10-13)

Dev: done and deployed. acc/prod: not deployed (blocked by Claude Code permission, needs the user).

## Components
- flows/rbb_Payment.flow-meta.xml: Business Entity lookup via explicit outputReference; timing no longer wiped on update; psp-dd collection date in working days (weekend due date → Friday first); I0 and other types unchanged
- classes/Batch_ProcessPayments.cls + Test_Batch_ProcessPayments.cls (replaces Batch_ProcessSetupPayments)
- customMetadata/JobDispatcherStep.Minut_ProcessPayments.md-meta.xml (Minut, Order 60, BatchSize 20)
- classes/Batch_JobDispatcher.cls + Test_Util_JobDispatcher.cls (schedule methods skip existing jobs → no more test collision with live schedules)
- destructiveChanges.xml (this folder): delete Batch_ProcessSetupPayments

## acc
```
D=force-app/main/default; R=".scratch/20261013 - processPayments"
sf project deploy start -o acc -d $D/flows/rbb_Payment.flow-meta.xml -d $D/classes/Batch_ProcessPayments.cls -d $D/classes/Test_Batch_ProcessPayments.cls -d $D/classes/Batch_JobDispatcher.cls -d $D/classes/Test_Util_JobDispatcher.cls -d $D/customMetadata/JobDispatcherStep.Minut_ProcessPayments.md-meta.xml --post-destructive-changes "$R/destructiveChanges.xml" --test-level NoTestRun
sf apex run test -o acc -n Test_Batch_ProcessPayments,Test_Util_JobDispatcher -w 10
sf data create record -o acc -s Subscription25__Schedulable_Class__c -v "Name=Batch_ProcessPayments Subscription25__Unique_Name__c=Batch_ProcessPayments Subscription25__Batch_Size__c=20"
```
Business_Entity__c FLS already granted in acc (2026-10-13).
⚠ Day dispatcher in acc: Day_UpdateContractProductPrice + Day_FinancialSystemRateLimitCheck are ACTIVE → decide before scheduleDaily() there.

## Status 2026-10-13
- acc: DEPLOYED (old class deleted), Schedulable_Class record created, 18/18 tests, coverage Batch_ProcessPayments 88% / Batch_JobDispatcher 100%, dispatcher runs the step with 0 errors.
- prod: first deploy attempt rejected by Salesforce (repo Test_Util_JobDispatcher references Batch_FinancialSystemAccountSync, not in prod) → nothing changed. Use prod_mdapi/ (prod test variant, step INACTIVE):
```
sf project deploy start -o prod --metadata-dir ".scratch/20261013 - processPayments/prod_mdapi" --test-level RunSpecifiedTests --tests Test_Batch_ProcessPayments --tests Test_Util_JobDispatcher -w 60
```

- prod 2026-10-13 ~15:20 UTC: DEPLOYED by user (17/17 tests, old class deleted). Schedulable_Class record created. Eligible = only PM#000205903 (14-10). Day dispatcher scheduled (next 22:13 UTC = 00:13).
- prod OPEN (blocked for Claude): (a) activate rbb_Payment **v9** (deployed as Draft, v8 still active); (b) activate Minut_ProcessPayments step:
  `sf project deploy start -o prod -d force-app/main/default/customMetadata/JobDispatcherStep.Minut_ProcessPayments.md-meta.xml --test-level NoTestRun`
- Backfill dry run (prod, rolled back, 53 sampled across all buckets): no errors, BE not set (v8 still active), and EVERY update overwrites Processing_Date__c with now (rbb_Payment dec_01_Processing_Date: set when not changed itself) → decide before backfill.

- prod DONE ~15:40 UTC: rbb_Payment v9 active (user), Minut_ProcessPayments step active (deploy needs RunSpecifiedTests in prod, NoTestRun is refused), first round 15:40 completed 0 errors.
- Backfill DONE: dry run 53/53 BE only (Processing_Date +1 s), then 12 chunks of 400 → 4,695/4,695 payments since 2026-09-29 have Business_Entity__c, 0 errors.
- CHECK 2026-10-14: PM#000205903 → Processing with PaymentIntentId__c (first run from 01:00 CEST); Day dispatcher ran Batch_DedupeCommunicationPreferences ~22:13 UTC.

## prod (on go-ahead)
1. Business_Entity__c FLS is already correct in prod.
2. Create the Schedulable_Class record FIRST (otherwise every Minut round fails at ReconcileStripeEvents.finishBatch → constructor).
3. Deploy with the step set to IsActive__c=false, RunSpecifiedTests: Test_Batch_ProcessPayments, Test_Util_JobDispatcher (validate → quick deploy). Include destructiveChanges.xml.
4. Eligible check — expect only PM#000205903 (collection 14-10):
   `SELECT Name, Status__c, Collection_Date__c FROM Payment__c WHERE Type__c='psp-dd' AND Status__c IN ('New','Setup') AND Payment_Batch__c = null AND Collection_Date__c <= TODAY AND Account__r.PayProv_CustomerId__c != null AND Account__r.PayProv_PaymentMethodId__c != null AND Account__r.PayProv_MandateId__c != null`
5. Activate the Minut_ProcessPayments step.
6. Day dispatcher (00:13; only Dedupe active in prod): anonymous Apex `Batch_JobDispatcher.scheduleDaily();` → check the CronTrigger 'GoMeddo Subscription - Batch_JobDispatcher - Day - 0 13 0 * * ?'; next morning check for an AsyncApexJob of Batch_DedupeCommunicationPreferences around 22:13 UTC.

## Business_Entity__c backfill (prod, after step 3)
Scope: payments created since 2026-09-29 18:35 UTC (4,691, 0 with BE). An update runs all of rbb_Payment, so:
1. Rolled-back before/after diff on a sample from each bucket (fs-dd/I0 New 4,196; psp-immediate p0/p1; psp-dd), comparing all fields.
2. If only Business_Entity__c changes → set Business_Entity__c directly (map Administration__r.Reseller__c → Business_Entities__c.Reseller__c), in chunks of 200.
3. Any other field changes (Collection_Date, Payment_Batch, Type, Status) → stop and report.

## Open
- Dev live Stripe run (job 707bd00001Z1wVu; PM#000110373/374 Darran Hiscox, PM#000110303 Brian Gourlay): result not checked (permission). Expect 373/374 Processing with a PaymentIntentId, 303 Failed + Case. Rerun with one reset to New → same PI id = idempotency works.
- Dev Day dispatcher: not scheduled (same active steps as acc).
