# Odoo invoice e-mails → Account / Contact / Sub25 Invoice / Order (PLAN v2 — not built)

Status 2026-11-05 evening: **PHASE 1 BUILT + TESTED IN DEV (uncommitted). Not in acc/prod.** See §5 for the build log and §6 for what the user must review.

Earlier status: PLAN v2. User answered the first questions. Source = Factur-X embedded in the Odoo PDF (UBL dropped).
All questions answered (§1, §1a). Phase 1 = SF intake; phase 2 = Exact with the Odoo number. Waiting for the go-ahead. Build in dev → acc. Nothing runs in prod without an explicit command.

## 0. Prod facts (analysed 2026-11-05)

- Email-to-Case: only `invoicing@echoes.solutions` receives mail (863 inbound / 90 days). The .nl/.co.uk/.de mailboxes had 0.
  Odoo invoice mails are self-copies: From = To = invoicing@. Subject is `… (Ref|Réf nnnnnnnn)`. Queue is "Case - Invoicing (FR)".
- **Every Odoo invoice PDF (15/15 checked) embeds an uncompressed Factur-X CII XML** (`urn:factur-x.eu:1p0:extended`).
  - Apex can cut it out of the PDF bytes (hex search for `<?xml` … `</rsm:CrossIndustryInvoice>`), so no external service is needed.
  - If an embedded XML is ever compressed or missing, the case stays New with a comment.
- Factur-X fields available:
  - number, type (380 invoice / 381 credit), issue date, due date, currency, buyer order ref / PO
  - seller name + VAT
  - buyer: name, VAT, SIRET (legal org), address, contact name, **contact e-mail (present on 14/15)**
  - lines: SellerAssignedID (code), name, qty (can be negative), unit price, VAT %
- `BillingSpecifiedPeriod` in the Odoo XML = invoice date → due date (the payment term), **not** a service period. It is ignored.
- Samples are kept in `fx/` (15 Factur-X XMLs) and `pdf/` (the source PDFs) next to this runbook.

## 1. Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | Start/end date | **Calendar month of the invoice date** (1st – last day). Invoice 2026-09-30 → 2026-09-01 … 2026-09-30. |
| 2 | Reseller/admin | **Ref prefix**: 01 → reseller 1 / Netherlands; 02 → 4 / France (echoes); 03 → 5 / Germany; 04 → 6 / United Kingdom. Unknown prefix → stays New + comment. |
| 3 | Contact | Contact with the Factur-X buyer e-mail. Name derived from the e-mail if it looks like `first.last@` / `first_last@` (→ "First Last"). Otherwise LastName = the Factur-X contact name, or the account name. Skip own domains (echoes.solutions, movingintelligence.*). If there is no usable e-mail → no contact, comment on the case. |
| 4 | Lines without a code | Create Product2 with **Name = ProductCode = line name** (e.g. "Formation"). |
| 5 | Source | **Factur-X from the PDF only.** UBL attachments are ignored. |
| 6 | Exact | 02: SF only. 01/03/04: Exact with the Odoo invoice number, nothing sent (phase 2), see §1a/§1b. |
| 7 | Case status | New Case.Status value **`Processed`** (closed). Failures stay `New`. |
| — | Account brand | `PrimaryBrand__c = 'E'` on create only. |

### 1a. Exact + linking — decided 2026-11-05
- **02 (Echoes FR)**: no Exact. Create the SF invoice (DRAFT now, FINALIZED later), Email_Status SENT. The case is Processed once the invoice is created and linked.
- **01/03/04**: sync to Exact **with the Odoo invoice number**. Exact only generates its own number for invoices that do not come from Odoo. **Nothing is sent from Exact**, because Odoo already sent it.
  This is phase 2. Phase 1 builds the SF side for all prefixes, with `Sync_State = NOT_APPLICABLE` until phase 2 is live.
- **Linking**:
  - `EmailMessage.RelatedToId` = invoice. It is updateable and the Sub25 invoice is allowed. ParentId stays on the Case.
  - Every e-mail attachment (PDF + CSV/XLSX) gets a ContentDocumentLink to the invoice.
  - **Never set `Subscription25__PDF_Attachment_Name__c`**. Writing it directly makes the package throw an NPE (known gotcha). The Odoo PDF is linked as a File only.

### 1b. Phase 2 — Exact design (to work out after phase 1)
- Proposal: Exact `salesinvoice/SalesInvoices` POST with `InvoiceNumber` = Odoo nr (raw, 8 digits), `YourRef` = PO, `Description` = "Odoo <nr>". Then `PrintedSalesInvoices` with `SendEmailToCustomer=false` / `SendInvoiceToCustomer=false`, which books it without sending.
  The old SalesInvoices/print endpoints are still in `Util_Exact copy.cls`.
  Alternative: `SalesEntries` (journal entry with EntryNumber = Odoo nr, G/L per product).
- Verify in acc:
  - Does the sales journal allow a manual InvoiceNumber, and can the Odoo range (0125…, 0325…, 0425…) collide with Exact's own range?
  - Do Exact Items exist for the Odoo codes (FMC880NL, CarFleetDE …)? Otherwise map the code or create an Item.
  - Account sync for new reseller 1/5/6 accounts via the existing `Minut_FinancialSystemAccountSync`.
  - SF `Subscription25__Invoice_Number__c` = admin prefix + Odoo nr, Status FINALIZED.
  - ⚠ The acc Exact token can write to a prod division. Check the division before any test.

## 2. Design

- **Sweep** `Batch_OdooInvoiceIntake` via the job dispatcher (Minut step, every 15 min).
  - Candidates: Case Status New, Origin Email, with an incoming EmailMessage from an invoicing@ address, subject matching `\((Ref|Réf) \d{8}\)` and not `RE:/TR:/FW:/AW:`, and a PDF attachment whose title matches the Ref number.
  - Each failure is commented once (marker), so it is not retried endlessly.
- **`Svc_FacturXExtractor`**: PDF Blob → hex → locate the XML → String.
- **`Svc_FacturXParser`**: namespace-aware DOM → DTO (header, seller, buyer, contact, lines, totals). 381 or a negative qty → negative lines.
- **Idempotency**: Invoice `Subscription25__External_ID__c = 'ODOO-<nr>'`. If it exists → Case `Processed` with the comment "duplicate", nothing is created. 02255708 arrived 3 times.
- **Account**: match on VAT (`VAT_Number__c`), then SIRET/SIREN, then exact name + postal code + country.
  - Create: Name, billing + shipping address, VAT, `Reseller_Name__c` (§1.2), `PrimaryBrand__c = 'E'`.
  - Existing accounts are never modified.
- **Contact**: §1.3. Match on Email within the account (then globally under the same account), otherwise insert.
- **Product**: match on ProductCode (SellerAssignedID, or the name for lines without a code).
  - Insert: Product2 (Name = name without the `[code] ` prefix, ProductCode, IsActive) + standard PricebookEntry in the invoice currency.
- **Invoice** (`Subscription25__Invoice__c`):
  - Account, Contact_Person, Administration (§1.2), Invoice_Date, Due_Date, Currency
  - Status DRAFT, Create_As_Draft, **Email_Status SENT**, UBL_Email_Status WILL_NOT_BE_SENT, Sync_State NOT_APPLICABLE
  - Sales_Channel (02/03 = Echoes, 01/04 = Moving Intelligence?), Purchase_Order_Number = buyer order ref
  - Description "Odoo <nr>", billing/shipping address, VAT number
  - E-mail linked via `EmailMessage.RelatedToId`; all attachments via ContentDocumentLink; `PDF_Attachment_Name__c` is NOT set
- **Order**: Account, Standard pricebook, EffectiveDate/EndDate = §1.1, Status Draft, Type ≠ Opportunity (the existing SalesOrder sync must not pick it up; phase 2 goes via the invoice, not the order), `Subscription25__Invoice__c`, Administration, OrderReferenceNumber/PoNumber.
  OrderItem per line: Product, PBE, Quantity, UnitPrice, ServiceDate/EndDate, VAT %, Description.
- **Case** success: Status `Processed`, AccountId, ContactId, Reason `Invoice questions`, and a CaseComment (summary + record ids).
- **Savepoint per case**: all-or-nothing.

## 3. Verify during the build
- `Batch_FinalizeInvoices(Limited)` filters on `Exact_Order_Number != null`, so it does not pick up our invoices. Check that no flow sets that field (`rbc/rbu_Subscription25_Invoice_c`).
- `rau_Subscription25_Invoice_c_Email_Status_Payment` (SENT → Payment__c): check the effect on insert.
- Account-create automation (`rbb_Account`, Account FinSys sync step `Minut_FinancialSystemAccountSync`): reseller 1/5/6 must not sync to Exact while §1a is open.
- The Sub25 invoice job must not pick up our Orders.
- Duplicate/validation rules on Account/Contact/Product2. Case.Status `Processed` must be added to the support process of RecordType Default.

## 4. Build steps (after go-ahead)
1. Dev: extractor + parser + tests (fixtures: the 15 Factur-X samples as a static resource or inline).
2. Dev: intake service, batch, dispatcher step, Case.Status `Processed`. Tests ≥ 85%.
3. Acc: deploy; replay copies of the real cases (01/02/03 examples, a duplicate, the "Formation" line, the credit qty on 03251903).
4. Prod: only on explicit command. Dry-run first (comment only, create nothing), then live.


## 5. Phase 1 build log (dev, 2026-11-05)

### Components (force-app, uncommitted)
- `classes/Svc_FacturX.cls`: extracts the Factur-X from the PDF (hex search; the XML is uncompressed in Odoo PDFs) and parses the CII into a DTO.
- `classes/Svc_OdooInvoiceIntake.cls`: the intake per e-mail, with a savepoint. `process(ids)` and `process(ids, dryRun)`; dry-run rolls everything back and writes no comment.
- `classes/Batch_OdooInvoiceIntake.cls`: Job_AbstractBatch2 + Util_JobDispatcher.Step.
  - Selects incoming e-mails from the 4 invoicing@ senders, with `(Ref |(Réf ` in the subject, case New, last 30 days.
  - **Batch size 1**: the Account/Order/Invoice automation uses most of the 100 SOQL per invoice.
- `classes/Test_Svc_FacturX.cls` (with the Factur-X fixture generator) and `classes/Test_Svc_OdooInvoiceIntake.cls`: 9 tests, all pass.
  Coverage: Svc_FacturX 92%, Svc_OdooInvoiceIntake 91%, Batch 79%.
- `customMetadata/JobDispatcherStep.Minut_OdooInvoiceIntake`: Order 5 (before AccountSync 10), batch size 1, IsActive true.
- Case.Status **Processed** (closed), in StandardValueSet CaseStatus + support process Default.
  - Deployed to dev via metadata dir `caseStatus-dev/` (dev's own retrieved copy + Processed).
  - For acc/prod: retrieve that org's own copy and add the value. Never deploy the dev copy (it replaces the whole value set).
- dev data: a `Subscription25__Schedulable_Class__c` record "Batch_OdooInvoiceIntake" (Schedulable false, batch 1). It is needed even for a manual executeBatch.

### End-to-end test in dev with 6 real prod e-mails/PDFs (scripts in the session scratchpad, `e2e/`)
| Odoo | Result |
|------|--------|
| 02256232 FR ACTION AUTOMOBILE | Processed. Account reseller 4 brand E; contact = generic mailbox (named after the account); product CarFidFR; net 600 / gross 720 = Odoo |
| 02254240 EUROPCAR UK (GB, 10 lines, export 0%) | Processed. Account reseller 4 (country default 6 overruled); contact Mark Rice (existed on another account → ACR); 10 products; net 43064.99 = gross (0% like Odoo); PO2645003651 |
| 03251903 DE CanoCar (incl. −6 credit line) | Processed under Germany. Net 435 / gross 517.65 = Odoo |
| 01250436 NL H4 Repair | **WAITING**: NL is an Exact administration and the account has no debtor number. Account created + flagged `SyncToFinancialSystem__c`; case stays New without comment |
| 02255708 FR ATLAS "Formation" | Processed. Product "Formation" (name = code); no contact (only invoicing@ in the Factur-X); gross 3600 = Odoo |
| 02256232 resend | DUPLICATE. Nothing created; case Processed; e-mail copy on the existing invoice |

### Findings and decisions made during the build (to review)
1. **A received e-mail's RelatedToId cannot be changed** ("You cannot edit this field"). The invoice therefore gets a **copy** of the e-mail as an activity (same from/to/subject/body/date). The original stays on the case. All attachments are linked to the invoice as Files.
2. **Exact administrations need a debtor number** for the account before the package accepts an invoice or order ("The account … is not present in the selected administration"). That number only comes from the Exact account sync.
   - In dev: NL + UK. In prod: NL + **DE** + UK.
   - Solution: the intake flags the account for the existing Exact account sync and leaves the case New (WAITING). The next run, after sync step 10 has delivered the number, creates the invoice.
   - **Consequence: for 01/03/04 new customers, an Exact debtor is created by the existing sync.** That is the existing behaviour for new MI accounts, and phase 2 needs it anyway.
   - If the account is under a different reseller than the invoice administration, or the sync is blocked → FAILED with a comment (handle manually).
3. **rbb_Account derives the reseller from the billing country on create** (NL/BE→1, GR→2, FR→4, AT/CH/DE→5, GB/IE→6).
   - The intake then sets the reseller of the Odoo company with an update. vr_FinancialEntityChange only allows this for sysadmin / `cp_AllowFinancialEntityChange`.
   - **The job user in prod must have that permission**, otherwise the country's reseller stays (comment "CHECK: …").
   - Account matching looks across resellers and prefers the Odoo company's one.
4. **New accounts get Payment_Method_Contracts/Opportunities = 08** (bank transfer; Odoo invoices are paid by transfer). The field default I8 is not allowed for reseller 6, so an account abroad failed with it.
5. **VAT**:
   - With `Subscription25__VAT_Number__c` on the invoice, the package applies intra-EU 0%. The France (echoes) administration has billing country **Netherlands**, so a French customer got 0% instead of 20%.
   - The VAT number is now only set when Odoo itself charged 0%.
   - For a NEW account where Odoo charged 0%, `Subscription25__Always_Apply_Domestic_VAT__c` is set to false (rbb sets it to true for B2B without a VAT number). The package then picks the EU / non-EU rate like Odoo.
   - Existing accounts are never changed. A remaining difference gives "CHECK VAT: …" in the case comment (the invoice is a draft anyway).
   - The net total must match Odoo, otherwise rollback + FAILED.
6. New accounts that get a contact also get Subscription25 **Digital Invoicing** switched on (existing automation). Our invoices have Email_Status SENT, so the package does not mail them.
7. Order.Type defaults to "Contract" (package/org default), Status Draft, not flagged for the Exact order sync.
8. Name from e-mail: `first.last@` → "First Last". Generic mailboxes (compta, info, admin, factur, …) and `jan-jito@` (one part) → LastName = account name.
9. Account matching: VAT → CoC (SIREN/SIRET) → exact name + postal code. Contact: the e-mail is unique in the org → existing contact on another account gets an AccountContactRelation.

### Leftover dev test data
- Accounts ACTION AUTOMOBILE, CanoCar GmbH, H4 Repair BV, ATLAS SOUTENIR LES COMPETENCES, EUROPCAR UK, "EUROPCAR UK (old e2e)" (brand E, created 2026-11-05).
  Delete is blocked: Digital Invoicing validation + contact lookups.
- Their invoices/orders, 6 test cases, and products CarFidFR, CarFleetDE, Formation, CarCollectFR, Data*FR.

## 6. Open points for the user (tomorrow)
1. Review §5 findings 2 (Exact debtor via the existing sync for 01/03/04), 3 (reseller overrule + job-user permission) and 5 (VAT).
2. Commit? Nothing is committed yet. Files: the 5 classes + meta, the dispatcher step mdt, this runbook + `caseStatus-dev/`, `fx/`, `pdf/`.
   Note that `pdf/` holds real customer invoices; maybe keep them out of git.
3. Acc: deploy classes + mdt (IsActive **false** first) + acc-own CaseStatus/Default process + Schedulable_Class record, then test with copies of real cases.
4. Prod (only on command): deploy with the dispatcher step **inactive**.
   - Dry run: `Svc_OdooInvoiceIntake.process(ids, true)` via anonymous Apex, **one e-mail per call** (SOQL limit).
   - The dry run writes no records and no comment, and `Order_Process__e` is PublishAfterCommit, so it is discarded on rollback.
   - Not verified: whether Logger / package events survive the rollback.
   - Then activate the step.
6. **DECISION before prod: backlog cutoff.** The first run takes every Odoo case that is still New from the last 30 days (about 30).
   - Staff may have handled some of them by hand already; those cases are never closed today.
   - For 01/03/04, the WAITING path creates Exact debtors right away.
   - Proposal: a "not before" date (go-live date) in the batch query. Alternatively, close or skip the old cases first.
7. **WAITING has no timeout yet.** If the Exact account sync keeps failing without blocking the account, the case falls out of the 30-day window without a comment.
   - To do: comment after N days, or as soon as `FinancialSyncLastError__c` is set.
8. **Finalize risk (later / phase 2).** A matched existing account with payment method pi/pr (Stripe) → when the draft invoice is finalized, `rau_Subscription25_Invoice_c_Finalized_Create_Payment` can create a Payment__c and collect money for an invoice that Odoo already sent (and the customer may have paid).
   - The e2e accounts had no payment method on the invoice and no Payment__c, but the existing-account case is not tested.
   - Before finalizing: exclude Odoo invoices (External_ID `ODOO-%`) in that flow, or set the invoice payment method to 08.
9. Verified in dev: Case.Status Processed is in the value set **and** the Default support process (retrieve check). The e2e test account H4 Repair BV (WAITING path) was unflagged afterwards (`SyncToFinancialSystem__c` false). The Minut dispatcher is not scheduled in dev.
5. Prod volume check: about 30 Odoo invoice e-mails in 90 days, all in queue "Case - Invoicing (FR)".

## 7. acc deploy (2026-11-05, on the user's command)
- Deployed: Svc_FacturX, Svc_OdooInvoiceIntake, Batch_OdooInvoiceIntake, 2 test classes (9/9 pass in acc).
- Case.Status **Processed**: from acc's own retrieved copy + Processed (`caseStatus-acc/`); value set + support process Default.
- `JobDispatcherStep.Minut_OdooInvoiceIntake` deployed **IsActive = false** (acc has no Odoo mail flow; the step stays off).
- Sub25 config record "Batch_OdooInvoiceIntake" created in acc (Schedulable false, batch 1).
- E2E in acc (manual `Database.executeBatch(new Batch_OdooInvoiceIntake(), 1)`): the 5 Odoo mails (FR 02256232, GB 02254240, DE 03251903, FR 02255708 "Formation", resend of 02256232) behave exactly as in dev. Net totals match Odoo, resend = DUPLICATE, 5 job items and 0 errors, so no stray cases were picked up.
- NL sample 01250436 was **deliberately not run in acc**: the WAITING path flags the account for the Exact sync and the acc Exact token can write to a prod division. Test it only after checking the acc division.
- acc differences: Germany has no Exact sync in acc (prod: Exact), so the DE WAITING path is not exercised in acc either.
- Leftover acc test data: accounts ACTION AUTOMOBILE, EUROPCAR UK, CanoCar GmbH, ATLAS SOUTENIR LES COMPETENCES (brand E, 2026-11-05), 4 invoices + orders, 5 test cases, products CarFidFR, CarFleetDE, Formation, CarCollectFR, Data*FR.
- Still open before prod: §6 points 5–7 (backlog cutoff, WAITING timeout, finalize pi/pr risk) and the job-user permission `cp_AllowFinancialEntityChange`.
