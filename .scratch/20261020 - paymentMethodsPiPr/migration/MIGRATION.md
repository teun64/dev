# Step 4: migrate UK Stripe I8 accounts to pr (prepared 2026-10-20, not run)

**Selection:** billing / establishment address country **GB** (`BillingCountryCode`), no visiting address. Of the 21 GB-billing accounts on a direct debit code (I8 / I3 / I4) in prod, only these use Stripe: reseller 6, a Stripe customer and a Stripe mandate on the account.

| Account | Id | Contracts | Opportunities | Stripe | Active contract, next invoice |
|---|---|---|---|---|---|
| C J Blinco | 001AO000002c1DAYAY | I8 → **pr** | I8 → ? (decision) | cus + mandate + pm | 00947899, 2026-11-08 |
| Marc Stone | 001Tx00000zeybqIAA | I8 → **pr** | p1 (Opayo) → ? (decision) | cus + mandate + pm | 00961992, 2026-10-28 |

Snapshots (prod, 2026-10-20): `before_prod_accounts.csv`, `before_prod_contract_products.csv`, `before_prod_payments_pspdd.csv`, and `analysis_prod_gb_billing_direct_debit.csv` with all 21.

## Not migrated (same GB-billing selection)

| Group | # | Why not | Action |
|---|---|---|---|
| Reseller 1 (NL entity), I8 contracts (6 with Exact mandate, 1 without; 1 account blocked) | 7 | Exact SEPA through the NL entity, a legitimate I8 route | none |
| Reseller 1, p0 contracts with I8 opportunities | 6 | Mollie legacy | none |
| Reseller 6, I3 without IBAN / Stripe (Hoyles Denholme; Whittlesey, deactivated) | 2 | no direct debit possible | decision: 08 / 30? |
| Reseller 6, opportunity method I8 (contracts I0 ×3, p0 ×1) | 4 | UK opportunity default wrong | decision: p1 / pi? |

## Decisions (user 2026-10-20)

1. Opportunity method: **leave** (Blinco I8, Stone p1). The contract payment method moves to pr **on the account** (`Payment_Method_Contracts__c`, `update_accounts_pr.csv`). The contracts themselves stay empty and inherit pr (clarified 2026-10-20; the contract update file was dropped).
2. Active contract products on I0: **leave, flagged**:
   - CP-1010146 (a0VbR00000NzZrdUAF), C J Blinco, Activated, I0
   - CP-1029657 (a0VTx00000MFm1FMAT), Marc Stone, Activated, I0
3. Payments: **I8 → pr** on the 3 paid Stripe payments (`update_payments_pr.csv`). rbb_Payment then sets Type psp-recurring (Method changed) and recalculates Collection_Date on these paid records. "Remove the other 2" is read as dropping the 2 contract updates (see 1). Nothing is deleted.
4. UK leftovers: **leave, flagged for follow-up** (wrong or missing payment set-up for UK). List:
   - John Amos (001AO000003FxBgYAK), I0, opportunity I8, Exact mandate
   - Alistair Colville (001AO000003H58iYAC), I0, opportunity I8, Exact mandate
   - Wayne McKenna (001AO000003HWKzYAO), I0, opportunity I8, Exact mandate
   - Tracey ODonnell (001AO000003HFxEYAW), p0, opportunity I8
   - Hoyles Denholme (001Tx000010BA5IIAW), I3 / I3, no bank details
   - Whittlesey Insurance services Ltd (001bR00000P82z7QAB), I3 / I3, deactivated

## What changes per migrated account

| Object | Change | Note |
|---|---|---|
| Account | `Payment_Method_Contracts__c` I8 → pr (`update_accounts_pr.csv`) | 1b rule: pr allowed because UK `PayProv_Use__c` = true |
| Contract | none: `Payment_Method__c` stays empty and inherits pr from the account | |
| Contract Product | active CP on **I0** (1 per account) | left as is, flagged (decision 2) |
| Order / Invoice | none | history stays I8; the next renewal order gets pr from the account |
| Payment | 3 × psp-dd, all **Paid**: Method I8 → pr (decision 3) | Type becomes psp-recurring through rbb_Payment |
| Exact | existing Exact bank account / mandate (FinancialIdBankMandate__c) stays | pr invoices are not collected by Exact; cancel later if wanted |

## Prerequisites (prod)

1. Steps 1–3 live in prod (value sets, record types, rule, payment settings, rbb_Payment / batch / setup flow, EN16931 part).
2. Exact **prod** UK division: payment condition `pr` exists.
3. `Payment_Setting.ps_6_pr`: real Exact layout id + `Term__c` (open point "later").
4. Not between 27-10 and 29-10, so Marc Stone's invoice run of 2026-10-28 is not mid-switch. Either before (only if 1–3 are done) or after.

Until then nothing breaks: I8 + Stripe keeps routing to psp-recurring (step 2).

## Run (prod, only on explicit go-ahead)

```
sf data update bulk -o prod -s Account --file "update_accounts_pr.csv" --wait 10
```

Verify:
- Both accounts on pr.
- The next renewal order is on pr.
- The next payment has Type psp-recurring and Processor Stripe.
- The invoice gets the pr remark and PaymentMeans 49 (bacs_debit, from the business entity until `PayProv_PaymentMethodType__c` is filled).

Then the payments:

```
sf data update bulk -o prod -s Payment__c --file "update_payments_pr.csv" --wait 10
```

Rollback:
- Accounts: `before_prod_accounts.csv` (Id + Payment_Method_Contracts__c) back to I8.
- Payments: Method__c back to I8 (Type then goes back to psp-recurring, not psp-dd).

## Flagged for follow-up

- Contract products on I0 under the 2 migrated accounts: CP-1010146 (Blinco), CP-1029657 (Stone).
- The 6 UK accounts of decision 4: 3 × I0 with an I8 opportunity default and an Exact mandate, 1 × p0 with an I8 opportunity default, 2 × I3 without bank details (one deactivated).

## Findings

- `PayProv_Mandate_Status__c` is **empty** on both accounts although a Stripe mandate id is present. `mandate.updated` apparently never set it. Batch_ProcessPayments only checks the mandate id, so collection works. Every "active mandate" check in phase 2 must allow for this.
- Marc Stone is the duplicate-charge case (see the Stripe duplicate charges open point). Check after the migration.
