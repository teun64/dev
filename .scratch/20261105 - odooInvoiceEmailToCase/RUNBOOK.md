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

## 8. Reseller 7 (Echoes GmbH) + debtor numbers for every administration (2026-11-06, dev)

Decisions (user): all administrations are handled equally; no Exact environment -> made-up debtor number from the account Id
(skip first 6 and last 3 characters; `0001Vh1Rj` from `001G500001Vh1RjIAJ`), on `Subscription25__Debtor_Number__c` only (never on
`Account.FinancialDebtorNumber__c`: that one feeds Exact and Stripe; rab_Account_Debtor_Number only fires when the account's own
number is filled, so it leaves the made-up record alone and replaces it by the real one later). Reseller 7 = "DE - Echoes GmbH",
same definition as reseller 4 (no Exact), VAT definition of Germany (shared rate records, default `DE - VAT high rate`),
definition + address of Moving Intelligence GmbH, legal + bank data of Echoes GmbH. Not selectable by users on accounts:
validation rule `vr_EchoesGmbHEntity` (needs custom permission `cp_AllowEchoesGmbHEntity` = ps_miAllowEchoesGmbHEntity, for the
automation / job users). Odoo prefix 03 -> reseller 7 (was 5).

Echoes GmbH data (printed on invoice PDF 03251903, checked 2026-11-06; the Factur-X only carries address, IBAN and a wrong HRB):
Gubener Straße 47, 10243 Berlin (same as MI GmbH, PLZ ok); Deutsche Bank, IBAN DE24 5907 0070 0037 0098 00 (mod-97 ok),
BIC DEUTDEDB595; Amtsgericht Berlin-Charlottenburg HRB 280681B; USt-IdNr DE352676584; managing director Mathieu Chènebit.
(Factur-X says HRB 108498: not used.)

Components (repo): globalValueSets/BusinessEnitites (+7; acc: its Administration.Reseller__c uses a second set `Reseller`: add 7 there
too), customPermissions/cp_AllowEchoesGmbHEntity, permissionsets/ps_miAllowEchoesGmbHEntity, Account validationRule
vr_EchoesGmbHEntity, Account sharing rules sr_Accounts_CustomerBase_FR + sr_Accounts_ServiceBase_FR (+ "DE - Echoes GmbH"; deploy
each org's OWN retrieved copy + the addition: git has `deactivated`, the orgs `Deactivated`; acc has no such rules), CMDT
Payment_Method_Rule I3/I4/I8 (Allowed_Resellers + 7) and BrandThemeConfig.E (ResellerCodes 4,7), Rest_UpsertAccount
(excludedResellers + '7'), Svc_OdooInvoiceIntake (maps, languageFor, ensureFakeDebtorNumber).
Records: `records/createEchoesGmbH.apex` (Business Entity + Administration "Germany (echoes)", idempotent, per org).
NOT done (optional, core flows): rbb_Account (fLanguage / fFinancialEntity), rbc_Opportunity (fOptionActivationFeeRemark excludes
6 and 4), rbb_Payment_Batch (dec_01_Reseller_Reset on reseller 4).

Findings: on FINALIZED the package prefixes the administration's Invoice_Number_Prefix__c to Invoice_Number__c
(dev: 02256232 -> FR02256232). New administration prefix: EG (-> EG03251903). Ask the user whether a blank prefix is wanted.
Job user needs both cp_AllowFinancialEntityChange and cp_AllowEchoesGmbHEntity.

Dev result 2026-11-06: 11/11 tests (Test_Svc_OdooInvoiceIntake + Test_Svc_FacturX). Extra findings while building:
- Record types hide a new global value until it is added: Account B2B + B2C (Reseller_Name__c), Case Default/Platform/Theft
  (Reseller__c + ServiceEntity__c; the case-close flow copies the account's reseller to the case; acc has no Platform RT).
  Lead Marketing/Sales also lack 7: not changed (no leads for this entity). Done in dev from dev's own copies; acc + prod prepared
  (`$scratch/rtall/deploy-<org>`, `rtcase/deploy-<org>`), not deployed. The mdapi RecordType retrieve only returns a picklist entry
  when the CustomField is in the same package.
- A new account for prefix 03 is created with reseller 7 by the automation user (needs cp_AllowEchoesGmbHEntity AND
  cp_AllowFinancialEntityChange); without the permission the intake keeps the country reseller and writes a "CHECK" note.
- The package applies the administration's VAT rate (DE 19%) to the lines, whatever the Odoo line says (the net always matches): a
  real GmbH invoice is 19%, so equal; a difference only gives the "CHECK VAT" note.
- Test_Rest_UpsertAccount.testUkPrivateOpportunityDefaultIsPi fails in dev WITHOUT our change (it expects pi, the temporary
  UK pi->p1 on create gives p1): fix/skip that test before Rest_UpsertAccount (+ '7' in excludedResellers) goes to prod.

### 8b. Reseller 7 rolled out to acc (2026-11-06, user: "rollout reseller 7 to acc 1st"), flows + sharing in dev
- acc: GVS BusinessEnitites + acc's own GVS `Reseller` (+7), cp/ps/vr, CMDT I3/I4/I8 + BrandThemeConfig.E, Account B2B/B2C and
  Case Default/Theft record types (+7), records (administration "Germany (echoes)" + business entity, prefix EG), the acc user got
  ps_miAllowEchoesGmbHEntity, Svc_OdooInvoiceIntake + tests 11/11. acc has no Account sharing rules (nothing deployed there).
- acc e2e (one e-mail per transaction; 3 in one transaction hit governor limits, as known): 02256107 + 02256345 (made-up debtor
  numbers, net/gross = Odoo), 03251903 (administration Germany (echoes), net 435.00 gross 517.65 = Odoo, debtor 0001VeWYY).
  Matched accounts get a "CHECK: its reseller is 5, the Odoo company is 7" note: expected for every DE customer (decision pending).
- Sharing (user): 7 follows 5. Repo Account.sharingRules = prod's current file + "DE - Echoes GmbH" added to
  sr_Accounts_CustomerBase_DE / ServiceBase_DE (value `DE - Moving Intelligence GmbH,DE - Echoes GmbH`). Deployed to dev only.
- Flows, 7 handled as 4 (dev only): rbb_Payment_Batch (reset to reseller 0 like 2 and 4), rbc_Opportunity (activation-fee remark
  excluded like 4 and 6), rbb_Account (fLanguage when the country is blank: 7 = de). Repo copies of rbb_Account / rbc_Opportunity
  were stale (hundreds of lines behind prod): they are now prod's copy + the edit; dev got dev's own copy + the edit.
  Rest_UpsertAccount ('7' in excludedResellers) deployed to dev with NoTestRun (its test fails without our change, see §8).
- Regression (REBEL Lease payload, fresh id) dev vs acc control: identical results (Mart roleless, billing contact Afdeling
  Administratie); the roles in the payload doc (Chris Main;Shipping) no longer match either org: doc is outdated, not our change.
- Invoice number: prod data (90 days) shows Finalized_In_Exact = true on every numbered NL, DE and UK invoice, so UK is not visible as
  "import"; the code decides dynamically (number already at Exact after the order sync = taken, else print then read). Not built.

### 8c. Decisions of 2026-11-06 (evening)
- The intake no longer writes "CHECK: its reseller is X, the Odoo company is Y" on a matched account (user: drop it). Exact
  administrations still stop in waitForDebtorNumber when the reseller differs; 4/7 have no financial system. Dev + acc 11/11.
- Business Entity setting `FinSysInvoiceNumberMethod__c` (Print / Import; blank = no financial system): UK = Import, NL + DE = Print
  (user: only UK is import; prod data cannot show it, all numbered invoices there have Finalized_In_Exact = true). Field in repo
  (objects/Business_Entities__c/fields), FLS: Admin profile + miModifyAllData edit, ps_miSubscription25_User read, deployed from each org's
  own retrieved copy. Values: records/setInvoiceNumberMethod.apex (dev + acc done). The sync (Util_FinancialSystem_Invoice) does NOT read
  it yet: it still decides dynamically (number already at Exact -> take it, else print). Use it for phase 2 (Odoo number on create).
- acc: flows rbb_Account / rbc_Opportunity / rbb_Payment_Batch (7 as 4) deployed from acc's own copies. Acc has no reseller sharing
  criteria rules (only 4 owner rules): nothing to extend; prod's rules are NOT copied there.
- Prod still needs (on explicit command): all of §8 + §8b components, the record types (Account B2B/B2C, Case Default/Platform/Theft),
  the sharing rules (prod file already in the repo), the 3 flows (lands as Draft: activate), the field + FLS + values, the records
  script, ps_miAllowEchoesGmbHEntity for the job user, and a fix for Test_Rest_UpsertAccount before Rest_UpsertAccount.

### 8d. Account matching per entity (user, 2026-11-06: "for now reseller 5 and 7 should result in a duplicate, the same for 4 in
relation to the rest") — interpreted as: an account belongs to one entity, the intake only matches an account of the Odoo company's
own reseller (VAT, CoC, name + postal code); the same customer under another entity (5 vs 7, 4 vs the rest) becomes a separate
account. Reseller 3 counts as 1 (same administration). One filter in findOrCreateAccount (`Reseller_Name__c IN :entities`): easy to
undo if the intention was the opposite (reuse across entities). Dev + acc 12/12.

### 8e. Decisions of 2026-11-06 (late) + phase 2 built (dev + acc, step INACTIVE, nothing posted to Exact yet)
- Account matching (user: "only if the source is 4 france or 7 echoes gmbh"): only Echoes France (4) and Echoes GmbH (7) keep their own
  accounts; they only match accounts of their own entity and no other entity matches theirs. All other sources (1/3/5/6) match any
  non-4/7 account, the own entity preferred (back to the earlier behaviour, in Apex `pick`). A reused account of another reseller in an
  Exact administration still stops in waitForDebtorNumber. Supersedes §8d.
- Sharing (user: "copy acc in prod, remove the existing", read as: prod's rules into acc): acc's 4 owner rules (srBeNeLuxManagement,
  srBeneluxReps, srGermanyManagement, srGermanyReps; backup in the session scratchpad acc-sharing/) deleted and prod's Account
  sharingRules (incl. 7 with DE) deployed to acc.
- Phase 2: `Svc_OdooExactSync` + `Batch_OdooExactSync` + `JobDispatcherStep.Minut_OdooExactSync` (IsActive false, order 45); tests
  `Test_Svc_OdooExactSync` (mocked Exact) 10/10 in dev and acc.
  - Exact docs: SalesInvoices.InvoiceNumber is "assigned at entry or at printing depending on setting": the number CANNOT be supplied.
    So the Odoo number goes in YourRef + Description ("Odoo <nr>"), Exact numbers itself (Import = at entry, Print = at printing,
    read from Business_Entities__c.FinSysInvoiceNumberMethod__c; blank = stop). Exact's number goes to FinSysInvoiceNumber__c, the
    Odoo number stays in Invoice_Number__c. NL/UK invoices therefore carry two numbers (open point for the user).
  - Direct POST salesinvoice/SalesInvoices (no Exact order), single sales journal looked up (Type 20, exactly one needed), items from
    Administration_Product.Exact_Id__c / Exact (never created), idempotent (lookup by YourRef first), back-off 1 day on failure.
  - Calls go through Util_FinancialSystem.doRequest: sandbox backstop for production divisions + isFinancialSyncAllowed.
  - Not set to FINALIZED, so the Payment flow (pi/pr collection) is not triggered; the `ODOO-%` exclusion in
    rau_Subscription25_Invoice_c_Finalized_Create_Payment is still needed before anything finalizes these invoices (the flow has
    uncommitted edits from other work in the repo: not touched).
  - UNVERIFIED against real Exact: Journal/VAT per item/layout on print, the POST response shape. First test in acc: check the
    division is NOT a production one, then `Svc_OdooExactSync.sync(<invoiceId>)` on one invoice.

### 8f. Odoo Product relation (user, 2026-11-06) — replaces Product2.ExtProductCode__c and the auto-created Product2
- New object `OdooProduct__c` (Name + `OdooCode__c` unique, `OdooName__c`, `Product__c` lookup Product2 = financial system product, `Entity__c`,
  `FirstInvoice__c`, formula `Mapped__c`), tab, list views Unmapped / All, permission set `ps_miOdooProductMapping` (Finance).
- Intake: each line code is looked up in `OdooProduct__c`; the linked Product2 is booked (price book entry + administration product as before).
  An unmapped code stops the intake BEFORE anything is created (`MappingHoldException`): unmapped rows are recorded, the case goes to
  Status **In progress** (user choice), owner = queue `gqCaseFinanceExcellenceCenter` (when it exists in the org), comment `[Odoo intake hold] ...` with the
  original owner. Finance links the products, sets the case back to New + its original queue; the next run creates the invoice
  (the hold comment does not block a retry, unlike the `[Odoo intake]` failure comment).
- The Exact booking (Svc_OdooExactSync) uses the linked Product2's ProductCode as Exact item code (ExtProductCode__c removed again).
- Queue + members + access: `records/createFinanceQueue.apex` (idempotent, per org). Dev/acc: queue exists, NO members (Jessica Hak / Floris van Beek are not
  active users there); prod: both are active (profile miFinance) and get the permission set.
- Dev: 114 OdooProduct rows prefilled from the 673 prod PDFs (1 mapped: CarFleetUK -> CarFleet.01). The 101 Product2 imported earlier under Odoo
  codes were deleted in dev on 2026-11-06 (with their 101 price book entries; none mapped, no order items). Mapping suggestions for NL/UK: exact-items/odoo_to_exact_mapping_NL_UK.csv.
- Prod needs: object/tab/permission set/FLS, the queue script, the 3 intake classes; prefill rows (unmapped) so Finance can work from a list.

### 8g. LOG 2026-11-06 — state and where to continue
- Commits (none pushed, nothing in prod): c1e55c2, 12a3420, f2d7489, e39cf71, 490f6f2 (code), 1b27605 (exact-items CSVs).
- Dev + acc: all intake/sync classes deployed, tests green (intake 23, Exact sync 10). Queue exists in both, no members.
- Dev: 114 OdooProduct rows, only CarFleetUK mapped. Acc: Product2 FMC880NL exists (no OdooProduct mapping yet).
- RESUME HERE (acc Exact test, NL only):
  1. USER: create item `800.313.0260` (FMC880 box) in the Exact acc NL division: VAT code 2, group 1903 (ledger 801903), price 125.00.
  2. Acc: create Product2 `800.313.0260`, OdooProduct `FMC880NL` -> that product; repoint/recreate NL test invoice `I-2611-00564705`
     (case 500G500000rCnT3IAK); run `Svc_OdooExactSync.sync(<invoiceId>)` (NL = Print).
  3. Check in Exact: number, lines, VAT, total vs Odoo net 125.00, YourRef = Odoo number, journal. Run twice: second run must skip.
  4. Optional: unmapped-code test (needs a queue member in acc, e.g. the user).
  5. UK: acc administration has Synchronisation null and there is no UK sample: needs setup first.
- Open questions for the user: (a) two numbers on NL/UK invoices (Odoo + Exact) acceptable? (b) use Last_Queue__c to return held cases
  automatically, or Finance by hand? (c) FR/DE use the relation too (implemented for all)? (d) CarFleet-combination UK products onto one
  Exact item? (e) InterceptionFR/DepotPlainteFR/LevPlainteFR also Service?
- Before prod (explicit command only): everything in §8-8f; prod OdooProduct object/tab/permission set/FLS, queue script + member assignment,
  prefilled unmapped rows; fix Test_Rest_UpsertAccount.testUkPrivateOpportunityDefaultIsPi; cutoff for ~30 old New Odoo cases (proposal 30 days);
  WAITING timeout comment (proposal 3 days); dispatcher step Minut_OdooInvoiceIntake must be inactive in prod, Minut_OdooExactSync inactive;
  `ODOO-%` exclusion in rau_Subscription25_Invoice_c_Finalized_Create_Payment once anything finalizes these invoices.
