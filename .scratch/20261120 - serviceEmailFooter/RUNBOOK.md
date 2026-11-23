# Service email footer + preference token rotation (2026-11-20)

Source: Claude Docs "Service Email Footer – Legal Requirements & Implementation" (https://claude.ai/artifact/KvTN8iNDDTCidqHVbWoKdR). Not legal advice: counsel review before prod.

## Status (2026-11-23)
- dev + acc: DONE and committed (db270d2): fields, invoice templates NL/DE/UK, rotation batch, guest masking, NL letterhead footer emptied. Previews sent from acc 2026-11-23.
- prod: not deployed (legal review, `Support_URL__c` fill, letterhead step below).

## What is in it
1. Fields (replaces the earlier block/FAQ-line design; `Legal_Company_Block__c` is now unused, `Legal_FAQ_Line_*`, `Legal_Show_FAQ__c` and label `Legal_FAQ_Url` are deleted): Administration `Legal_Address__c`; Invoice mirrors `Legal_Name/Address/CoC/VAT/Managing_Directors__c` (from Administration) and `Legal_Support/Terms/Privacy_Url__c` (from `Business_Entity__r`); Business Entity `Support_URL__c` (plain URL, not synced; fill per entity).
2. `InvoiceNL/DE/UK` footer: FAQ line, why-you-receive, preference link (Recipient.Preference_Center_Url__c), personal links notice, company block. Terms stay in the letterhead footer (so the company block sits above terms, not below). InvoiceNL: signature image removed (one logo).
3. Contact: `Preference_Token_Previous__c`, `Preference_Token_Date__c`. Key = HMAC(email|yyyymm) (period inside the MAC; a plain .yyyymm suffix would be forgeable). `Batch_RotatePreferenceTokens` (90 days, cap 5000/run, batch size <=100): old key -> previous, new key + url. Guest page: current key ok, previous key ok + "older link" toast, else expired message. Email change clears previous + resets date.
4. Guest Preference Center shows first name + masked email only, no phone.

## STANDARD footer for service mails (the "template footer")
Use this block, in this order, as the footer of every service mail template. Text size 11px, line-height 18px, color #8A8F8A, links #5B625B (not bold), one empty line between groups, no separator line, no extra footer from the letterhead:
1. Company block: name (bold), address, registration number + VAT (`Legal_Name__c`, `Legal_Address__c`, `Legal_CoC__c`, `Legal_VAT__c`; label text written per language: NL "KvK / BTW", DE "Handelsregister / USt-IdNr.", UK "Company no. / VAT"); DE only: managing directors line (`Legal_Managing_Directors__c`).
2. "U ontvangt dit bericht omdat u klant bent van Moving Intelligence en het betrekking heeft op uw dienstverlening." (why you receive)
3. "Deze e-mail bevat persoonlijke links. Stuur hem daarom niet door."
4. "U bepaalt zelf welke andere e-mails u van ons ontvangt: beheer uw e-mailvoorkeuren." (`Recipient.Preference_Center_Url__c`)
5. FAQ line "Vragen over uw dienst? Bekijk onze veelgestelde vragen." with `Legal_Support_Url__c`. Only in templates whose business entity has a support URL (NL now); a template cannot hide it, so languages without a support page simply leave the line out, with its blank line.
6. Terms line "Op al onze diensten zijn onze algemene voorwaarden van toepassing. Lees onze algemene voorwaarden en privacyverklaring." with `Legal_Terms_Url__c` / `Legal_Privacy_Url__c` (in the template block, NOT in the letterhead; DE/UK still use their letterhead line until their templates get the same treatment).
Reference implementation: `force-app/main/default/email/Invoicing/InvoiceNL.email` (last div). Gotchas: Text/formula fields are HTML-escaped in Lightning templates, so sentences with links live in the template and only URLs/values come from fields. Data source today: Administration (name, address, CoC, VAT, directors) and Business Entity (`Support_URL__c`, terms, privacy) through Invoice mirror formulas; both move to the Business Entity later (see memory business-entity-source-of-truth).

## Letterhead step (per org, part of the deploy)
Enhanced letterheads cannot be retrieved or deployed with sf; use the data API. For every letterhead whose template now carries the terms line in its own footer block (NL now: `lh_M_Preferences_NL`), empty the letterhead footer so the terms line is not shown twice:
```
sf data query -o <org> -q "SELECT Id,LetterheadFooter FROM EnhancedLetterhead WHERE Name='lh_M_Preferences_NL'"   # save the old footer first
sf data update record -o <org> -s EnhancedLetterhead -i <Id> -v "LetterheadFooter=' '"
```
Original NL footer (restore text) is the "Op al onze diensten zijn onze algemene voorwaarden van toepassing. Lees onze <a href=https://movingintelligence.nl/algemene-voorwaarden>algemene voorwaarden</a> en <a href=https://movingintelligence.nl/privacy>privacyverklaring</a>." div, 11px #8A8F8A, padding 0 10px 10px. Do this in the same window as the InvoiceNL template deploy. dev + acc done 2026-11-23 (ids dev 0Rnbd0000000DdBCAU, acc 0RnG50000000o4rKAA); prod: look up the Id. The letterhead may also be used by mails not in the repo: check before emptying in prod.

## Deploy order (each org)
fields (Admin, Invoice, Contact) -> FLS (Admin profile partial, ps_miSubscription25_User read: deploy from the org's own copy) -> Business Entity `Support_URL__c` + FLS (ps_BusinessEntitiesAdmin/ReadOnly, Admin profile) -> Apex (Util_CommunicationPreferenceToken, Trigger_Contact, Ctrl_PreferenceCenterGuest, Ctrl_PreferenceCenter, Batch_RotatePreferenceTokens + tests, run Test_Trigger_Contact too for coverage) -> preferenceCenter LWC -> templates. Then fill `Support_URL__c` per Business Entity and do the letterhead step. Schedule the rotation batch only after a dry look (first cycle over ~213k legacy tokens).

## To do (other touchpoints)
DirectDebit templates (12), Opportunity_OrderConfirmation, DealerPortal mails (B2B, VF), campaign/2G mails, hub headers/footers, payment success screen, NPS thank-you, Mustang/PDF (reuse the Invoice fields). Prod: managing director for Germany differs between dev (Patrick Horst) and prod (Mathieu Chènebit): confirm. Letterhead footer terms wording vs approved text. Preference page guest messages are English only.
