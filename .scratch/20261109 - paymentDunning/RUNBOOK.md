# Payment dunning + card expiry — RUNBOOK

Started 2026-11-09. Built and tested in **dev**; acc/prod not deployed yet (prod only on explicit command).

## What it does
Failed off-session payment (Type psp-recurring / psp-dd), driven by `Payment__c.Dunning_Step__c`:

| Step | When | What |
|---|---|---|
| Retry Planned | first temporary failure (insufficient funds, generic decline) | mail 1 `paymentRetryPlanned_*`; Batch_ProcessPayments retries once on `Retry_Date__c` (day 4, own idempotency key `-retry`) |
| Payment Requested | retry failed, or permanent failure / reversal / 3DS not confirmed | mail 2 `paymentFailedPay_*` or (Renew) `paymentFailedRenew_*`; link = pay-now PaymentIntent (dd + card/wallets, saves the method) |
| Final Notice | +5 days still open (or a new failure) | mail 3 `paymentFinalNotice_*`, suspension after `Suspension_Date__c` (+5), amount stays due |
| Suspension Case | +5 days still open | Case "Suspend service – failing payment – PM#…" in gqPayment<reseller>; the agent acts |

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
6. Check gqPayment<reseller> queues exist (dev has none → Case owner = running user).
7. Prod-only check: let the user allow a prod read of `stripeGC__Stripe_Event__c` failure bodies to confirm the real code/decline_code values against RENEW_CODES / PAY_CODES (acc only had `insufficient_funds/generic_decline` on bacs).

## dev log
- 2026-11-09 deployed; FLS 27 rows; e2e on TEST Teun card NL 2 with `pm_card_chargeCustomerFail`: batch decline → Retry Planned + mail 1 (NL) → webhook no change, no Case → retry (new PI) → Payment Requested + mail 2 → page pay-now PI created + reused → Final Notice + mail 3 → Suspension Case MI00234198. Account card restored (pm_1UXj8p…), pay-now PI canceled, payment PM#000110403 set Cancelled. Customer Hub republished.
- 2026-11-09 advisor review fixes: webhook restriction (+2 tests), Sub25 record Batch_CardExpiryCheck created in dev (a1Ybd000004gAdN; dev has no dispatcher schedule), dates render 13-11-2026 / "EUR 12,50" in NL mails, one card-expiry mail per account.
- SEPA pay-now e2e (TEST Teun sepa NL, IBAN NL39RABO0300065264 confirmed via API): 1st run found the stale-mandate bug; after the TypeJob fix the Account got pm_1UZqxW… + mandate_1UZqxW…, payment Paid. Account restored to pm_1UVAJw… / mandate_1UVAJw…. Test payments a1nbd00000sP1Ex, a1nbd00000sRZQn (Paid) stay in dev.
- Layout Payment__c-Payment: Dunning section deployed dev.

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
