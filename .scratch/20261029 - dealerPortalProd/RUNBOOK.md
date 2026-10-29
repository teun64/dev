# Dealer Portal prod deploy — 2026-10-29

**DONE 2026-10-29:** deployed 0AfTx0000014KFhKAM, site republished (home_view verified), rbc_Opportunity v34 + rbu_Opportunity v31 active (verified), docs updated.

One deploy for everything built on 2026-10-29 (commits 39b2d33 + ecc95f4):

- Order history / order detail / menu translatable (DealerOrder_*, DealerNav_*), order status + currency
- Server-side order pricing with volume tiers (price bug), product detail stores the base price
- Home page cards + "Become a dealer" form translatable (DealerHome_*)
- Signer: rbc/rbu_Opportunity fill an empty Sales_Contact__c with the account's Main role contact
- Contact person choice in the cart's order options (DealerShop_ContactPerson)

Package: `deploy/` (4 classes, 8 LWCs, 2 flows, 59 labels + nl_NL/de/fr subsets; translation
subsets merge, they don't replace). Prod's rbc/rbu were identical to the repo before this change.

Validated in prod: **0AfTx0000014KArKAM** (84/84 tests, 77 components), 2026-10-29. Valid 10 days.
Supersedes the earlier validation 0AfTx0000014JMrKAM (order labels + pricing only) — don't use that one.

## Steps

1. Quick deploy (user runs it; the auto-mode classifier blocks prod deploys from Claude):
   `sf project deploy quick --job-id 0AfTx0000014KArKAM -o prod -w 30`
2. Republish the site: `sf community publish -n "Dealer Portal" -o prod`
3. Activate the two flows — prod deploys flows as Draft. Find the new version numbers:
   `sf data query -o prod --use-tooling-api -q "SELECT Id, DeveloperName, ActiveVersion.VersionNumber, LatestVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName IN ('rbc_Opportunity','rbu_Opportunity')"`
   then per flow:
   `sf data update record -o prod --use-tooling-api -s FlowDefinition -i <Id> -v "Metadata='{\"activeVersionNumber\":<LatestVersion>}'"`
4. Verify (read-only):
   - Labels: `Ctrl_DealerPortal.getHomeText` / `getPortalLabels` for nl_NL, de, fr, en → no `_NOT_FOUND`.
   - Site bundle: `home_view` contains `DealerHome_BecomeDealer`.
   - Flows: rbc_Opportunity / rbu_Opportunity active version = the new one.
   - No test orders in prod (standing rule); the first real dealer order shows the contact person
     choice and fills Sales_Contact__c.
5. Docs: Dealer Guide (order pages no longer Dutch-only, contact person choice), key-user doc,
   developer doc deployment row → prod.
