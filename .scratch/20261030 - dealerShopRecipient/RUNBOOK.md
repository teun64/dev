# Dealer Shop delivery recipient + Process Order feedback (2026-10-30)

Dev commits 714cc65, dd765b1, eb73dda, e2fed52.

- Opportunity.ShippingCompany__c / ShippingAttention__c (Text 80), from the cart order options (different delivery address only).
- Order confirmation: company bold (blank = Account.Name), attention below it.
- Process Order button: closes synchronously and shows a refusal at once. Order_Process_Error__c read-only on the Opportunity-Webshop layout.
- FLS: Admin profile + miModifyAllData (also Account.Hide_Prices__c edit), ps_miOportunityManagement edit, ps_miDealerShopInternal read.

Before the deploy, acc and prod code matched the repo at f0616eb (checked 2026-10-30).

Each package was built from that org's own layout + permission sets plus the new lines only: `acc/`, `prod/`.

| Org | Deploy | Tests | Site |
|---|---|---|---|
| acc | 0AfG500000TIA6fKAH | 82/82 | Dealer Portal republished |
| prod | validated 0AfTx0000014QubKAE → quick deploy 0AfTx0000014QwDKAU (23/23) | 82/82 | Dealer Portal republished |
