# acc rollout: portal access (Dealer Portal + Customer Hub) — 2026-10-26

Target model (verified in dev):
- **Profile:** `miCustomerCommunityPlus` is an empty base profile with no object or field access.
- **Access:** everything comes through permission sets and groups.
- **Site membership:** via the `_User` set, and that set must be assigned **directly**. Through a group it does not count; the login then fails with "No community access".
- **Contact buttons:** Enable/Disable Dealer Portal force the username `<email>.miDealer.acc` and the profile.

| Site | Logged-in | Guest | Group |
|---|---|---|---|
| Dealer Portal | ps_miDealerPortal_User | ps_miDealerPortal_Guest | pg_miDealerPortal |
| Customer Hub | ps_miCustomerHub_User | ps_miCustomerHub_Guest | pg_miCustomerHub |

## acc before (checked 2026-10-26, snapshot in `acc-before/`)
- **Profile:** `miCustomerCommunityPlus` does not exist. Customer Community Plus: 1 seat, 0 used. There are no portal users.
- **Site members** (Dealer Portal `0DBG50000004pLhOAI`, Customer Hub `0DBG50000004lI5OAI`): System Administrator only.
- **Old sets:**
  - `Authenticated_DealerPortal`: not assigned.
  - `ps_miCustomerHub`: Customer Hub guest + Teun.
  - `ps_miCustomerHub_Payment`: Customer Hub guest + Teun. Redundant: its 3 classes are a subset of `ps_miCustomerHub`.
- **Dealer Portal guest** (`dealer_portal@00dg500000aykwfmab.org.force.com`): no extra permission set.
- **No drift:** `rp_Contact` and `ps_miExperienceCloudCustomer_Admin` equal the repo state before the change.
- **Guest set:** acc's `ps_miCustomerHub` is identical to dev's `ps_miCustomerHub_Guest`, apart from the label.

## Dry run (2026-10-26)
Main package validated against acc with RunSpecifiedTests (Test_Svc_DealerUserSetup, Test_Inv_CustomerUser): Succeeded, 12/12 tests.

## Steps
1. **Main package** (RunSpecifiedTests, the 2 test classes):
   - Field: `Contact.Customer_User_Type__c`
   - Classes: `Svc_DealerUserSetup`, `Inv_CustomerUser` + tests
   - Flows: `scr_Contact_Enable/Disable_Customer_User`
   - Quick actions: `Contact.act_DealerPortal_Enable/Disable`
   - Page: `rp_Contact`
   - Profile: `miCustomerCommunityPlus`
   - Permission sets: `ps_miDealerPortal_User/_Guest`, `ps_miCustomerHub_User/_Guest`, `ps_miExperienceCloudCustomer_Admin`
   - Groups: `pg_miDealerPortal`, `pg_miCustomerHub`
2. **Field access:** deploy `acc-fls/` (`miModifyAllData` = acc copy + read on Customer_User_Type__c; Admin profile, partial).
3. **Profile check:** ObjectPermissions / FieldPermissions of `miCustomerCommunityPlus` must be 0. Delete them if the platform added defaults on create.
4. **Site members** (Data API, NetworkMemberGroup):
   - `ps_miDealerPortal_User` + `ps_miDealerPortal_Guest` → Dealer Portal
   - `ps_miCustomerHub_User` + `ps_miCustomerHub_Guest` → Customer Hub
   - The guest sets are added only to stay equal to dev.
5. **Guests, new first, then old:**
   - Assign `ps_miDealerPortal_Guest` → dealer_portal guest, and `ps_miCustomerHub_Guest` → customer_hub guest.
   - Then remove the `ps_miCustomerHub` and `ps_miCustomerHub_Payment` assignments (guest + Teun).
6. **Delete old sets:** `Authenticated_DealerPortal`, `ps_miCustomerHub`, `ps_miCustomerHub_Payment`. None of them is a site member in acc, so no Setup UI step is needed.
7. **Test data** (our own, never a real customer):
   - B2B account "MI Tech Test Dealer acc", Relation type Dealer, owner Teun (role miGroup).
   - Contact with a test email address of the user's choice.
8. **Tests:**
   - The buttons are visible only on that contact (not on an End User contact).
   - **Enable:** new user `<email>.midealer.acc`, profile miCustomerCommunityPlus, pg_miDealerPortal + ps_miDealerPortal_User, welcome email.
   - Log in to the Dealer Portal, then Place order.
   - **Disable:** the login fails. **Enable again:** the same user comes back.
   - Customer Hub without login: one payment link + one preference link.
   - Optional: the buttons as a non-admin holder of ps_miExperienceCloudCustomer_Admin.

## Rollback
- Old sets: redeploy from `acc-before/` and reassign them (guest: `ps_miCustomerHub` + `_Payment`).
- `rp_Contact`: redeploy from `acc-before/`.
- New components: destructive deploy.
