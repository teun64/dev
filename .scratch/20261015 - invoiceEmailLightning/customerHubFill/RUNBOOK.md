# Customer Hub URL fill — acc / prod

**Why:** `Business_Entities__c.CustomerHub_URL__c` is a copy of `Subscription25__Administration__c.CustomerHub_URL__c`
(`Sync_Administration_to_Business_Entity` copies every mirrored field on each Administration save). The Administration
field was empty everywhere, so every Administration save blanked the Business Entity value (NL/UK/DE in acc + prod on
2026-10-14/15; BE/FR/GR only still have a value because their Administrations were not saved since 2026-09-29).
`Payment__c.Setup_URL__c` (the direct debit link in all DD templates and in the invoice email block) is built from the
Business Entity value, so an empty value = no link.

Nobody could see/fill the Administration fields: FLS is granted via `pg_Subscription25Admin`, yet the field stayed
invisible to the System Administrator user (describe/SOQL "No such column"); a direct grant on the System Administrator
profile fixed it in dev (2026-10-15). Root cause of the group grant not applying: unknown.

Values: dev `https://movingintelligence--dev.sandbox.my.site.com/hub` (done 2026-10-15) ·
acc `https://movingintelligence--acc.sandbox.my.site.com/hub` · prod `https://customer.movingintelligence.com`
(= what the 6 prod DD templates have hard-coded today, + `/payment?token=`).

## Steps (per org, acc first)
1. Grant FLS (profile deploy is additive):
   `sf project deploy start -o <org> --metadata-dir ".scratch/20261015 - invoiceEmailLightning/customerHubFill/profile" --wait 10`
2. Check: `sf data query -o <org> -q "SELECT Name, CustomerHub_URL__c FROM Subscription25__Administration__c"` works (no "No such column").
3. Fill: `sf apex run -o <org> -f ".scratch/20261015 - invoiceEmailLightning/customerHubFill/hubfill_<org>.apex"`
4. Verify the sync: `sf data query -o <org> -q "SELECT Name, CustomerHub_URL__c, LastModifiedDate FROM Business_Entities__c"` → all 6 filled.

Prod only on explicit go. Order vs the step-2 deploy: the fill can go first (Setup_URL__c is not used by the live prod
templates until the new templates are deployed); it must be done before the new DD templates go live, or links are empty.
