# Payment dunning + card expiry — RUNBOOK

Started 2026-11-09. Built and tested in **dev**; acc/prod not deployed yet (prod only on explicit command).

## What it does
Failed off-session payment (Type psp-recurring / psp-dd), driven by `Payment__c.Dunning_Step__c`:

| Step | When | What |
|---|---|---|
| Retry Planned | first temporary failure (insufficient funds, generic decline) | mail 1 `paymentRetryPlanned_*`; Batch_ProcessPayments retries once on `Retry_Date__c` (day 4, own idempotency key `-retry`) |
| Payment Requested | retry failed, or permanent failure / reversal / 3DS not confirmed | mail 2 `paymentFailedPay_*` or (Renew) `paymentFailedRenew_*`; link = pay-now PaymentIntent (dd + card/wallets, saves the method) |
| Final Notice | +5 days still open (or a new failure) | mail 3 `paymentFinalNotice_*`, suspension after `Suspension_Date__c` (+5), amount stays due |
| Suspension Case | +5 days still open | Case "Suspend service – failing payment – PM#…" in gqCasePayment<reseller>; the agent acts |

- Permanent failure (expired/lost/stolen card, closed account, revoked mandate…, `Svc_PaymentDunning.RENEW_CODES`): no retry, saved method cleared from the Account (`Dunning_Action__c = Renew`), the customer renews via the link (pays right away, new details saved).
- No Cases for the early steps (webhook, batch decline, 3DS expiry, failed attempt on the page). Configuration errors and duplicate charges still get a Case.
- Webhook only treats a **collection** failure as dunning: `payment_intent.payment_failed` of the batch's off-session charge (no `setup_future_usage`), or a debit that was already accepted (Processing/Paid/Collected → fails/reversed later). A failed first checkout/setup on the payment page keeps the old Failed + Case.
- A direct debit method saved by a payment (pay-now SEPA) gets its own mandate: TypeJob reads `latest_charge.payment_method_details.<type>.mandate` (SEPA sends no mandate event; before the fix the Account kept the previous method's mandate).
- Paying (Processing/Paid) ends the cycle: the flows only act while Failed/Reversed on their own step.
- Card expiry: `Batch_CardExpiryCheck` (Day dispatcher, order 65) mails `paymentCardExpiring_*` when the saved card (re-read from Stripe) expires before an open payment's collection date; the page saves new details with a SetupIntent (nothing charged), the batch collects on the collection date. Wallet cards are skipped.

## Components
- Fields Payment__c: Dunning_Step__c, Dunning_Action__c, Retry_Date__c, Suspension_Date__c, Failure_Code__c, Card_Renewal_Requested__c, Card_Expires_Before_Collection__c (formula)
- Fields Account: PayProv_CardExpiry__c, PayProv_CardWallet__c
- Apex: Svc_PaymentDunning (new), Batch_CardExpiryCheck (new), Test_Svc_PaymentDunning (new); changed Svc_StripeEventProcessor, Batch_ProcessPayments, Svc_PaymentActionRequired, Svc_PaymentIntent, Ctrl_Payment, Test_Svc_PaymentActionRequired
- Flows (new): rab_Payment_Dunning_Retry_Planned / _Payment_Requested / _Final_Notice / _Suspension_Case
- Email templates (DirectDebit, NL/DE/EN): paymentRetryPlanned_, paymentFailedPay_, paymentFailedRenew_, paymentFinalNotice_, paymentCardExpiring_ (images as public file-asset URLs; `{[devName:…]}` refs don't deploy for new templates)
- LWC paymentPage (texts EN/NL/DE/FR, no Case on a failed page attempt in dunning)
- CMDT JobDispatcherStep.Day_CardExpiryCheck
- Layout Payment__c-Payment: new section **Dunning** (retrieve the org's own layout first and add the section — the repo copy is dev's)

## Deploy steps (per org)
1. `git status` first; deploy by file path (Payment__c object file is untracked: fields only).
2. Fields → Apex + tests → flows, templates, LWC, CMDT (same order as dev). Tests: Test_Svc_PaymentDunning + payment regression set (164 tests green in dev 2026-11-09).
3. FLS: anonymous Apex `fls.apex` (FieldPermissions insert: System Administrator + miModifyAllData read/edit, ps_miSubscription25_User read; formula read only). Prod: give the user a `!` command.
4. Data **before the CMDT deploy**: `Subscription25__Schedulable_Class__c` Name = Unique Name = `Batch_CardExpiryCheck` (Schedulable false, no cron: runs via the Day dispatcher). Without it the dispatcher's startStep throws and every later Day step is skipped. Count first: open card payments with unknown expiry = Stripe calls on the first run.
5. `sf community publish -n "Customer Hub"` (LWR serves the last-published paymentPage).
6. Check gqCasePayment<reseller> queues exist (dev has none → Case owner = running user).
7. Prod-only check: let the user allow a prod read of `stripeGC__Stripe_Event__c` failure bodies to confirm the real code/decline_code values against RENEW_CODES / PAY_CODES (acc only had `insufficient_funds/generic_decline` on bacs).

## dev log
- 2026-11-09 deployed; FLS 27 rows; e2e on TEST Teun card NL 2 with `pm_card_chargeCustomerFail`: batch decline → Retry Planned + mail 1 (NL) → webhook no change, no Case → retry (new PI) → Payment Requested + mail 2 → page pay-now PI created + reused → Final Notice + mail 3 → Suspension Case MI00234198. Account card restored (pm_1UXj8p…), pay-now PI canceled, payment PM#000110403 set Cancelled. Customer Hub republished.
- 2026-11-09 advisor review fixes: webhook restriction (+2 tests), Sub25 record Batch_CardExpiryCheck created in dev (a1Ybd000004gAdN; dev has no dispatcher schedule), dates render 13-11-2026 / "EUR 12,50" in NL mails, one card-expiry mail per account.
- SEPA pay-now e2e (TEST Teun sepa NL, IBAN NL39RABO0300065264 confirmed via API): 1st run found the stale-mandate bug; after the TypeJob fix the Account got pm_1UZqxW… + mandate_1UZqxW…, payment Paid. Account restored to pm_1UVAJw… / mandate_1UVAJw…. Test payments a1nbd00000sP1Ex, a1nbd00000sRZQn (Paid) stay in dev.
- Layout Payment__c-Payment: Dunning section deployed dev.

## acc log
- 2026-11-10 deployed: 9 fields, FLS 27 rows, Apex (135 payment tests green, incl. Util_FinancialSystemStripePosting fix), 4 flows (active), 15 templates, paymentPage/paymentCheckout/paymentProvider, Sub25 record Batch_CardExpiryCheck (a1YG5000004VX2DMAW) before CMDT Day_CardExpiryCheck, layout (acc's own + Dunning section), Customer Hub republished. 0 open card payments for the first expiry run. No gqCasePayment queues in acc (same as before: Case owner = running user).
- e2e TEST Teun card NL (001G500001UqbEbIAJ) with pm_card_chargeCustomerFail: PM#000136974 (a1nG500000ihTGfIAM) → Retry Planned 14-11 + mail paymentRetryPlanned_EN (payment had no Contact → EN), no Case → retry (Retry_Date set to today) new PI → Payment Requested + paymentFailedPay_EN → page: pay-now card PI, reused on reload. Account card restored to pm_1UVY4A…. Payment left open as acc demo (token eedfc96dbb2ab572c00d016bc01a4319): Final Notice ~11-15, Suspension Case ~11-20 unless paid/cancelled.

## 2026-11-10 change: iDEAL | Wero on Pay saves its SEPA mandate (user)
iDEAL | Wero comes with a SEPA direct debit approval, so the Pay link now sets payment_method_options[ideal][setup_future_usage]=off_session and TypeJob.payNowMethod saves the charge's generated_sepa_debit + generated_sepa_debit_mandate on the Account (type sepa_debit). Old pay-now intents without it are replaced on the next visit (savesIdeal). Texts: page dunningPayText (EN/NL/DE/FR) + paymentFailedPay_* — card and iDEAL | Wero (SEPA approval) saved, bank transfer only this invoice. Deployed dev + acc (81 tests green), both hubs republished; acc demo PM#000136974 intent refreshed.

- acc iDEAL | Wero e2e by user (PM#000136974): Paid; Account got generated SEPA pm_1UaDCO… + mandate_1UaDCO… (active, multi_use, online acceptance). TEST Teun card NL now has SEPA instead of its card (pm_1UVY4A…).
- Consent checkbox (paymentCheckoutHtml) follows the method picked in the Payment Element. User (same day): a saved card needs consent too → shown + required for every saved method (direct debit, card, wallets, iDEAL), hidden only for bank transfer (customer_balance, one-off) and 3-D Secure confirmation (authenticate); iframe ?v=19. Deployed dev + acc, republished. acc demos: PM#000136975 Pay (token cb8b9ace9a0387140a64fa635d07129b), PM#000136976 Renew (token d71d5da3d8d6b3c28bb45778f425ae65).

- acc demos closed 2026-11-10: PM#000136976 Cancelled (PI canceled); PM#000136975 was already Paid by the user (my cancel overwrote it to Cancelled, restored to Paid within the hour). TEST Teun card NL now holds SEPA pm_1UaDRV… + mandate_1UaDRV… (from the user's test payments).
- Key-user manual (536f1973) updated: iDEAL | Wero saves its SEPA mandate, consent checkbox rule, return screen after the bank.

## Prod check 2026-11-10 (prod_check.apex, run by user)
- Live Stripe: NL acct_1S3wZf… card/Apple Pay/iDEAL/SEPA active, **bank transfer (customer_balance) not active**; DE acct_1S3wcn… **card only** (no SEPA, iDEAL, bank transfer); UK acct_1Ro22z… card/Apple Pay/Bacs, **no bank transfer**.
  → as built, every Pay link (offers customer_balance) and a DE Renew link (offers sepa_debit) would fail to create the PaymentIntent in prod.
- Failure codes (4 events, last year): authentication_required (1), payment_intent_authentication_failure (3) — both in PAY_CODES.
- **No gqCasePayment queues in prod** → suspension Case owner = running user (scheduled flow = Automated Process). Stripe customers: only reseller 6 (UK, 56 accounts).

- User: bank transfer switched on in Stripe (NL, UK) — re-run prod_check.apex before the prod deploy to confirm. DE: Wero (not iDEAL) and SEPA to be activated by Floris (identification on the DE Stripe account).
- Fallback (Svc_PaymentIntent.createWithActiveTypes): a type the Stripe account refuses ('The payment method type "x" is invalid') is left out with its options and the create retried (card never); pay-now / renewal intents. Pay-now reuse accepts an intent offering a subset of the wanted types. Deployed dev + acc (102 tests green).
- Queues gqCasePayment1 (NL), gqCasePayment3 (BE), gqCasePayment5 (DE), gqCasePayment6 (UK) — Case, no members yet — deployed dev + acc; **include in the prod deploy** and add members in prod. Test_Ctrl_PaymentCase reuses an existing gqCasePayment1.
- 2026-11-10 renamed gqPayment* → gqCasePayment* (naming like gqCaseAdministration*); dev + acc deployed, old queues deleted (destructive), 59/59 tests. The prefix is also used by Batch_ProcessPayments, Svc_StripeEventProcessor and Ctrl_PaymentCase (live in prod) — **deploy those together with the queues to prod**.
- 2026-11-10 queue members (dev + acc, in the queue metadata): gqCasePayment1 NL, gqCasePayment3 BE, gqCaseAdministration1 NL → guAftersalesNL + guFinanceNL; gqCasePayment5 / gqCaseAdministration5 DE → guAftersalesDE + guFinanceDE; gqCasePayment6 / gqCaseAdministration6 UK → guAftersalesUK + guFinanceUK. No individual users (Maruan removed). **Prod: a queue deploy REPLACES its members, and gqCaseAdministration1/5/6 are live in prod** — before the deploy run `! sf data query -o prod -q "SELECT Group.DeveloperName, UserOrGroupId FROM GroupMember WHERE Group.DeveloperName LIKE 'gqCaseAdministration%' OR Group.DeveloperName LIKE 'gqCasePayment%'"` and add any member that is not one of these groups to the metadata first (or agree it may go).

## prod log
- 2026-11-10 user go. Prod versions of all changed classes/LWC/static resource = repo before 75de552 (whitespace only), so the deploy carries dunning commits only.
- Validated 0AfTx0000015DC9KAM (127/127 tests: Test_Batch_ProcessPayments, Test_Ctrl_Payment, Test_Svc_PaymentDunning, Test_Ctrl_PaymentCase, Test_Svc_PaymentActionRequired, Test_Svc_PaymentIntent, Test_Svc_StripeEventProcessor, Test_Batch_ReconcileStripeEvents, Test_Batch_ReconcileProcessingPayments, Test_Batch_FinancialSystemInvoiceIds, Test_Util_FinancialSystemStripePosting), quick-deployed 0AfTx0000015DGzKAM: 9 fields, 13 classes (incl. Util_FinancialSystemStripePosting), 4 flows, 15 templates, paymentPage/paymentCheckout/paymentProvider, prod's own Payment__c layout + Dunning section, queues gqCasePayment1/3/5/6 (after sales + finance groups). Staging copy in the session scratchpad (Jest __tests__ removed: no .forceignore there).
- Flows landed Draft → activated v1 via tooling FlowDefinition (all 4 Active). Customer Hub republished.
- gqCaseAdministration1/5/6 deployed to prod on user request (2026-11-10): individual users replaced by the groups (after sales + finance per country). Previous members saved in prod_admin_queues_before_2026-11-10/. Active users who were direct members and are not in the groups (no longer queue members): NL Bas Vink, Guy Mooyman, Jonas Maassen, Martin Hunen, Paul Schuttevaer, Rob Groenen, Ron Plomp, Robert Kekem, Roxanne Vogelzang, Sylvana Geeve, Tom Beekmans; DE Arndt Bachmann, Matthias Kühnel, Sascha Hribar; UK Amanda Smith, Laura Wilson, Matt Abery, Sarah Bateman.
- 2026-11-10 user ran fls.apex (27 rows, 3 sets) and sub25_record.apex (record created; 0 open card payments for the first expiry run); CMDT JobDispatcherStep.Day_CardExpiryCheck deployed (Day, order 65, active). **Prod rollout complete.** prod_check re-run 17:08: bank transfer (customer_balance) available + on for NL and UK; DE still card + Apple/Google Pay only (fallback leaves the rest out); 4 gqCasePayment queues present. Remaining: Later items below.

## Post go-live actions 2026-11-10 (prod)
- Open payments checked: no Failed / Reversed psp payments in prod. 23 Processing (all bacs_debit, collection 11-05 → 11-20), 14 Setup (10 Mail Sent since 10-29, 4 Awaiting Invoice Email), 1 New, 1 Action Required.
- 9 escalation Cases "Direct Debit Escalation — No Authorisation Received" (MI00433087/088, MI00433596/597/598/599, MI00434912/913, MI00435443; 11-04 → 11-09) were owned by Teun (no queue then) → moved to gqCasePayment6 (Case - Payment (UK)) on user request. (Correction 11-11: they did NOT go to the queue: rab_Payment_Direct_Debit_Escalation created the Case without OwnerId → running user. MI00436017 (Karl Davis, 11-10 22:29) also landed on Teun; it and 1 older open UK escalation Case moved to gqCasePayment6 on 11-11.) Setup payments without a method are not collected and never enter the dunning cycle: the escalation Case + call is the only follow-up.
- PM#000207118 (jason robertson, first payment, 3DS not confirmed on the page since 11-09): on user request expired early via Svc_PaymentActionRequired.run(step 'expire') → Failed, Payment Requested, action Pay, code authentication_required; mail "Your payment is still outstanding – PM#000207118" sent 16:37 to jason_robertson@btinternet.com, no Case. The D+7 path (11-16) is a no-op now. Next if unpaid: Final Notice ~11-15, Suspension Case ~11-20 in gqCasePayment6. (Check plan dates for this payment move 5-6 days earlier.)
- PM#000211638 (C J Blinco, New, collection 11-06, has PM + mandate) waits for its invoice email: I-2611-00785740 PENDING. Part of 3,711 UK invoices of the 11-08 run still PENDING (only 1 invoice mail sent on 11-10 vs 765 on 11-09); Job_FinalizeInvoicesInExact is working through them. User is on it.
- Exact rate limits 11-10 16:35 (Administration fields, reset 11-11 00:00 UTC): UK 4,580 / 5,000 left (~420 used), NL 192,416 / 200,000, DE 4,970 / 5,000. FinancialRateLimitMaxPercentage__c empty → 90% default (~4,500 UK calls/day). No 429 / rate-limit messages in 224 error/warning Event_Logs of the last 3 days (top errors: invalid VAT numbers 61, Invoice address Forbidden 23, invalid bank account 11). The UK backlog is not limited by Exact.

## 2026-11-11 fix: escalation Case owner (rab_Payment_Direct_Debit_Escalation)
- D+6 escalation Case now gets OwnerId = fCaseOwnerId = BLANKVALUE(vQueueId, $User.Id); vQueueId from Get Payment Queue (Group Type Queue, DeveloperName fQueueName = 'gqCasePayment' & TEXT(Account.Reseller_Name__c)). Same queue rule as Ctrl_PaymentCase / Batch_ProcessPayments / Svc_PaymentDunning.
- Deployed dev (active v4) + acc (active v3) 2026-11-11. Not runtime-tested (D+6 scheduled path); deploy-validated only.
- **Prod: open, needs the user's go.** Until then every new escalation Case lands on the running user → move it to gqCasePayment<reseller> (Jonathan Stockdale PM#000207173 expected ~11-13). Prod: flow lands Draft → activate via FlowDefinition.
- Manuals updated 11-11 for the post go-live changes: Stripe key-user (escalation Case in the payment queue, Setup payments not collected / no follow-up, "ask the administrator to send the link sooner", change row 2026-11-11 dev+acc), Stripe developer (escalation owner in process step + flow row, 2 procedures: early expire via Svc_PaymentActionRequired.run step 'expire', moving Cases to the queue; change row 2026-11-11), generic manual Finance → Payments (escalation in the queue, Setup follow-up), Financial System Sync developer (Exact limits stored 11-10: NL 200,000, UK 5,000, DE 5,000). Open question: that manual still says Exact DE sends no rate-limit headers (assumed 10,000), but DE now has Daily_Limit__c 5,000 stored.

## Go-live check plan (prod, read-only: dunning_monitor.apex)
Prod volume is low (UK only, 56 Stripe customers; 15 collections 11-12 → 11-23), so the checks follow the first real cases:
| Date | What to see |
|---|---|
| ~~2026-11-16~~ done early 11-10 | PM#000207118 (jason robertson, UK, Action Required since 11-09 08:09 UTC) expires: Failed, step Payment Requested, action Pay, mail paymentFailedPay_EN, **no Case**; its link offers card / Apple Pay / Google Pay / bank transfer |
| 2026-11-19 | Bacs results of the 11-12 / 11-13 collections (~6 days): a failure → Retry Planned + mail 1, retry date +4, no Case; or Payment Requested for a permanent code (action Renew, method cleared) |
| 2026-11-15 | PM#000207118 (mail 2 sent early on 11-10) still open → Final Notice + mail 3, suspension date set |
| 2026-11-23 / 24 | first retries run (new PI, own -retry key); result back via webhook |
| 2026-11-20 | PM#000207118 still open → Case "Suspend service – failing payment – PM#000207118" owned by queue gqCasePayment6 (After sales UK + Finance UK) |
Each check: `sf apex run -o prod -f ".scratch/20261109 - paymentDunning/dunning_monitor.apex" | grep CHECK`. Also watch "outside cycle" (Failed without a step) and payment Cases other than Suspend service / configuration / charged twice. Side note: PM#000207118 has Collection Date 11-20 although charged 11-09 (date moved after the charge?) — look at it on 11-16.

## Later (user, 2026-11-10)
- Stripe payment-method activation and checks: owned by Floris (user, 2026-11-10), no further checks from us.
- **DE Wero**: once Floris has activated it on the DE Stripe account, offer Wero on the DE Pay link (payNowTypes now offers iDEAL for NL only).
- **Renew with iDEAL | Wero in Wero countries (NL…)**: offer iDEAL on the Renew link, but only together with a SEPA direct debit mandate (iDEAL payment + generated SEPA PM/mandate saved as the recurring method). Not built.

## Open before prod
- Exact posting (checked 2026-11-10): no double post, but Util_FinancialSystemStripePosting matches a balance transaction to Payment__c only by the CURRENT PayProv_PaymentIntentId__c. Retry and pay-now put a new PI on the payment, so a later reversal (payment_failure_refund / dispute) of the old PI lands on Suspense ('No Salesforce payment for pi_…') while the pay-now charge closes the invoice again → invoice looks paid twice in Exact, reversal sits in suspense. FIXED 2026-11-10: addEarlierIntents — unmatched PI → GET the PI, match via metadata[PaymentID] (max 20 lookups per transaction, rest stays suspense). Deployed dev, Test_Util_FinancialSystemStripePosting 11/11 + Test_Svc_PaymentDunning green. **Util_FinancialSystemStripePosting is LIVE in prod (UK+NL): include it in the acc and prod deploys.**
- Browser check of the page texts (LWC never rendered by me; Node lint broken locally).
- Manuals: Stripe Payments key-user (536f1973) + developer (d0e930cc), Payment Methods docs, generic manual Finance → Payments.

## dev demo payments (for the user's browser check, 2026-11-09)
- PM#000110406 Retry Planned (card NL 2) — token c8fae308179d506307b7ab923c5d85e6
- PM#000110407 Payment Requested / Pay (card NL 2) — token cc95c14ff1b96279720cf7ac94b4cf44
- PM#000110408 Payment Requested / Renew (googlepay NL, no method) — token 3f7c5e8926240c5edf49d26a1ac5dcd6
- PM#000110409 renewCard (New, card NL 2 expiry set to today+20) — token e945e59ea852f550885a9bb45f98be5f
They advance by themselves in dev (+5/+6 days → mail 3, suspension Cases). Later fixes: paid-after-suspension note on the Case, mail problem noted in the Case (167 tests green).

## 2026-11-09 change: pay-now methods (user)
Pay-now link = card (+ Apple/Google Pay), iDEAL (EUR + billing country NL) and bank transfer (`customer_balance`, eu_bank_transfer country = billing country if BE/DE/ES/FR/IE/NL else NL; gb_bank_transfer for GBP). No SEPA/Bacs. Card saved; iDEAL saves its generated SEPA PM + mandate (TypeJob payNowMethod); bank transfer saves nothing; page shows Stripe's hosted instructions (also on revisit). Pay-now webhooks never write the PM to the Account directly (TypeJob decides). Old pay-now intents with other methods are canceled + recreated on the next visit. 172 tests green; dev demo PIs now card/ideal/customer_balance.
**Before acc/prod:** check that iDEAL and bank transfers (customer balance) are activated on the live Stripe accounts NL/DE/UK — dev test mode accepts them, live mode may need activation.
- Update (user, same day): **Renew** = renewal of the recurring method → PI with business entity dd method + card, top-level setup_future_usage; no iDEAL / bank transfer. **Pay** = card + iDEAL + bank transfer; only card saved (iDEAL one-off, no generated SEPA). TypeJob payNowMethod: card → itself; sepa/bacs → PM + charge mandate; iDEAL/customer_balance → nothing.
- iDEAL "nothing happens" fix: Stripe.js needs a return_url and redirects inside the iframe (banks refuse framing). The iframe now uses confirmIdealPayment(..., {handleActions:false}) and posts `providerRedirect` → paymentCheckout opens the bank page in the whole window; return_url = the payment link (window.location.href). iframe `?v=17`. 173 tests green; dev republished.
- 2026-11-09 browser test by user: iDEAL (Wero) on PM#000110407 → bank page in full window → back on the link; PI succeeded (ideal), payment Paid, saved card pm_1UXj8p… unchanged. Renew link (PM#000110408) not tested yet.
- Return message fix: paymentPage reads `redirect_status` from the return URL → succeeded/processing shows "Payment received" (not "already completed"); failed shows a warning above the checkout. Deployed dev + republished; not browser-checked yet.
