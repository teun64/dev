# acc rollout: Dealer Shop batch 2026-10-27 (runbook)

Status: **prepared and dry-run validated on acc on 2026-10-27 (36/36 components, 0 errors). NOT deployed.**
Waiting for: the user's test in dev, then the go for acc.

## What's in it
| Change | Commit |
|---|---|
| Favorites per user + account. Internal users also see the account's dealer favorites (read-only "Dealer favorite" badge). New field `Dealer_Product_Favorite__c.Account__c` | 9424a84 |
| Cart "Order options": customer reference (blank = order number) + different delivery address (earlier shop-order addresses, or a new one). Reorder keeps the address and clears the reference | d0e0e0c |
| `Account.Show_List_Prices__c`: list price (dealer pricebook price before discounts) shown above the prices | d0e0e0c |
| rp_Account / rp_Order / pg_miSales = **prod copy** + Hide/Show List Prices in the Account Webshop section | d18a2de, d8465d7 |

Already on acc (not in this package): product image visibility fix and `Ctrl_ProductImageManager` (c58fa70).

## acc before (checked 2026-10-27)
- Ctrl_DealerShop, Test_Ctrl_DealerShop and the 7 shop LWCs on acc are **identical** to the repo before this batch (ignoring trailing newlines). The deploy overwrites nothing that only exists on acc.
- rp_Account / rp_Order on acc = the old dev state. The prod copy **removes these buttons on acc** (same as in dev and prod):
  - Account: Send to Exact, Opportunity Standard, Opportunity Insurance.
  - Order: the old "Sync to Financial System" (admin-only).
- pg_miSales on acc doesn't have `ps_miLeadIntegrationUser` or `trailheadapp__Th_Badge_User`; the prod copy adds them (the dry run confirms both exist on acc).
- `ps_DealerShopHidePricesAdmin` **doesn't exist on acc**, so this package creates it (FLS on Hide_Prices__c and Show_List_Prices__c). It isn't assigned to anyone yet.
- `Dealer_Product_Favorite__c` has 0 records on acc, so no backfill is needed.

## Package
`mdapi/` (metadata format, 44 files), built from `src/`:
- Apex: Ctrl_DealerShop, Test_Ctrl_DealerShop.
- LWC: dealerShop, dealerCart, dealerCartStorage, dealerOrderDetail, dealerProductCard, dealerProductDetail, dealerProductGrid.
- Fields: Account.Show_List_Prices__c, Dealer_Product_Favorite__c.Account__c.
- Labels: **only the 14 new** DealerShop_* labels and their nl_NL/de/fr translations. acc's other labels stay untouched.
- FLS:
  - Admin profile: partial, only the 2 new fields.
  - miModifyAllData and ps_DealerProductFavoriteAdmin: **acc's own retrieved copy** + the new fields.
  - ps_DealerShopHidePricesAdmin: repo version (new on acc).
- FlexiPage rp_Account, rp_Order; PermissionSetGroup pg_miSales.

**Gotcha:** the `sf` CLI skips folders whose names start with a dot, like `.scratch`. Converting or deploying from inside `.scratch` gives an empty package ("not found in zipped directory" / "No local changes"). So always **copy to a folder without a dot in its path first**.

## Steps
1. Copy and deploy (NoTestRun; Test_Ctrl_DealerShop has 1 known failure, see step 3):
   ```
   rm -rf /tmp/dsacc && cp -R ".scratch/20261027 - dealerShopBatchAcc/mdapi" /tmp/dsacc
   sf project deploy start -o acc --metadata-dir /tmp/dsacc --test-level NoTestRun -w 30
   ```
2. Republish the site (enableApexCDNCaching): `sf community publish -n "Dealer Portal" -o acc`
3. Tests, run on their own:
   - `sf apex run test -o acc -n Test_Ctrl_DealerShop -w 20`. Expected: everything passes except `testPlaceOrder_internalUser_opportunityFollowsAccountCurrency_notRunningUserCurrency` (existing failure: "Payment method I8 is not allowed for reseller 6", unrelated).
   - `sf apex run test -o acc -n Test_Ctrl_ProductImageManager -w 20`.
4. Checks:
   - `pg_miSales` status = Updated.
   - Account page: the Webshop section shows Hide/Show List Prices.
   - As **mdevos@movingintelligence.nl.midealer.acc**: images, order options (reference + address), Show List Prices on the dealer account, reorder from order history.
   - Internal user via the Account "Dealer Shop" action: favorites per account + dealer-favorite badge.
5. Assign ps_DealerShopHidePricesAdmin to whoever needs to edit Hide/Show List Prices (user's decision).

## Rollback
Restore rp_Account / rp_Order / pg_miSales (and the permission sets) from `acc-before/` (acc's own copy, metadata format, retrieved 2026-10-27). Copy it to a folder without a dot in its path first (see the gotcha). Code: deploy the repo files from commit `9424a84^`. The new fields can stay.
