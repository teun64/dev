# Contractor_Service__c phase-out (2026-10-13, user decision)

- dev: delete object `Contractor_Service__c` + lookup `Subscription25__Contract_Product__c.Contractor_Service__c` (copied from prod earlier the same day).
- acc + prod: delete only the lookup field `Subscription25__Contract_Product__c.Contractor_Service__c`; the object itself stays for now.
- Dependencies 2026-10-13: prod = 2 layouts only (cleaned automatically). acc = 2 layouts + obsolete (inactive) flows
  `rac_Contract_Product_Create_Contractor_Service` (301AO0000000psOYAQ) and `rau_Contract_Product_Maintain_Contractor_Service`
  (301AO0000000psPYAQ) -> delete those first. acc `rbb_Contractor_Service` (active, on the object) does not reference the field.
- Backup of the prod values: `prod_contract_product_contractor_service.csv` (57,647 rows: Contract Product Id, Name, Contractor Service Id).
  A deleted field stays restorable for 15 days (Setup > Object Manager > Contract Product > Deleted Fields).
- Repo: object folder + field removed, all permission-set entries for the object and the field removed (11 permission sets).
- Destructive packages: session scratchpad `csdel/field` (acc, prod) and `csdel/dev` (dev). Run by the user (auto mode blocks deletes).

## Result 2026-10-13
- acc: obsolete flows 301AO0000000psOYAQ / 301AO0000000psPYAQ deleted (Tooling); field deleted (deploy 0AfG500000SyxOVKAZ).
- prod: field deleted (deploy 0AfTx00000139XdKAI). In Deleted Fields for 15 days (restorable), backup CSV here.
- dev: field deleted + erased by the user in Setup, object deleted (deploy 0Afbd00000BeEdpCAF). Done.

## Completed 2026-10-13 (all orgs)

- acc: flow rbb_Contractor_Service (v1, active) deactivated + deleted; related list Contractor_Services_Entity__r removed
  from rp_Case_Default_AS (acc-only); Case.Subscription__c + Contract_Product.Contractor_Service__c erased by the user;
  object deleted (0AfG500000SzMl3KAF).
- prod: backup of all 57,725 Contractor_Service__c records -> prod_contractor_service_all.csv (local, not in git).
  Case.Subscription__c (47 values, lookup to the object) was deleted/erased by the user in Setup before a backup was made.
  Related list removed from rp_Case_Default, quick action Contractor_Service__c.act_Update + object deleted
  (0AfTx0000013B9dKAE). Restorable from Setup > Deleted Objects for 15 days.
- Subscription25__Contract_Product__c.Do_Contractor_Service__c (formula: reseller 1/2/4 + subscription product):
  no flows, Apex, formulas, workflow, list views or (1,674 public) reports used it, only the Contract Product layout.
  Removed from the layout and deleted in dev (0Afbd00000BePm9CAF), acc (0AfG500000Sz8WpKAJ), prod (0AfTx0000013BCrKAM).
  Note: ~170 reports in private folders could not be checked.
