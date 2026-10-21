# Runbook — payment methods pi / pr (Stripe route split)

Plan + decisions: Claude Doc "Payment methods pi / pr — Stripe route split"
https://claude.ai/code/artifact/909cb4ca-f6bb-4c39-bec2-8bb2a9c16803

Prod: only on explicit go-ahead. acc/dev: RunLocalTests is broken, so deploy with `--test-level NoTestRun` and run the tests listed below separately.

## Status

| Step | Component | dev | acc | prod |
|---|---|---|---|---|
| 0 | `rac_Order` p0→I8 queue (commit 3f60541) | ✅ v24 | ✅ v22 | ⏳ go-ahead; deploys as Draft → activate via Tooling |
| 1 | Exact payment conditions `pi` / `pr` | ✅ (Finance) | ✅ (Finance) | ⏳ Finance |
| 1 | Global value set `Payment_Method`: + pi, pr | ✅ 2026-10-20 | ✅ 2026-10-21 | ⏳ |
| 1 | Account record types B2B / B2C: + pi, pr on `Payment_Method_Contracts__c` / `Payment_Method_Opportunities__c` | ✅ 2026-10-20 | ✅ 2026-10-21 | ⏳ |
| 1 | `Payment__c.Type__c`: + psp-recurring | ✅ 2026-10-20 | ✅ 2026-10-21 | ⏳ |
| 1 | CMDT `Payment_Method_UNCL4461_Mapping`: field `Payment_Method_Type__c` + rows PM_pi, PM_pr, PM_pr_sepa_debit, PM_pr_bacs_debit, PM_pr_card; `Svc_CIIInvoiceXmlBuilder` picks code+type; new field `Account.PayProv_PaymentMethodType__c` | ✅ 2026-10-20 (on top of EN16931 WIP) | ✅ 2026-10-21 | ⏳ with EN16931 |
| 1 | Labels `paymentRemarkPI` / `paymentRemarkPR` (en, nl_NL, de, fr; draft wording) + `Ctrl_Invoice.getPaymentType` | ✅ 2026-10-20 (on top of EN16931 WIP) | ✅ 2026-10-21 | ⏳ with EN16931 |
| 1b | CMDT `Payment_Method_Rule__mdt` + 13 rows, `Util_PaymentMethodRule`, trigger `AccountPaymentMethodRule` | ✅ 2026-10-20 | ✅ 2026-10-21 | ⏳ |
| 1b | Report + clean-up of existing wrong combinations in prod | — | — | ⏳ |
| 2 | `Payment_Setting__mdt.Method__c` + pi / pr; rows ps_1_pi, ps_1_pr, ps_6_pi, ps_6_pr (Stripe, AutoCreate) with **placeholder** Exact layouts and **no Term__c** | ✅ 2026-10-20 | ✅ 2026-10-21 with **acc** placeholder ids (`ps_acc_deploy`) | ⏳ needs real layout ids |
| 2 | `rbb_Payment`: fType pi → psp-immediate, pr → psp-recurring; I + Stripe → psp-recurring; psp-dd accepted as legacy | ✅ 2026-10-20 (v31) | ✅ 2026-10-21 (v11 active) | ⏳ |
| 2 | `rab_Payment_Direct_Debit_Setup`: psp-recurring or psp-dd | ✅ 2026-10-20 | ✅ 2026-10-21 (v2 active) | ⏳ |
| 2 | `Batch_ProcessPayments`: Type IN (psp-recurring, psp-dd) | ✅ 2026-10-20 | ✅ 2026-10-21 | ⏳ |
| 3 | REST: `Rest_UpsertAccount` (v1) already passes pi / pr through (also without IBAN), so no code change; test `testPaymentProviderCodeWithoutIban` added. `Rest_UpsertContract` v1 / V2 pass `paymentMethod` through unchanged. Default mappings kept. | ✅ 2026-10-20 (test) | ✅ 2026-10-21 (test class) | ⏳ test class only |
| 3 | `Rest_UpsertAccountV2`: **obsolete** (user 2026-10-20), only in dev; phase out, no changes. Its tests already fail in dev (`getIntegrationUser`: no rows) | — | — | — |
| 4–6 | migration, clean-up, manuals | ⏳ | ⏳ | ⏳ |

## acc deploy — done 2026-10-21

Pre-checks: acc Apex / flows / value sets / record types / CMDT definitions all equal the base (e3affcb). The only differences were the confirmed CII buyer country and a default in rbb_Payment `dgr_03_BusinessEntity`.

Deployed (all NoTestRun, all Succeeded):
1. Step 1 + 1b source deploy.
2. `rt_deploy`: Account record types B2B / B2C.
3. `labels_deploy`: remarks pi / pr.
4. EN16931 part source deploy.
5. Step 2 source deploy (Payment_Setting Method__c, rbb_Payment, rab_Payment_Direct_Debit_Setup, Batch_ProcessPayments + tests) and the step 3 test class.
6. `ps_acc_deploy`: Payment_Setting ps_1_pi / ps_1_pr / ps_6_pi / ps_6_pr with **acc** placeholder layouts. acc NL uses `db8e7a5d-…`, not dev's ids; UK ids are the same in both.
7. **Extra, acc drift:** `processor_acc_deploy`. The global value set `Payment_Processor` (field `Payment__c.Processor__c`) had no "Stripe" in acc, while dev and prod do. Without it no Stripe payment can be created in acc. "Stripe" was added to acc's own value set.

Tests in acc: 252 run (Test_Svc_InvoicePaymentBlock does not exist in acc). 251 passed, 1 failed: Test_rbb_Payment_Type, caused by the missing "Stripe" processor. After fix 7, the rerun of the 6 payment tests passed 55/55.

Verified: pi / pr on record types B2B / B2C. 13 Payment_Method_Rule rows. 4 pi / pr Payment_Setting rows (Stripe, AutoCreate). acc also has active record types Archived_B2B / Archived_B2C (0 accounts, not in dev / prod); pi / pr were not added there.

### acc Stripe configuration (2026-10-21, same as dev)

| Administration (acc) | PayProv_Use__c | Direct debit method | Stripe account |
|---|---|---|---|
| Netherlands (1) | **true** | sepa_debit | NL - Acc |
| Belgium (3) | false | — | NL - Acc |
| Germany (5) | false | sepa_debit | DE - Acc |
| United Kingdom (6) | true | bacs_debit | UK - Acc (renamed from "UK - acc") |

- Set on the **Administration**. The flow `Sync_Administration_to_Business_Entity` copies PayProv_Use__c, PayProv_DirectDebit_PaymentMethod__c and PayProv_Account__c to the business entity; a value set only on the entity is overwritten at the next save of the administration.
- Validation on the Administration: PayProv_Use__c needs a Stripe account.
- dev: the Belgium link (yesterday set on the business entity only) is now also on the Belgium Administration.
- Not checked from Salesforce: Stripe webhooks / inbound connection for the new NL / DE acc accounts. Keep the webhook events equal on all Stripe accounts.

## acc deploy — pre-check notes (2026-10-20)

Commits: 3f60541 (rac_Order, already in acc), e3affcb (EN16931), 2a89700 (pi / pr).

Pre-checks found on 2026-10-20:
- acc already has the EN16931 classes. `Ctrl_Invoice` and `Util_InvoiceLineAggregator` in acc equal commit e3affcb. `Svc_CIIInvoiceXmlBuilder` in acc differs in one place: the buyer country comes from `VisitingAddress__CountryCode__s` in acc and from `BillingCountryCode` in the repo. Deploying moves acc to BillingCountryCode. **Confirmed correct by the user on 2026-10-20 (billing address).**
- Do the same drift checks as in dev before each deploy: flows (rbb_Payment, rab_Payment_Direct_Debit_Setup), Batch_ProcessPayments, Account record types, Payment_Setting rows.
- Payment_Setting pi / pr rows hold placeholder Exact layouts. In acc, either leave pi / pr unused or get the acc Exact layout ids first.

Order: step 1 + 1b → step 1 EN16931 part → step 2 → step 3 test class. Then run the test lists per step.

## Step 1 + 1b — deploy (per environment)

Source deploy:

```
sf project deploy start -o <env> --test-level NoTestRun --wait 20 \
  -d force-app/main/default/globalValueSets/Payment_Method.globalValueSet-meta.xml \
  -d force-app/main/default/objects/Payment__c/fields/Type__c.field-meta.xml \
  -d force-app/main/default/objects/Payment_Method_Rule__mdt \
  -d "force-app/main/default/customMetadata/Payment_Method_Rule.*.md-meta.xml" \
  -d force-app/main/default/classes/Util_PaymentMethodRule.cls \
  -d force-app/main/default/classes/Test_Util_PaymentMethodRule.cls \
  -d force-app/main/default/triggers/AccountPaymentMethodRule.trigger
```

Record types: deploy the **minimal** metadata package, which has only the two payment picklists. Don't deploy the repo record type files: they carry 13 other picklists that may differ per org.

```
sf project deploy start -o <env> --metadata-dir ".scratch/20261020 - paymentMethodsPiPr/rt_deploy" --wait 10
```

(Contents of `rt_deploy`: `objects/Account.object` with `recordTypes` B2B / B2C, each with `picklistValues` for both fields listing all 14 codes; package.xml type RecordType Account.B2B / Account.B2C.)

Before deploying to acc / prod, check:
- The org's picklist values equal the repo's value set: `sf sobject describe -s Payment__c` → Method__c / Type__c values.
- Record type values: retrieve with `RecordType:Account.B2C`, `RecordType:Account.B2B`, `CustomField:Account.Payment_Method_Contracts__c` and `CustomField:Account.Payment_Method_Opportunities__c` together. Without the CustomField members the retrieve omits those picklists.

Tests (dev 2026-10-20: 153/153 passed):

```
sf apex run test -o <env> -w 30 -r human -n Test_Util_PaymentMethodRule -n Test_rac_Order \
  -n Test_Rest_UpsertAccount -n Test_Rest_UpsertContract -n Test_Rest_UpsertContractV2 \
  -n Test_Util_FinancialSystemAccount -n Test_Orders -n Test_Batch_ProcessPayments
```

Verify:
- UI API `/ui-api/object-info/Account/picklist-values/<rtId>/Payment_Method_Contracts__c` lists pi and pr for B2B and B2C.
- Set Payment_Method_Contracts__c = I8 on a UK (reseller 6) test account → the save is refused.

## Step 1 — EN16931 part (deploy together with the EN16931 work)

These files contain uncommitted EN16931 work: `Ctrl_Invoice`, `Svc_CIIInvoiceXmlBuilder` (+ test), `Payment_Method_UNCL4461_Mapping__mdt`. They go to acc / prod only together with that work.

Labels + translations: deploy the **minimal** package. The repo translation files miss the existing paymentRemark* translations, so deploying them whole would be incomplete.

```
sf project deploy start -o <env> --metadata-dir ".scratch/20261020 - paymentMethodsPiPr/labels_deploy" --wait 10
```

Source deploy:

```
sf project deploy start -o <env> --test-level NoTestRun --wait 20 \
  -d force-app/main/default/objects/Payment_Method_UNCL4461_Mapping__mdt/fields/Payment_Method_Type__c.field-meta.xml \
  -d "force-app/main/default/customMetadata/Payment_Method_UNCL4461_Mapping.PM_pi.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Method_UNCL4461_Mapping.PM_pr.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Method_UNCL4461_Mapping.PM_pr_sepa_debit.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Method_UNCL4461_Mapping.PM_pr_bacs_debit.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Method_UNCL4461_Mapping.PM_pr_card.md-meta.xml" \
  -d force-app/main/default/objects/Account/fields/PayProv_PaymentMethodType__c.field-meta.xml \
  -d force-app/main/default/classes/Svc_CIIInvoiceXmlBuilder.cls \
  -d force-app/main/default/classes/Test_Svc_CIIInvoiceXmlBuilder.cls \
  -d force-app/main/default/classes/Ctrl_Invoice.cls
```

| Code + type | UNCL4461 |
|---|---|
| pi | 68 |
| pr (no type known) | 59 |
| pr + sepa_debit | 59 |
| pr + bacs_debit | 49 |
| pr + card | 48 (48 vs 54 still to confirm) |

Type source: `Account.PayProv_PaymentMethodType__c` first; when that is empty, the reseller's business entity `PayProv_DirectDebit_PaymentMethod__c` (read in SYSTEM_MODE). `Account.PayProv_PaymentMethodType__c` has no FLS grants yet; it is filled in phase 2 (webhook). Add FLS when that is built.

Tests (dev 2026-10-20: 12/12 + 22/22 passed): Test_Svc_CIIInvoiceXmlBuilder, Test_Svc_CIIHybridPdfMerge, Test_Invoices, Test_Invoice, Test_Ctrl_InvoiceEstablishmentAddress, Test_Svc_InvoicePaymentBlock, Test_Util_InvoiceLineAggregator, Test_Batch_FinalizeInvoicesLimited, Test_Util_FinancialSystem_Invoice.

## Step 2 — deploy

```
sf project deploy start -o <env> --test-level NoTestRun --wait 20 \
  -d force-app/main/default/objects/Payment_Setting__mdt/fields/Method__c.field-meta.xml \
  -d "force-app/main/default/customMetadata/Payment_Setting.ps_1_pi.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Setting.ps_1_pr.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Setting.ps_6_pi.md-meta.xml" \
  -d "force-app/main/default/customMetadata/Payment_Setting.ps_6_pr.md-meta.xml" \
  -d force-app/main/default/flows/rbb_Payment.flow-meta.xml \
  -d force-app/main/default/flows/rab_Payment_Direct_Debit_Setup.flow-meta.xml \
  -d force-app/main/default/classes/Batch_ProcessPayments.cls \
  -d force-app/main/default/classes/Test_Batch_ProcessPayments.cls \
  -d force-app/main/default/classes/Test_rbb_Payment_Type.cls
```

Before acc / prod:
- Replace the **placeholder** `Exact_Invoice_Template__c` values in ps_*_pi / ps_*_pr. Today they hold the p0 / p1 / I8 layout ids. Finance supplies the real Exact layouts.
- Fill `Term__c` for pi / pr. The due date comes from it (open point "later").
- acc / prod have fewer Payment_Setting rows than dev (prod: ps_1_I8 Bank, ps_1_p0 Mollie, ps_6_I8 Stripe, …). Only deploy the pi / pr rows; never redeploy existing rows from the repo.
- prod flows deploy as Draft: activate `rbb_Payment` and `rab_Payment_Direct_Debit_Setup` via Tooling FlowDefinition.

Tests (dev 2026-10-20: 88/88 passed): Test_rbb_Payment_Type, Test_Batch_ProcessPayments, Test_Batch_ReconcileStripeEvents, Test_Ctrl_Payment, Test_Ctrl_PaymentCase, Test_Ctrl_PaymentMandate, Test_Inv_getPaymentProviderConstant, Test_Svc_InvoicePaymentBlock, Test_Svc_PaymentIntent, Test_Svc_StripeEventProcessor, Test_Util_StripeEvent, Test_Util_PaymentMethodRule, Test_Invoices.

## Step 3 — verification (dev 2026-10-20)

- Test_Rest_UpsertAccount + Test_Util_PaymentMethodRule: 29/29 passed.
- Live v1 call in dev: NL (reseller 1, PayProv_Use on) with `paymentMethodExactCode` "pr" and no IBAN → account on pr. DE (reseller 5) → refused: "Payment method pr needs the payment provider, which is not active for reseller 5." (the REST response carries the DML error).
- Dev test account "PR Test NL B.V." (ext id 4876721) could not be deleted (associated account); harmless dev data.
- REBEL Lease regression (fresh ext id 4876720, 3 calls): Mart roleless, Afdeling Administratie Invoice;Digital (+Reminder) and Contact_Billing__c, Chris Main;Shipping. Passed.

## Rules (Payment_Method_Rule__mdt)

| Code | Allowed resellers | Requires PayProv_Use__c |
|---|---|---|
| 14, 30, 60, 08, C | all | no |
| I3, I4, I8 | 0,1,2,3,4,5 (blocked for UK 6) | no |
| I0, p1 | 6 | no |
| GR | 2 | no |
| pi, pr | all | yes |
| p0, O8 | no rule = allowed | — |

Checked only when the payment method or the reseller is new or changed, so existing wrong combinations don't block unrelated saves.

## Gotchas found

- `rac_Payment` and `rac_Payment_DirectDebit_Setup_Email` exist only in the repo, in no org. The live flows are `rbb_Payment` and `rab_Payment_Direct_Debit_Setup`. Remove the dead files in the clean-up step.
- `Payment_Setting__mdt` (reseller + method) decides Processor and AutoCreate of the Payment on invoice finalize (`rau_Subscription25_Invoice_c_Finalized_Create_Payment`). `Util_FinancialSystem_Invoice` refuses to print in Exact without a row that has `Exact_Invoice_Template__c`.
- prod UK Stripe currently runs on **ps_6_I8 = Stripe**. Those UK I8 accounts are the ones to migrate to pr. The 1b rule now blocks I8 for UK on change only, so they keep working until migrated.

- `Ctrl_Invoice` stays on apiVersion 62.0. Moving it to 67.0 would switch its queries to user mode, so it was deliberately left out of the 67.0 rule.
- `Invoice.Payment_Method_Result__c` formula: a credit invoice on 'P0' becomes I8, but the formula compares with upper-case 'P0' while the value is 'p0'. Check how credits on pi / pr must be handled (refund through Stripe).

- **Don't hook into `Trigger_Account`.** The repo version contains `updateVisitingAddressLabels` (Account address model), which is not in acc / prod. Deploying it would ship that too. The check lives in its own trigger `AccountPaymentMethodRule`.
- `sf project retrieve start --output-dir` returned "Nothing retrieved" for Flow and RecordType. Use `--target-metadata-dir … --unzip` instead.
- A record type retrieve omits a custom field's picklist values unless that CustomField is in the same retrieve.
- Business entity per reseller: `Business_Entities__c.Reseller__c` (1 NL, 2 GR, 3 BE, 4 FR, 5 DE, 6 UK).

## Existing wrong combinations (prod, 2026-10-20) — for the 1b clean-up

- Reseller 1 (NL) with I0: 1 account
- Reseller 6 (UK) with I8: 2, I3: 2, p0: 1 (p0 has no rule)

## Rollback

- Rule check: deactivate trigger `AccountPaymentMethodRule` (deploy with `<status>Inactive</status>`), or delete the CMDT row of the code concerned.
- Picklist values: deactivate pi / pr in the global value set (only if no records use them).
