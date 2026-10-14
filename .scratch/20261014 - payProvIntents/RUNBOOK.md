# Release 2 — PayProv_ intent fields, intent reuse, duplicate detection (2026-10-14)

dev ✓ (38/38, live: UK PaymentIntent created upfront by flow+queueable and reused on page loads; NL SetupIntent created once, reused),
acc ✓ (fields, FLS mirrored, code, flow, layout; 42/42). prod: blocked for Claude → user.

## Status 2026-10-14
- prod DONE: deploy 38/38 (commit 7f1e66f), afl_Payment_Direct_Debit_Setup v5 activated (tooling FlowDefinition PATCH),
  FLS PayProv_SetupIntentId__c = PayProv_PaymentIntentId__c (6 grants), layout deployed.
- Migration DONE for the 3 current payments only: PM#000196930, PM#000205903 (C J Blinco), PM#000201568 (Marc Stone → pi_3UNEnb…,
  the real checkout; the two 07-10 duplicates were refunded by the user). The 13 legacy p1 rows (Nov/Dec 2025) were NOT migrated:
  user thinks they can be deleted — awaiting confirmation.
- C J Blinco: the 6 canceled PaymentIntents of 04-10 (reason "duplicate") were canceled manually in the Stripe dashboard by the user.
- Stripe check of all 16 stored intents (2026-10-14): 13 match. PM#000149538 (Ian Ross) and PM#000154553 (Paul Wild): Stripe
  intent canceled but SF Paid is correct — paid via Opayo (Processor__c=Opayo + Opayo reference); the Stripe intent was an
  abandoned attempt. PM#000149534 (Spinney Flintshire, £4,074, opp "order 28.11.25" Closed Won, no other payment!) and
  PM#000149715 (test opp) were New in SF, canceled in Stripe (canceled_at 2026-10-14 11:15/11:35 UTC, manual dashboard) →
  set to Cancelled with Processing_Date = canceled_at.
- dev: 6 unused dev-only PayProv_ fields removed from the dev layout and deleted (recycle bin 15 days).

## prod
1. Deploy (fields + code + flow):
   sf project deploy start -o prod -d force-app/main/default/objects/Payment__c/fields/PayProv_PaymentIntentId__c.field-meta.xml -d force-app/main/default/objects/Payment__c/fields/PayProv_SetupIntentId__c.field-meta.xml -d force-app/main/default/classes/Svc_PaymentIntent.cls -d force-app/main/default/classes/Test_Svc_PaymentIntent.cls -d force-app/main/default/classes/Ctrl_Payment.cls -d force-app/main/default/classes/Test_Ctrl_Payment.cls -d force-app/main/default/classes/Batch_ProcessPayments.cls -d force-app/main/default/classes/Test_Batch_ProcessPayments.cls -d force-app/main/default/classes/Svc_StripeEventProcessor.cls -d force-app/main/default/classes/Test_Svc_StripeEventProcessor.cls -d force-app/main/default/flows/afl_Payment_Direct_Debit_Setup.flow-meta.xml --test-level RunSpecifiedTests --tests Test_Svc_PaymentIntent --tests Test_Ctrl_Payment --tests Test_Batch_ProcessPayments --tests Test_Svc_StripeEventProcessor -w 40
   (also deploys the already-committed Util_StripeEvent refactor of Svc_StripeEventProcessor, af49bad, never in prod before)
2. Activate the new version of afl_Payment_Direct_Debit_Setup (prod deploys land as Draft).
3. FLS: copy PayProv_PaymentIntentId__c grants to PayProv_SetupIntentId__c (flsmirror script, as in dev/acc).
4. Layout: sf project deploy start -o prod --metadata-dir ".scratch/20261014 - payProvIntents/layout_accprod" --test-level RunSpecifiedTests --tests Test_Ctrl_Payment
5. Migration: migrate.apex with DRY=true → only PayProv_PaymentIntentId__c (and Processing_Date +1 s) may change → DRY=false.
   16 rows: 13 legacy ProviderPaymentIntentID__c (p1, Nov/Dec 2025), PM#000196930, PM#000205903, PM#000201568 (Marc → pi_3UNEnb…).

## Old fields DELETED 2026-10-14 (dev 2, acc 7, prod 7; prod 38/38 tests)
- Before deletion: no Data Cloud stream on Payment__c (dev/acc/prod), no metadata dependencies left; remaining values migrated to
  PayProv_PaymentIntentId__c (prod: 13 legacy ProviderPaymentIntentID__c rows — rbb_Payment also filled the empty Type__c
  (psp-immediate) and Business_Entity__c on 11 of them; dev: 6 test payments).
- Cancelled PM#000149534 / PM#000149715 kept: both linked to an opportunity (149534 also to activated Order 01953695).
- Repo: field files removed, grants removed from ps_miPaymentCheckout (and from the untracked ps_miAPIPlatformIntegration file).

## (was) Later: delete old fields
PaymentIntentId__c, SetupIntentId__c, ProviderPaymentIntentID__c, ProviderPaymentMessage__c, ProviderPaymentStatus__c,
ProviderPaymentType__c, Provider_Dashboard_Link__c (+ their grants in ps_miPaymentCheckout / ps_miAPI*). Check Data Cloud
Payment__c stream mappings first. Do NOT touch stripeGC__Stripe_Event__c.PaymentIntentId__c / SetupIntentId__c (different object).

## Open checks
- Reminder stop: PM#000110385 (dev, 'Mail Sent' 2026-10-14) should get its D+2 reminder; flip a second record to see the scheduled path cancel.
- Batch cancel path TESTED dev 2026-10-14: PM#000110387 (Darran Hiscox, mandate) with stored open intent pi_3UQQsI… →
  batch canceled it (reason abandoned) and created exactly one off-session intent pi_3UQQsV… (succeeded); payment Processing
  with the new id; no Cases. Webhook leg NOT tested: dev receives no Stripe webhook events since 2026-07-01 (last
  stripeGC__Stripe_Event__c), so payment stays Processing in dev. Test the webhook leg in acc if needed.
- dev-only leftover Payment fields: PayProv_Message__c, PayProv_Mode__c, PayProv_PaymentIntentStatus__c, PayProv_SetupIntentStatus__c, PayProv_SetupNeeded__c, PayProv_DirectDebitSetup__c (not in repo/acc/prod).
