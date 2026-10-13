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
