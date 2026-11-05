# Runbook — FinSys invoice ids + Stripe payouts → Exact (prod)

Commits: 4f2153d (phase 1: invoice ids + Stripe metadata), cbede80 (phase 2: payout posting), 53353e7 (general journal: receivables G/L on debtor lines), 2a17287 (bank journal: receivables G/L on debtor lines; fee split processing + Radar).

## Status 2026-11-05: LIVE prod for UK, NL, DE

- `prod/` = the deployed package. Validated 0AfTx0000014nHhKAI (69/69: Test_Batch_FinancialSystemInvoiceIds, Test_Batch_ProcessPayments, Test_Svc_PaymentIntent, Test_Util_FinancialSystem_Invoice, Test_Util_FinancialSystemStripePosting, Test_Ctrl_Payment), quick deploy 0AfTx0000014nPlKAI.
  - Prod payment classes were equal to dev before 4f2153d (whitespace only). `Util_FinancialSystem_Invoice` was new in prod.
  - The two JobDispatcherStep records in `prod/` are **inactive**; activated afterwards from the repo copies (deploy 0AfTx0000014nWDKAY).
  - Admin profile: partial file with only the new field/object permissions.
- `prodperm.apex`: grants via DML (additive): ps_miSubscription25_User read (38 fields + 2 objects), miModifyAllData edit (38 fields). A permission set deploy would replace the whole set.
- Subscription25__Schedulable_Class__c records created: Batch_FinancialSystemInvoiceIds (20), Batch_FinancialSystemStripePostings (1).
- `ukids.apex`: data repair, Exact ids filled on the two UK invoices paid out since 2026-11-01 (GB26754787, GB26755137).
- UK Business Entity a3ETx000000cQ9ZMAU: journal 28 (General, VAT off), fee 470700, transit 100099, suspense 210000, PostingFrom 2026-11-01.
- First run (manual): FSP-000000 po_1UXVVd… → Exact 112143 entry 26280001 (debtor 146842 / 26755137 −15, fee 0.40, payout 14.60); FSP-000001 po_1UXsHU… → 26280002 (debtor 147491 / 26754787 −15, fee 0.24, payout 14.76). Suspense 0.

## Bank journal fix (NL) — 2026-11-05

- Exact also wants the receivables G/L on a debtor line of a **bank** entry ("Verplicht: Grootboekrekening"), not only on a general journal entry. Deployed prod 0AfTx0000014odZKAQ (10/10), commit 2a17287.
- NL connection user FinancialNC+1 got bank-entry create rights in Exact (UserHasRights: BankEntries POST true).
- NL Business Entity a3ETx000000cPztMAE: journal 28 (Bank), fee 470700, transit 100099, suspense 210000, PostingFrom 2026-11-01. Test run: posted 0, failed 0 (no NL payouts yet).

## Stripe fee split — 2026-11-05

- Question: entry 26280001 (Marc Stone, pi_3UVbSUGliYpbpuQB1tlYMaDH) books £0.40 fees, Stripe dashboard shows £0.24.
- Cause: Stripe bills **Radar** (£0.04 per screening) as separate daily `stripe_fee` balance transactions ("Radar (2026-10-28): Standard", no source, no link to a payment) and takes them from the next payout. Payout po_1UXVVd carried £0.20 processing + Radar 10-24, 10-28, 10-30, 11-01 (£0.20) = £0.40; bank got £14.60. Only Radar 10-28 (£0.04) is Marc Stone's. The booking was correct per payout; per payment it differs.
- Radar can't be attributed per customer: the API doesn't link it and the daily amounts don't follow the number of payments (11-02: 12 PaymentIntents, Radar £0.04).
- Change: fee line split into `Stripe processing fees po_…` (fees on the payments) + one line per separately billed Stripe fee with Stripe's description (`Stripe Radar (2026-10-28): Standard`), all on the fee G/L. Deployed prod 0AfTx0000014pMjKAI (10/10), acc 0AfG500000TOcBVKA1 (10/10), dev; commit 2a17287.
- Correction of booked entries (`feesplit.apex`; Exact API can't edit/delete an entry): journal 28, same dates, 470700 only:
  - **26280003** (2026-11-03, po_1UXVVd): −0.40 "Split Stripe fees po_1UXVVd…", +0.20 processing, +0.04 Radar 10-24, +0.04 Radar 10-28, +0.04 Radar 10-30, +0.08 Radar 11-01.
  - **26280004** (2026-11-04, po_1UXsHU): −0.24 "Split Stripe fees po_1UXsHU…", +0.20 processing, +0.04 Radar 11-02.
  - Both balance 0; 470700 total unchanged (0.64). 26280001/02 untouched. The 5 prod FinSysPostingLine__c Fee lines got the Stripe Radar descriptions.
- Explanation page: https://claude.ai/artifact/Kq7cyXnEZdxTiGVUi94GCK

## DE — 2026-11-05

- DE Business Entity a3ETx000000cQ7xMAE: journal 28 (Bank), fee **450200** (user; briefly 6855), transit 100099, suspense 210000, PostingFrom 2026-11-01 → posting ON. FinancialNC+5 has BankEntries POST rights.
- Not yet verified that 450200 exists in Exact DE 67822 (manual test run was blocked) → first check is the Day run 2026-11-06.

## Open

- [ ] Matching in Exact: invoice and Stripe payment stay two open items (net 0) → Finance matches, or automatic matching.
- [ ] Check the first automatic Day run (step 70) and the Minut step 55 (invoice ids, all countries, writes Stripe metadata).
- [x] NL / DE settings + bank-entry rights (see above).
- [ ] 2026-11-06: check Germany posting log after the Day run (no "G/L 450200 not found"); first NL/DE payouts when they come.
- [ ] Stripe fee G/L: UK + NL 470700, DE 450200; no own Stripe fee G/L yet. Finance: Radar on its own G/L?
