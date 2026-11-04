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
- prod: validated `0AfTx0000014k0UKAQ` (75/75 tests, 96% coverage). **Quick deployed `0AfTx0000014kq5KAA` on 2026-11-04 (the user ran it).** Read-only check for Fleetaccess B.V. on 800.001.0000: unitPrice 175, tiers only from 11 at 160. The site republish is still ON HOLD.

## Steps (prod)
1. Quick deploy (the user runs this, within 10 days of the validation):
   `sf project deploy quick --job-id 0AfTx0000014k0UKAQ -o prod`
2. **ON HOLD:** republish the site:
   `sf community publish -n "Dealer Portal" -o prod`
   - Hold until Salesforce confirms FRA56 is fixed. Trust incident 20004559 / Known Issue a02g700000DKcPp: LWR sites on 264.10 render rich text and HTML blocks without styling after a publish. The impact on FRA56 started 2026-10-27 19:00 UTC.
   - The quick deploy (step 1) can go ahead without the publish. The price fix is Apex, so N/A and tier pricing are fixed server-side. Only the `dealerCart` safety guard waits for the publish.
   - To check whether FRA56 is fixed: `curl -s https://api.status.salesforce.com/v1/instances/FRA56/status`. Incident 20004559 should have an `endTime`.
3. Check in prod: shop on Fleetaccess B.V., 800.001.0000:
   - qty 1–10 → €175
   - qty 11+ → €160
   - no N/A

## Impact on other prod data
Out of 4,094 active discounts, only one other record changes: a1fbR00000AJOvKQAX (De Romein, Green.01). Its 0% slot 2 has no quantity and is now skipped, so the price doesn't change.

## Rollback
Deploy `prod-before/unpackaged` with RunSpecifiedTests Test_Ctrl_DealerShop, then republish the site.
