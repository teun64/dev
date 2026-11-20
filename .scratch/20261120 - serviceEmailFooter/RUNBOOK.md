# Service email footer + preference token rotation (2026-11-20)

Source: Claude Docs "Service Email Footer – Legal Requirements & Implementation" (https://claude.ai/artifact/KvTN8iNDDTCidqHVbWoKdR). Not legal advice: counsel review before prod.

## Status
- dev: DONE (fields, invoice templates NL/DE/UK, rotation batch, guest masking). Preview mails sent 2026-11-20.
- acc: not deployed. prod: not deployed (wait for legal review).

## What is in it
1. Administration + Invoice formula fields: `Legal_Company_Block__c` (language neutral), `Legal_FAQ_Line_NL/EN/DE/FR__c`, checkbox `Legal_Show_FAQ__c`. Invoice fields mirror the Administration (Lightning templates are single-hop). Label `Legal_FAQ_Url` holds the FAQ URL (currently the NL support page, to be replaced by the generic .com FAQ page).
2. `InvoiceNL/DE/UK` footer: FAQ line, why-you-receive, preference link (Recipient.Preference_Center_Url__c), personal links notice, company block. Terms stay in the letterhead footer (so the company block sits above terms, not below). InvoiceNL: signature image removed (one logo).
3. Contact: `Preference_Token_Previous__c`, `Preference_Token_Date__c`. Key = HMAC(email|yyyymm) (period inside the MAC; a plain .yyyymm suffix would be forgeable). `Batch_RotatePreferenceTokens` (90 days, cap 5000/run, batch size <=100): old key -> previous, new key + url. Guest page: current key ok, previous key ok + "older link" toast, else expired message. Email change clears previous + resets date.
4. Guest Preference Center shows first name + masked email only, no phone.

## Deploy order (each org)
fields (Admin, Invoice, Contact) -> FLS (Admin profile partial, ps_miSubscription25_User read: deploy from the org's own copy) -> label Legal_FAQ_Url (targeted) -> Apex (Util_CommunicationPreferenceToken, Trigger_Contact, Ctrl_PreferenceCenterGuest, Ctrl_PreferenceCenter, Batch_RotatePreferenceTokens + tests, run Test_Trigger_Contact too for coverage) -> preferenceCenter LWC -> templates. Then set `Legal_Show_FAQ__c` per Administration. Schedule the rotation batch only after a dry look (first cycle over ~213k legacy tokens).

## To do (other touchpoints)
DirectDebit templates (12), Opportunity_OrderConfirmation, DealerPortal mails (B2B, VF), campaign/2G mails, hub headers/footers, payment success screen, NPS thank-you, Mustang/PDF (reuse the Invoice fields). Prod: managing director for Germany differs between dev (Patrick Horst) and prod (Mathieu Chènebit): confirm. Letterhead footer terms wording vs approved text. Preference page guest messages are English only.
