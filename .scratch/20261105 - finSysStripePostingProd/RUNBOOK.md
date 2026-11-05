# Runbook — FinSys invoice ids + Stripe payouts → Exact (prod)

Commits: 4f2153d (phase 1: invoice ids + Stripe metadata), cbede80 (phase 2: payout posting), 53353e7 (general journal: receivables G/L on debtor lines).

## Status 2026-11-05: LIVE prod for UK

- `prod/` = the deployed package. Validated 0AfTx0000014nHhKAI (69/69: Test_Batch_FinancialSystemInvoiceIds, Test_Batch_ProcessPayments, Test_Svc_PaymentIntent, Test_Util_FinancialSystem_Invoice, Test_Util_FinancialSystemStripePosting, Test_Ctrl_Payment), quick deploy 0AfTx0000014nPlKAI.
  - Prod payment classes were equal to dev before 4f2153d (whitespace only). `Util_FinancialSystem_Invoice` was new in prod.
  - The two JobDispatcherStep records in `prod/` are **inactive**; activated afterwards from the repo copies (deploy 0AfTx0000014nWDKAY).
  - Admin profile: partial file with only the new field/object permissions.
- `prodperm.apex`: grants via DML (additive): ps_miSubscription25_User read (38 fields + 2 objects), miModifyAllData edit (38 fields). A permission set deploy would replace the whole set.
- Subscription25__Schedulable_Class__c records created: Batch_FinancialSystemInvoiceIds (20), Batch_FinancialSystemStripePostings (1).
- `ukids.apex`: data repair, Exact ids filled on the two UK invoices paid out since 2026-11-01 (GB26754787, GB26755137).
- UK Business Entity a3ETx000000cQ9ZMAU: journal 28 (General, VAT off), fee 470700, transit 100099, suspense 210000, PostingFrom 2026-11-01.
- First run (manual): FSP-000000 po_1UXVVd… → Exact 112143 entry 26280001 (debtor 146842 / 26755137 −15, fee 0.40, payout 14.60); FSP-000001 po_1UXsHU… → 26280002 (debtor 147491 / 26754787 −15, fee 0.24, payout 14.76). Suspense 0.

## Open

- [ ] Matching in Exact: invoice and Stripe payment stay two open items (net 0) → Finance matches, or automatic matching.
- [ ] Check the first automatic Day run (step 70) and the Minut step 55 (invoice ids, all countries, writes Stripe metadata).
- [ ] NL / DE: no FinSysStripe* settings on the Business Entity → posting off. Journal 28 is a Bank journal there → first check that the prod Exact login may POST BankEntries (acc personal login: 403). DE fee/suspense G/L still to decide by Finance.
- [ ] Stripe fee G/L: UK uses 470700 "Costs regarding Card payments"; no own Stripe fee G/L yet.
