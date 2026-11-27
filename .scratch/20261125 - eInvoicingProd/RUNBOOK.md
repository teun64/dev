# EN 16931 e-invoicing (ZUGFeRD / Factur-X hybrid PDF, DE) - production runbook

Written 2026-11-25. Status: **dev, acc and PROD live for Germany (2026-11-26).** Prod: Lambda, metadata, secret, permission sets, Business Entity fill done, flag `Include_CII_Hybrid_PDF__c` ON for Germany only, 4 real invoices merged and validated. Remaining items are in 'Open after go-live' below. Prod changes still need an explicit command (see memory `feedback_prod_deploy_requires_explicit_command`). Context and history: memory `project_en16931_einvoicing_rollout`.

Commits (main, not pushed): `f8c8870` header fix, `f6a5509` first-PDF fix, `02a050a` XML content (Business Entity seller, direct debit, buyer reference, delivery period).

## What it does
A German invoice PDF (Subscription25 "Generate PDF") is linked as a File to the invoice. `Trigger_ContentDocumentLink` sees it, enqueues
`Svc_CIIHybridPdfMerge`, which builds the CII XML (`Svc_CIIInvoiceXmlBuilder`), sends PDF + XML to an AWS Lambda (Mustang 2.26.0 + Ghostscript 10.08.0)
and stores the returned PDF/A-3u as a **new version of the same File**. Status goes to `Invoice.CII_Merge_Status__c` (SUCCESS / ERROR + `CII_Merge_Error__c`).
Switch per administration: `Subscription25__Administration__c.Include_CII_Hybrid_PDF__c`. A merge failure never removes the plain PDF.

## Verified in dev/acc (2026-11-24/25)
- acc, German invoices I-2611-00569367 and I-2611-00569927: one Generate PDF click -> SUCCESS, PDF/A-3u compliant (veraPDF inside Mustang, 3,000+ checks), XML EN 16931 valid.
- Remaining validator notices are XRechnung/Peppol-only (R001, R010, R020, BR-DE-21) and BR-DE-15 (no buyer reference on that account): not needed for ZUGFeRD B2B.
- Direct-debit data (code 59 + buyer IBAN + mandate + creditor id) only proven in a rolled-back dev simulation, not on a real account (acc DE accounts have no IBAN).

## Prod state (done 2026-11-25/26)
- **Prod Lambda:** account 972907416352, stack `mi-invoice-merge` (profile `mi-prod-admin`), bucket `mi-prod-deployment-artifacts-972907416352`, URL `https://5bu2ciugwes4ejct6xo4wuem2a0eqvnr.lambda-url.eu-central-1.on.aws/`, own secret (in `account-ids.local.md`). Acc has its own Lambda too; dev, acc and prod secrets all differ.
- **Prod already had an older version of the pipeline** (classes from 2026-10-21/22, Administration/Invoice fields, global value sets, CMDT, UNCL5305 categories on the German VAT codes). The deploy `0AfTx0000016RcrKAE` (RunSpecifiedTests, 15/15) updated `Svc_CIIHybridPdfMerge`, `Svc_CIIInvoiceXmlBuilder`, `Trigger_ContentDocumentLink` + 3 tests, created the 5 Business Entity fields, `ec_/nc_CIIMergeService` (NC = prod URL, `allowMergeFieldsInHeader` true), `ps_miCIIMergeService`, and replaced `ps_EN16931_Invoicing` (prod's 6 grants kept + 5 new).
- **Deliberately NOT deployed:** `Ctrl_Invoice` refactor (changes PDF rendering for all invoices, NL/UK too; prod PDF still uses its own inline grouping, XML uses `Util_InvoiceLineAggregator`; checked equal on 4 real invoices), flow `rbb_OrderItem` (diff is reordering + one `getFirstRecordOnly` difference, unexplained), `Inv_TriggerCIIHybridPdfMerge` (deprecated).
- **Config:** secret stored on the `DefaultGroup` principal; `ps_miCIIMergeService` + `ps_EN16931_Invoicing` assigned to trietman@movingintelligence.nl (the dealer-portal user with the same name got nothing); Country_Code was already set on all 6 administrations; Business Entity Germany (reseller 5) filled with IBAN/BIC/phone/finance email from the Administration and `Creditor_Identifier__c = DE89ZZZ00000557087`; flag ON for Germany only.
- **Prod reseller codes:** 1 NL, 2 Greece (G4S), 3 Belgium, 4 France (echoes), 5 Germany, 6 UK. Prod has no "Germany (echoes)".
- **Prod VAT categories (Germany, already set):** `2` S, `6` G, `0` O, `7` K. Finance still has to confirm.
- **Pilot result:** I-2611-00775617 (and 00775685/86/87): `CII_Merge_Status__c = SUCCESS`, file version 2, Mustang 2.26.0: PDF/A-3u compliant, XML EN16931 valid, only XRechnung/Peppol notices + BR-DE-15. XML lines and totals equal the PDF (3/2/1/2 lines, net/VAT/gross identical), all 19%, grouping on.
- Note: SOQL as the normal user could not see the new fields before the permission set was assigned (FLS), "No such column" does not mean the field is missing.

## Decisions / information needed BEFORE prod (history, prod is live now: items 1, 4, 5 are still open)
1. **Finance confirms the VAT mapping** (`Subscription25__VAT_Code__c.UNCL5305_Category__c`): draft values in dev/acc (codes 4, 5, S at 0% were set to S, which breaks rule BR-S). Prod needs the confirmed category per package VAT code.
2. **Creditor id (Glaeubiger-ID)**: Germany = `DE89ZZZ00000557087` (given 2026-11-25). Prod has NO "Germany (echoes)" administration or Business Entity (checked 2026-11-25; that one only exists in dev/acc), so only one id is needed.
3. **Managing director of Germany** differs between dev and prod (see service email footer runbook): irrelevant for the XML, but do not mix the two topics up.
4. **Prod IBAN availability (checked 2026-11-25):** Germany (reseller 5) has 3,802 accounts, 1,697 with `Bank_Account_Number__c`, 1,530 with IBAN + mandate. So direct debit works for most; the rest fall back to code 1 ("instrument not defined"), valid but not a usable direct-debit invoice. acc has 0 IBANs (sandbox masking).
5. **Mandate reference source**: in prod Germany 0 accounts have `PayProv_MandateId__c`, so ALL mandates come from `FinancialIdBankMandate__c`. Logic is `PayProv_MandateId__c`, else `FinancialIdBankMandate__c` (Exact mandate id, hyphens removed, max 35). Confirm with finance that the Exact id is what the customer's mandate shows. A flow on Account clears `PayProv_MandateId__c` when it is set by hand, so test with a real provider mandate.
6. **Legal timing** (from the 2026-10-16 manual): DE issue obligation from 2027 if prior-year turnover > EUR 800k, everyone from 2028. This is a pilot, not a deadline.

## Part A - AWS (needs AWS access, not possible from the Claude session: no credentials)
Repo `~/mi-aws-infrastructure` (`lambda/invoice-merge/`, `account-ids.local.md` is gitignored). Dev and acc each have their own Lambda (acc stack `mi-invoice-merge` deployed 2026-11-25 with profile `mi-acc-admin`, own URL and secret, in `account-ids.local.md`; acc Named Credential repointed). Prod has none. The three AWS accounts are separate (profiles `mi-dev-admin`, `mi-acc-admin`, `mi-prod-admin`), template `infrastructure/invoice-merge/template.yaml`, prebuilt jar + `ghostscript-layer.zip`, no Docker needed. Dev was not created from this template (no stack there), acc was: acc is the proof that the template works.
1. Deploy a **separate prod Lambda** (own Function URL, own `MERGE_SHARED_SECRET`, Ghostscript layer 10.08.0, Java 21, Mustang 2.26.0), following the dev -> acc -> prod model of `project_aws_connect_multi_region_restructure`. Do acc first so acc stops using the dev URL.
2. The EventBridge warmer (rate 5 min) is in the template; dev has no provisioned concurrency, so do not add it.
3. Store the secret in `account-ids.local.md` (never in git). Function URL auth stays "none" + the `x-merge-secret` header check.
4. Smoke test with curl and the secret: expect `500 {"error":"Request body must contain pdfBase64 and ciiXml..."}` (secret accepted), and `401` without the secret.

## Part B - Salesforce metadata to prod (deploy only on explicit command)
Prod rules: `--test-level RunSpecifiedTests` (no NoTestRun), per-class coverage >= 75% for every deployed class, flows land as **Draft** and must be activated, retrieve first and diff when a component already exists in prod (`feedback_sf_retrieve_overwrites_uncommitted`).

Components (all in `force-app/main/default`):
- Apex: `Svc_CIIHybridPdfMerge`, `Svc_CIIInvoiceXmlBuilder`, `Util_InvoiceLineAggregator`, `Ctrl_Invoice` (refactor to the aggregator), `Trigger_ContentDocumentLink`, trigger `ContentDocumentLink`, tests `Test_Svc_CIIHybridPdfMerge`, `Test_Svc_CIIInvoiceXmlBuilder`, `Test_Util_InvoiceLineAggregator`, `Test_Trigger_ContentDocumentLink`, `Test_Invoice`.
- **Leave out `Inv_TriggerCIIHybridPdfMerge`** (deprecated, 0% coverage, nothing calls it) and the old flow `rau_Subscription25_Invoice_c_Trigger_CII_Merge`.
- Fields: Administration `Country_Code__c`, `Include_CII_Hybrid_PDF__c`; Invoice `CII_Merge_Status__c`, `CII_Merge_Error__c`; `Subscription25__VAT_Code__c.UNCL5305_Category__c`; `OrderItem.VAT_Code__c`; Business Entity `IBAN__c`, `BIC__c`, `Phone__c`, `Email_Finance__c`, `Creditor_Identifier__c`.
- Global value sets `UNCL5305_VAT_Category`, `UNCL4461_PaymentMeans`; custom metadata types `Payment_Method_UNCL4461_Mapping__mdt` and `Unit_Of_Measure_UNECE_Mapping__mdt` with their records (18 + 3).
- Flow `rbb_OrderItem` (VAT code lookup): check the prod version first; flow lands as Draft, activate afterwards (`reference_prod_flow_deploy_draft`).
- Permission sets `ps_EN16931_Invoicing` (FLS on the fields above) and `ps_miCIIMergeService` (principal access). Permission set deploys REPLACE the whole set (`reference_permissionset_platform_gotchas`): retrieve prod's version first.
- Named / External credential: `ec_CIIMergeService` and `nc_CIIMergeService`. **The repo NC points at the DEV Lambda URL. Do not deploy it to prod as is.** Set the prod Function URL in the NC before deploying, `allowMergeFieldsInHeader` must be `true`.
- Coverage warning seen in acc: `Ctrl_Invoice` had 73% with only the CII tests. In prod add the other Ctrl_Invoice tests (`Test_Invoice`, `Test_Invoices`, `Test_Ctrl_Invoice*`) to the run, or the deploy is rejected.
- Dry-run first (`--dry-run`), then the real deploy, then `graphify update .` and commit.

## Part C - Prod configuration after the deploy
1. Store the prod secret on the principal (not in git):
   `sf api request rest /services/data/v68.0/named-credentials/credential --method POST --body @cred.json --target-org prod`
   body `{"externalCredential":"ec_CIIMergeService","principalName":"DefaultGroup","principalType":"NamedPrincipal","credentials":{"MergeSecret":{"value":"<secret>","encrypted":true}}}`. Use PUT if it already exists.
2. Assign `ps_miCIIMergeService` and `ps_EN16931_Invoicing` to the users that trigger PDF generation. Prod check 2026-11-25: all 17,884 `Invoice_%` files of the last 30 days were created by one named user (Teun Rietman), so a user triggers it, no integration user. Assign to that user; if a batch ever runs it, that user needs it too. The callout runs as that user. If the permission set is missing there, the merge fails with an ERROR status on every invoice.
3. `Country_Code__c` on every Administration (prod administrations: Netherlands, Greece (G4S), Belgium, France (echoes), Germany, United Kingdom; reseller codes in prod: 1 NL, 2 Greece, 3 Belgium, 4 France, 5 Germany, 6 UK. Verify the dev/acc mapping before copying anything).
4. `UNCL5305_Category__c` on every package VAT code of prod (finance-confirmed mapping, see decision 1). Germany has only 4 codes: `2` DE VAT high rate (likely S), `0` No VAT (likely Z), `6` sell outside EU (likely G), `7` sell within EU (likely K). Other administrations only if they get the feature.
5. Business Entity: fill `IBAN__c`, `BIC__c`, `Phone__c`, `Email_Finance__c` from the Administration (same Apex fill as in dev/acc; anonymous Apex cannot use SYSTEM_MODE) and `Creditor_Identifier__c` (Germany). Check the result per reseller.
6. Do **not** switch `Include_CII_Hybrid_PDF__c` on yet.

## Part D - Pilot (Germany only)
1. Pick a few **real** German invoices, no test data in prod (`feedback_no_test_data_in_prod`). Regenerating a real invoice's PDF creates a second File with the same name: agree beforehand which one the customer receives.
2. Switch `Include_CII_Hybrid_PDF__c` on for `Germany` only. Generate PDF on one invoice.
3. Check: `CII_Merge_Status__c = SUCCESS`, file version 2 exists, size matches Salesforce (`ContentSize`).
4. Download the file with `sf api request rest "/services/data/v68.0/sobjects/ContentVersion/<id>/VersionData" --stream-to-file out.pdf` (**without `--stream-to-file` the CLI corrupts binary files**) and validate:
   `java -jar Mustang-CLI-2.26.0.jar --action validate --source out.pdf` (Maven Central, `org.mustangproject:Mustang-CLI`). Expect PDF/A-3u compliant and XML valid.
5. Open one file in a real German accounting tool (DATEV / Lexware / sevDesk or the customer's) and check that the XML is read.
6. Monitor for a week: `SELECT Name, CII_Merge_Status__c, CII_Merge_Error__c FROM Subscription25__Invoice__c WHERE CII_Merge_Status__c = 'ERROR'`.

## Findings after go-live (2026-11-26)
- **Trigger bug (fixed, prod deploy `0AfTx0000016a3RKAQ`, commit `71a7933`):** accounts with Automatic UBL Emails get the PDF AND the package UBL XML linked in one transaction; `Trigger_ContentDocumentLink` kept only the last file per invoice (the XML), so the PDF never merged (I-2611-00791826 showed no status, no job). Now it keeps all linked files and picks the one titled like the invoice PDF. New test `test_triggersWhenPdfAndUblXmlAreLinkedTogether`. The package UBL itself is expected (Dutch-market feature) and is not touched. After the fix, regenerating the invoice merged automatically (job at 19:00:52).
- **Direct debit verified on a real prod invoice:** I-2611-00791826 (payment I8): means 59, buyer IBAN, mandate = Exact id without hyphens, creditor id DE89ZZZ00000557087, PDF/A-3u + XML valid, ungrouped account (`Invoice_Grouping__c` false), 1 line = PDF = package UBL.
- **1-cent rounding (Mustang warning 10, not an error):** 7.50 x 19% = 1.425. PDF and our XML say VAT 1.42 / gross 8.92 (the package computes the line VAT as 1.42); the package UBL and Mustang say 1.43 / 8.93. Decision: leave it, the hybrid must equal the printed PDF. Some accounting tools may flag the cent.
- Package UBL known quirks (not ours): country as text ("Germany"), IBAN with spaces, empty bank/order ids, leading space in IssueDate, payment means 30 even for direct debit, no CustomizationID/ProfileID.
- Deleting the UBL file on an invoice does not affect our merge (needs only the PDF); effect on the pending UBL email not checked.

## German accounts with Automatic UBL Emails (`Subscription25__Include_UBL_In_Email__c` = true), prod, 2026-11-26
Selected with `Reseller_Name__c = '5'` on the Account (Germany). 18 accounts, listed for later use: for these accounts Generate PDF links the PDF AND the package UBL XML in one transaction (the case fixed by commit `71a7933`), so check their first merged invoices. 17 of 18 have `Invoice_Grouping__c` = true.

| Account Id | Name | Grouping |
|---|---|---|
| 001AO0000040aBJYAY | BS Haustechnik GmbH | true |
| 001AO000002zAd9YAE | CLIMATECH Montage GmbH | true |
| 001bR000003QsawQAC | eConcept+ Swen Korz | true |
| 0013W00000OXACBQA5 | Ernst Kähler GmbH | true |
| 0013W00000OXA6IQAX | F&F Fisch und Feinkost Handelsgesellschaft mbH | true |
| 0013W00000OXAC8QAP | Filter-Müller GmbH | true |
| 001bR00000MSCuQQAX | KÖTTER SE & Co. KG Security | true |
| 001bR00000A0u4XQAR | Kötter SE & Co. KG Security München | true |
| 001AO000003qpywYAA | Kötter SE & Co. KG Security München | true |
| 001bR00000A0vyGQAR | Kötter SE & Co. KG Security München | true |
| 001bR00000A109wQAB | Kötter SE & Co. KG Security München | true |
| 001bR00000BJw3ZQAT | Kötter SE & Co. KG Security München | true |
| 001bR00000bU2NGQA0 | Kötter SE & Co. KG Security München | true |
| 001bR000009KMSEQA4 | KÖTTER SE & Co. KG Security München | true |
| 001bR00000A16yTQAR | Kötter SE & Co. KG Security München, NL Fürth | true |
| 001bR00000yqgwhQAA | KÖTTER SE & Co. KG Security, Düsseldorf | true |
| 0013W00000OXAH5QAP | Mawo Elektro e.K. | true |
| 001bR00000GpvW5QAJ | Trucktat GmbH | false |

Also noted: `001AO000002plpXYAQ` Automobile Obermeier (reseller 5, ungrouped, direct debit I8): UBL option is **off** (switched off by the user on 2026-11-26; its invoice I-2611-00791826 was the first real direct-debit hybrid check). Query to refresh the list: `SELECT Id, Name, Invoice_Grouping__c FROM Account WHERE Subscription25__Include_UBL_In_Email__c = true AND Reseller_Name__c = '5' ORDER BY Name`.

## Findings 2026-11-27
- **Batch bug (fixed, prod deploy `0AfTx0000016axtKAA`, commit `e91bc64`):** the nightly PDF batch (21:16 UTC) created 10 German invoices; 5 merged, 5 got ERROR "You have uncommitted work pending": one queued job handled several invoices, the first merge inserted the new file version (DML) and every following callout was refused. `Svc_CIIHybridPdfMerge` now handles ONE invoice per job and chains the rest (chain skipped in tests: `Test.isRunningTest()`); new regression test. The 5 failed invoices (DE26712939/41/42/43/47) had gone out as plain PDF; re-merged by hand in one job (5 chained jobs, all SUCCESS, Mustang valid, totals and lines = PDF).
- **Email vs merge:** package jobs (org time): `Job_InvoiceCreation` 19:16, `Job_InvoicePDFCreation` 22:16, `Job_EmailInvoice` 23:16 (= 21:16 / 22:16 UTC). The merge takes seconds, so it is done about an hour before the email. Proof: I-2611-00791826 merged 19:00 UTC, EmailMessage 22:18 UTC links the same ContentDocument whose latest version is the merged file (85,327 bytes). Only the manual email button within ~5 s of Generate PDF could still send the plain file.
- **Payment method vs PDF:** XML code follows the PDF text (I8 -> 59 "abgebucht", 14 -> 30 "bitte ueberweisen"). The package UBL ALWAYS writes PaymentMeansCode 30, whatever the method (checked on 7 method/reseller combinations in prod, 3 files each: I8, 08, E8, 14, 30). So the package UBL says credit transfer for direct-debit invoices; accepted, UBL is the separate Dutch-market file. Our CMDT mapping has no entry for method `E8` (6 NL invoices in 60 days): no PaymentMeans written for those; irrelevant for Germany (only I8 and 30 occur), add `E8` before NL/UK use the hybrid.
- **Mixed VAT rates:** none in the last 30 days (0 of 4,430 invoices); not a case to cover.
- **`Ctrl_Invoice` refactor now in prod** (deploy `0AfTx0000016bIrKAI`, 15/15 tests, class coverage 81%, run with `Test_Invoice`, `Test_Invoices`, `Test_Ctrl_InvoiceRemarks`, `Test_Ctrl_InvoiceEstablishmentAddress`, `Test_Util_InvoiceLineAggregator`). Prod now equals dev/acc/repo. Before/after check on 20 real invoices (NL, DE, UK; grouped and ungrouped; credit notes; TOTAL VAT method), rendering `/apex/Invoice?h=1` via anonymous Apex: rendered text identical (hash and length) before and after. Rollback copy of the old class: scratchpad `ctrl_prod.cls` (not durable); the old version is in git history (before e3affcb).
- Technique worth reusing: `new PageReference('/apex/Invoice')` with `Id` and `h=1`, `getContent()` in anonymous Apex, strip scripts and tags, hash (the log escapes `|` as `&#124;`).
- Accepted: 1-cent rounding comes from the package; buyer reference (BT-10) not required yet.

## Open after go-live (2026-11-26)
- **Flag is ON for Germany**: the evening run (about 18:20, invoices created + FINALIZED + emailed) now merges every German invoice. Switch off with `Include_CII_Hybrid_PDF__c = false` if needed.
- Direct debit path verified (see findings). Still open: a grouped account with direct debit, and PayProv-mandate accounts (none in Germany).
- **Only single-rate (19%) grouped invoices checked** against the PDF: check a mixed-rate, an ungrouped account and a credit note.
- **Finance:** confirm VAT categories (2 S, 6 G, 0 O, 7 K) and the Exact mandate id as mandate reference (no German account has `PayProv_MandateId__c`).
- **Buyer reference BT-10** is empty unless the account has a cost center or payment remark.
- No other administrations yet (UK/NL).

## Open verification items (not yet checked anywhere)
- **Never re-run the merge on an already merged file:** re-merging a hybrid PDF embeds a second XML and fails PDF/A validation (acc test 2026-11-25: file version 3 invalid, MIME type of the embedded files). Normal flow (Generate PDF creates a plain file) is fine; a guard in `Svc_CIIHybridPdfMerge` (skip when the PDF already has the XML) is a possible hardening.
- **Race with the invoice email:** the merge is asynchronous (Queueable + callout). Check whether the invoice email attaches the file before or after the merge, and whether it takes the latest version. If it can send the plain version, the hybrid PDF never reaches the customer.
- Which PDF the customer portal / `Rest_Invoices` / public ContentDistribution links serve after the merge (latest version of the same document, so expected fine).
- Prod IBAN availability (decision 4) and the real mandate reference source (decision 5).
- First-PDF behaviour in prod: depends on file title `Invoice_<number>.pdf`; confirm prod invoices use the same naming (UK numbers on create, NL/DE on print).

## Rollback
- Immediate: `Include_CII_Hybrid_PDF__c = false` on the administration. New PDFs are no longer merged; existing merged files stay (they remain valid PDFs).
- Lambda down or secret wrong: invoices get `ERROR`, the plain PDF stays untouched; nothing blocks invoicing.
- Metadata: the new fields and classes are additive; no destructive change is needed to roll back.

## Later (not part of this rollout)
- UK / NL: native UBL via the Subscription25 package setting `Include_UBL_In_Email__c` on B2B accounts (separate path, see memory).
- Peppol / XRechnung only if a customer asks (electronic address BT-34/BT-49, Leitweg-ID as buyer reference).
- Account field for a Leitweg-ID (today BT-10 = Cost Center, else Invoice Payment Remark).
- Separate acc Lambda (Part A step 1) before acc is used for anything else.
