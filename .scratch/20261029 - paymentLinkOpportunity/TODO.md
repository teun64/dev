# Payment link / Opportunity project: to-do (started 2026-10-29, separate from the pi/pr project)

## ps_1_pi (NL, method pi)
- Today: `Payment_Setting.ps_1_pi` (reseller 1 NL, method pi) has AutoCreate **true**, Processor **Stripe**, invoice text "Gelieve het factuurbedrag voor {0} te voldoen via de betaallink in de factuurmail." When an NL invoice with pi is finalized, a Stripe one-off payment (psp-immediate) + payment link is created automatically.
- UK pi (ps_6_pi) was rerouted on 2026-10-28 to the p1 webshop route (AutoCreate false, Opayo, "already paid" text).
- Prod usage 2026-10-29: **0** NL accounts / opportunities / invoices on pi; NL Business Entity PayProv_Use__c = false (Stripe not live for NL) → the path does nothing today, but breaks as soon as someone picks pi in NL.
- To decide in this project: (a) leave it until NL goes live on Stripe; (b) align with UK → NL webshop route (p0 / Mollie: AutoCreate false or Processor Mollie, "already paid" text); (c) block pi for NL via Payment_Method_Rule__mdt (Allowed_Resellers__c).
- Related: the payment link on the invoice / Opportunity (one-off payments), Opportunity payment method lock (live 2026-10-29: vr_PaymentMethodOpportunityLock + vr_PaymentMethodOpportunitiesLock, ps_miOpportunityPaymentMethod_Change).
