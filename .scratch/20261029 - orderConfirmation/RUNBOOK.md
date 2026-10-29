# Prod: Dealer Shop permissions + Webshop order confirmation (2026-10-29)

One package (`deploy-prod/`), validated in prod: **0AfTx0000014MarKAE** (87/87 tests, 44 components).
Contains pg_miDealerShop (ps_miDealerShopProducts + ps_miDealerShopAccounts), the image-replace fix, and the
order confirmation (Util_OrderConfirmation, Order_Process__e + trigger, template, fields, button, rp_Opportunity,
labels nl/de/fr, FLS: Admin profile + prod's own miModifyAllData + ps_miDealerShopInternal).
Live in dev + acc 2026-10-29 (acc 0AfG500000TGcbiKAD, 78/78; preview rendered on acc order 2026-00054562).

## Steps (the user runs prod commands)
1. Deploy: `sf project deploy quick --job-id 0AfTx0000014MarKAE -o prod -w 30`
2. Activate the button flow (prod deploys flows inactive):
   `sf data query -o prod --use-tooling-api -q "SELECT Id, LatestVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName = 'scr_Opportunity_Process_Order'"`
   then `sf data update record -o prod --use-tooling-api -s FlowDefinition -i <Id> -v "Metadata='{\"activeVersionNumber\":<n>}'"`
3. Permissions Guy + Jonas: assign pg_miDealerShop, remove ps_DealerShopHidePricesAdmin (Claude gives the exact
   commands with the ids after step 1), later delete ps_DealerShopHidePricesAdmin (destructive deploy).
4. Shipping Business Hours: `./prod_business_hours.sh`, then `sf apex run -f prod_business_entities.apex -o prod`
   (NL/BE/FR/DE = Office (NL), UK = Office (UK), GR = Office (GR), cut-off 15:00).
5. Setup (UI, user): Business Hours > Office (NL) > Holidays: add the NL holidays; create the UK bank holidays and
   add them to Office (UK). Without holidays only Saturday/Sunday are non-working days.
6. Setup (UI, user): Organization-Wide Addresses: add + verify the Email (Sales) addresses (sales@movingintelligence.nl,
   .be, .fr, info@movingintelligence.de, info@movingintelligence.co.uk) with **Allow All Profiles**. Until then the
   sender is the Administration billing email if verified + all profiles (today only aftersales@movingintelligence.nl),
   else do-not-reply@movingintelligence.com; Reply-To is always Email (Sales).
7. Optional, per business entity: tick **Auto-Process Orders (Dealer Portal)** to close shop orders automatically.
8. Check (no test data in prod): the first real Webshop order that goes to Closed Won gets Order Processed At,
   Order Shipping Date and Order Confirmation Sent; problems show in Order Process Error.
