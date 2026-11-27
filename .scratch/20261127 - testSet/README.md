# TESTSET (dev/acc only) - reusable e-invoicing / billing regression set
Accounts `TESTSET A B.V.` (2 yearly contracts: Black.12, White.12, 2 assets) and `TESTSET B B.V.` (monthly: BlackR.01 + 2 x All-in-one, 1 asset), Dutch administration (ZUGFeRD flag on), 3 contacts per account (Main / Invoice+Digital / Shipping), start 2026-10-01, no mail.
1. `01_base.apex` accounts, contacts+roles, assets, flag on NL admin. (Debtor number on Account: `FinancialDebtorNumber__c = 'TSA'/'TSB'`, needed for activation.)
2. `02_contract.apex` once per `WHICH` = A1, A2, B1, B_AIO (sed the placeholder; REST handler eats the SOQL limit).
3. Run `Batch_ActivateDraftContractProducts`, then package jobs via the package page 'Run Now' (`runjob.sh <org> <Job>`, needs `playwright-cli open <url of /apex/Subscription25__JobManagement>`): Job_RecurringOrderManagement, Job_RecurringOrderApplication, Job_InvoiceCreation, then set new invoices `Email_Status__c = WILL_NOT_BE_SENT`, then give the invoices a number (the PDF job only handles numbered invoices; set `Subscription25__Invoice_Number__c = <admin prefix> + 26900001..` inside `Util_System.setEruIluvatar(true)` / `false`, a plain update is refused), then Job_InvoicePDFCreation (+ Job_CalculateContractRevenues, Job_ApplyIndexation, Job_UnblockAccounts). Never the Exact/payment/email jobs.
4. `03_cleanup.apex` removes the set.

Notes: dev cannot make PDFs (Visualforce 'URL no longer exists', dev-only); acc can. Job_InvoiceCreation is org-wide (dev: 129 extra invoices; acc has ~44k Draft orders due): all new invoices must be set to WILL_NOT_BE_SENT.

## Acc / any org with a big backlog (verified 2026-11-27, acc)
Do NOT run the org-wide package jobs (Job_InvoiceCreation etc.) or Batch_ActivateDraftContractProducts there. Instead:
1. `01_base.apex`, then `02_contract.apex` for A1, A2, B1, B_AIO.
2. Activate only the test contract products by DML (`Subscription25__Status__c = 'Activated'` where contract account name LIKE 'TESTSET %'); the package then creates the orders itself.
3. Invoice only the test orders with the package invocable action `Subscription25__Inv_InvoiceOrders` (REST: POST /services/data/v62.0/actions/custom/apex/Subscription25__Inv_InvoiceOrders, body {"inputs":[{"orderIds":[...]}]}), one call per invoice group (account + effective date).
4. WILL_NOT_BE_SENT + invoice number via `Util_System.setEruIluvatar(true)`, then render `/apex/Invoice` (getContentAsPDF), save `Invoice_<number>.pdf` linked to the invoice (fires the merge trigger), validate with Mustang.
The package filter AUTO_INVOICE_FILTER_FIELD does NOT limit Job_InvoiceCreation (tested dev 2026-11-27).
