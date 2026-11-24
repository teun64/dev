# Step 6: standard service-mail footer on payment mails, order confirmation, Dealer Portal mails (prod steps)

Status 2026-11-24: LIVE IN PROD (steps 1-6 done 2026-11-24). Deploys: fields 0AfTx0000016G9ZKAU, FLS 0AfTx0000016GCnKAM, code/templates 0AfTx0000016GEPKA2, flow 0AfTx0000016GJFKA2 (version 3 active, v2 obsolete). 6 Business Entities seeded; 6 previews sent and resent to the user. Open: flow sync confirmation on next Administration save; managing directors empty on 5 of 6 entities (DE should have Mathieu Chènebit).

Order matters (fields -> FLS -> data -> code/templates -> flow). Packages in this folder; deploy with `sf project deploy start -o prod --manifest <pkg> --test-level RunSpecifiedTests -t Test_Ctrl_EmailLetterheadFooter` (NoTestRun is rejected in prod; field-only and flow-only packages need a test level too, use the same test).

## 0. Preconditions (read-only)
- Prod Business Entities exist for reseller 1, 3, 5, 6 (and 2, 4): yes (read 2026-11-23). Prod Support_URL__c only set on Netherlands (https://movingintelligence.nl/support); DE/UK FAQ lines are off anyway.
- Prod Sync_Administration_to_Business_Entity: version 2 active (activated 2026-11-23). New version lands as Draft and must be activated (FlowDefinition Metadata activeVersionNumber), old version then obsolete.
- Retrieve the org copies of ps_BusinessEntitiesReadOnly, ps_BusinessEntitiesAdmin, ps_miPaymentCheckout before step 2 (permission set deploys replace the whole set).

## 1. Fields (package_fields.xml)
4 on Business_Entities__c (Business_Name, Address (custom Address type), CoC_Number, VAT_Number) + 8 formula mirrors on Payment__c (Legal_Name, Address, CoC_Number, VAT_Number, Managing_Directors, Support_Url, Terms_Url, Privacy_Url). New fields have zero FLS: tests/readers fail until step 2.

## 2. FLS (needed before anything reads them)
- Business Entity fields: add to ps_BusinessEntitiesReadOnly (read) and ps_BusinessEntitiesAdmin (edit) on the retrieved prod copies (script scratchpad fls.py: beRO / beAdmin), plus Support_URL__c (missing in the sets).
- Payment mirrors: read on ps_miPaymentCheckout (retrieved prod copy, fls.py pay) and the Admin profile (minimal profile file, merge deploy). Without it the mail renders the company lines empty (seen in dev 2026-11-24).
- Admin profile: edit on the 4 Business Entity fields (needed for the seed/check by an admin).

## 3. Business Entity data
The flow fills the 4 fields from the Administration billing fields on the next Administration save. To not wait/touch Administrations: one-off anonymous Apex (scratchpad seedbe2.apex + seedbe3.apex logic: Business_Name, CoC, VAT, Address street/postal/city + country code NL/DE/GB/BE/FR/GR) updating only Business_Entities__c. Verify: 6 prod entities with name, address, CoC, VAT; DE has Managing_directors__c (Mathieu Chènebit).

## 4. Code, component, templates (package_code.xml)
Ctrl_EmailLetterheadFooter (+ test), component emailLetterheadPreferences (footer part now company block, controller resolves the Business Entity by mail language: nl=1, fr=4, de=5, else 6), 27 payment templates (3 InvoiceBlock templates excluded: include block, no footer), Opportunity_OrderConfirmation, DealerPortal_Welcome/PasswordReset/Invite. Note: the 12 reminder/setup/authentication templates in the repo carry full image URLs now (were {[devName:..]}); check the live body of one after deploy (feedback_stub_restore_verify_live).

## 5. Flow (package_flow.xml)
Deploys as Draft. Activate with the Tooling/Metadata activeVersionNumber call, then check the old version is obsolete. Afterwards one Administration save (or step 3) confirms the sync; check the 4 fields on one entity.

## 6. Previews from prod (to the user's own contact only)
paymentFailedPay NL/DE/EN, one DirectDebit reminder, Opportunity_OrderConfirmation, DealerPortal_Welcome. Check: company name/address/KvK/BTW filled, terms/privacy/FAQ links work, no empty lines. Do not trigger real dunning.

## 7. Roll back
Templates/component: redeploy the previous versions from git (before 8619a30). Fields/flow can stay (harmless).

## Open
Invoice footers still read the Administration (Invoice Legal_* mirrors), payment/dealer mails read the Business Entity; reversing the flow so the Business Entity is master is the parked source-of-truth work.
