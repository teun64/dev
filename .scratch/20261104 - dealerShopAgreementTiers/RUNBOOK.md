# Dealer Shop: price agreement replaces pricebook tiers (prod)

**Rule (user, 2026-11-04):** an active Product_Discount__c replaces the pricebook volume tiers entirely; the pricebook From_Quantity/From_Price fields are then ignored.

**Bug in prod:** Fleetaccess B.V. (0011t00000G85UJAAZ), 800.001.0000.
- The discount a1fbR000000nxi5QAA has one tier: from 11, −8.571428572%.
- The pricebook entry has tiers 5/11/25.
- Result: tiers 11→160, 11→null, 25→null, so the cart showed N/A from quantity 11.

Commit 57d80b6.

## Components
- ApexClass `Ctrl_DealerShop`, `Test_Ctrl_DealerShop`
- LWC `dealerCart`

`prod-before/` holds prod's copies from before the deploy. The only drift from the pre-change repo is the trailing newline.

## Status
- dev: deployed, 75/75 tests, site republished.
- acc: deployed `0AfG500000TMuNpKAL` (75/75), site republished. Rolled-back test with the prod Fleetaccess discount:
  - qty 3 and 7 → 175
  - qty 11 and 25 → 160
  - tier list shows only "from 11".
- prod: **validated `0AfTx0000014k0UKAQ`** on 2026-11-04 (75/75 tests, Ctrl_DealerShop coverage 96%).

## Steps (prod)
1. Quick deploy (the user runs this, within 10 days of the validation):
   `sf project deploy quick --job-id 0AfTx0000014k0UKAQ -o prod`
2. Republish the site:
   `sf community publish -n "Dealer Portal" -o prod`
3. Check in prod: shop on Fleetaccess B.V., 800.001.0000:
   - qty 1–10 → €175
   - qty 11+ → €160
   - no N/A

## Impact on other prod data
Out of 4,094 active discounts, only one other record changes: a1fbR00000AJOvKQAX (De Romein, Green.01). Its 0% slot 2 has no quantity and is now skipped, so the price doesn't change.

## Rollback
Deploy `prod-before/unpackaged` with RunSpecifiedTests Test_Ctrl_DealerShop, then republish the site.
