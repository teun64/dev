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

## Open after go-live (2026-11-26)
- **Flag is ON for Germany**: the evening run (about 18:20, invoices created + FINALIZED + emailed) now merges every German invoice. Switch off with `Include_CII_Hybrid_PDF__c = false` if needed.
- **Direct debit path (code 59, buyer IBAN, mandate, creditor id) not yet seen on a real prod invoice**: the pilot invoice used code 30 (credit transfer, seller IBAN as payee). Find an invoice whose payment method maps to 59 with IBAN + mandate and validate it.
- **Only single-rate (19%) grouped invoices checked** against the PDF: check a mixed-rate, an ungrouped account and a credit note.
- **Finance:** confirm VAT categories (2 S, 6 G, 0 O, 7 K) and the Exact mandate id as mandate reference (no German account has `PayProv_MandateId__c`).
- **Buyer reference BT-10** is empty unless the account has a cost center or payment remark.
- Later: deploy the `Ctrl_Invoice` refactor (add `Test_Invoice`, `Test_Invoices` etc. to the run for 75% coverage) so PDF and XML share one grouping; no other administrations yet.

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
