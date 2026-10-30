# Order confirmation fix + optional send (2026-10-30)

Root cause: Util_OrderConfirmation (API 68, user mode) -> EventBus.publish denied for users without Create on
Order_Process__e -> no prod confirmation was ever sent automatically. Fix: Util_OrderProcessPublisher (API 66.0).
New: Business_Entities__c.DealerPortal/CustomerHub_Opportunity_SendConfirm__c (default off).

dev + acc deployed (acc 0AfG500000THmcEKAT, 7/7), commit 077b973. Only Netherlands ticked in dev + acc.

## Prod (the user runs these)
Package `deploy-prod/` = prod's own layout + ps_BusinessEntitiesAdmin/ReadOnly (retrieved 2026-10-30) + fix.
Validated: **0AfTx0000014PAXKA2** (7/7).
1. `sf project deploy quick --job-id 0AfTx0000014PAXKA2 -o prod -w 30`
2. Business Entity: tick **Send Order Confirmation (Dealer Portal)** where confirmations should go (all off after deploy).
3. Check: next Webshop order to Closed Won gets Order Confirmation Sent (only if ticked).

Done 2026-10-30: the 4 unsent prod orders (2026-00077889/904/905/907) marked Order_Confirmation_Sent__c, not sent.

**LIVE prod 2026-10-30:** 0AfTx0000014PIbKAM. Publisher on API 66 verified; all Send Order Confirmation flags off.
Help texts (independent settings) LIVE prod 0AfTx0000014PYjKAM.
