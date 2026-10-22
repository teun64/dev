# Runbook — payment methods pi / pr (Stripe route split)

Plan + decisions: Claude Doc "Payment methods pi / pr — Stripe route split"
https://claude.ai/code/artifact/909cb4ca-f6bb-4c39-bec2-8bb2a9c16803

## ⏰ FIRST THING, MORNING 2026-10-22: rbb_OrderItem outage follow-up

Background: see "Incident 2026-10-21" lower down. Prod runs `rbb_OrderItem` **v3** (v4 has been rolled back). The 19 lost first orders have been recovered.

- [x] **Check the nightly run (~01:00 UTC):** compare the number of OrderItems created and modified with previous nights, and check Event_Log for flow errors since 20:46 UTC.
  - Interim check 02:16 UTC: OK.
    - 01h: 273 OrderItems, against 282 and 289 on the previous nights.
    - Job_RecurringOrderManagement ran with 0 errors.
    - Job_RecurringOrderApplication shows the same error pattern as every night (28 / 5 / 3–4 / 13–14 / 0 / 6, "CPU time limit"). This pattern predates the outage.
    - No flow errors after 20:46:02.
    - Unrelated: the Exact sync of "Stichting Bedrijfstakschool Anton Tijdink" fails on an invalid VAT number (data).
  - Final check 2026-10-22 06:14 UTC: ✅ normal. 01h 273 / 02h 88 / 03h 62 / 04h 151 / 05h 3, against 282/83/36/151 (10-21) and 289/28/77/166 (10-20).
    - Event_Log non-success since 20:46 (`Event_Log__c`): only 8 INTEGRATION rows (Anton Tijdink ×4, Peter Blom, Cobraspen Beheer, BlackR.12, Black.12). No flow errors.
    - All 577 OrderItems created or modified today were saved by the batch user (Teun Rietman). There were no staff UI saves yet at 06:14 UTC.
- [x] **Error emails "rbb - OrderItem":** count them and note the Current User. If a staff user appears, their UI save failed and needs to be redone. The Current User also shows whether the cause was timing or access.
  - 2026-10-22 (mailbox read via the M365 connector, folder Salesforce, 17:00–21:00 UTC): 259 "rbb - OrderItem" mails, 17:23:21–20:46:07Z, all v4 dgr_03_VAT_Code_Lookup `__NotFound`. The "approaching 100 error emails/hour" warnings mean some mails were suppressed.
    | Current User | mails | what |
    |---|---|---|
    | Teun Rietman | 131 | burst 17:23–17:25 = 173 existing OrderItems (all re-saved OK ~21h UTC) + recurring No ID retries |
    | Security Platform | 120 | 2 OrderItems retried every ~5 min (802bR00000N7yv5QAB / 02096821, 802bR00000UVlgXQAT / 02467998): both saved OK 20:51 UTC + No ID retries |
    | **Guy Mooyman** | 7 | No ID inserts = Opportunity → Administration (afl Create Order) |
    | Platform Integration | 1 | 18:00:38 = UK `/UpsertContract` 93004_1 (see Waldron) |
    - Raw tally: scratchpad `rbb/orderitem_ids_with_user.tsv` (session-only).
  - **⚠ Follow-on: 11 "afl - Opportunity - Create Order" mails (act_02_CreateOrders → CANNOT_EXECUTE_FLOW_TRIGGER rbb - OrderItem).**
    - 5 are Webshop #2026-00077427: Guy ×3, Teun ×2 retries. It was fixed at 20:52 by setting the stage Administration → Closed Won, which created Order 02752008.
    - **6 Opportunities of Guy Mooyman are still in Administration with no Order (`Order__c` null), so no warehouse order exists for them:**
      - 006Tx00000feawRIAQ Webshop #2026-00077449 (AST Auto Shop Totaal, €2,475)
      - 006Tx00000fecTZIAY Webshop #2026-00077447 (AST Car Inside Nijverdal, €285)
      - 006Tx00000fedZKIAY KZZ-93-T/ 90219 (DLM, €288.43)
      - 006Tx00000febVuIAI Inbouw 19-10 MC8684 (Dusseldorp Rotterdam West, €395)
      - 006Tx00000feiVmIAI Inbouw 19-10 MC0604 (Dusseldorp Rotterdam West, €395)
      - 006Tx00000fejgLIAQ Inbouw 19-10 MC4434 (Dusseldorp Rotterdam West, €395)
    - ✅ **Fixed 2026-10-22 ~07:27 UTC** (user's go-ahead). Each Opportunity was set to Closed Won one at a time, and Orders 02752624–02752629 were created with all 10 OrderItems. They start as Draft and are Activated by the regular financial-system sync (the first one at ~07:30), so there is nothing further to do.
  - Unrelated: there are 93 "rau - Order - Contract - Activated" mails (17:23–17:25, the same burst) and pef - Integration GUID errors.
  - ✅ **GUID fix LIVE 2026-10-22.** Commit 3a50668 plus 52b06c2 (52b06c2 adds the missed `pef_Internal` input).
    - acc: deployed and tested.
    - prod: deploy 0AfTx0000013k5lKAA, 2/2 tests passed, pef_Integration v7 and pef_Internal v3 activated.
    - Tested in both orgs: 5 events in one transaction gave 5 unique GUIDs. The test logs were deleted.
- [x] **David Waldron (00965276):** ✅ closed 2026-10-22, see the outcome below. the UK `/UpsertContract` call extId `93004_1` (2026-10-21 18:00:34) failed and was never retried. The UK side has to resend it. Also check his `Direct_Debit_Mandate_Status__c` = LIVE without a Stripe mandate, and follow PM#000206388 (first psp-recurring payment in prod) until it is paid.
  - 2026-10-22 06:14 UTC:
    - `93004_1`: still not resent. Event_Log has 18:00:08 200 (created contract 00965276, extId 93004_1-3) and 18:00:34 400. There is no later call.
    - Account 001Tx000011XwKHIA0: pr, `Direct_Debit_Mandate_Status__c` = LIVE, but PayProv_MandateId / Mandate_Status / PaymentMethodId are all empty (only cus_VU4oRyKMwOfo7D).
    - **Outcome 2026-10-22: nothing missing, no UK resend needed.**
      - The 18:00:34 call was a **duplicate send**. In every 18:00 run UK sends ~8 contracts twice (e.g. 25120_1, 64941_1, 77835_1, 93030_1).
      - The first call (18:00:08) created CP-1034621 (93004_1-3, iTrack Ultimate Monthly DD £12.50, the only product), and it was Activated at 18:00:14.
      - The duplicate's update re-fired `RecurringOrderAfterUpsert`. Its order insert hit rbb_OrderItem v4, so the update was rolled back (400). The lost first order was regenerated last night as 02752013 (invoiced).
      - Stripe: Waldron is in mandate setup (user 2026-10-22), so PM#000206388 waits for him and needs no action from us.
      - Unrelated, chronic: 92582_1 / 86996_1 / 90267_1 / 90741_1 have failed twice a day since 2026-10-13 with "No Account (80861 / 32063 / 15646 / 14518) found". The UK accounts were never created in Salesforce, which is a UK-side data issue.
    - PM#000206388: £15, psp-recurring, **Setup**, Interaction Mail Sent (21:02 UTC). It has a PaymentIntent pi_3UT6eSGliYpbpuQB0gUbZBbK but no SetupIntentId, and Collection_Date 2026-10-19 lies in the past. It is waiting for the customer to complete the mandate setup.
- [ ] **Today's Draft orders** (02752003–02752028, 02752285–02752289) go through the normal invoice run; check that they are invoiced.
  - 2026-10-22 06:14 UTC: 28 orders exist: 21 Activated, of which 20 are invoiced (FINALIZED, invoices I-2610-00772113…124; Waldron's 02752013 is on I-2610-00772018). 02752016–018 don't exist.
    - 02752008 (Autobedrijf van Os, 08) is Activated without an invoice: `Enable_Automatic_Invoices__c` = false, so it is invoiced manually, as intended.
    - 7 GBP orders are still Draft. 02752019/020 have invoice date 2026-11-08, so they are fine. 02752285–289 (p1, created 2026-10-22) should go in the **UK invoice run, which runs daily ~17:00 UTC**. Re-check after 17:00 UTC today.
  - Side note: my user has no FLS on the new `Account.PayProv_PaymentMethodType__c` (field exists in all orgs; Apex reads it WITH SYSTEM_MODE, so no functional impact).
- [ ] **rbb_OrderItem VAT_Code: analysis 2026-10-22 + prod activation pending**
  - **Cause of the outage: deploy timing, not metadata and not FLS.**
    - In prod, v4 was compiled 11 s after `VAT_Code__c` was created in the same deploy (object 17:21:47, flow 17:21:58). It bound the object and field as `__NotFound`.
    - dev (1 h gap) and acc (24 min gap) work with the same permissions.
    - Prod can query the object today. **Re-activating v4 would fail again; deploy a fresh version.**
  - **Data:** VAT_Code__c now holds the 5 real codes in dev, acc and prod (user choice). They come from the package's `Subscription25__VAT_Code__c` per Administration.
    | code | UNCL5305 | meaning |
    |---|---|---|
    | 0 | O | No VAT (outside scope) |
    | 1 | S | low rate (NL 9%) |
    | 2 | S | high rate (19–24% per Administration) |
    | 6 | G | outside the EU (export) |
    | 7 | K | within the EU (intra-community) |
    - Codes in use over the last 12 months: 2, 6 and 7.
    - The dev guesses 3/4/5/E/S were deleted.
    - Only UNCL5305 is functional (CII XML). The rate comes from `OrderItem.Subscription25__VAT_Percentage__c`.
  - ✅ **FLS added 2026-10-22, all orgs (prod 0AfTx0000013kKHKAY, commit 80f3704):**
    - System Administrator profile and `miModifyAllData`: edit.
    - `ps_miSubscription25_User`: read, plus object read. Through it, pg_Subscription25User, pg_Subscription25Admin and pg_CCC_User get read.
    - Fields: `VAT_Code__c.Description__c` and `OrderItem.VAT_Code__c`. `Percentage__c` has since been removed.
    - Prod Percentage and Description are now filled.
  - ~~**FLS (not the cause, but a gap):**~~ `VAT_Code__c.Percentage__c` and `Description__c` are readable only through `ps_EN16931_Invoicing`, and nobody has that permission set in prod. So in prod, Percentage and Description are **still empty** (loaded with required fields only). To show or maintain them, add FLS read/edit for those 2 fields to an admin permission set (e.g. `miModifyAllData`, which already has object access), or assign `ps_EN16931_Invoicing`, then fill them in.
    - Internal_Code__c and UNCL5305_Category__c are required, so they are always readable.
    - The flow (system context) and Svc_CIIInvoiceXmlBuilder (SYSTEM_MODE) don't need FLS.
  - **apiVersion 67.0 (commit 078449c):**
    - rbb_OrderItem: dev v12 and acc v5 active and tested (OrderItem save links code 2 → 2/S). **Not deployed to prod yet.**
    - pef_Internal: dev v7, acc v4 and prod v4 (0AfTx0000013kDpKAI) active.
  - ✅ **Prod v5 (API 67) ACTIVE 2026-10-22 08:45:40 UTC** (user's go-ahead). The test save on 802Tx00000IXtHtIAL linked 2 → 2/S. Real saves after activation ran without errors, and the 60-min monitor was stopped after the first real saves.
  - ✅ **Insert gap closed through activation, no new flow needed (analysis 2026-10-22).**
    - When an Order is activated, `rau_Order_Contract_Activated` (synchronous) and `Inv_FinancialSystemCreateOrders` update every line with `setProductName__c = true`. That fires the prod-only flow `rbu_OrderItem_setProductName` **and** `rbb_OrderItem` v5, which links VAT_Code.
    - Activation happens about 1 s before FINALIZED, and the XML is only built when the PDF is attached (CDL trigger). So invoiced lines are always linked.
    - **Check after the UK run (~17:00 UTC):** new invoice lines have `VAT_Code__c` set and the CII XML shows the category.
    - Optional later: move the lookup into `rbu_OrderItem_setProductName`, and put that flow plus `rau_Subscription25_Invoice_c_Email_Error` in the repo (they are prod-only).
  - ✅ **`VAT_Code__c.Percentage__c` removed 2026-10-22 (commit 7833aa8).** It was redundant: the rate comes from `OrderItem.Subscription25__VAT_Percentage__c`, and one value per code is wrong across Administrations.
    - Removed from the 3 test fixtures, then the field was deleted in dev, acc and prod (0AfTx0000013klhKAA, 8/8 tests).
    - It sits in "Deleted Fields" for 15 days.
  - (earlier analysis) **Gap: on INSERT the link stays empty.** The package's before-insert triggers (`OrderItem`, `OrderItemBeforeUpsert`) set `Subscription25__VAT_Code__c` only after our before-save flow has run. So a new item gets `VAT_Code__c` only on a later update (e.g. 802Tx00000IXtubIAD on 02752668).
    - acc shows the same: 0 links on inserts, because there was no data before today.
    - **Proposal (awaiting go-ahead):** a fallback in `Svc_CIIInvoiceXmlBuilder`: when `VAT_Code__r` is empty, look up the category via Subscription25__VAT_Code__c → VAT_Code__c.Internal_Code__c.
  - ✅ **Backfill of Draft OrderItems in prod, 2026-10-22:**
    - 5,198 linked (20 test + 5,178 in batches of 150), 0 failed, amounts unchanged (UnitPrice / Quantity / TotalPrice / VAT %).
    - 144 items without a package VAT code stay empty.
    - Activated / invoiced items were not backfilled.
  - Draft orders are mostly created by the nightly run, 01–04 UTC, running as the batch user. Their invoice dates are mostly Oct (2,559) and Nov (2,850) 2026. About 800 old Draft orders date from 2023–2025.
  - ~~**Prod step (on go-ahead, outside business hours):**~~
    1. Deploy rbb_OrderItem. It lands as Draft.
    2. Activate the new version via FlowDefinition.
    3. Immediately do 1 no-op OrderItem save.
    4. On error, set FlowDefinition back to v3.
 outside business hours, followed by a single test save. Load the VAT_Code__c data into acc and prod first or at the same time (dev has 9, acc/prod 0).

Prod: only on explicit go-ahead. acc/dev: RunLocalTests is broken, so deploy with `--test-level NoTestRun` and run the tests listed below separately.

## Status

| Step | Component | dev | acc | prod |
|---|---|---|---|---|
| 0 | `rac_Order` p0→I8 queue (commit 3f60541) | ✅ v24 | ✅ v22 | ✅ 2026-10-21 v22 active |
| 1 | Exact payment conditions `pi` / `pr` | ✅ (Finance) | ✅ (Finance) | ✅ (Finance, user 2026-10-21) |
| 1 | Global value set `Payment_Method`: + pi, pr | ✅ 2026-10-20 | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) |
| 1 | Account record types B2B / B2C: + pi, pr on `Payment_Method_Contracts__c` / `Payment_Method_Opportunities__c` | ✅ 2026-10-20 | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) |
| 1 | `Payment__c.Type__c`: + psp-recurring | ✅ 2026-10-20 | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) |
| 1 | CMDT `Payment_Method_UNCL4461_Mapping`: field `Payment_Method_Type__c` + rows PM_pi, PM_pr, PM_pr_sepa_debit, PM_pr_bacs_debit, PM_pr_card; `Svc_CIIInvoiceXmlBuilder` picks code+type; new field `Account.PayProv_PaymentMethodType__c` | ✅ 2026-10-20 (on top of EN16931 WIP) | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ), with EN16931 |
| 1 | Labels `paymentRemarkPI` / `paymentRemarkPR` (en, nl_NL, de, fr; draft wording) + `Ctrl_Invoice.getPaymentType` | ✅ 2026-10-20 (on top of EN16931 WIP) | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ), with EN16931 (prod's own Ctrl_Invoice + remark branch) |
| 1b | CMDT `Payment_Method_Rule__mdt` + 13 rows, `Util_PaymentMethodRule`, trigger `AccountPaymentMethodRule` | ✅ 2026-10-20 | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) |
| 1b | Report + clean-up of existing wrong combinations in prod | — | — | ⏳ |
| 2 | `Payment_Setting__mdt.Method__c` + pi / pr; rows ps_1_pi, ps_1_pr, ps_6_pi, ps_6_pr (Stripe, AutoCreate) with **placeholder** Exact layouts and **no Term__c** | ✅ 2026-10-20 | ✅ 2026-10-21 with **acc** placeholder ids (`ps_acc_deploy`) | ✅ 2026-10-21 (0AfTx0000013ilVKAQ); layout ids = prod I8 / p0-p1 layouts; no Term__c (0 days, decided) |
| 2 | `rbb_Payment`: fType pi → psp-immediate, pr → psp-recurring; I + Stripe → psp-recurring; psp-dd accepted as legacy | ✅ 2026-10-20 (v31) | ✅ 2026-10-21 (v11 active) | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) (v10 active) |
| 2 | `rab_Payment_Direct_Debit_Setup`: psp-recurring or psp-dd | ✅ 2026-10-20 | ✅ 2026-10-21 (v2 active) | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) (v2 active) |
| 2 | `Batch_ProcessPayments`: Type IN (psp-recurring, psp-dd) | ✅ 2026-10-20 | ✅ 2026-10-21 | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) |
| 3 | REST: `Rest_UpsertAccount` (v1) already passes pi / pr through (also without IBAN), so no code change; test `testPaymentProviderCodeWithoutIban` added. `Rest_UpsertContract` v1 / V2 pass `paymentMethod` through unchanged. Default mappings kept. | ✅ 2026-10-20 (test) | ✅ 2026-10-21 (test class) | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) (test class) |
| 3 | `Rest_UpsertAccountV2`: **obsolete** (user 2026-10-20), only in dev; phase out, no changes. Its tests already fail in dev (`getIntegrationUser`: no rows) | — | — | — |
| 2 | `afl_PaymentDirectDebitSetup_SendMail`: Mail Sent only after a real send; on failure status cleared + `AlertMessage__c` + case (commit f31e6e4) | ✅ 2026-10-21 (v16) | ✅ 2026-10-21 (v4) | ✅ 2026-10-21 (0AfTx0000013ilVKAQ) (v3 active) |
| 4 | Migration of the 2 UK Stripe accounts I8 → pr + 3 paid payments I8 → pr: package prepared in `migration/` (MIGRATION.md) | — | — | ⏳ after prod deploy |
| 5 | Clean-up: repo-only flows `rac_Payment` / `rac_Payment_DirectDebit_Setup_Email` removed (a378cd5). Removing the I8 + Stripe branches and deactivating psp-dd waits for the migration | ✅ partly | — | ⏳ after migration |
| 6 | Manuals: Payment Methods key-user (3e4ed1e5) + developer (1d00eaa3) created; Stripe Payments, REST (both kinds) and the generic manual updated 2026-10-21. PDFs on the weekly backlog (rows 10–11) | ✅ docs | | PDFs ⏳ |
| 2 | `rbb_OrderItem` v4 (EN16931 VAT_Code lookup) | ✅ | ✅ (since 2026-09-21) | ⚠ v4 activated 2026-10-21 17:23 → outage, **v3 active again** (see Incident); re-activate later |
| — | EN16931 SYSTEM_MODE fixes (`Trigger_ContentDocumentLink`, `Svc_CIIInvoiceXmlBuilder`, `Svc_CIIHybridPdfMerge`, test fixtures, `Test_Ctrl_InvoiceRemarks`), commit ce00cb4 | ✅ 2026-10-21 | ⏳ acc still has the user-mode trigger: invoice PDF fails for users without ps_EN16931_Invoicing | ✅ 2026-10-21 |
| P2 | Phase 2: card + Apple Pay / Google Pay (see "Phase 2 start"), commit 8ae638c | ✅ 2026-10-21 | — | — |

## NEXT STEPS (as of 2026-10-21) — start here in a new session

Context: plan doc https://claude.ai/code/artifact/909cb4ca-f6bb-4c39-bec2-8bb2a9c16803; manuals: Payment Methods developer 1d00eaa3 / key-user 3e4ed1e5. Commits: 3f60541, e3affcb, 2a89700, f31e6e4, a378cd5 (+ runbook commits).

### Next 1 — UK test in acc

Goal: prove the pr route for UK (Bacs via Stripe "UK - Acc", GBP) end to end in acc, then the migration on an acc account.

1. Pick a **test** UK account in acc (never a real customer, see memory "acc tech-dept test accounts"). Candidates found 2026-10-21:
   - "Test the UK Tester" (001G5000014aIdcIAE): I0, Stripe customer + mandate.
   - "Test Ltd." (001G5000014b7xnIAA): I0, Stripe customer, no mandate.
   - Or create a new one (reseller 6, B2B/B2C), like "TEST Claude pr NL" (001G500001UBhERIA1).
2. Rule check: set the account to I8 → must be refused ("not allowed for reseller 6"); to pr → accepted (UK `PayProv_Use__c` = true).
3. Payment pr for that account (anonymous Apex as in the NL test: Method pr, Processor Stripe, Administration UK a0U3W0000041AZtUAM, GBP, amount > 1):
   - expect Type **psp-recurring**, Business Entity United Kingdom, bacs_debit times (processing 2 / setup 10 working days), collection date.
   - **With mandate** (Test the UK Tester): status New → `Batch_ProcessPayments` should charge it off-session in Stripe "UK - Acc" (test mode) → Processing → Paid via webhook. Run the batch and check Stripe test dashboard / payment status.
   - **Without mandate** (Test Ltd.): status Setup → setup flow → Stripe SetupIntent on the UK account (`seti_…` ends in the UK - Acc account id `…GxR72SaSls`); mail blocked by deliverability "system email only" → status empty + AlertMessage + case (expected).
4. Invoice side (optional, pushes to Exact acc): finalize an invoice on pr for the UK test account → Payment created via `Payment_Setting` ps_6_pr (placeholder layout 922a4ff1… = I8 layout). Only if acc Exact UK division has condition `pr`. Check the invoice PDF remark (paymentRemarkPR, EN) and the CII payment means (49 for bacs_debit).
5. Migration dry run on acc: put a UK test account on I8 + Stripe payment(s), then run the same steps as `migration/MIGRATION.md` (account → pr, paid payments I8 → pr) and verify Type psp-recurring.
6. Record results here and in the plan doc; clean up or keep the test data (decide with the user).

#### Run 2026-10-21 — NL + UK full chain, mails to the user's private address

- Accounts (B2C, created by Claude): "TEST Teun pr NL" 001G500001UDJz7IAH (reseller 1, EUR, pr) and "TEST Teun pr UK" 001G500001UDJz8IAH (reseller 6, GBP, pr). Each has its own contact with email teun.rietman@outlook.com (address kept; ACR roles Main/Payment/Invoice/… set by automation).
- ✅ Rule check UK: I8 refused ("Payment method I8 is not allowed for reseller 6."); pr accepted.
- No Stripe customer yet on either account; `afl_Payment_Direct_Debit_Setup` creates it when the first payment arrives.
- ⚠ Webhook: acc holds only 5 `stripeGC__Stripe_Event__c` rows, all from UK - Acc (2026-10-14). NL - Acc has never delivered an event, so check its webhook endpoint in the Stripe dashboard.
- ⚠ pi is not wired end to end. `Ctrl_Payment.getPaymentData` ignores `Type__c`: with a mandate on file it answers "already scheduled", and without one it runs a DD setup or a Bacs payment. `Batch_ProcessPayments` only takes psp-recurring / psp-dd, so a pi payment on a mandated account is never charged.
- Deliverability: the user switches acc to "All email" just before the payments are inserted and back right after the mails arrive.
- Contracts (OrangeR.12, prepaid 12 months, pr, start 2026-10-21): NL 01908899 (800G500000qAzHGIA0, CP €9.95 + auto Activation Fee), UK 01908900 (800G500000qAzHHIA0, CP £13.90). Created via anonymous Apex. `Contract.Reseller__c` and `Subscription25__Order_Generation_Start__c` are formulas.
- CP activation needs a `Subscription25__Debtor_Number__c` ("account not present in the selected administration"). For Exact administrations: set `SyncToFinancialSystem__c = true`. `Batch_FinancialSystemAccountSync` (5 min) creates the debtor in Exact acc, `rab_Account_Debtor_Number` creates the junction, and `Batch_ActivateDraftContractProducts` (5 min) activates the CPs.
- ✅ NL chain ran by itself within about 1 minute of activation:
  - Debtor 12295645.
  - Orders 03322993 (€119.40) and 03322994 (€25 activation fee), both pr.
  - Invoice I-2610-00560538 FINALIZED (€144.40 net / €174.72 gross, Payment_Method pr).
  - Payment PM#000136954: Type psp-recurring, Setup, Mail Sent, Stripe customer cus_VTvQyFG6PGtru1 on NL - Acc, SetupIntent seti_1USxZJABHKG9R0t2… (NL - Acc).
  - No manual Sub25 job needed. Sub25 jobs are not global, so they can't be started from Apex anyway.
  - Note: Collection_Date__c = 2026-10-20, one day before the request date.
- ⚠ The setup mail link pointed to **dev**. The user edited the link to acc by hand and completed the SEPA mandate. The payment went to "Request Processed by Customer", but:
  - **No mandate reached Salesforce.** The account's PayProv_MandateId / PaymentMethodId are empty, and there were 0 Stripe events today. So the NL - Acc webhook is missing, as suspected, and the batch can't charge.
  - The link cause is the known open item (commit 8f743de, `.scratch/20261015 - invoiceEmailLightning/customerHubFill/RUNBOOK.md`). The fix is dev only:
    - dev templates use `{{{Payment__c.Setup_URL__c}}}`, a formula of Business_Entity__r.CustomerHub_URL__c + /payment?token= + externalId.
    - acc: all 6 DD templates hard-code `https://movingintelligence--dev.sandbox.my.site.com/hub/payment?token=`. `Setup_URL__c` does not exist. There are no DE templates.
    - prod: hard-coded `https://customer.movingintelligence.com/payment?token=`, set deliberately (changed on 2026-09-29). `Setup_URL__c` does not exist.
  - Webhook config (`stripeGC__Stripe_Webhook_Endpoint__c`):
    - dev (NL/DE/UK) and prod (3 accounts) all have the same 14 events: payment_intent.{amount_capturable_updated, canceled, created, partially_funded, payment_failed, processing, requires_action, succeeded}, setup_intent.{canceled, created, requires_action, setup_failed, succeeded} and mandate.updated.
    - In Stripe the NL mandate shows 3 events (setup_intent.created, payment_method.attached, setup_intent.succeeded), but 0 reached acc. That confirms the missing NL endpoint.
    - UK: acc's UK (and DE) Administration has `Subscription25__Synchronisation__c` empty. In prod both are Exact; in acc the UK Exact credential is not authenticated, so this is deliberate. The account sync failed with "This accounts reseller does not synchronize with Exact". The debtor number was then generated as in `Util_Rest.checkDebtorNumber` for non-Exact admins (`Id.left(15).right(9)` = 0001UDJz8), and the sync flag was cleared. `rab_Account_Debtor_Number` created the junction.
    - UK chain after the faked Exact sync:
      - Debtor 0001UDJz8 on the account plus junction a0ZG5000003LNXlMAO (United Kingdom).
      - CP-1416263 activated by hand.
      - Order 03322995 created at once (£166.80, pr).
      - No invoice yet. NL got its invoice within 30 s via the Exact-synced Job_Synchronisation path; non-Exact UK only gets invoices from the nightly Job_InvoiceCreation (19:16 UTC). acc UK has 34 FINALIZED invoices from that path, the last on 2026-10-08.
      - ✅ The user invoiced the order by hand (Sub25 "Invoice orders"):
        - Invoice I-2610-00560539 FINALIZED, £166.80 net / £200.16 gross, pr.
        - PDF Invoice_GB26000152.pdf is attached **twice** (13:00:33 and 13:00:47, different files).
        - Payment PM#000136955: psp-recurring, Setup, Mail Sent, GBP 200.16.
        - Bacs → PaymentIntent pi_3USz8gGxR72SaSls… was created upfront on UK - Acc; there is no SetupIntent.
        - Collection_Date 2026-10-19, two days before the request date (same pattern as NL).
      - ✅ The user completed the UK Bacs page at 13:12. Events arrived: payment_intent.created, payment_intent.processing, mandate.updated. PM#000136955 → Processing.
        - Account: PaymentMethodId pm_1USzJgGxR72SaSls… is set; MandateId is still empty, because `mandate.updated` is only processed when status = active (Bacs mandate pending).
        - Waiting for payment_intent.succeeded → Paid, and the mandate going active.
      - ✅ UK: payment_intent.succeeded arrived at 13:13 → PM#000136955 **Paid**. Mandate mandate_1USzJhGxR72SaSls… is now on the account.
      - NL / DE webhook endpoints created by the user at 13:15 / 13:16 (we_1USzMBABHKG9R0t2…, we_1USzNMApWepTsd3c…). Both are subscribed to **only `account.updated`**, and none of the 14 events. UK still lacks the 5 setup_intent.* events.
      - Adding the events only in the Stripe dashboard + Resend → still 0 NL events in acc; the SF endpoint record still had only account.updated.
      - After the stripeGC wizard update, NL / DE endpoint records changed at 13:32 to 15 events (the 14 + account.updated). Lesson: set webhook events via the stripeGC setup, not only in the Stripe dashboard.
      - The old NL events could not be resent to the new endpoint, and redoing the mandate via the link is impossible: `Svc_PaymentIntent.getOrCreate` reuses the stored, already-succeeded SetupIntent → "already processed".
        - Fix 13:40: read seti_1USxZJ… via `Svc_PaymentIntent.call` (GET, read-only) and wrote PayProv_PaymentMethodId__c pm_1USxd3ABHKG9R0t2… and PayProv_MandateId__c mandate_1USxd3ABHKG9R0t2… on TEST Teun pr NL. That is the same write Svc_StripeEventProcessor does on setup_intent.succeeded, and it matches the user's Stripe event payload.
        - ✅ 13:45 Batch_ProcessPayments charged PM#000136954 off-session (pi_3USzpTABHKG9R0t2…). The first NL webhook events arrived: created + processing at 13:45:21, succeeded at 13:45:48. Result: **Paid**, Processed_Date 2026-10-21, 0 Cases. NL pr chain proven end to end (apart from the manual mandate write).
      - 14:20: UK - Acc endpoint now has all 14 events too. All three acc accounts are in line with dev / prod. prod checked: all 3 endpoints have 14 events; UK had 28 events in 30 days, NL / DE unused.
      - ✅ Repeat charge UK: PM#000136956 (£2.50, inserted directly, collection date 10-28 by the flow, moved to today for the test) was charged off-session by Batch_ProcessPayments at 14:25 (pi_3UT0S0GxR72SaSls…) → Paid at 14:25:28. 0 Cases.
      - ✅ Link fix acc (14:30):
        - `hubfill_acc.apex` filled the 6 Administrations; the sync filled the 6 Business Entities, and PayProv_* stayed intact.
        - Deployed `Payment__c.Setup_URL__c` and 9 DD templates (SetupInitial / Reminder1 / Reminder2 × EN / NL / DE; DE are new in acc) from the repo, including dev's newer layout. Validated first.
        - Added Admin profile read on Setup_URL__c.
        - Render check of SetupInitial_NL for PM#000136954 → acc link.
        - **Prod done the same day:** hubfill_prod.apex filled the 6 Administrations (the BE sync changed nothing else). The user deployed Setup_URL__c + the 9 templates (0AfTx0000013hz7KAA) and Admin FLS (0AfTx0000013i0jKAA). Render check of PM#000201568 → `https://customer.movingintelligence.com/payment?token=…`. No open DD payments in prod.
      - Collection date before request date — root cause: `rbu_Subscription25_Invoice_c.fDuePeriod` derives the term from the method code (numeric → days; last digit 3 / 4 / 6 / 8 → 30 / 14 / 60 / 8; anything else 0). pi / pr → 0, so invoice due date = invoice date (history: 11-04 → 10-21 at FINALIZE). rbb_Payment.fCollectionDate = due date − processing working days. Fix needs a term per pi / pr. **Parked by the user 2026-10-21 ("later")**: add pi / pr to fDuePeriod once the terms are decided; it belongs with the open `Term__c` point.
      - Duplicate UK PDF: a second ContentDocument 069G500000HlFufIAF (13:00:47) was deleted at 13:11 by the user. Not our code: the CII merge is off everywhere and adds versions only. Across 3,087 finalized invoices of the last 20 days, every one has ≤ 1 PDF. The user confirmed generating it manually; nothing to fix.
      - NL at 13:15: unchanged. Still no NL endpoint, 0 NL events; PM#000136954 is Setup with no mandate.
    - acc: **NL - Acc and DE - Acc have no endpoint at all.** UK - Acc (we_1U8f93GxR72SaSls…) lacks the 5 setup_intent.* events. Handed to the user 2026-10-21 to fix in the stripeGC setup.
    - Data: `Subscription25__Administration__c.CustomerHub_URL__c` is empty in acc and prod. `Sync_Administration_to_Business_Entity` copies it to the Business Entity on every Administration save, so the BE value gets wiped. acc BE NL/BE/DE/UK and prod BE NL/DE/UK are now null.

Known acc facts: Stripe accounts NL - Acc / DE - Acc / UK - Acc linked on the Administrations; NL + UK Use on; org-wide emails set; Payment_Processor has Stripe; deliverability = system email only (no mails).

### Next 2 — prod deploy: DONE 2026-10-21 (0AfTx0000013ilVKAQ)

Fixes for the 9 validation failures (repo + package):
- `Trigger_ContentDocumentLink` invoice query `WITH SYSTEM_MODE` (invoice PDF blocker); `Svc_CIIInvoiceXmlBuilder` invoice + OrderItem queries `WITH SYSTEM_MODE`; `Svc_CIIHybridPdfMerge` status update in SYSTEM_MODE (silently failed without FLS).
- EN16931 test fixtures: DML + asserts in SYSTEM_MODE; `Test_Svc_CIIInvoiceXmlBuilder` sets `OrderItem.VAT_Code__c` itself (prod validates against the old rbb_OrderItem).
- `Test_rbb_Payment_Type` / `Test_rac_Order` left out of the deploy run (Draft flows) and run after activation: pass.
- `Ctrl_Invoice` coverage (prod itself is at 71%): new `Test_Ctrl_InvoiceRemarks` + `Test_Controllers` added to the test list.
- Validation 0AfTx0000013ijtKAA: 212 tests, 0 failures → quick deploy 0AfTx0000013ilVKAQ.
- Flows activated: rac_Order v22, rbb_Payment v10, rab_Payment_Direct_Debit_Setup v2, afl_PaymentDirectDebitSetup_SendMail v3, rbb_OrderItem v4.
- Open after the deploy:
  - [ ] Belgium Administration a0U3W000004QateUAC → PayProv_Account__c a2qbR000000Gl6DQAS (NL Stripe; Use stays off). Blocked by the permission check; run it yourself or give a go-ahead:
    `sf data update record -o prod -s Subscription25__Administration__c -i a0U3W000004QateUAC -v "PayProv_Account__c=a2qbR000000Gl6DQAS"`
  - [ ] Step 4 migration (C J Blinco, Marc Stone I8 → pr, `migration/MIGRATION.md`) — not run; needs a go-ahead. Marc Stone's next UK Stripe run is 2026-10-28.
  - [ ] acc: deploy the EN16931 SYSTEM_MODE fixes (ce00cb4) — acc still has the user-mode `Trigger_ContentDocumentLink`.
  - [ ] Key-user Payment Methods docs + PDFs: were waiting for prod go-live, now unblocked.
  - [ ] Re-activate `rbb_OrderItem` v4 (see the morning checklist / Incident).
  - FYI: `flow_701Tx000011cU0nIAE_…` (created in prod 2026-10-21, no active version) is system-generated and not part of this package.

#### Before the deploy (history)

User decisions 2026-10-21:
- **Exact conditions:** pi / pr exist in Exact prod (UK, NL, DE).
- **EN16931:** deploy it too, but without influence on current PDFs. The package carries **prod's own `Ctrl_Invoice`** (v62, no Util_InvoiceLineAggregator refactor) plus only the 5-line pi / pr remark branch. The hybrid merge stays off (`Include_CII_Hybrid_PDF__c` is new, default false); there are no VAT_Code__c records, so the rbb_OrderItem lookup returns empty.
- **Term:** migrate with 0 days (pr due date = invoice date; parked fDuePeriod fix).
- **Belgium:** link the Belgium Administration to the NL Stripe account (Use stays off).
- **Migration:** C J Blinco and Marc Stone I8 → pr after the deploy (`migration/MIGRATION.md`).

Pre-checks against prod (all clean):
- The 4 flows (rbb_Payment, rab_Payment_Direct_Debit_Setup, afl_PaymentDirectDebitSetup_SendMail, rac_Order), rbb_OrderItem, Batch_ProcessPayments, Ctrl_Invoice, Test_Rest_UpsertAccount, Test_Batch_ProcessPayments and Rest_UpsertAccount all equal the repo base they were built on. The semantic flow diff ignores comments and order. The only difference is the `getFirstRecordOnly` default, as in acc.
- Value set / Type__c / Payment_Setting.Method__c / record types: prod values + pi / pr only, nothing dropped.
- Repo ps_*_pi / pr layout ids already equal prod: pr = I8 layout (ps_1_I8 c46c05ea…, ps_6_I8 922a4ff1…), pi = p0 / p1 layout (f68dc67b…, 2e5ddea3…).
- `psp-dd` sweep: only rbb_Payment, rab_Payment_Direct_Debit_Setup, Batch_ProcessPayments and Type__c refer to it, all handling psp-recurring as well. rab_Payment_Direct_Debit_Escalation has no type filter, so UK reminders keep working.
- DE stays unusable for pi / pr: no ps_5 rows, PayProv_Use off.

Package: `prod_deploy/package` (96 components: rac_Order, steps 1–3, SendMail, EN16931 minus Inv_TriggerCIIHybridPdfMerge and the placeholder NC / EC, record types + labels merged in). Tests: `prod_deploy/prod_pipr_tests.txt`. Flow activation afterwards: `prod_deploy/activate_flows_prod.sh`.

Validation (dry run, RunSpecifiedTests) 0AfTx0000013iAPKAY: **Failed, 9 of 205 tests**:
1. ⚠ **Trigger_ContentDocumentLink (v67 = user mode) queries `Include_CII_Hybrid_PDF__c` without FLS → "No such column" → every ContentDocumentLink on an invoice fails, i.e. every invoice PDF in prod would break.** Fix: query in SYSTEM_MODE. Test_Invoices.testGetInvoiceWithFileSuccess.
2. Test_Svc_CIIHybridPdfMerge (2), Test_Svc_CIIInvoiceXmlBuilder, Test_Trigger_ContentDocumentLink (3): "fields being inaccessible on VAT_Code__c". The new fields have no FLS for the running admin (dev / acc passed because trietman has ps_EN16931_Invoicing). Fix: Admin profile FLS for the new EN16931 fields in the package.
3. Test_rbb_Payment_Type and Test_rac_Order fail because prod deploys flows as **Draft**, so the old active versions run during validation. Run them after activation instead of in the deploy.
4. Coverage below 75%: Svc_CIIHybridPdfMerge 0%, Svc_CIIInvoiceXmlBuilder 3%, Trigger_ContentDocumentLink 44% (follow from 1–2), Ctrl_Invoice 71% (Test_Invoices failing; recheck after fix 1).
   - Earlier attempt 0AfTx0000013i5ZKAQ: ps_EN16931_Invoicing referenced the excluded Inv_TriggerCIIHybridPdfMerge; removed in the package copy.

### Next 2 — prod (only on explicit go-ahead)

Prerequisites (block the deploy until done):
- [ ] Exact **prod** divisions: payment conditions `pi` / `pr` (Finance).
- [ ] Real Exact layout ids for Payment_Setting ps_1_pi / ps_1_pr / ps_6_pi / ps_6_pr (prod values; build a `ps_prod_deploy` package like `ps_acc_deploy`).
- [ ] `Term__c` for pi / pr (due date) — open point "later".
- [ ] EN16931 part: EN16931 itself is not in prod (prod has no `Payment_Method_UNCL4461_Mapping__mdt`). Either deploy EN16931 (e3affcb) first, or deploy pi / pr without the EN16931 part (`Ctrl_Invoice`, `Svc_CIIInvoiceXmlBuilder`, UNCL rows, `PayProv_PaymentMethodType__c`) — decide with the user.
- [ ] Remark wording pi / pr approved; card UNCL4461 48 vs 54 (only matters with EN16931).
- [ ] Not around a UK Stripe invoice run (Marc Stone next 2026-10-28, C J Blinco 2026-11-08 at the time of writing; re-check `Contract.Subscription25__Next_Date__c`).

Deploy order (same as acc, see the step sections below; pre-check drift per file against e3affcb first):
1. 0: `rac_Order` (3f60541) — not yet in prod.
2. Step 1 + 1b source deploy; record types via `rt_deploy` (check prod record types first: prod has only B2B / B2C).
3. Labels via `labels_deploy` (+ EN16931 part only if decided).
4. Step 2 source deploy + Payment_Setting rows (prod package) + `afl_PaymentDirectDebitSetup_SendMail` (f31e6e4).
5. Step 3 test class.
6. **Prod flows deploy as Draft**: activate `rac_Order`, `rbb_Payment`, `rab_Payment_Direct_Debit_Setup`, `afl_PaymentDirectDebitSetup_SendMail` via Tooling FlowDefinition.
7. Prod uses RunLocalTests? Prod deploys need tests: run with `--test-level RunSpecifiedTests` and the test lists of the steps (check what prod requires).
8. Check prod `Payment_Processor` value set has Stripe (it does, 2026-10-21) and the prod Administrations (NL Use off, UK Use on; BE → NL Stripe account link still to set on the Belgium Administration).
9. Then step 4 migration (`migration/MIGRATION.md`), then step 5 clean-up.

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

- Org-wide email (`Subscription25__Organization_Wide_Email__c`), copied from prod on 2026-10-21. The send-mail subflow needs it, otherwise "not sent" + case:
  - acc: NL aftersales@movingintelligence.nl, DE buchhaltung@movingintelligence.de, UK accounts@movingintelligence.co.uk (Belgium empty, as in prod).
  - dev: only Germany was empty → buchhaltung@movingintelligence.de. dev NL (aftersales@movingintelligence.com) and UK (noreply@movingintelligence.com) were left as they were.
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

- Prod: activating a flow that references a **just-created object** (rbb_OrderItem v4 → VAT_Code__c, ~90 s after creation) failed on every save ("RawFieldImpl … __NotFound"). After deploying new objects, verify one record save right after activating a flow that uses them, and preferably activate outside business hours.
- Prod validation passes while dev / acc fail to show FLS problems: v67 classes run SOQL / DML in user mode, and the deploying user has the feature permission sets in dev / acc but not in prod.

## Existing wrong combinations (prod, 2026-10-20) — for the 1b clean-up

- Reseller 1 (NL) with I0: 1 account
- Reseller 6 (UK) with I8: 2, I3: 2, p0: 1 (p0 has no rule)

## Rollback

- Rule check: deactivate trigger `AccountPaymentMethodRule` (deploy with `<status>Inactive</status>`), or delete the CMDT row of the code concerned.
- Picklist values: deactivate pi / pr in the global value set (only if no records use them).

## Phase 2 start — card + Apple Pay / Google Pay (dev only, 2026-10-21)

Built in dev (not acc / prod):
- `Svc_PaymentIntent`: SetupIntent (SEPA) and PaymentIntent (Bacs) offer `card` next to the direct debit method; the Payment Element then shows card + wallets. `hasUsableMethod` = PM id AND (type card OR mandate). New `TypeJob` (queueable): GET /v1/payment_methods/{id} → `Account.PayProv_PaymentMethodType__c`; a card clears an old mandate.
- `Svc_StripeEventProcessor`: queues TypeJob for a new / untyped PM (trigger can't call out); Stripe account from `stripeGC__Stripe_Account__c` (= BE PayProv_Account__c).
- `Batch_ProcessPayments`: gate `mandate != null OR type = card`; charges with the saved type (blank → BE direct debit method, as before); no `mandate=` for card.
- `Ctrl_Payment` + `PrepareJob`: "already scheduled" / skip via `hasUsableMethod`.
- `rbb_Payment` v32: Setup only when mandate blank AND type ≠ card (else every card payment re-sent the setup mail).
- `paymentCheckout` iframe: `allow="payment"`.
- Stripe payment method domain `movingintelligence--dev.sandbox.my.site.com` on NL - Dev (pmd_1UT3LrA2nsZIOV3Qqb0hA1Fe) and UK - Dev (pmd_1UT3LsKBFNlFAI2p9QfnUUNw): Apple Pay + Google Pay active.
- 78/78 payment tests pass in dev.
- Not built: card `requires_action` (3DS off-session) status / mail → for now a 402 → payment Failed + Case.

Test data dev: account "TEST Teun card NL" 001bd00000lll6rAAA (B2C, reseller 1, pr), contact teun.rietman@outlook.com; payment PM#000110391 a1nbd00000eyJITAA2 (€12.50, Setup, SetupIntent seti_1UT3MuA2nsZIOV3QKw3SbTvy = [sepa_debit, card]); link https://movingintelligence--dev.sandbox.my.site.com/hub/payment?token=6d3c4c574b8db9be7999b5f01f0fd425 (dev mail not sent: no template / org-wide address).

Phase 2 test plan (dev):
1. Open the link above: the component should show SEPA + Card; Apple Pay in Safari with a card in Wallet, Google Pay in Chrome (test mode, nothing is really charged).
2. Pay with test card `4242 4242 4242 4242` (any future date / CVC) → payment Setup, Interaction "Request Processed by Customer"; account gets PayProv_PaymentMethodId__c + (via TypeJob) PayProv_PaymentMethodType__c = card, MandateId empty.
3. Off-session charge: set Collection_Date__c of PM#000110391 to today, run `Database.executeBatch(new Batch_ProcessPayments(), 20);` → Processing → Paid via webhook.
4. Repeat payment on the same account: new pr payment should be Status **New** (not Setup) and get no setup mail; batch charges it.
5. 3-D Secure case: card `4000 0027 6000 3184` (check Stripe's test-card docs) → off-session charge gets 402 → payment Failed + Case (requires_action handling not built yet).
6. UK: same with a reseller 6 / GBP account (Bacs PaymentIntent + card).
- Only new payments show card: payments created before 8ae638c keep their stored SEPA-only / Bacs-only intent.

#### Incident 2026-10-21 — rbb_OrderItem v4 blocked every OrderItem save in prod
- From 17:23:14 UTC (v4 activation), `dgr_03_VAT_Code_Lookup` failed on every save with "unable to parse field ... RawFieldImpl[tableName: 01ITx000004NAHM__NotFound, columnName: 00NTx00000BcOHk__NotFound]". Those are prod's own ids: `VAT_Code__c`, created 17:21:47, and `Internal_Code__c`.
- No OrderItem was created or changed after 17:23:17. The same v4 has run fine in acc since 2026-09-21, also with 0 VAT codes.
- Probable cause: the flow was activated about 90 s after the object was created, and the runtime could not resolve the object yet. Not confirmed: the Current User in the error email has not been checked against VAT_Code__c access.
- ~20:46 UTC: v3 re-activated by the user through FlowDefinition. v4 adds nothing in prod for now (0 VAT_Code__c records).
- To do: confirm one OrderItem save; re-activate v4 outside business hours, then do a single test save; load VAT_Code__c data in acc and prod (dev has 9).
- Damage found (Event_Log + CP/RO/Order check): 7 failed operations. Most self-healed after v3 was re-activated:
  - Security Platform `/UpsertContract` retries succeeded at 20:51 (Peter Honing, Ferry Helmer, Harry hubbard Black.12, Qane BlackR.12).
  - `Batch_ActivateDraftContractProducts` created Diane Ouzman's order at 20:50.
- Still broken: 14 Activated CPs whose RO has `Next_Date = Start = 2026-10-21` and no order. The normal pattern is that the first order arrives within ~5 min and Next_Date moves forward a period; the baseline was checked per product type.
  - Badr Achattib ×2, David Waldron, High Efficiency Heating, Forza Doors, DLM, Autoshop Bergeijk ×2, Qane fee, Harry hubbard fee, Neelissen ×2, Van de Velde Yerseke ×2.
- Repair: a no-op `update` on the CP fires `RecurringOrderAfterUpsert`. This is the same path as the 20:51 retries. Pilot = CP-1034645 (Harry fee), then the other 13. Scripts were in the session scratchpad (pilot.apex / bulk.apex).
- David Waldron: one UK `/UpsertContract` call (extId 93004_1, 18:00:34) failed and was never retried. Whatever it carried has to be resent by the UK system.
- Not checked: Elaine Roden / Mark Hicks (UK .999, start 2031-08) and Peter Hicks (start 11-21). They are not due yet, so no damage is expected.
- Repair DONE 2026-10-21/22. Method: a no-op `update` on the CP, **one transaction per CP**; a single transaction for 11 CPs hit "Subscription25: Too many SOQL queries: 101".
  - 14 activated CPs have their order: Badr ×2, Waldron (invoiced by the user, PM#000206388 psp-recurring in Setup + mail), High Efficiency, Forza, DLM, Autoshop ×2, Qane fee, Harry fee, Neelissen ×2, Van de Velde Green.12.
  - The Van de Velde 800.900.9009 fee gets no order line. This is normal: that account's earlier contract and several other accounts don't get one either.
  - 5 Closed UK CPs (start ≤ ~1 month) got their order: Carol Macaulay 02752285, John Skinner 02752286, Derek Thomas 02752287, Wendy Nock 02752288, stephen williams 02752289. Closed UK CPs that start in 2027+ normally get no order at creation, so they were left alone.
- Still open: the UK `/UpsertContract` call 93004_1 (David Waldron), never retried; the error emails / UI saves; re-activate v4 + load the VAT_Code__c data.
