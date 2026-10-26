# Prod rollout: portal access, Dealer Portal login & emails — runbook

Status: **NOT executed.** Prod deploy only after the user's explicit go.
Everything below was built in dev, tested, and rolled out and tested in acc on 2026-10-26.
For acc see `../20261026 - acc portal access rollout/RUNBOOK.md`.

## Target model
- **Profile:** `miCustomerCommunityPlus` (Customer Community Plus) is an empty base profile with no object or field access. It has its own password policy: the prod org policy without the 1-day minimum lifetime, minimum length 8.
- **Access:** all through permission sets and groups.
- **Site membership:** via the `_User` set, which must be assigned **directly**; through a group, the login fails with "No community access".

| Site | Logged-in users | Guest | Group |
|---|---|---|---|
| Dealer Portal | ps_miDealerPortal_User | ps_miDealerPortal_Guest | pg_miDealerPortal |
| Customer Hub | ps_miCustomerHub_User | ps_miCustomerHub_Guest | pg_miCustomerHub |

**Contact buttons** `act_DealerPortal_Enable/Disable` (Enable/Disable Dealer Portal):
- Visibility: sysadmin or `cp_miExperienceCloudCustomer_Admin`.
- Enable shows when `Customer_User_Type__c` = Dealer Portal (B2B + Dealer/Distributor) and `Customer_User_Active__c` = false. Disable shows when `Customer_User_Active__c` = true.
- Username `<email without +tag>.miDealer`, language from Contact.Language__c → Account.Sales_Language__c → nl.

**Login:** Dealer Portal login / forgot password with the email address; every failure gives the same generic message with the administration's email.

**Emails:** own VF templates `unfiled$public/DealerPortal_Welcome` / `DealerPortal_PasswordReset`, in the recipient's language. Sender Moving Intelligence <info@movingintelligence.com>.

## Prod before (checked 2026-10-27, snapshot in `prod-before/`)
- **Profile:** `miCustomerCommunityPlus` doesn't exist. Customer Community Plus: 21 seats, 0 used, no portal users.
- **Site members** (Dealer Portal `0DBTx00000018unOAA`, Customer Hub `0DBTx000000188POAQ`): System Administrator only, so **no Setup UI step is needed** to remove members.
- **Old sets:**
  - `Authenticated_DealerPortal` (unassigned).
  - `ps_miCustomerHub` + `ps_miCustomerHub_Payment`, both on the Customer Hub guest (`005Tx00000Pm5wfIAB`) and on Teun.
- **Dealer Portal guest** `005Tx00000QU1EEIA1`: no extra set.
- **Sender:** Dealer Portal already sends from info@movingintelligence.com (verified, set by the user); name "Dealer Portal"; standard templates. Paths are already `dealers` / `hub`.
- **No drift against the start state:** `ps_miExperienceCloudCustomer_Admin`, `ps_miCustomerHub` (= `ps_miCustomerHub_Guest` apart from the label), `Authenticated_DealerPortal`, the Login/ForgotPassword views and `Svc_DealerUserSetup` all match.
- **`rp_Contact`:** prod no longer has the standard EnableCustomerPortal/DisableCustomerPortal buttons; the rest matches the repo. The repo version adds our custom buttons.
- **Label `CustomerHubBaseURL`:** still holds the dev URL; it is deleted in this rollout.
- **⚠ Owners without a role:** 105 B2B Dealer/Distributor accounts have an owner without one (Platform Integration 99, Nico Koemans 6). Enable is refused on those. Decision needed: change the owner or give the owner a role.

## Prod gotchas
- No NoTestRun: use **RunSpecifiedTests** with Test_Svc_DealerUserSetup, Test_Inv_CustomerUser, Test_Queue_ContactCustomerUser, Test_Ctrl_DealerPortalLogin, Test_Ctrl_DealerPortalEmail. Every class in the package needs ≥ 75% (in acc: Svc 99, Inv 100, Login 89, Queue 100, Trigger_User 90, Email 100).
- Deployed **flows land inactive (Draft)**: activate `scr_Contact_Enable_Customer_User` and `scr_Contact_Disable_Customer_User` via Tooling FlowDefinition (activeVersionNumber).
- **Permission sets:** deploy `miModifyAllData` from **prod's own copy** (a deploy replaces the whole set).
- **Network:** deploy prod's own copy with only the template/name fields changed. Never deploy CustomSite + Network together ("This URL is already taken").
- **Translations:** a mdapi deploy containing only the new customLabels merges, it doesn't replace.
- **On creation the profile gets default grants** (acc: 14 object + 2,528 field): back them up and delete them. SurveyInvitation goes before Survey.
- **No test data in prod**, unless the user says so.

## Steps
0. **Validate (dry-run)** the main package with RunSpecifiedTests, then the go/no-go with the user.
1. **Labels + field** (with tests, prod rule):
   - 12 `DealerPortal_Email*` labels, `PaymentCheckoutFutureConsentLabel/Required` (neutral text).
   - `Contact.Customer_User_Type__c`, `Contact.Customer_User_Active__c`.
2. **Main package** (RunSpecifiedTests):
   - Classes: Svc_DealerUserSetup, Inv_CustomerUser, Trigger_User, Queue_ContactCustomerUser, Ctrl_DealerPortalLogin, Ctrl_DealerPortalEmail + their tests; trigger `User`.
   - Flows: scr_Contact_Enable/Disable_Customer_User; quick actions: Contact.act_DealerPortal_Enable/Disable; page: rp_Contact.
   - Components: LWC dealerLogin; VF component dealerPortalContactEmail; email templates unfiled$public/DealerPortal_Welcome + _PasswordReset.
   - Profile: miCustomerCommunityPlus.
   - Permission sets: ps_miDealerPortal_User/_Guest, ps_miCustomerHub_User/_Guest, ps_miExperienceCloudCustomer_Admin. Groups: pg_miDealerPortal, pg_miCustomerHub.
3. **Password policy:** `ProfilePasswordPolicy` miCustomerCommunityPlus, after the profile exists.
4. **Activate the flows** (Tooling FlowDefinition).
5. **Translations:** temp mdapi with only the new/changed customLabels (nl_NL/de/fr).
6. **FLS:** `miModifyAllData` (prod copy + read Customer_User_Type__c / Customer_User_Active__c) + Admin profile (partial).
7. **Empty the profile:** back up and delete the ObjectPermissions/FieldPermissions of the miCustomerCommunityPlus profile PermissionSet; then 0/0.
8. **Site members** (Data API NetworkMemberGroup):
   - ps_miDealerPortal_User + _Guest → Dealer Portal.
   - ps_miCustomerHub_User + _Guest → Customer Hub.
9. **Guests, new first, then old:**
   - ps_miDealerPortal_Guest → dealer_portal guest; ps_miCustomerHub_Guest → customer_hub guest.
   - Then remove the ps_miCustomerHub + ps_miCustomerHub_Payment assignments (guest + Teun).
   - **Check right away:** a Customer Hub payment link + preference link without login (live customers!).
10. **Delete old sets:** Authenticated_DealerPortal, ps_miCustomerHub, ps_miCustomerHub_Payment; delete the label CustomerHubBaseURL.
11. **Dealer Portal views** Login + ForgotPassword (dealerLogin) → **publish the site**.
12. **Network Dealer Portal** (prod copy): welcome/forgot/change template → DealerPortal_*, sender name "Moving Intelligence" (address stays info@).
13. **Smoke tests without data:**
    - The login page loads.
    - Wrong login → generic message with the administration email.
    - "Forgot password" with an unknown address → neutral confirmation.
    - On an existing Dealer contact: only "Enable Dealer Portal" is visible (don't click).
    - Customer Hub guest pages work.
    - Payment page: the new consent text.
14. **First real dealer:** the user clicks Enable. Then check the welcome email, login, an order, the user's language.
15. **Repo/memory:** RUNBOOK progress, commit.

## Rollback
- Old sets / rp_Contact / network / views / labels: redeploy from `prod-before/`, then reassign the guest sets (`ps_miCustomerHub` + `_Payment` → customer_hub guest).
- New components: destructive deploy.
- Profile defaults: from the backup CSVs.
