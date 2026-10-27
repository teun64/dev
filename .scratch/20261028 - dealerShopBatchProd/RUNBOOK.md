# prod rollout: Dealer Shop batch (runbook for 2026-10-28)

Status: **PREPARED, not deployed.** Needs the user's explicit go on the day. Same batch as on acc (`../20261027 - dealerShopBatchAcc/RUNBOOK.md`), with prod's own copies for the permission sets.

## What's in it
- Favorites per user + account. New field `Dealer_Product_Favorite__c.Account__c`.
- Cart "Order options": order reference and a different delivery address.
- `Account.Show_List_Prices__c`, including the empty line when the list price equals the unit price.
- Grid/layout fixes.
- rp_Account / rp_Order / pg_miSales with Hide/Show List Prices in the Account Webshop section.
- New permission set `ps_DealerShopHidePricesAdmin`, to be assigned to **Guy Mooyman** and **Jonas Maassen** (user's request 2026-10-27).

Commits: 9424a84, d0e0e0c, d18a2de, d8465d7, 6668f81, f276d81. Already in prod: the image visibility fix and `Ctrl_ProductImageManager` (c58fa70).

## prod before (checked 2026-10-27)
- Ctrl_DealerShop, Test_Ctrl_DealerShop and the 7 shop LWCs in prod are **identical** to the repo before this batch (`9424a84^`), apart from trailing newlines. Nothing prod-only gets overwritten.
- rp_Account, rp_Order and pg_miSales in prod are **identical** to the repo (d8465d7) minus our 2 fields. So unlike acc, no buttons disappear in prod.
- `ps_DealerShopHidePricesAdmin` **doesn't exist in prod**, so the package creates it. `Hide_Prices__c` already exists in prod.
- `Show_List_Prices__c` and `Dealer_Product_Favorite__c.Account__c` don't exist yet.
- **`Dealer_Product_Favorite__c` has 10 records in prod, all without an account.** The new code filters on `Account__c`, so without a backfill these favorites disappear from the shop (see step 4).
  - The admin CLI user has no FLS on `User__c`, so the records couldn't be read yet (even anonymous Apex fails to compile).
- `prod-before/` is prod's own copy (metadata format, retrieved 2026-10-27) for rollback.

## Package
`mdapi/` = the acc package (36 components), except:
- `miModifyAllData` and `ps_DealerProductFavoriteAdmin` are **prod's own copies** plus only the new field permissions.
  - A permission set deploy replaces the whole set, so never use acc's or the repo's copy.
- The Admin profile is partial (only the 2 new fields). The labels and translations contain only the 14 new entries.

**Gotcha:** the `sf` CLI skips folders whose names start with a dot, like `.scratch`. Always copy to a folder without a dot in its path first.

## Steps
0. **Check prod is unchanged** since `prod-before/`: retrieve the same manifest and diff it. If anything differs, stop and rebuild.

1. **Validate** (check-only, prod requires tests):
   ```
   rm -rf /tmp/dsprod && cp -R ".scratch/20261028 - dealerShopBatchProd/mdapi" /tmp/dsprod
   sf project deploy validate -o prod --metadata-dir /tmp/dsprod --test-level RunSpecifiedTests --tests Test_Ctrl_DealerShop --tests Test_Ctrl_ProductImageManager -w 60
   ```
   - ⚠ `testPlaceOrder_internalUser_opportunityFollowsAccountCurrency_notRunningUserCurrency` fails on dev and acc ("Payment method I8 is not allowed for reseller 6"). If it also fails in prod, the validation fails.
     - Then the test fixture needs fixing first, e.g. a payment method that is allowed for the reseller. That's the user's decision.
     - Fix it in dev and acc too.
   - Check coverage of Ctrl_DealerShop is ≥ 75%.

2. **Deploy** (after the user's go): use quick deploy with the validation id (`sf project deploy quick -o prod --job-id <id>`), or the same command as step 1 with `start`.

3. **Republish the site** (enableApexCDNCaching): `sf community publish -n "Dealer Portal" -o prod`

4. **Favorites backfill** (10 records):
   - Give the deploying admin read access on `User__c`, for example a temporary `ps_DealerProductFavoriteAdmin` assignment. Remove it afterwards.
   - List the records: `Id, User__r.Name, User__r.UserType, User__r.Contact.AccountId`.
   - **Portal users** (`UserType` PowerPartner etc.): set `Account__c = User__r.Contact.AccountId`.
   - **Internal users**: the account can't be derived. Show the list to the user and let them decide: delete, or pick an account.
   - Before the update, save a CSV backup in this folder.

5. **Permission set assignment**:
   - Assign `ps_DealerShopHidePricesAdmin` to Guy Mooyman (`0051t000003C97tAAC`, gmooyman@movingintelligence.nl) and Jonas Maassen (`0051t0000011zHZAAY`, jmaassen@movingintelligence.nl). Both are active miSales users.
     ```
     sf org assign permset -o prod -n ps_DealerShopHidePricesAdmin --on-behalf-of gmooyman@movingintelligence.nl --on-behalf-of jmaassen@movingintelligence.nl
     ```
   - In acc and dev both users are **inactive**, so they're not assigned there (the user asked for prod at least).

6. **Checks** (read-only; no test orders in prod):
   - `pg_miSales` status is Updated.
   - FLS on both new fields: Admin, miModifyAllData and the ps_* sets.
   - The Account page Webshop section shows Hide/Show List Prices. Guy and Jonas can edit them.
   - As a dealer user, run a read-only probe in the style of the acc probe (`@IsTest(SeeAllData=true)` + `System.runAs`; deploy and delete it, or run it as a validate-only test):
     - Products with images.
     - `getOrderOptions` returns a default address and the countries.
     - Labels are correct.
   - No `placeOrder` in prod.

7. Update this runbook, the memory file `project_dealer_shop_favorites_per_account.md` and the MEMORY.md line.

## Rollback
Deploy `prod-before/` (copy it to a folder without a dot in its path first). This restores the code, LWCs, pages, pg_miSales, miModifyAllData and ps_DealerProductFavoriteAdmin.
- `ps_DealerShopHidePricesAdmin` and the new fields can stay.
- Republish the site afterwards.
