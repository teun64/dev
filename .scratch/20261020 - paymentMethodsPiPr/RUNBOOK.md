# Runbook — payment methods pi / pr (Stripe route split)

Plan + decisions: Claude Doc "Payment methods pi / pr — Stripe route split"
https://claude.ai/code/artifact/909cb4ca-f6bb-4c39-bec2-8bb2a9c16803

## ✅ DONE — rbb_OrderItem outage follow-up (morning 2026-10-22)

**Final state (re-checked 2026-10-28):** active `rbb_OrderItem` = prod **v7** (since 2026-10-22 11:36 UTC), acc **v7**, dev **v14**. Design: `OrderItem.VAT_Code__c` → `Subscription25__VAT_Code__c` (category in `UNCL5305_Category__c`); own `VAT_Code__c` object removed. v4 / v5 were deleted along the way. No other runbook covers rbb_OrderItem; the memory notes are summarised here.

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
- [x] **VAT category moved to the package VAT code (user decision 2026-10-22, commit 8b23c04)**
  - **New design:**
    - `Subscription25__VAT_Code__c.UNCL5305_Category__c` holds the category per Administration and code (0 O, 1 S, 2 S, 6 G, 7 K, 25 rows per org).
    - `OrderItem.VAT_Code__c` is recreated (same name) as a lookup to `Subscription25__VAT_Code__c`. rbb_OrderItem fills it by code + `Order.Subscription25__Administration__c`.
    - `Svc_CIIInvoiceXmlBuilder` resolves the category itself from the package VAT codes of the invoice's Administration, no longer through the lookup.
    - The `VAT_Code__c` object is removed.
  - **dev + acc: done.**
    - Deleted the obsolete flow versions that referenced the old field: rbb_OrderItem dev v11/v12, acc v4/v5; rau_Contract_Termination_Reverted dev v3/v4, acc v1.
    - Deleted 1 acc error interview (user OK).
    - Field and object deleted with purge, then recreated.
    - Draft lines re-linked: dev 231; acc 12,000 of ~42,500 (rest not needed).
  - **prod 2026-10-22 (user's go-ahead):**
    - A: 0AfTx0000013lhlKAA (8/8 tests) put the picklist, FLS, builder, tests and interim rbb v6 (v3 logic) live at 11:04 UTC.
    - B: categories filled.
    - C: deleted the 101 error interviews from the outage (user OK) and rbb v4/v5.
    - D: deleted the old field (0AfTx0000013lkzKAA); the user erased it in Setup; then deleted the object (0AfTx0000013lt3KAA).
    - E: new lookup + FLS (0AfTx0000013lwHKAQ, 11:14 UTC).
    - F: final rbb v7 deployed (0AfTx0000013m7ZKAQ) and active since 11:36 UTC. Test saves: UK 2 → United Kingdom/S (×2), NL 2 → Netherlands/S.
    - G: 6,023 Draft lines re-linked, 0 failed, amounts unchanged, 0 remaining. ✅
  - The user changed in prod, and the same was copied to dev and acc:
    - label "Category (UNCL5305)" (6a2b1bd)
    - VAT Code Layout (fc270e6)
    - Administration layouts, own + package (3dea30d)
  - **Still to check:** after the UK invoice run (~17:00 UTC), the CII XML of the new invoices shows the category (now via the package VAT codes).
- [x] ~~**rbb_OrderItem VAT_Code: analysis 2026-10-22 + prod activation pending**~~ (superseded by the move above)
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
| 4 | Migration of the 2 UK Stripe accounts I8 → pr + 3 paid payments I8 → pr: package prepared in `migration/` (MIGRATION.md) | — | — | ◐ accounts ✅: **C J Blinco pr** (2026-10-22 14:08 UTC) and **Marc Stone pr** (2026-10-28 07:40 UTC), both by Teun Rietman; Stone's draft order 02757166 (28-10) already on pr; Stone's invoice I-2610-00762075 corrected I8 → pr by the user (2026-10-28 07:43 UTC). Blinco's invoices I-2610-00767505 / I-2609-00746189 still I8. ✅ **3 paid payments → pr** 2026-10-28 (user go-ahead, bulk job 750Tx00000gPqL2IAK, 0 failed): PM#000196930 / PM#000201568 / PM#000205903 now pr / psp-recurring / Paid / Stripe. Side effect as expected: rbb_Payment recalculated Collection_Date on 2 (09-20 → 09-16, 10-13 → 10-09); originals in `migration/before_prod_payments_20261028.csv`. No Cases. Prod now 0 psp-dd payments and 0 accounts I8 + Stripe mandate → step 5 unblocked |
| 5 | Clean-up: repo-only flows `rac_Payment` / `rac_Payment_DirectDebit_Setup_Email` removed (a378cd5). Removing the I8 + Stripe branches and deactivating psp-dd: go-ahead given 2026-10-28, unblocked 2026-10-28 (step 4 done: prod 0 psp-dd payments, 0 accounts I8 + Stripe mandate) | ✅ partly | — | ⏳ after step 4 |
| 6 | Manuals: moved to the end of phase 2 (user 2026-10-28), see "CONTINUE 2026-10-28" | ✅ docs | | ⏳ end of phase 2 |
| 2 | `rbb_OrderItem` (EN16931 VAT_Code lookup, now to `Subscription25__VAT_Code__c`) | ✅ v14 | ✅ v7 | ✅ v7 since 2026-10-22 11:36 UTC (checked 2026-10-28); v4 outage resolved |
| — | EN16931 SYSTEM_MODE fixes (`Trigger_ContentDocumentLink`, `Svc_CIIInvoiceXmlBuilder`, `Svc_CIIHybridPdfMerge`, test fixtures, `Test_Ctrl_InvoiceRemarks`), commit ce00cb4 | ✅ 2026-10-21 | ✅ 2026-10-28: `Trigger_ContentDocumentLink`, `Svc_CIIHybridPdfMerge`, `Svc_CIIInvoiceXmlBuilder` deployed (NoTestRun) + `Test_Ctrl_InvoiceRemarks`; tests 9/9 pass | ✅ 2026-10-21 |
| P2 | Phase 2: card + Apple Pay / Google Pay + 3DS (see "Phase 2 start"), commits 8ae638c + bfe4942 | ✅ 2026-10-21 | ✅ 2026-10-28 | — |

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
- 2026-10-27: the test link showed the checkout without a Stripe element. Cause: the dev Customer Hub LWR site still served an old published build. That build's payment_view had no `alreadyScheduled` handling, used iframe `?v=11` and had no `allow="payment"`. A card was already saved on 2026-10-26 (pm_1UUmqWA2nsZIOV3QeCbwqlAC), so `getPaymentData` returned alreadyScheduled with no client secret, and the old build rendered an empty checkout. Fix: published the dev site. acc and prod builds checked and current. PM#000110391 now shows "scheduled" (collection 2026-10-29); testing the card form again needs a new pr payment on an account without a saved method. Side note: the scheduled text says "Direct Debit" for a card too (label wording, phase 2).
- 2026-10-27, test step 5 (3DS) result on PM#000110391: the card saved on 2026-10-26 was the 3DS test card (…3184). Collection date set to today and `Batch_ProcessPayments` run (707bd00001bVvwj). Stripe returned `authentication_required` (pi_3UV7qmA2nsZIOV3Q0ZZ7WjQC, requires_payment_method), so the payment is **Failed** with a Case, as expected while 3DS handling is not built. Findings: two Cases per failure (MI00234168 from the batch, MI00234169 from the payment_failed webhook), and both subjects say "Direct Debit" for a card. Also: in dev the batch never runs by itself (dispatcher step Minut_ProcessPayments not firing), so dev payments stay in Setup until it is run manually.
- 2026-10-27, new test data for steps 1–4: account "TEST Teun card NL 2" 001bd00000nC0kdAAC (contact 003bd00000zvVxAAAU, teun.rietman@outlook.com), payment PM#000110392 a1nbd00000jFG17AAG (€12.50, pr, psp-recurring, Setup, collection 2026-10-29, SetupIntent seti_1UV7rhA2nsZIOV3QHZX9T2qi, customer cus_VWACI5PJxXw9fF). Link: https://movingintelligence--dev.sandbox.my.site.com/hub/payment?token=a5053188e1be20e51e43ee602364c946. Payment.Processor__c is empty (the old test payment had Stripe).
- 2026-10-27, dev test steps 1–4 **PASSED** on "TEST Teun card NL 2":
  - Step 1: the page loads the form with SEPA + card.
  - Step 2: card 4242 saved. Account gets pm_1UV7uVA2nsZIOV3QMCGuHaML; TypeJob sets the type to card; no mandate, which is correct, since a card has none. The page then shows "already scheduled".
  - Step 3: batch charges PM#000110392 off-session → Paid (pi_3UV7vHA2nsZIOV3Q03OUzu1o).
  - Step 4: repeat payment PM#000110393 a1nbd00000jGhDZAA0 starts in New, with no setup and no mail. After a due date was set, the batch charged it → Paid (pi_3UV7x8A2nsZIOV3Q1ltq6zuf).
  - Test-data note: a payment created without Due_Date__c gets no Collection_Date__c (rbb_Payment fCollectionDate = due date − processing time), so the batch never picks it up. Real payments get the due date from the invoice.
  - The setup email Case MI00234170 is the known dev gap (no template / org-wide address).
  - The success screen after saving a card says "payment received", although nothing has been charged yet; check the wording.
  - Not yet tested: Apple Pay / Google Pay (step 1 wallets), UK reseller 6 + card (step 6).

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

#### Phase 2 changes 2026-10-27 (dev, deployed + site published; not committed)
- Apple Pay merchant token: `paymentPage.applePayRequest` → `c-payment-checkout apple-pay` → iframe `elementOptions.applePay = { recurringPaymentRequest }` (paymentCheckoutHtml `?v=13`).
- Labels: paymentPage "Automatic payment scheduled" + new "Payment method saved" texts after a SetupIntent (en/nl/de/fr).
- Case subjects: "Card payment failed / failure / reversal / charged twice" when Account.PayProv_PaymentMethodType__c = card (Batch_ProcessPayments, Svc_StripeEventProcessor; its payment query is now WITH SYSTEM_MODE because the type field has no FLS). Ctrl_PaymentCase (on-session failure) left alone because it has unrelated uncommitted WIP.
- Tests: Test_Batch_ProcessPayments + Test_Svc_StripeEventProcessor 14/14 (new testDueCardPaymentCaseSubject). Jest not run: local node is broken (missing libicu 73).
- 3-D Secure approach written in the plan doc ("Phase 2" section): Action Required status + payment-link mail, on-session confirmation of the same PaymentIntent, Failed + one Case after N days.

#### 3-D Secure build 2026-10-27 (dev, deployed + site published; not committed)
- New Payment__c.Status__c value **Action Required**.
- Batch_ProcessPayments and Svc_StripeEventProcessor: authentication_required → Action Required + PI id + token `Svc_PaymentIntent.newToken(paymentId, intentId)`; the token is deterministic so batch and webhook write the same one. No Case.
- Svc_PaymentIntent.stripeError(e) reads code / intent / method out of the stripeGC "Stripe callout error: {json}" message.
- Ctrl_Payment: Action Required → mode `authenticate` (stored PI client secret + saved/declined pm, via applyAuthenticateIntent).
- Page / iframe (`?v=14`): no Payment Element in this mode; confirmPayment({clientSecret, confirmParams.payment_method}); error shown in the iframe; no on-page failure Case.
- Flow rab_Payment_Action_Required v1 (active in dev) → Svc_PaymentActionRequired: mail right away, reminder day 3, expire day 7 (Failed + one Case gqPayment).
- Templates needed in acc / prod: paymentAuthenticationRequired_NL/_DE/_FR/_EN (Classic, by Name; EN fallback). dev: AlertMessage "no email template found".
- Tests 47/47: Test_Svc_PaymentActionRequired (new), Test_Svc_PaymentIntent, Test_Svc_StripeEventProcessor, Test_Batch_ProcessPayments, Test_Ctrl_Payment. Coverage: Ctrl_Payment 82%, Svc_PaymentIntent 75% (tight).
- Test data:
  - A. Recovery: PM#000110391 a1nbd00000eyJITAA2 set to Action Required (pi_3UV7qm…, card 3184). Link token 6d3c4c574b8db9be7999b5f01f0fd425.
  - B. Full chain: account "TEST Teun 3DS NL" 001bd00000nCgp0AAC, payment PM#000110394 a1nbd00000jHmntAAC (Setup, due + collection 2 days ahead). Link token a1065dec5fa38c54a825917e7babfeb7.
- 2026-10-27 test A **PASSED**:
  - PM#000110391 Action Required → page in authenticate mode → 3DS challenge → Complete. The same PI pi_3UV7qm went requires_action → succeeded, and the payment is Paid (11:36). No new Case; MI00234168 and MI00234169 are from the run before the build.
  - Fix found during the test: the challenge was clipped by the iframe height. The iframe now grows to 680px while the challenge is open (`?v=15`, site published).
- 2026-10-27 retest after resize, batch path:
  - New payment PM#000110395 a1nbd00000jHI3XAAW (€14.75) on "TEST Teun card NL" (card 3184).
  - The batch got 402 and set **Action Required** with pi_3UV8hpA2nsZIOV3Q0Gmm4ter and a generated token 289458fda1d5ed41a745c71dac4b4912.
  - The payment_failed webhook arrived and kept Action Required; **no Case**. The flow ran the mail step (AlertMessage: no template in dev).
  - The page confirmation by the user is pending.
- 2026-10-27 retest page confirmation: Stripe has pi_3UV8hp **succeeded** (ch_3UV8hp…). The page set PM#000110395 to Processing. But payment_intent.succeeded is stuck at Stripe (pending_webhooks=1, first delivery failed; the neighbouring events arrived), so the payment is not Paid yet. Fix: resend from the Stripe dashboard, or wait for the test-mode retry. Gap: nothing reconciles Processing payments whose final event is lost.
- 2026-10-27 test B (full chain):
  - The user saved card 3184 with a 3DS challenge at setup: pm_1UV8tB…, type card.
  - The batch got 402 and set PM#000110394 to **Action Required** (pi_3UV8vYA2nsZIOV3Q1E2ELlUa). The existing setup token a1065dec… was kept, so the same link works. No Case; mail step → AlertMessage (dev).
  - Note: rbb_Payment recalculates Collection_Date__c only on create / Request_Date / Method change, not when Due_Date__c changes.
- 2026-10-27 test B **PASSED**: the user confirmed via the same link (requires_action 12:33:20 → succeeded 12:33:25), and PM#000110394 is **Paid**. No Case on either test account.
- PM#000110395 (retest): Stripe's retry delivered payment_intent.succeeded at 12:14 (~30 min after the failed first attempt), so it is **Paid**. The delivery gap healed itself in test mode. The open point stays: there is no reconcile for a Processing payment whose final event is lost for good.
- 2026-10-27 test data for the method matrix (each payment €/£12.50, pr, Setup, due date today+3):
  - C1 Apple Pay: "TEST Teun applepay NL" 001bd00000nEdi3AAC, PM#000110396, token b3953cb069c0c2002834d7fabe35eb4f.
  - C2 Google Pay: "TEST Teun googlepay NL" 001bd00000nEdi4AAC, PM#000110397, token 40b876df8662568288ee271e25185eb5.
  - D SEPA: "TEST Teun sepa NL" 001bd00000nEdi5AAC, PM#000110398, token f9b7237bc515b4a2d3137f6e2ec6e235.
  - E UK Bacs (reseller 6, GBP): "TEST Teun bacs UK" 001bd00000nEdi6AAC, PM#000110399, Bacs PaymentIntent pi_3UV9ai… on UK - Dev, token 33d6ac9b884ed45b37b03fd66d425694.
- 2026-10-27 "element not loading / no SEPA / no Apple Pay" on the NL setup pages:
  - Not a load failure. With real time (DevTools client, scratchpad cdp.py) the element shows Card | SEPA Debit tabs; the headless screenshots with --virtual-time-budget were taken before Stripe finished.
  - But Card was the default tab. Fix: `paymentMethodOrder = [entity method, apple_pay, google_pay, card]` (`?v=16`, site published). SEPA (NL) / Bacs (UK) is now pre-selected.
- Payment methods per intent (checked in Stripe 2026-10-27):
  - SetupIntent (SEPA entities): [sepa_debit, card], usage=off_session.
  - First-payment PaymentIntent (Bacs entity): [bacs_debit, card], setup_future_usage=off_session.
  - Batch off-session PaymentIntent: [saved type] + payment_method (+ mandate unless card), off_session=true.
  - Apple Pay / Google Pay are not separate types: they come with `card`.
  - Ctrl_StripePayment1 (hard-coded £20, automatic_payment_methods) has no callers: a dead prototype, remove in clean-up.
  - Cosmetic: the batch sets metadata PaymentType=Direct Debit for card charges too.
- Test E UK Bacs: PM#000110399 **Paid** with pm_1UVA71… type bacs_debit. Account mandate still empty (Bacs mandate activation is delayed in test mode → mandate.updated later); check before an off-session repeat.
- 2026-10-27 test D SEPA **PASSED**: the setup saved pm_1UVAJw… + mandate_1UVAJw…, then the batch charged off-session and pi_3UVAKV… gave PM#000110398 **Paid** (SEPA test IBAN settles fast). PayProv_Mandate_Status__c still empty (known).
- 2026-10-27 Apple Pay / Google Pay not shown: cause = the Stripe account's default payment method configuration had apple_pay / google_pay **off** (NL - Dev pmc_1S3waIA2nsZIOV3QxloEhv2K; card + sepa on). Turned **on** via the API for NL - Dev (test mode). UK - Dev and DE - Dev are **not changed** (the permission check blocked the automated change; ask the user / do it in the dashboard). acc + prod Stripe accounts: check the same setting before a wallet go-live.
- 2026-10-27 test C1 Apple Pay **PASSED**: the setup saved pm_1UVAmW… (type card, wallet apple_pay, Mastercard 0408), then the batch charged off-session and PM#000110396 is **Paid** (pi_3UVAnx…).
- Demo data: "TEST Teun applepay demo" 001bd00000nEgkoAAC, PM#000110400 a1nbd00000jMPU5AAO, token 4e75fcdc05c1acd3635e68f4df6d0be9.
- 2026-10-27 demo link in Chrome ("not working"): checked with the DevTools client in real Chrome. The element loads fine (SEPA Debit pre-selected + Card, fields prefilled, no errors). Apple Pay never shows in Chrome (Safari / Apple devices only). Google Pay only shows when Chrome is signed in to a Google account with a saved card. Waiting for the user's screenshot if "not working" means something else.

#### pr lock on Account.Payment_Method_Contracts__c (2026-10-28, dev + acc deployed, not committed)
- User decisions: lock **pr only**, block back to **I-codes** only (pr → 08 / 30 stays allowed), Payment_Method_Opportunities__c **unlocked** (Opportunity lock: evaluate at the end), exception via Finance.
- `vr_PaymentMethodContractsProviderLock` (Account): ISCHANGED + PRIORVALUE = pr + new LEFT 1 = I; exempt `$User.isSysAdmin__c`, profile miAPIIntegration, `cp_AccountPaymentMethod_Change`.
- Custom permissions `cp_AccountPaymentMethod_Change` (used by the VR) and `cp_OpportunityPaymentMethod_Change` (no rule yet, reserved for the Opportunity lock).
- Permission sets `ps_miAccountPaymentMethod_Change` and `ps_miOpportunityPaymentMethod_Change` (names with mi per the naming rule; user asked for ps_OpportunityPaymentMethod_Change).
- `Rest_UpsertAccount`: existing account on pr keeps pr when the mapping would give an I-code (no IBAN-based I8 / UK I0 overwrite). Test `testPrNotOverwrittenByDirectDebitCode`; VR tests in `Test_Util_PaymentMethodRule`. dev 32/32, acc 32/32.
- **pg_miFinance exists only in prod** (dev / acc have the old pg_Finance_NL), so the group change is prod-only: retrieve prod's pg_miFinance, add both ps.
- Sales users Jonas Maassen, Laura Wilson, Sean McGrath, Dennis Lorenz, Ricardo Wilke exist only in prod → assign ps_miOpportunityPaymentMethod_Change there.
- Prod (on go-ahead): deploy cp ×2, ps ×2, VR, Rest_UpsertAccount + 2 test classes (RunSpecifiedTests), pg_miFinance, then the 5 assignments.

#### Contract codes + UK contract default (2026-10-28, dev + acc deployed, not committed)
- **p1, pi and C are not allowed as the Account's contract payment method** (C = credits only). New CMDT checkbox `Payment_Method_Rule__mdt.Not_On_Contracts__c` = true on PMR_p1 / PMR_pi / PMR_C; `Util_PaymentMethodRule.checkContracts` runs for `Payment_Method_Contracts__c` only (new or changed values, as the rest of 1b). Opportunity field unaffected.
- Scope is the **Account** field only. Prod has p1 on 12,421 Contracts and 2,913 Activated Contract Products, C on 200 Activated CPs (webshop / credit route), so Contract / CP level is not checked. Existing accounts: C ×19, p1 ×9 (all 2023), untouched until edited.
- **`Rest_UpsertAccount` UK contract default I0 → pr** (user): UK with bank account (no code, or an I-code sent) → pr; UK without bank account stays 08. Requires UK PayProv_Use__c = true (true in dev / acc / prod), else the 1b rule rejects pr. Test `testUkDirectDebitDefaultIsPr`.
- Risk: a platform sending p1 / pi / C as contract code now gets a 400 on the account. None created since 2023, so not expected.
- Tests dev 34/34, acc 34/34 (Test_Util_PaymentMethodRule + Test_Rest_UpsertAccount).

#### Opportunity default p1 → pi in Rest_UpsertAccount — analysis 2026-10-28 (built, see below)
- Line 171, **new accounts only**: UK (6) → platform 5 '14', business '08', private **'p1'**; others → no IBAN '08', else 'I8'. **No I0 in the Opportunity default**; the I0 was in the Contracts default and is now pr (see above).
- p1 route today: `ps_6_p1` (prod only, not in repo) AutoCreate **false**, Processor Opayo; the payment is created by `scr_General_Get_Payment_Opayo` (Method p1). Invoice remark "paid via webshop". Order flows treat p0 / p1 as paid: `rbb_Order` dec_01 (first order payment reference) + dec_02 (renewal reset), `rbc_Order` dec_02 (reset), `rbc_Order_Package_Subscription25` dec_01 (reference).
- pi today: `ps_6_pi` AutoCreate **true**, Stripe → Stripe payment (psp-immediate) + payment link on invoice finalize; remark paymentRemarkPI; not in any order-flow p0 / p1 condition.
- Consequence if the default simply becomes pi: webshop (Opayo) customers get an extra Stripe payment link for an already paid order; no payment reference on the first order; renewals not reset; wrong invoice remark.
- To route pi like p1 (for now): add pi to the 4 order-flow conditions; ps_6_pi → AutoCreate false + Processor Opayo (as ps_6_p1); Ctrl_Invoice (prod's own version) give pi the P remark; scr_General_Get_Payment_Opayo unchanged (sets p1 on the payment).

#### pi follows the p1 route + C for Finance (2026-10-28, dev + acc deployed)
- User 2026-10-28: C stays allowed on the account contract method for Finance / admins (new CMDT checkbox `Contracts_With_Permission__c` on PMR_C; uses cp_AccountPaymentMethod_Change); p1 / pi never. The 4 internal C accounts (Moving Intelligence B.V. ×2, Technocon, Patrick Horst; 200 active €0 CPs) stay on C. Own code for free subscriptions: not now.
- **pi = p1 route (for now):**
  - `rbb_Order`: pi added next to p0 / p1 in dec_01 (first-order payment reference) and dec_02 (renewal reset). dev v21, acc v11 active. `rbc_Order` / `rbc_Order_Package_Subscription25` are active nowhere, so they are not changed.
  - `Payment_Setting.ps_6_pi`: AutoCreate false, Processor Opayo, invoice text = p1's ("already paid via card payment"). `ps_6_p1` added to the repo (same in all orgs). `ps_1_pi` (NL) unchanged: still Stripe AutoCreate.
  - `Ctrl_Invoice`: only pr keeps its own remark; pi gets the p1 remark. Repo = dev = acc. **Prod has its own Ctrl_Invoice**: same change prepared in `prod-pilock/Ctrl_Invoice.cls` (copy to a non-dot folder before deploying).
  - `Rest_UpsertAccount`: UK private Opportunity default p1 → **pi** (new accounts only). Test `testUkPrivateOpportunityDefaultIsPi`.
  - UNCL4461 left: pi = 68 (online payment service), p1 = 48 (bank card).
- Tests dev 42/42, acc 42/42 (Test_Rest_UpsertAccount, Test_Util_PaymentMethodRule, Test_Ctrl_InvoiceRemarks, Test_Ctrl_InvoiceEstablishmentAddress).
- **acc test before prod (user):** new UK private account through REST → Opportunity pi → order → first order gets the payment reference, invoice shows the p1 remark, no Stripe payment created. Also: set a pr account to I8 as a UI user (blocked), and C on a contract method without the permission (blocked).
- **acc REST replay 2026-10-28 — PASS:** the 3 prod `RestUpsertAccount` request bodies for UK private customer Peter Sledge (MI 85281, platform 3) were taken from OAuth_Log__c.Request_Body__c and replayed in acc, with the email changed to trietman@movingintelligence.nl. Results:
  1. Create (08, no bank): Opportunity **pi**, contract 08.
  2. Bank update (I0): contract **pr**.
  3. Repeated I0: contract stays **pr**.

  acc account: 001G500001UpbUHIAZ. Still open: Opportunity → order → invoice on that account; the UI pr→I8 and C checks are covered by unit tests.
- **acc replay of hardware + contract 2026-10-28:**
  - Hardware 9297100: no request left in the logs (they go back to 2026-10-19), so it was rebuilt from the prod asset (`9297100-hw-3`, serial 4635409592). In acc it is placed on Sledge's account (85281); in prod it sits on MI account 60744, which doesn't exist in acc. acc asset: 02iG500000BoWXpIAN.
  - Contract 93154_1: the prod request was replayed unchanged (`paymentMethod: "I0"`). acc contract UK.ITRACK.S5P.01.D, CP-1478574 (a0VG500000H7VbZMAV).
  - ⚠ **Gap:** the contract and the CP got **I0** while the account is on **pr**. MI sends `paymentMethod: "I0"` on every UK DD contract. `Rest_UpsertContract` (around line 466 for the contract, around line 822 for the CP) copies that code whenever it differs from the account's method. So every new contract on a pr account lands on I0, and the pr lock is bypassed at contract level. The same code is in `Rest_UpsertContract - Prod.cls` (442/740) and `Rest_UpsertContractV2.cls` (496/852). Must be fixed before the prod deploy: if the account is pr, an incoming I-code is treated as pr.
- **Prod 2026-10-28 (user request): Peter Sledge 001Tx0000122JuaIAE → pr.** Account Payment_Method_Contracts__c I0 → pr; draft order 02756583 I0 → pr (it did not follow the account automatically). Old values in `migration/before_prod_sledge_*_20261028.csv`. Done the same way as Blinco/Stone/Waldron: the CP (CP-1035659) stays I0 and the contract method stays empty; the Opportunity method stays p1. No invoice or payment yet. The first pr invoice gives a psp-recurring payment + mandate setup mail (as with Waldron). Prod pr accounts now 4. ⚠ Until 350c7f6 (REST guard + VR) is in prod, the next MI `/UpsertAccount` call with I0 resets the account to I0 (this affects Waldron too): check after each MI update.
- **Prod (after the acc test, on go-ahead):** commits 350c7f6 + the pi route commit. Deploy cp ×2, ps ×2, VR, CMDT fields + PMR rows, Util_PaymentMethodRule, Rest_UpsertAccount, prod Ctrl_Invoice copy, ps_6_pi, ps_6_p1, rbb_Order (lands as Draft → activate via FlowDefinition, then 1 test save) + tests (RunSpecifiedTests). Then pg_miFinance (retrieve prod copy, add both ps) and ps_miOpportunityPaymentMethod_Change for Jonas Maassen, Laura Wilson, Sean McGrath, Dennis Lorenz, Ricardo Wilke.

#### acc test set 2026-10-28 (after 8858288 + 8e1b801)
- **Rest_UpsertContract fix (8858288):** a pr account plus an incoming I-code gives pr: a new contract inherits pr, and the CP gets pr. Activated contracts are not touched by REST (contract fields only change on new or Draft contracts), so Sledge's existing contract was cleared by hand (Payment_Method__c → empty); its CP CP-1478574 became pr through the resend. Prod: deploy together with 350c7f6 (the prod copy `Rest_UpsertContract - Prod.cls` has the same guard but also unrelated uncommitted changes, check before deploy).
- **Util_Crypto bulk bug (8e1b801):** the invocable returned 1 result for N requests, so with several payments set up in one transaction only one got a token / Setup_URL, yet all were marked "Mail Sent" (link without a token). Also used by rab_Contact. Fixed dev + acc; **prod needs it** before more pr payments arrive in bulk (invoice run).
- Stripe payment method domain `movingintelligence--acc.sandbox.my.site.com` registered: NL - Acc pmd_1UVWdrABHKG9R0t248ynINrn, UK - Acc pmd_1UVWdsGxR72SaSls6klzRCV5 (Apple Pay + Google Pay active).
- Test payments (all mail to teun.rietman@outlook.com; the REST endpoint strips the +tag):
  - Card: "TEST Teun card NL" 001G500001UqbEbIAJ, PM#000136966, token 796a81777163aa1850b99790e2b7f10f
  - Apple Pay: "TEST Teun applepay NL" 001G500001UpmKMIAZ, PM#000136965, token 784c5ac690cff455d6e06961264fa873
  - Google Pay: "TEST Teun googlepay NL" 001G500001UqbHpIAJ, PM#000136967, token ad123463fe081705c183a7f4ef237c32
  - Direct debit (UK Bacs): Peter Sledge 001G500001UpbUHIAZ, PM#000136958 (£15, pi_3UVVv0…), token 7bfba48a74711f43b2aa20a1c0b78664; first mail went to trietman@movingintelligence.nl (contact now teun.rietman@outlook.com).
  - Sledge's second contract: hardware 990000001 "TEST-SLEDGE-2" (02iG500000BodUTIAZ), contract 990001_1 (CP-1479381, pr, Draft until the activation job) → order → invoice → 2nd payment: expect status New (mandate known), no setup mail, charged by the batch.

#### ⏰ CONTINUE 2026-10-28 (phase 2, dev)
- [ ] Demo link Chrome: get the user's screenshot (token 4e75fcdc…) and trace it if it isn't just the missing wallet tab.
- [ ] C2 Google Pay test in Chrome signed in with a Google account + card (PM#000110397, token 40b876df8662568288ee271e25185eb5).
- [ ] E UK Bacs repeat charge once the Bacs mandate is active (account 001bd00000nEdi6AAC; check PayProv mandate fields first).
- [ ] Wallets on UK - Dev / DE - Dev payment method configuration: user decides (dashboard, or allow the API change). Same check on acc / prod Stripe accounts before a wallet go-live.
- [ ] Classic email templates paymentAuthenticationRequired_NL/_DE/_FR/_EN (dev first, then acc / prod).
- [ ] One Case per failure on the setup side (Ctrl_PaymentCase; has unrelated uncommitted WIP).
- [ ] Reconcile for Processing payments whose final Stripe event is lost.
- [ ] Optional: "Visa •••• 3184" line in authenticate mode (offered, not confirmed).
- [ ] Clean-up: remove Ctrl_StripePayment1; batch metadata PaymentType for card charges.
- [ ] Decide pi (one-off) link/mail flow.
- [ ] Commit phase 2 + 3DS (nothing committed yet; use a `-- <files>` pathspec, other WIP is in the tree).
- [x] Commit phase 2 + 3DS: bfe4942 (2026-10-28).
- [x] acc deploy 2026-10-28: 8ae638c + bfe4942 (16 components: 4 payment classes + Svc_PaymentActionRequired + 5 tests, rbb_Payment → acc v12, rab_Payment_Action_Required v1 active, paymentCheckout / paymentPage, static resource paymentProvider, Payment__c.Status__c + Action Required). Before the deploy, acc was exactly the pre-phase-2 repo state. Tests 88/88 (payment tests + Util_PaymentMethodRule + Rest_UpsertAccount). Customer Hub acc published; serves paymentCheckoutHtml `?v=16`. Not in acc yet: paymentAuthenticationRequired_* templates (not built anywhere), Apple/Google Pay domain on the acc Stripe accounts (not checked), Ctrl_PaymentCase WIP. Prod only on explicit go-ahead.
- [x] Step 4 (prod) done 2026-10-28: both accounts + the 3 paid payments on pr.
- [ ] Verify that Stone's order 02757166 (pr) is invoiced on pr with a psp-recurring payment.
- [ ] David Waldron 001Tx000011XwKHIA0, the first new customer on pr (not migrated): mandate set up (mandate_1UTvUT…, pm_1UTvUS…, PayProv_Mandate_Status__c empty as known). Invoice I-2610-00772018 is pr. PM#000206388 (£15, psp-recurring) has been **Processing** since 2026-10-24 03:19 UTC; Bacs settles in ~3 working days, so it should be Paid by ~10-29. Check it. Prod pr accounts (2026-10-28): 3 = Blinco, Stone, Waldron.
- [ ] Step 5 clean-up (go-ahead 2026-10-28) right after step 4: drop I8 + Stripe routing (rbb_Payment, Payment_Setting ps_6_I8 = Stripe), psp-dd from Batch_ProcessPayments / rab_Payment_Direct_Debit_Setup / rbb_Payment, deactivate `Payment__c.Type__c` psp-dd. Check 0 accounts I8 + PayProv mandate and 0 psp-dd payments first.
- [ ] Step 6 manuals (moved here 2026-10-28): update Payment Methods key-user 3e4ed1e5 + developer 1d00eaa3 with phase 2 / 3DS, then the PDFs (weekly backlog rows 10–11).

## acc test results + follow-up fixes (2026-10-28, afternoon)

Tested by Teun in acc: card (PM#000136966) OK, Apple Pay (PM#000136965, Safari) OK, Bacs Sledge (PM#000136958) OK → Paid. Google Pay: not offered by Chrome, parked by Teun.

| Commit | Fix | dev | acc |
|---|---|---|---|
| (data) | Sledge's pre-phase-2 PaymentIntent got `card` added (open intents are reused as-is → old ones stayed DD-only; code fix 7075220 now adds card on reuse, dev + acc) | – | ✓ |
| 6611087 | Payment page: Stripe Link off (prefilled email → Link took over the form) | ✓ | ✓ |
| 93c1689, 81a94bd | Payment page language from contact (payment contact → payment/main contact → billing country), hub header pill follows | ✓ | ✓ (site published) |
| d1bb70c | Svc_StripeEventProcessor: mandate.updated arriving before the intent event is linked afterwards (Sledge got no mandate) | ✓ | ✓ (+ Sledge mandate set by hand) |
| 766cece | pr due date = email send date (else invoice date) + DirectDebit_Method_Setting working days (setup only without saved method, + processing); new rau_Subscription25_Invoice_c_Due_Date_Payment syncs open payments (New/Setup/Pending); rbb_Payment recalcs collection date on due date change | ✓ | ✓ (rollback dry-run: Bacs 10-28 → due 11-13 / coll 11-11; SEPA → 11-03 / 11-02; with saved method UK 10-30, NL 10-29) |

Prod list (go-ahead pending): phase 2 + 3DS, add-card-on-reuse (7075220), Rest_UpsertContract pr guard (check prod copy first), Util_Crypto bulk fix, Link off, page language, mandate race fix, pr due date.
Closed: the 3 old "Direct Debit Setup Failure" Cases in acc (MI00273366-68, from the token-less test mails).

## ⏰ Checklist 2026-10-29 (morning)

1. acc: PM#000136966 (card) + PM#000136965 (Apple Pay) charged by Batch_ProcessPayments (collection 10-29) → Processing/Paid, no Cases. Sledge acc 2nd contract (990001_1): payment New, charged via mandate.
2. Prod compare: Rest_UpsertContract (V1 only, V2 stays out; prod copy has unrelated uncommitted changes), rbb_Payment, rbu_Subscription25_Invoice_c vs live prod.
3. Check-only deploy → go-ahead → deploy, activate flows (prod lands Draft), publish Customer Hub, verify bundle.
4. **Prod Peter Sledge** (001Tx0000122JuaIAE, pr): on 2026-10-28 evening still only Draft order 02756583 (Invoice_Payment_Method__c pr), no invoice, no Payment__c. Check: order activated → invoice → Payment__c on **Setup** (psp-recurring, Interaction 'Mail Sent', token + Setup_URL filled), setup mail sent.
5. **New UK customers on I0 → pr** (prod): 15 accounts Reseller 6, Payment_Method_Contracts__c = I0, created ≥ 2026-10-21 (list 2026-10-28: Hatton, Savage, Sanderson, Thistlewood, Lumb, Turner, Bull, Nock, Hattersley, hall, Sawyer, Kerr, Dadds, Spooner, Cosmic Campervans; re-query, more will come). Same as Sledge: account → pr, draft/open orders → pr, CP stays I0, contract method empty; backup CSV first.
   - Do this AFTER the deploy (350c7f6 pr guard): before it, an MI UpsertAccount with I0 resets pr.
   - Per account first check: existing Exact mandate / already invoiced on I0 (then ask Teun), activated orders/invoices are not changed.

- **Prod 2026-10-28 evening (user request): Jill Lumb 001Tx000011go2aIAA, William Bull 001Tx000011htMmIAI, Robert Sawyer 001Tx000011nRKeIAM → pr.** New UK customers since 10-21 with one activated contract (method empty) and a Draft order: account Payment_Method_Contracts__c I0 → pr, draft orders 02752963 / 02752970 / 02755673 Payment_Method__c I0 → pr (Invoice_Payment_Method__c follows). CPs (CP-1034834 / CP-1034841 / CP-1035367) stay I0, as for Sledge. No invoices or payments yet. Old values in `migration/before_prod_uk_i0_{accounts,orders}_20261028.csv`. Prod pr accounts now 7. ⚠ Same reset risk until 350c7f6 is in prod: check all 7 before the month-end run. The other 12 new UK I0 accounts have no contract/order yet → move after the deploy.

- **Prod 2026-10-28 evening (user request): active CPs of the 7 pr accounts I0 → pr** (CP-1010146 Blinco, CP-1029657 Stone, CP-1034621 Waldron, CP-1034834 Lumb, CP-1034841 Bull, CP-1035367 Sawyer, CP-1035659 Sledge). Blinco's 2 Terminated CPs (CP-718583, CP-918188) left on I0 (history). Backup `migration/before_prod_pr_cps_20261028.csv`. ⚠ Until 8858288 is in prod, a contract update from the platform puts a CP back to I0: include the CPs in the "still pr?" check.

### 🔍 To investigate: remove Payment_Method__c from the contract product (possible legacy)

Decision Teun 2026-10-28: a contract has one payment method; there is no separate method at product level. So **no** flow change to honour the CP method in the order (the earlier TODO was dropped). The CP values set to pr today stay as they are.

Investigate whether `Subscription25__Contract_Product__c.Payment_Method__c` can be removed:
- Who writes it: Rest_UpsertContract / V2 (from the platform's `paymentMethod`, incl. the pr guard 8858288), and possibly other flows, Apex or the package.
- Who reads it: `rbc_Order_Package_Subscription25` (payment reference condition p0/p1), reports, list views, page layouts, Exact/financial sync, Data Cloud streams.
- Today the order method = Contract.Payment_Method__c → else Account.Payment_Method_Contracts__c, so the CP value has no effect on billing.
- If it's legacy: move the p0/p1 condition to Order.Payment_Method__c / Contract, stop writing it in REST, then delete the field (all envs).

## 2026-10-29 morning: checklist results + prod validation

- acc: PM#000136966 (card) and PM#000136965 (Apple Pay) charged by the batch at 00:00 → **Paid**; Sledge's 2nd payment PM#000136968 charged via the Bacs mandate → **Paid**; no new Cases. PM#000136967 (Google Pay) still Setup (parked).
- prod "still pr?": all 7 accounts, their orders and their active CPs are on pr. Stone's new payment PM#000206640 was charged off-session (Processing). Sledge's order 02756583 is still Draft (no payment yet).
- Prod compare (retrieved 2026-10-29), against the repo version from just before our first change:
  - Equal: Batch_ProcessPayments, Ctrl_Payment, Svc_PaymentIntent, Svc_StripeEventProcessor, Util_Crypto, Rest_UpsertContract (V1; V2 stays out), Rest_UpsertAccount, Util_PaymentMethodRule, rbb_Payment (v10), rbb_Order, LWCs, CMDT.
  - **rbu_Subscription25_Invoice_c**: the repo has a dev-only "Direct Debit Weekend" step (fDueDateDirectDebit, ass_05/06, ass_1_DueDate_DirectDebit) that has never been in prod (prod v34). Prod variant = HEAD without that block → only the pr due date changes go live.
  - **Ctrl_Invoice**: the repo has dev-only work (132 lines). Prod variant = prod live + only the c369c73 change (the pi remark follows p1).
- Package: `.scratch/20261029 - paymentsProd/package` (41 components; deploy from a non-dot copy).
- **Validation 0AfTx0000014JOTKA2: Succeeded, 41/41 components, 135 tests, 0 failures** (RunSpecifiedTests: payment, REST, Util_Crypto, PaymentMethodRule, Ctrl_Invoice tests). Quick deploy is possible on go-ahead.
- After the deploy: activate flows (rbb_Payment, rbu_Subscription25_Invoice_c, rbb_Order, rab_Payment_Action_Required, rau_Subscription25_Invoice_c_Due_Date_Payment), publish the Customer Hub, check the bundle, assign ps_mi*PaymentMethod_Change where needed.
- Finding: in prod, Account.PayProv_PaymentMethodType__c has FLS only for integration permission sets (admins/users can't see it) → add FLS per [[feedback_fls_standard_grants]] (Admin + miModifyAllData).

## ✅ PROD DEPLOY 2026-10-29 (quick deploy 0AfTx0000014JTJKA2 of validation 0AfTx0000014JOTKA2, run by Teun)

- 41 components live: phase 2 + 3DS, add-card-on-reuse, Rest_UpsertContract pr guard (V1), 350c7f6 (VR pr lock, cps/ps, Rest_UpsertAccount guard), c369c73 (pi follows p1, Ctrl_Invoice prod variant), Util_Crypto bulk fix, Link off, page language, mandate race fix, pr due date (rbu prod variant without the dev-only weekend block).
- Flows activated (`.scratch/20261029 - paymentsProd/activate_flows.py`): rbb_Payment 10→11, rbu_Subscription25_Invoice_c 34→35, rbb_Order 10→11, rab_Payment_Action_Required →1, rau_Subscription25_Invoice_c_Due_Date_Payment →1.
- Customer Hub published (0DBTx000000188POAQ); payment_view bundle db7b59b0… contains the new code.
- Open: assign ps_miAccountPaymentMethod_Change / ps_miOpportunityPaymentMethod_Change to the right users; FLS on Account.PayProv_PaymentMethodType__c (Admin + miModifyAllData); Apple Pay / Google Pay: register the prod hub domain on the live Stripe accounts (only on go-ahead); paymentAuthenticationRequired_* templates.

### ⚠ Finding 2026-10-29: new UK I0 customers have a LIVE direct debit mandate

The moved accounts Lumb, Bull, Sawyer and Sledge all have Bank_Account_Number__c + Bank_6_Sort_Code__c, Direct_Debit_Mandate_Status__c = **LIVE** and FinancialIdBankAccount__c (Exact). So they already had a working I0 (Exact) direct debit mandate when they were moved to pr. On pr they will be asked for a new Stripe Bacs mandate.
Candidates 2026-10-29 (13 UK I0 accounts since 10-21): Savage, Dadds and Bishop have a contract and a Draft order on I0 plus a LIVE mandate; Kerr has bank details but no mandate status; the other 9 have no bank details and no contract. **Step 6 paused** until Teun decides.

### Decision Teun 2026-10-29: only customers WITHOUT a mandate move to pr

- **Rule:** a new UK customer with a LIVE Exact direct debit mandate (Direct_Debit_Mandate_Status__c = LIVE / bank details on the account) stays on I0. Only customers without bank details or mandate move to pr.
- **Back to I0** (account, draft order, CP): Lumb (02752963, CP-1034834), Bull (02752970, CP-1034841), Sawyer (02755673, CP-1035367). No invoice yet, so nothing was billed on pr.
- **To pr** (account only, no contract/order yet): Hatton, Sanderson, Thistlewood, Turner, Nock, Hattersley, hall, Spooner, Cosmic Campervans.
- **Stay on I0:** Savage, Dadds, Bishop (LIVE mandate, contract + Draft order), Kerr (bank details, no mandate status → treated as a mandate).
- **Sledge stays pr** (explicit request, despite a LIVE mandate): he gets a Stripe mandate request on his first invoice.
- Result: UK accounts created ≥ 10-21: I0 7, pr 10. Local backups (untracked, without bank data): `migration/before_prod_uk_mandate_split_accounts_20261029.csv`, `migration/before_prod_uk_revert_orders_20261029.csv`.
- **Going forward:** for new UK I0 accounts, check Direct_Debit_Mandate_Status__c / bank details first. Now that the REST guard is live, later contracts for the 9 pr accounts get pr automatically.

### ⏰ Check after the UK monthly run (~2026-11-08): Sledge's first pr payment

UK I0/pr contract orders stay Draft until the monthly UK run (2026-10-08: 4,818 orders activated); p1 orders are activated right away. Teun (2026-10-29): wait for the run, do not activate by hand.
After the run, check prod Sledge (001Tx0000122JuaIAE):
1. Order 02756583 is activated, and an invoice exists on pr.
2. Payment__c psp-recurring on **Setup**, Interaction 'Mail Sent', token + Setup_URL__c filled, setup mail sent.
3. Due date = email send date + 12 working days (Bacs 10 + 2), the payment due date is synced, and collection = due − 2 working days.
4. The 9 new pr accounts: contracts that came in since should be on pr.
