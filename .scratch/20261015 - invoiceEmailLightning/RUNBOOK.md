# Invoice email + direct debit mandate request in one email — RUNBOOK

Status 2026-10-15 (end of day): **built and tested in dev, committed `8f743de` (not pushed). acc/prod: nothing done.**
Continue: see "Next session" at the bottom.

## Goal
One email per invoice: the Subscription25 invoice email (Lightning template, PDF attached) also carries the direct debit
authorisation link, instead of a separate DD setup email minutes after finalize. Classic invoice templates retired.

## What is built (dev)

### Templates
| Template | Folder | Letterhead | Notes |
|---|---|---|---|
| `InvoiceNL` / `InvoiceUK` / `InvoiceDE` | Invoicing (Lightning) | `lh_M_Preferences_NL` / `_EN` / `_DE` | original names kept → Administration values unchanged; merge `{{{Subscription25__Invoice__c.Payment_Setup_Block__c}}}`; brand block under signature; UK/DE signature with T./E. lines |
| `InvoiceNL_Classic` / `UK_Classic` / `DE_Classic` | Invoicing_Classic ("Invoicing (Classic)") | — | Classic originals, renamed in the org via data API (Ids kept); not in the repo |
| `paymentDirectDebitSetupInitial_*`, `Reminder1_*`, `Reminder2_*` (EN/NL/**DE new**) | DirectDebit | `lh_M_Preferences_EN/NL/DE` | link = `{{{Payment__c.Setup_URL__c}}}` (no hard-coded host); inline brand block moved under signature; generic "personal, secure link" text |
| `paymentDirectDebitInvoiceBlock_EN/NL/DE` | DirectDebit | — | not sent; rendered into the invoice block |

Letterheads `lh_M_Preferences_EN/NL/DE/FR` (EnhancedLetterhead = **data, not metadata**): header = MI email header, footer =
terms & conditions + privacy statement line per language. JSON in `letterheads/` — recreate by hand per org
(`POST /services/data/v67.0/sobjects/EnhancedLetterhead/`), then set `EmailTemplate.EnhancedLetterheadId` via data API
(a template redeploy keeps the link). FR links to movingintelligence.ai (no French MI site).

### Data model / code
- `Subscription25__Invoice__c.Payment_Setup_Block__c` (rich text) — read FLS on `ps_miSubscription25_User` (in pg_Subscription25User + pg_Subscription25Admin).
- `Payment__c.Setup_URL__c` = `Business_Entity__r.CustomerHub_URL__c & "/payment?token=" & externalId__c`.
- `Payment__c.Interaction_Status__c` + value **Awaiting Invoice Email**.
- `Svc_InvoicePaymentBlock` (invocable fill/clear; language from the Administration's invoice template) + test (3/3, 96%).

### Flows
| Flow | Change |
|---|---|
| `afl_Payment_Direct_Debit_Setup` (v28) | invoice email still PENDING → payment `Awaiting Invoice Email` + block on invoice, no separate mail; block fill fails → `Mail Sent` + separate mail |
| `rau_Subscription25_Invoice_c_Email_Status_Payment` (new) | invoice Email_Status SENT → payment `Mail Sent` (reminders start); ERROR / WILL_NOT_BE_SENT → separate setup mail, clear block, `Mail Sent` |
| `rab_Payment_Direct_Debit_Awaiting_Invoice` (new) | D+3 still awaiting → separate setup mail, clear block, `Mail Sent` |
| `rab_Payment_Direct_Debit_Processed` (new) | mandate done (`Request Processed by Customer`) → clear block |
| `rab_Payment_Direct_Debit_Escalation` (v3) | reminder template by Contact.Language__c (was always `_EN`) |

### Tests in dev (account Teun Rietman 001bd00000kl0ruAAA, UK)
- Render of all templates: OK (merge fields, letterheads, links).
- SENT path: PM#000110390 / GB26000018 → Awaiting + block → user sent invoice via package → `Mail Sent`, only the invoice mail. ✅
- ERROR path (simulated Email_Status=ERROR): separate setup mail 10:05 UTC, block cleared, `Mail Sent`. ✅ Side effect: existing flow created Case **MI00234163** "Invoice delivery failure" (test, still open).
- Safety net D+3: ⏳ not tested. Reminder 1 for PM#000110390 due ~2026-10-17 (checks reminder language).
- PM#000110389 set to Cancelled (test only).

## Decisions taken
- Mandate request goes out with the invoice email (prod example: 1–2 days later than today). Reminders count from that moment.
- Payment contact ≠ invoice contact (prod: UK 17 / NL ~7,000 / DE ~680 accounts): **leave as is** (user, 2026-10-15).
- DE in scope (templates ready); DE customers only get DD once Germany Business Entity `PayProv_Use__c` + Payment_Setting autocreate are switched on (config decision).

## Known issues / findings
- **Customer Hub URL empty** on NL/UK/DE Business Entities in acc + prod (root cause: mirrored from the Administration field, which was empty and invisible to the admin user despite pg_Subscription25Admin FLS). Fixed in dev; acc/prod → `customerHubFill/RUNBOOK.md`. **Must be done before the new DD templates go live, or all DD links are empty.**
- Prod DD templates have the prod host hard-coded and differ from the repo (repo had the dev host) → retrieve-diff prod templates before deploying.
- `ps_miSubscription25_User` prod is 1 field behind dev/repo (`Subscription25__Administration__c.Include_…`) — comes along with the next deploy; permission set deploys REPLACE the whole set (retrieve-diff before/after).
- dev has 99 PENDING invoices and no Sub25 send job: never run `Job_EmailInvoice` in dev.
- Classic folder `Invoicing` (prod) vs Lightning folder `Invoicing`: in the org both may exist; prod cutover renames Classic first (data API), then deploys Lightning.

## Deploy plan (acc first, prod only on explicit go)
1. Customer Hub URL fill — `customerHubFill/RUNBOOK.md`.
2. Rename Classic templates `InvoiceNL/UK/DE` → `*_Classic` and folder → `Invoicing_Classic` (data API). **From here the Administrations point to templates that don't exist until step 3 → do 2–4 back-to-back, outside the Job_EmailInvoice window (prod: 21:16 UTC).**
3. Deploy (commit `8f743de` content): field Payment_Setup_Block__c, Setup_URL__c, Interaction_Status__c, Svc_InvoicePaymentBlock (+test), templates (Invoicing + DirectDebit), flows, ps_miSubscription25_User (full file, retrieve-diff), Admin profile.
4. Recreate letterheads `lh_M_Preferences_EN/NL/DE/FR` from `letterheads/*.json`, link to the 3 invoice + 9 DD templates.
5. Smoke test in acc with a test account (not a real customer): finalize → Awaiting + block → send → Mail Sent; ERROR path.
6. Prod: same, with explicit go; afterwards monitor first nightly run (payments `Awaiting Invoice Email` → `Mail Sent`).

## Next session
- [ ] Close test Case MI00234163 (ask user).
- [ ] Check reminder 1 for PM#000110390 (~2026-10-17), language + link.
- [ ] Optionally test the D+3 safety net.
- [ ] Push `8f743de` (on request).
- [ ] acc deploy following the plan above.

## acc 2026-10-29 (user go) — deployed, ready for an end-to-end test

State before: acc = prod design for the DD templates (header image inline in the body, **no** letterhead, Arial 10-28). The repo DD templates are older (letterhead-based) → **not deployed**; the repo should be aligned to acc/prod later. Customer Hub URL fill was already done on 10-21.

Done in acc:
1. Letterheads `lh_M_Preferences_EN/NL/DE/FR` copied from dev (state 10-28, prod-hosted header image): 0RnG50000000o3FKAQ / o4rKAA / o6TKAQ / o85KAA.
2. Classic `InvoiceNL/UK/DE` (folder Finance) renamed to `*_Classic` via the data API (Ids 00X3W000000pHHTUA2 / HHtUAM / HHsUAM kept).
3. Deploy 0AfG500000TG3e0KAD (NoTestRun, 17 components; package copy `acc-package-20261029/`): Payment_Setup_Block__c, Interaction_Status__c (+ Awaiting Invoice Email), Svc_InvoicePaymentBlock + test, Lightning folder Invoicing + InvoiceNL/UK/DE, block templates EN/NL/DE, flows afl_Payment_Direct_Debit_Setup v5, rau_Subscription25_Invoice_c_Email_Status_Payment v1, rab_Payment_Direct_Debit_Awaiting_Invoice v1, rab_Payment_Direct_Debit_Processed v1, rab_Payment_Direct_Debit_Escalation v2 (all active), ps_miSubscription25_User (repo = acc + 1 field, checked).
   - The first attempt with tests failed: new-field FLS on the admin profile. Fixed via FieldPermissions (Admin read+edit Payment_Setup_Block__c), then Test_Svc_InvoicePaymentBlock 2/2 run separately.
4. EnhancedLetterheadId: InvoiceUK → _EN, InvoiceNL → _NL, InvoiceDE → _DE.
5. Administrations: UK → InvoiceUK, DE → InvoiceDE (were empty; = prod values). NL stays `InvoiceNl`.
6. Render check (no send): InvoiceUK on I-2610-00560539: header + terms footer, no open merge fields; block EN on PM#000136967 with the payment link.

Next: end-to-end in acc with a test account (not a real customer): new pr invoice (FINALIZED, Email_Status PENDING) → payment Awaiting + block on the invoice, no separate mail → send the invoice through the package → payment Mail Sent, one mail with PDF + block. Then the ERROR path and the D+3 safety net.
Prod later (explicit go): same steps; also align the repo DD templates to prod first, and do steps 2–4 back-to-back outside Job_EmailInvoice (21:16 UTC).

### acc end-to-end test (started 2026-10-29 ~09:15 UTC)
- Test account "TEST Teun invoiceblock UK" 001G500001Uv0jBIAR (platform 3, extId 990085, reseller 6, contact teun.rietman@outlook.com, no bank details), created via /UpsertAccount (sent with 08) → set to pr by hand.
- Hardware 990000002 "TEST-IB-1" (02iG500000BpO1xIAF), contract 990002_1 = 01956720 (Activated, method empty), CP-1486852 Draft **pr** (REST guard turned I0 into pr ✓).
- acc schedule: CP activation via the dispatcher (~5 min); Job_InvoiceCreation 18:16 UTC; Job_InvoicePDFCreation 21:16 UTC; **no Job_EmailInvoice in acc** → the invoice email stays PENDING until Teun sends it from the package UI.
- Expected: FINALIZED → Payment__c psp-recurring Setup, Interaction **Awaiting Invoice Email**, Payment_Setup_Block__c filled on the invoice, **no** separate setup mail. After a manual send → **Mail Sent**, one mail (InvoiceUK + PDF + block). Not sent within 3 days → safety net sends the separate setup mail.
- Payloads: scratchpad ev/ib_account_acc.json, ib_hw_acc.json, ib_contract_acc.json.
