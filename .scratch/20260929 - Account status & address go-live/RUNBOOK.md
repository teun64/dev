# Account status & address model — prod go-live 2026-09-29

Window 18:00–19:30 Amsterdam (actual: ~12:10 pre-deploy, 18:10–20:00 window, clean-up until ~21:15).
Repo state: dev versions in `force-app`; the **prod-specific** packages exactly as deployed are in `packages/`.

## What went live in prod

| Time | Step | Result |
|---|---|---|
| 12:10 | P1 (`packages/P1_prod_fields_values`): 10 new fields, pvs_AccountStatus 6 new + 3 old values, B2B/B2C record types | quick-deployed after RunLocalTests validation (265/265, ~7 min) |
| 12:15 | `packages/P1b_prod_permissionset_group`: ps_miAccountStatus_Admin (Status/Previous/ChangedBy) + pg_miAPIPlatformIntegration (prod members kept) | assigned to Teun Rietman, Jessica Hak, Maruan Mourad |
| 12:20 | FLS for the new fields (`scripts/copy_fls.py`) | licence profiles (Anypoint, Identity) and pg_* aggregates can't be granted |
| 12:25 | Status backfill (`scripts/status_backfill.py`): bankrupt > blocked > deactivated > active | 183,317 accounts, 0 failures (active 171,483 · deactivated 10,708 · blocked 931 · bankrupt 201) |
| 18:10 | Backups (local only, contain customer data): accounts, debtor numbers, historic debtor numbers, sync-flag snapshot (75) | scratchpad `golive_backup_prod/` |
| 18:16 | Exact sync flow `rau_Account_Sync_to_Financial_System` **off** (v7) | |
| 18:17–18:45 | Address migration (`scripts/address_migration.py`) | 183,361 accounts, 6,426 debtor numbers, 182 historic, 0 failures. Prod debtor numbers have no Exact_Visiting id → Exact_Billing_Address_ID__c left empty, invoice id moved to Exact_Invoice_Address_ID__c |
| 18:45 | Rename DeactivatedOn__c → StatusChangedOn__c | **broke Account saves** (old rbb_Account v61 assigns `$Record.DeactivatedOn__c` by name) |
| 18:56 | Rename reverted | saves OK again. Outage 18:45–18:56; integration log showed no failed calls |
| 18:59–19:02 | rbb_Account off → rename → deploy `packages/P2a_prod_rbb_invoice_flows` → activate rbb_Account v62 | prod deploys flows as **Draft** ("deploy flows as active" is off) → every deployed flow must be activated by hand |
| 19:15 | rbu_Subscription25_Invoice_c v34 activated | |
| 19:29–19:31 | P2 (`packages/P2_prod_logic`) validation 283/283 → quick deploy, 7 flows activated (`scripts/activate_p2_flows.py`) | needed extra: Subscription25__Administration__c.Country_Code__c (EN16931 field) and prod-only Test_Exact fix (asserts Exact_Invoice_Address_ID__c) |
| 19:35–19:40 | Invoice address labels filled (touch) | 183,358 accounts |
| 19:58 | Status__c edit only via ps_miAccountStatus_Admin; Exact flow back **on** (v7) | migration set 0 sync flags → nothing to reset |
| 20:08 | Country_Code__c filled (NL×4, DE, GB) | Belgium/France (echoes)/Greece (G4S) billing address is Zaltbommel → NL |
| 20:11 | Invoice run (held from 19:16) | 351 invoices, all with the account invoice address; establishment box verified on PDF (I-2609-00756704) |
| 20:30 | `rau_Lead_Converted_Address_to_Acoount_Visiting` off in prod, acc, dev (repo: Obsolete) | standard lead mapping fills Billing |
| 20:54 | 556 accounts "identical except formatting": useInvoiceAddress unticked | invoice address = establishment |
| 21:01–21:10 | 312 near-identical addresses corrected to the BAG (PDOK) address + unticked (`scripts/bag_check.py`) | WSONE_DATA trigger hits CPU limit above ~5 records per transaction → small batches |

## Actions for tomorrow

1. **rbb_Account Exact sync rule** — `dec_01_FinancialSystemSync` uses `$Record.BillingAddress IsChanged`, which a flow does not detect for the compound address: Billing (= Exact main address) changes are never flagged. Replace by BillingStreet/PostalCode/City/StateCode/CountryCode IsChanged (dev → acc → prod), then decide whether to flag the 247 BAG-corrected accounts for an Exact sync.
2. **Delete retired fields in prod**: Active__c, Deactivated__c, IsBankrupt__c, Is_Blocked__c, Dealer_status__c (+ obsolete rbb_Account versions that reference them). Static resource `Platforms` (scan 2026-09-29: no references left in prod). The 3 old reports (user).
3. **Address clean-up** (lists on the Desktop, not in git): group 3 = 435 accounts where the house number differs (manual); 40 of group 2 without a clear BAG match; 7 accounts whose Visiting mirror differs only in capitals.
4. **Invoices**: confirm tonight's 351 invoices got their invoice number and PDF (Job_FinalizeInvoicesInExact runs hh:00/16/32/48).
5. **Data issues seen in the Exact log**: James Dyke duplicate FinancialIdAccount__c (with 001Tx00000zzpX8IAI); Reflex Insulation Group invalid VAT check digit / no bank account.
6. **Setup (manual)**: rename the standard Billing Address label to "Establishment / Billing Address".
7. Confirm Country_Code__c for Belgium / France (echoes) / Greece (G4S) (now NL).
8. First real lead conversion after go-live: check Billing/Visiting/Invoice.
9. Later: retire VisitingAddress__c and useBillingAddress__c; approval process for status changes (four-eyes); REBEL/Horizon regression (blocked by the rab-Contact bulk bug).
10. Send the key-user email (artifact "Account Go-Live Email").

## Lessons

- A field rename is only safe when no **active** flow references the field by name; switch the flow off, rename, deploy the new flow, activate.
- Prod deploys flows as Draft: plan an activation step for every flow in a package.
- Validate against acc with RunSpecifiedTests checks per-class coverage; prod RunLocalTests uses org-wide coverage.
- WSONE_DATA (WebServices One) trigger is CPU-heavy on address changes: bulk address updates in batches of ≤5.
