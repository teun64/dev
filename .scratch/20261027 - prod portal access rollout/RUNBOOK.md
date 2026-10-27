# Prod rollout: portal access, Dealer Portal login & emails — runbook

Status: **steps 0–13 done 2026-10-27** (user's go for 1–2, then 3–15). Step 14 is the user's.
Everything below was built in dev, tested, and rolled out and tested in acc on 2026-10-26.
For acc see `../20261026 - acc portal access rollout/RUNBOOK.md`.

## Target model
- **Profile:** `miCustomerCommunityPlus` (Customer Community Plus) is an empty base profile with no object or field access. It has its own password policy: the prod org policy without the 1-day minimum lifetime, minimum length 12.
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

## Progress 2026-10-27
- Password policy minimum length changed 8 → 12 (repo file), deployed to dev + acc; prod gets 12 in step 3.
- Step 0 done: steps 1 + 2 combined (manifest `step0-validate/package.xml`) validated against prod with RunSpecifiedTests (5 test classes): **Succeeded, 26/26**, validation id `0AfTx000001477BKAQ`. Coverage: Ctrl_DealerPortalEmail 100, Ctrl_DealerPortalLogin 89, Inv_CustomerUser 100, Svc_DealerUserSetup 98, Trigger_User 90, Queue_ContactCustomerUser 100, trigger User 100.
  - Quick deploy possible within 10 days, as long as prod doesn't change in between: `sf project deploy quick -o prod --job-id 0AfTx000001477BKAQ`.
- Owners without a role: 105 accounts moved (user decision): Platform Integration → Guy Mooyman (99), Nico Koemans (inactive) → Jonas Maassen (6), both with role miCustomerBase - NL (Representatives). Bulk update 105/105; backup `owner_backup.csv` (rollback: update with that file), input `owner_update.csv`. Check: 0 dealer accounts with a role-less owner.
- Steps 1 + 2 done: quick deploy `0AfTx00000147FFKAY` of validation `0AfTx000001477BKAQ`, Succeeded.
- Step 3 done: ProfilePasswordPolicy (min length 12) deployed, Succeeded.
- Step 4 done: scr_Contact_Enable/Disable_Customer_User v1 active (Tooling FlowDefinition).
- Step 5 done: `step5-translations/` (14 labels × nl_NL/de/fr, merge), Succeeded.
- Step 6 done: `step6-fls/deploy/` = fresh prod retrieve of miModifyAllData (no drift vs prod-before) + read on Customer_User_Type__c / Customer_User_Active__c, Admin profile partial. Succeeded.
  - Note: the retrieve returned 0 fieldPermissions, but prod kept its 2 existing grants (Subscription25__VAT_Code__c.UNCL5305_Category__c, OrderItem.VAT_Code__c); now 4 in total.
  - miModifyAllData is assigned to nobody and in no group in dev/acc/prod, so these grants have no effect today.
- Step 7 done: profile 0PSTx000000AYtFOAW had 14 ObjectPermissions + 2,475 FieldPermissions (defaults). Backup in `step7-profile/profile_*_backup.csv`, all deleted (Survey last); now 0/0.
- Step 8 done: NetworkMemberGroups `_User` + `_Guest` on Dealer Portal (0DLTx0000000m4f, m6H) and Customer Hub (m7t, m9V).
- Step 9 done:
  - ps_miDealerPortal_Guest → Dealer Portal guest (0PaTx00000SvDQD), ps_miCustomerHub_Guest → Customer Hub guest (0PaTx00000Sv2kw).
  - Checked first that ps_miCustomerHub_Guest covers everything of ps_miCustomerHub + _Payment (setup entity, object and field access; nothing missing).
  - Removed the 4 old assignments (guest + Teun); backup `step9_assignments_before_delete.csv`.
  - Customer Hub guest still also has ps_miPaymentCheckout + ps_miCommunicationPreferences (unchanged).
  - Check without login: payment page PM#000196930 (Paid, so no intent is created) shows "Already completed"; the preferences page of an internal contact loads its data and 15 preferences.
- Step 10 done: `step10-destructive/` deleted Authenticated_DealerPortal, ps_miCustomerHub, ps_miCustomerHub_Payment and the label CustomerHubBaseURL. Succeeded.
- Step 11 done: views login + forgotPassword (community_login → c:dealerLogin, the only diff vs prod-before), Succeeded; site published (job 08PTx00000dNm3uMAC, Complete).
- Step 12 done: `step12-network/deploy/` = fresh prod copy of the Dealer Portal network (only today's member sets differ vs prod-before) with welcome → DealerPortal_Welcome, forgot/change → DealerPortal_PasswordReset, sender name Moving Intelligence (address stays info@). Succeeded.
- Step 13 done (headless Chrome, no data):
  - /login and /ForgotPassword render c-dealer-login.
  - Wrong login (made-up address) → "Login failed. Check your details or contact us at aftersales@movingintelligence.nl."
  - Unknown address on forgot password → neutral confirmation.
  - 9,318 dealer contacts, 0 active → only Enable shows.
  - Consent labels are the neutral text.
  - Customer Hub guest pages: see step 9.
  - Small finding: the Dealer Portal footer reads "Moving Intelligence B.V.. All rights reserved." (dealerFooter `{footer.companyName}.` while the name already ends with a dot).
- Step 14 open: the user clicks Enable on the first real dealer, then checks the welcome email, login, an order and the language.

## Follow-ups 2026-10-27 (dev + acc, prod pending the user's go)
- **Footer "B.V.."** fixed: dealerFooter getter `copyrightCompanyName` adds the dot only when the name doesn't end with one. dev + acc deployed + published; acc checked ("Moving Intelligence B.V. All rights reserved."). Commit d783549.
- **Letterhead on the Dealer Portal emails:** VF templates can't use a (classic) letterhead, so the new VF component `emailLetterheadPreferences` (part = header | logo | footer, language = recipient.LanguageLocaleKey) copies the lh_M_Preferences_EN/NL/DE/FR HTML. Welcome + PasswordReset use it instead of the dark "Moving Intelligence Dealer Portal" bar. Body styling matches the Lightning templates. Commit 5923968.
  - Rendered in dev (renderStoredEmailTemplate, nothing sent): EN/NL/DE with existing users, FR via a language change in a rolled-back transaction. Each language shows its own website + terms/privacy links.
  - FR website in the logo block = movingintelligence.ai (no Lightning template uses lh_M_Preferences_FR yet; taken from the FR footer links).
  - The images are prod file assets (oid 00D1t000000uTfK), so they work in every org.
- **Prod (user go):** dealerFooter + emailLetterheadPreferences + the 2 templates deployed (RunSpecifiedTests Test_Ctrl_DealerPortalEmail, `0AfTx00000147ojKAA`, Succeeded); prod dealerFooter had no drift (only the trailing newline). Dealer Portal published (job 08PTx00000dNjqpMAC).
- **Administration links** (Privacy_Policy_URL__c / Terms_Conditions_URL__c) dev → acc/prod: dev has them only on Netherlands. prod already had the same values; acc Netherlands (a0U3W000002VuQiUAK) filled. All other administrations are empty in all 3 orgs.
- **Administration links UK/DE/FR** (user go), filled in dev + acc + prod with the lh_M_Preferences footer links: United Kingdom movingintelligence.co.uk/pages/privacy-policy + /pages/terms-and-conditions; Germany movingintelligence.de/datenschutzerklaerung + /agb; France (echoes) movingintelligence.ai/privacy/ + /terms/. Belgium + Greece (G4S) stay empty.
  - Checked after the publish (Complete): dealer.movingintelligence.nl and .co.uk show "© 2026 Moving Intelligence B.V. All rights reserved." The .co.uk domain also shows the B.V. (guest footer entity doesn't follow the domain; existing behaviour, not changed).
- **Footer links before login** (user request): `Ctrl_DealerPortal.getFooterInfo(hostname)`. Without a dealer account (guest, or a dealer without a Reseller), the Administration is picked by the portal domain: `.nl` → 1, `.fr` → 4, `.de` → 5, `.co.uk` → 6, anything else → 1 (Netherlands). A logged-in dealer keeps their own Administration. dealerFooter + dealerLogin pass `window.location.hostname` (it is also a wire parameter, so each domain gets its own cached result).
  - Before: guests never read an Administration; they got fixed values (B.V., aftersales@, no privacy/terms links) on every domain. The Dealer Portal sets have no access to Administration, but that doesn't matter: the query runs in SYSTEM_MODE.
  - Test_Ctrl_DealerPortal 10/10, Ctrl_DealerPortal 97%. dev + acc deployed + published.
  - acc/prod need Ctrl_DealerPortal.cls-meta.xml with Subscription25 **2.66** (repo pins 2.67, package drift): deploy from a temp copy with minorNumber 66.
  - Prod drift check: no real differences (2.66 pin + trailing newlines only).
  - **Prod (user go):** deployed from the 2.66 temp copy, `0AfTx00000147rxKAA`, Test_Ctrl_DealerPortal 10/10, Ctrl_DealerPortal 97%. Dealer Portal published.
  - Checked after the publish (Complete), not logged in: .nl → NL links + B.V.; .de → movingintelligence.de/agb + /datenschutzerklaerung + GmbH; .co.uk → UK links + Ltd.
- **Hover double line** on Privacy/Terms (user finding): the theme's a:hover underline plus our 2px border-bottom. Fix: `text-decoration: none !important` on .footer-legal-link:hover/:focus (commit ccc6bc0). dev + acc deployed + published. Checked by hovering in Chrome: acc Privacy/Terms/Contact = none + border only; prod before the fix = underline + border on Privacy/Terms. Prod pending the user's go.
- **Forgot-password email empty / wrong letterhead** (user test acc: Dutch mail with .co.uk letterhead, "Beste ,", no login address, info@ instead of aftersales@):
  - Cause: Site.forgotPassword renders the email as the site guest, who can't see site members (enableGuestMemberVisibility = false, kept). All recipient fields are empty (FirstName, Email, Id, LanguageLocaleKey); labels are still translated to the recipient's language. Existing since round 2, made visible by the letterhead.
  - Fix (user chose option 1; not guest visibility, not System.resetPassword, which would invalidate the password and let anyone lock out a dealer):
    - Letterhead language from the new label `DealerPortal_EmailLanguage` (en; nl/de/fr translations).
    - Greeting `DealerPortal_EmailGreetingNoName` (Hello, / Beste, / Hallo, / Bonjour,) when FirstName is empty.
    - Login-address line only when recipient.Email is filled.
    - Contact address stays info@ (fallback) in the guest case.
  - dev + acc deployed (labels + component + 2 templates; translations via mdapi with only these 2 labels). Render check dev EN/NL/DE/FR: letterhead language = body language. The guest case needs the user's forgot-password test on acc. Prod pending the user's go (together with the footer hover fix).
