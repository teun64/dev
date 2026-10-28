# prod rollout: Dealer Shop batch (runbook for 2026-10-28)

Status: **LIVE prod 2026-10-28** (quick deploy `0AfTx0000014Hw9KAE`, steps 0–6 done). Originally: PREPARED. Needs the user's explicit go on the day. Same batch as on acc (`../20261027 - dealerShopBatchAcc/RUNBOOK.md`), with prod's own copies for the permission sets.

## What's in it
- Favorites per user + account. New field `Dealer_Product_Favorite__c.Account__c`.
- Cart "Order options": order reference and a different delivery address.
- `Account.Show_List_Prices__c`, including the empty line when the list price equals the unit price.
- Grid/layout fixes.
- rp_Account / rp_Order / pg_miSales with Hide/Show List Prices in the Account Webshop section.
- New permission set `ps_DealerShopHidePricesAdmin`, to be assigned to **Guy Mooyman** and **Jonas Maassen** (user's request 2026-10-27).
- **Dealer Portal emails (added 2026-10-28, user's request; ✅ already LIVE prod 2026-10-28 via a separate deploy `0AfTx0000014H3JKAU`, so redeploying them in this package changes nothing):** `DealerPortal_PasswordReset`, `DealerPortal_Welcome` and the shared VF component `emailLetterheadPreferences`.
  - Changes: Arial inline on every text element, and an extra blank line under the button (marketing's comments).
  - prod == git HEAD for these 3 files (whitespace only), so nothing prod-only gets overwritten. prod's copies are in `prod-before/`.
  - Header: the user chose `miemailheader` (red ›) as the standard on 2026-10-28. The component already uses it, so `mdapi/` stays as it is. The other templates follow `../20261028 - emailTemplatesArial/RUNBOOK.md`.

Commits: 9424a84, d0e0e0c, d18a2de, d8465d7, 6668f81, f276d81. Already in prod: the image visibility fix and `Ctrl_ProductImageManager` (c58fa70).

## dev vs acc (checked 2026-10-28)
Equal: Ctrl_DealerShop + test, Ctrl_ProductImageManager, the 7 shop LWCs, rp_Account/rp_Order, the 3 fields, the DealerShop/DealerPortal labels, both ps and the Dealer Portal emails.
- The only difference is the Sub25 package `minorNumber` in 2 `-meta.xml` files (known drift).
- acc **still had the 27-10 Dealer Portal emails**: they had never been deployed to acc. The earlier "acc" deploy `0Afbd00000Bpp0XCAR` was in fact a dev deploy (DeployRequest exists in dev, not acc). Deployed to acc as `0AfG500000TFQvxKAH` and verified by retrieve.

## prod before (checked 2026-10-27)
- Ctrl_DealerShop, Test_Ctrl_DealerShop and the 7 shop LWCs in prod are **identical** to the repo before this batch (`9424a84^`), apart from trailing newlines. Nothing prod-only gets overwritten.
- rp_Account, rp_Order and pg_miSales in prod are **identical** to the repo (d8465d7) minus our 2 fields. So unlike acc, no buttons disappear in prod.
- `ps_DealerShopHidePricesAdmin` **doesn't exist in prod**, so the package creates it. `Hide_Prices__c` already exists in prod.
- `Show_List_Prices__c` and `Dealer_Product_Favorite__c.Account__c` don't exist yet.
- **`Dealer_Product_Favorite__c` has 10 records in prod, all without an account.** The new code filters on `Account__c`, so without a backfill these favorites disappear from the shop (see step 4).
  - The admin CLI user has no FLS on `User__c`, so the records couldn't be read yet (even anonymous Apex fails to compile).
- `prod-before/` is prod's own copy (metadata format, retrieved 2026-10-27) for rollback.

## Package
`mdapi/` = the acc package (36 components) plus the 3 Dealer Portal email files (39), except:
- `miModifyAllData` and `ps_DealerProductFavoriteAdmin` are **prod's own copies** plus only the new field permissions.
  - A permission set deploy replaces the whole set, so never use acc's or the repo's copy.
- The Admin profile is partial (only the 2 new fields). The labels and translations contain only the 14 new entries.

**Gotcha:** the `sf` CLI skips folders whose names start with a dot, like `.scratch`. Always copy to a folder without a dot in its path first.

## Steps
0. **Check prod is unchanged** since `prod-before/`: retrieve the same manifest and diff it. If anything differs, stop and rebuild.
   - ✅ **Done 2026-10-28 07:2x UTC: no drift.** All files in the manifest are identical.
     - `Show_List_Prices__c` doesn't exist yet. `Hide_Prices__c` exists.
     - `ps_DealerShopHidePricesAdmin` doesn't exist yet.
     - `Dealer_Product_Favorite__c` still has 10 records.

1. **Validate** (check-only, prod requires tests):
   ```
   rm -rf /tmp/dsprod && cp -R ".scratch/20261028 - dealerShopBatchProd/mdapi" /tmp/dsprod
   sf project deploy validate -o prod --metadata-dir /tmp/dsprod --test-level RunSpecifiedTests --tests Test_Ctrl_DealerShop --tests Test_Ctrl_ProductImageManager -w 60
   ```
   - ⚠ `testPlaceOrder_internalUser_opportunityFollowsAccountCurrency_notRunningUserCurrency` fails on dev and acc ("Payment method I8 is not allowed for reseller 6"). If it also fails in prod, the validation fails.
     - Then the test fixture needs fixing first, e.g. a payment method that is allowed for the reseller. That's the user's decision.
     - Fix it in dev and acc too.
   - Check coverage of Ctrl_DealerShop is ≥ 75%.
   - ❌ **Run 2026-10-28 (user's go): validation `0AfTx0000014H6XKAU` FAILED. Check-only, nothing deployed.**
     - 39/39 components OK, 73 tests, 1 failure.
     - The failure is the known `testPlaceOrder_internalUser_opportunityFollowsAccountCurrency_notRunningUserCurrency`: the test account update to GB/GBP gets `FIELD_CUSTOM_VALIDATION_EXCEPTION, Payment method I8 is not allowed for reseller 6. [Payment_Method_Contracts__c]`.
     - ✅ Fixed 2026-10-28 (user's go). The test account update now also sets `Payment_Method_Contracts__c` and `Payment_Method_Opportunities__c` to `I0`.
       - `Util_PaymentMethodRule` checks both fields. I0 is allowed for reseller 6, and the rules are the same in prod.
       - Deployed to dev (`0Afbd00000BqhFRCAZ`) and acc (`0AfG500000TFMdrKAH`). Both orgs: 76/76 pass, Ctrl_DealerShop 92%, Ctrl_ProductImageManager 100%.
       - `mdapi/classes/Test_Ctrl_DealerShop.cls` is replaced with the fixed version (the old copy == HEAD). Re-validate in prod with the step 1 command.
   - ✅ **Re-validation 2026-10-28 (user's go): `0AfTx0000014H9lKAE` SUCCEEDED** (check-only, completed 17:31:51 UTC).
     - 39/39 components, 74/74 tests, 0 errors. Ctrl_DealerShop coverage 91.7%, no coverage warnings.
     - Fix commit: 2b3f25d.
     - The CLI wait failed with `fetch failed` (network); the status comes from prod's DeployRequest.
     - **Step 2 can use quick deploy** (needs the user's go): `sf project deploy quick -o prod --job-id 0AfTx0000014H9lKAE`. A validation stays usable for quick deploy for 10 days, unless something else is deployed to prod in between.

2. **Deploy** (after the user's go): use quick deploy with the validation id (`sf project deploy quick -o prod --job-id <id>`), or the same command as step 1 with `start`.
   - ✅ **Done 2026-10-28 18:18 UTC** (user's go): quick deploy `0AfTx0000014Hw9KAE` from validation `0AfTx0000014H9lKAE`.
     - 39/39 components, 0 errors.
     - Checked in prod: DeployRequest Succeeded (not check-only), both new fields exist, `ps_DealerShopHidePricesAdmin` exists, `pg_miSales` status Updated.
   - ⚠ Until step 4 is done, the 10 prod favorites without `Account__c` don't show in the shop.

3. **Republish the site** (enableApexCDNCaching): `sf community publish -n "Dealer Portal" -o prod`
   - ✅ Done 2026-10-28 (job `08PTx00000dWbXUMA0`). Salesforce mail "Site Published Successfully" arrived 18:21:37 UTC.
   - The shop bundle sits behind the login, so it wasn't checked via curl.

4. **Favorites backfill** (10 records):
   - Give the deploying admin read access on `User__c`, for example a temporary `ps_DealerProductFavoriteAdmin` assignment. Remove it afterwards.
   - List the records: `Id, User__r.Name, User__r.UserType, User__r.Contact.AccountId`.
   - **Portal users** (`UserType` PowerPartner etc.): set `Account__c = User__r.Contact.AccountId`.
   - **Internal users**: the account can't be derived. Show the list to the user and let them decide: delete, or pick an account.
   - Before the update, save a CSV backup in this folder.
   - ⏳ 2026-10-28: **all 10 belong to internal users**: Guy Mooyman (7) and Jonas Maassen (3). None are from portal users, so nothing is filled automatically.
     - Backup: `favorites_prod_backup_20261028.csv`.
     - The user decides per user: delete, or a fixed account.
     - The temporary `ps_DealerProductFavoriteAdmin` assignment (admin) is already removed again (`0PaTx00000T1thhKAB`).
   - ✅ User's decision 2026-10-28: **deleted**, all 10 (count now 0). Restore from `favorites_prod_backup_20261028.csv` if needed.

5. **Permission set assignment**:
   - Assign `ps_DealerShopHidePricesAdmin` to Guy Mooyman (`0051t000003C97tAAC`, gmooyman@movingintelligence.nl) and Jonas Maassen (`0051t0000011zHZAAY`, jmaassen@movingintelligence.nl). Both are active miSales users.
     ```
     sf org assign permset -o prod -n ps_DealerShopHidePricesAdmin --on-behalf-of gmooyman@movingintelligence.nl --on-behalf-of jmaassen@movingintelligence.nl
     ```
   - In acc and dev both users are **inactive**, so they're not assigned there (the user asked for prod at least).
   - ✅ Done 2026-10-28: both are assigned, both users are active.

6. **Checks** (read-only; no test orders in prod):
   - `pg_miSales` status is Updated.
   - FLS on both new fields: Admin, miModifyAllData and the ps_* sets.
   - The Account page Webshop section shows Hide/Show List Prices. Guy and Jonas can edit them.
   - As a dealer user, run a read-only probe in the style of the acc probe (`@IsTest(SeeAllData=true)` + `System.runAs`; deploy and delete it, or run it as a validate-only test):
     - Products with images.
     - `getOrderOptions` returns a default address and the countries.
     - Labels are correct.
   - No `placeOrder` in prod.
   - Dealer Portal emails, read-only: retrieve both templates and the component and diff them against `mdapi/`. Optionally render one with `Messaging.renderStoredEmailTemplate` in anonymous Apex, **without sending**.

   - ✅ **Done 2026-10-28:**
     - pg_miSales Updated.
     - FLS: `Show_List_Prices__c` edit for System Administrator, miModifyAllData and ps_DealerShopHidePricesAdmin; `Favorite.Account__c` edit for Admin, miModifyAllData and ps_DealerProductFavoriteAdmin.
       - Dealers need no FLS: Ctrl_DealerShop reads the Account `WITH SYSTEM_MODE`.
     - rp_Account has Hide/Show List Prices (in the deployed package).
     - **prod has no active portal users at all** (0 PowerPartner). So the probe ran as Guy Mooyman (internal path), via a check-only validation of the temporary `Probe_DealerShopProd` (`0AfTx0000014IFVKA2`). It fails on purpose to carry the output; the class is not in prod.
       - Van Mossel (NL): 69 products, 65 with an image, default address Tilburg NL, 240 countries.
       - DG Motorhomes (UK): 7/7 products with an image, Chatteris GB.
       - Labels nl/en/de/fr: 59 each, translated (Bestelopties / Order options / Bestelloptionen / Options de commande).
     - No placeOrder.
7. Update this runbook, the memory file `project_dealer_shop_favorites_per_account.md` and the MEMORY.md line.

## Rollback
Deploy `prod-before/` (copy it to a folder without a dot in its path first). This restores the code, LWCs, pages, pg_miSales, miModifyAllData, ps_DealerProductFavoriteAdmin and the 2 Dealer Portal templates plus `emailLetterheadPreferences`.
- `ps_DealerShopHidePricesAdmin` and the new fields can stay.
- Republish the site afterwards.
