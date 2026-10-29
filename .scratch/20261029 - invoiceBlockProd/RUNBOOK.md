# Prod: invoice email + payment block (Lightning invoice templates)

Tested end to end in acc on 2026-10-29 (see `.scratch/20261015 - invoiceEmailLightning/RUNBOOK.md`). **Prod only on explicit go.**

## Package A: validated 2026-10-29, check-only **0AfTx0000014KkLKAU** (19/19, Test_Svc_InvoicePaymentBlock 3/3)
`packageA/`: Payment_Setup_Block__c, Interaction_Status__c (+ Awaiting Invoice Email), Svc_InvoicePaymentBlock + test, block templates EN/NL/DE (generic text), flows afl_Payment_Direct_Debit_Setup / rau_Subscription25_Invoice_c_Email_Status_Payment / rab_Payment_Direct_Debit_Awaiting_Invoice / rab_Payment_Direct_Debit_Processed / rab_Payment_Direct_Debit_Escalation, label paymentRemarkPR + NL/DE/FR translations, ps_miSubscription25_User (**prod variant** = prod + 1 field; the repo would make FinancialSystemIdWarehouse__c read-only), Admin profile FLS Payment_Setup_Block__c.
- Can go live any time: flows arrive **inactive** in prod. Effect right away: only the new PDF remark (label) and the new block templates (not used yet).
- `sf project deploy quick -o prod --job-id 0AfTx0000014KkLKAU` (valid 10 days, as long as these components don't change).
- The DirectDebit folder meta is left out on purpose (would reset the folder sharing).

## Package B: cutover (back-to-back, **not** 21:00–21:30 UTC, Job_EmailInvoice 21:16 UTC)
Prod: the Classic InvoiceNL/UK/DE are in Classic folder **Invoicing** (same name as the Lightning folder); Administrations NL/UK/DE → InvoiceNL/UK/DE.
1. `python3 -I cutover.py 1 --write`: Classic folder → `Invoicing_Classic`, templates → `*_Classic` (Ids kept). From here until step 2 the Administrations point at a non-existent name → keep it short.
2. Deploy `packageB/` (Lightning folder Invoicing + InvoiceNL/UK/DE) from a non-dot copy, RunSpecifiedTests Test_Svc_InvoicePaymentBlock.
3. `cutover.py 3 --write`: letterheads lh_M_Preferences_EN/NL/DE/FR (`letterheads_from_dev.json`, dev state 10-28) + EnhancedLetterheadId on the 3 invoice templates.
4. `cutover.py 4 --write`: activate the 5 flows.
5. Check: `cutover.py check`; render InvoiceUK on a prod invoice (no send); the next nightly run: payments `Awaiting Invoice Email` → `Mail Sent` after Job_EmailInvoice.
Rollback: deactivate the flows (the separate setup mail comes back) → rename the Lightning templates → rename `*_Classic` back.

## Open
- Legal/finance: pre-notification period for repeat invoices (see the invoice email runbook).
- Existing prod payments in Setup/Mail Sent are not affected (the flow only acts at payment creation).

## ✅ DONE 2026-10-29 (Teun: A + B together), 11:25–11:40 UTC
- Package A: quick deploy refused (the validation was no longer usable) → normal deploy **0AfTx0000014L25KAE** (19/19, 3 tests).
- Step 1: Classic folder 00lbR000002P1SnQAK → Invoicing_Classic "Invoicing (Classic)", templates 00X3W000000pHHTUA2 / HHtUAM / HHsUAM → InvoiceNL/UK/DE_Classic.
- Step 2: package B **0AfTx0000014L5JKAU** → Lightning InvoiceDE 00XTx00000k9yYjMAI, InvoiceNL 00XTx00000k9yYkMAI, InvoiceUK 00XTx00000k9yYlMAI (folder Invoicing).
- Step 3: letterheads lh_M_Preferences_EN 0RnTx00000003kHKAQ, _NL 0RnTx00000003ltKAA, _DE 0RnTx00000003nVKAQ, _FR 0RnTx00000003p7KAA; linked UK→EN, NL→NL, DE→DE.
- Step 4: flows active: afl_Payment_Direct_Debit_Setup 5→6, rab_Payment_Direct_Debit_Escalation 1→2, rau_Subscription25_Invoice_c_Email_Status_Payment 1, rab_Payment_Direct_Debit_Awaiting_Invoice 1, rab_Payment_Direct_Debit_Processed 1.
- Step 5: render (no send) InvoiceUK GB26755168, InvoiceNL (invoice without number → subject without number, the package only sends once there is a number), InvoiceDE DE24709988: header + footer, no open merge fields.
- ⏰ Check tomorrow morning: the first Job_EmailInvoice run (21:16 UTC) uses the Lightning templates (2 UK invoices with a number pending this week, incl. Sledge GB26755147, whose payment is already Mail Sent → separate mail already sent, no block). New pr payments from now on: Awaiting Invoice Email → Mail Sent after the send.

## ⚠ Incident 2026-10-29 14:15–14:45 UTC: 'Template with name InvoiceNL not found'
The new Lightning folder Invoicing was Hidden without shares → Finance users (Bianca Jonkers, Anneke Keinemans) could not send invoices (6 NL invoices ERROR + 'Invoice delivery failure' Cases MI00430625 / 774 / 782 / 797 / 798). Fix fcb5270: folderShares AllInternalUsers View → prod 0AfTx0000014MXdKAM (Teun), verified via retrieve. Next: Finance resends the ERROR invoices and closes the Cases.
