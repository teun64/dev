# 2G Migratie MiBlack — Campaign + Call List — RUNBOOK

Status: **dev build in progress (see 2026-11-06 (4) RESUME)** — was: PLAN ONLY. Resume 2026-11-04 (answer open questions first, then start in dev).

## ▶ RESUME HERE (state at end of 2026-11-03)
**Scope has moved from "MiBlack only" to "hardware-based"**: End User accounts with ≥1 Activated + active Contract (any subscription) on 2G hardware (`Modem__c = '1'` or empty) of type Mi50 / Mi40 / Mi01 / Mi04 / Beacon. Teltonika is out; contracts without known hardware are out.
Current result = **Matrix v5** below (+ Total column), Excel: `2G_matrix_hardware.xlsx` (countries as rows; per hardware group B2C / B2B (1-2) / B2B (3+) / Total). Reproduce with `build_matrix.py` (see header in script).

| Hardware | B2C | B2B (1-2) | B2B (3+) | Total |
|---|---:|---:|---:|---:|
| Mi50 | 11,911 (13,190 / 12,433) | 6,730 (7,479 / 7,028) | 1,258 (11,362 / 7,225) | 19,899 (32,031 / 26,686) |
| Mi40 | 141 (203 / 174) | 792 (912 / 860) | 656 (5,494 / 2,843) | 1,589 (6,609 / 3,877) |
| Mi01 | 3,589 (3,983 / 3,717) | 1,683 (1,796 / 1,725) | 322 (1,734 / 968) | 5,594 (7,513 / 6,410) |
| Mi04 (MiRetreever) | 5 (5 / 5) | 0 | 1 (15 / 15) | 6 (20 / 20) |
| Beacon | 112 (115 / 115) | 153 (171 / 171) | 215 (2,523 / 2,523) | 480 (2,809 / 2,809) |
| **Total (unique)** | **15,457 (18,121 / 16,444)** | **9,160 (10,690 / 9,784)** | **1,926 (22,375 / 13,574)** | **26,543 (51,186 / 39,802)** |

Cell = accounts (active subs on that hardware / of which 2G). Total row = unique accounts. B2B 1-2 vs 3+ = all active subs of the account on these hardware types.
Labels: Mi01 = hardware "MiTracer" (type 73), shown only as "Mi01" (user's wish). Mi04 = MiRetreever (type 87).
Priority: Mi50 probably first.

**Decisions 2026-11-04 (user):**
- Scope = **platform 1 only** (`Contract.System_Platform__c = '1'`) → 26,354 accounts (B2C 15,360 / B2B 1-2 9,725 / B2B 3+ 1,051 / beacon-only 218), 37,452 contracts.
- **Beacons included, but handled separately** (own segment / own track).
- **Mails from Salesforce** (Marketing Cloud and/or service mails).
- Account data = the **contract's account** (1,537 hardware assets sit on another account: old owner / dealer / lease; not used).
- Next: user wants process **enhancement proposals first**, then settle open questions, then build in dev.

**Trial day = Tue 2026-11-03 (reported by user 2026-11-04):** 4 callers, 81 calls → 49 Opportunities: 8 Closed Won directly + 41 offers (≈ 20 calls/caller/day; 60% → Opp, 10% direct sale, 51% offer). User: offers need a **follow-up** step.
- Prod: Opportunity stages used by these callers: Preparation, Offer, Administration, Closed Won/Lost/Unqualified (record types Standard_Opportunity, Insurance_Opportunity, Webshop). The trial day could not be separated from regular sales in the data (no campaign link) → future Opps must get `CampaignId`.
- Prod check 2026-11-03 (4 callers): only 20 Call tasks logged (Jonas 11, Roxanne 9; Syl/Tom 0) and 24 Opps created (10 Offer, 12 Closed Won, 2 Administration), mixed with regular business (webshop, SCM klasse TV), none with CampaignId → trial mostly not traceable in SF; tooling must log every attempt + link Opps to the campaign.
- Capacity: 81 calls per Tuesday, part of which go to offer follow-ups → roughly 40 new accounts per week. Calls alone cannot cover 26k accounts, so mail-first + prioritising stays necessary.

**2026-11-06: mails via Marketing Cloud Growth (plan only).** Open question 1 (mails) answered: **Growth**. Cycle: batches by priority → mail 1 → reminder 1 → reminder 2 (+ "Not interested") only if no reaction → final mail (no more contact + 2G info). Buttons Call me / Make an offer / Not now (Q1–Q4 2027) via a Customer Hub token page with a confirm click. Hardware blocks via visibility rules on HasMi50__c… flags. Proposal: Salesforce keeps the mail stage (scheduled flow), Growth sends. 4 mails instead of the "2 mails" in the request → question G1. Full plan + questions G1–G12: https://claude.ai/artifact/9hs4zdZ4RdNFfprAxDLozT (section "2G Migratie campaign: mails through Growth"). Prerequisite: dataCloudActions (Contact stream broken, no CampaignMember stream).

**2026-11-06 (2): decisions + G12 built in dev.**
- Decisions: Call me → Omni call-back Case, Type "2G/4G conversion", skills scCase+sdSales+slDutch (all 4 callers have them; existing callback flow routes to gqAftersalesNL = support). Make an offer → Opportunity (CampaignId) + lines per hardware type → offered product (mapping = separate action, G15). Case button `scr_Case_Create_Opportunity` gets a 2G branch. Not interested → new member in a "2G Migratie – Not interested" campaign + original Declined. G1: 4 mails; call outcomes Call back (2nd try) / Not interested / Not now (manual Qx) / Offer, all through one "apply answer" subflow. **Recipient = Main contact only** (replaces decision 5).
- Prod check: 26,295 accounts in scope → 26,235 exactly one Main contact (all with email), 60 none, 769 Email Opt Out, only 283 with Preference_Center_Url__c (backfill never run in prod).
- **G12 built in dev (uncommitted):** Campaign `MaxMailAttempts__c`, `MailIntervalDays__c` (default 14), `MailCompletedStatus__c`; CampaignMember `Priority__c`, `MailBatch__c`, `MailBatchReleasedOn__c`, `MailStage__c` (Waiting/Due/Completed/Stopped), `MailNumber__c`, `MailDueOn__c`, `Response__c` (Call me/Offer/Not now/Not interested), `ResponseOn__c`, `RecontactFrom__c`. Flows `afl_CampaignMember_Mail_Cycle` (logic) + `stf_CampaignMember_Mail_Cycle` (daily 03:00 UTC, Waiting/Due members). Test `Test_afl_CampaignMember_Mail_Cycle` 6/6 pass. FLS Admin profile + miModifyAllData granted in dev by FieldPermissions DML (`fls_mailcycle.apex`; repeat per org). Not in acc/prod.
- Next: "apply answer" subflow + response page + 2G callback Case + Case button branch + offer lines subflow; add the fields to the CampaignMember Data Cloud stream.

**2026-11-06 (3): generic sales call-back BUILT in dev (not acc/prod).** Replaces the "Type 2G/4G conversion + skills" decision above.
- Decisions: a call-back queue per department; sales = `gqCaseSalesCallback1` "Case - Sales - Callback (NL)", members role group `rg_miCustomerBaseNL_Management` (+ subordinates), routing `rcCaseSalesCallback1` priority 3 (Least Active, weight 5 like rcLead1). `gqCaseSales1` untouched (148 open manual Cases). 2 tries within 2 working days; then close (Unsuccesfull / Customer Unavailable) + mail to the agent's manager (fallback label = Niels Boersma) + member back into the mail cycle.
- Components (deploy together, then FLS): CustomField Campaign.CallbackLabel__c, Case.Campaign__c, Case.CampaignMemberId__c, Case.CallbackSource__c, Case.CallbackAttempts__c, Case.CallbackDueOn__c, Case.CallbackLastAgent__c; QueueRoutingConfig:rcCaseSalesCallback1; Queue:gqCaseSalesCallback1; CustomLabel:SalesCallback_FallbackManagerEmail; ApexClass Svc_SalesCallback + Test_Svc_SalesCallback (9/9); Flow rab_Case_Callback_Due, scr_Case_Callback_Not_Reached, rab_Voice_Call (Callback scenario skips Cases with CallbackSource__c); QuickAction:Case.Callback_Not_Reached; FlexiPage:rp_Case_Default.
- FLS per org: `sf apex run -o <org> -f ".scratch/20261103 - 2gMigratieCampaign/fls_salescallback.apex"` (Admin + miModifyAllData read/edit; miSales, miFinance, miMarketing, miAfterSales read; dev done).
- rp_Case_Default: repo file = prod + button. Dev lacks the Einstein classification component → dev got a variant via --metadata-dir; never deploy the repo page to dev.
- Before go-live: check the manager mail in acc (dev managers inactive); reps need an Omni status with the Case channel (Available / Available - Cases / Available for Voice); Niels + Ron have no Service Cloud licence.

**2026-11-06 (4): apply answer + response page + mail schedule BUILT in dev (not acc/prod). PAUSED here — resume below.**
- User input: sales may use Omni-Channel or work the queue by hand (their choice) → list view `Case.gqCaseSalesCallback1_Case` added (shared to role group rg_miCustomerBaseNL_Management + subordinates). Mail schedule decided: batch 1 = 500 members by priority (later batch sizes follow the response); mail 1 day 0 (release), mail 2 day 5, mail 3 day 12 if no reaction; day 20 = closed (Completed + Mail Completed Status) and moved to the Follow-up Campaign. Interpreted: no separate mail 4 any more (the old "final mail") → confirm with user.
- **Apply answer** `Svc_CampaignResponse` (invocable "Apply Campaign Answer"; one entry for page + call): Response__c/ResponseOn__c, MailStage Stopped, member Status only if the campaign has it (Call me→Call requested, Offer→Offer requested, Not now→Postponed, Not interested→Declined). Call me → sales call-back (Svc_SalesCallback request). **Offer → also a call-back Case noted "offer requested"; rep makes the Opportunity with Create Opportunity** (interim, replaces "Opportunity from the page" until G15 + an owner rule exist → DECISION FOR USER). Not now → RecontactFrom__c = chosen quarter start (default next quarter). Not interested → contact added to Campaign.FollowUpCampaign__c. Same answer twice = unchanged; a different answer overwrites and notes an open call-back. Svc_SalesCallback: addNote public; not reached/expire also puts "Offer" members back in the cycle.
- **Token**: CampaignMember.ResponseToken__c (64-hex random, unique ext id) + ResponseUrl__c (Customer Hub base + /response?token=), stamped by new trigger `CampaignMember` (before insert/update, blank only). Mail buttons: ResponseUrl__c + `&a=callme|offer|notnow|notinterested`. Both fields must be added to the CampaignMember Data Cloud stream.
- **Response page**: Customer Hub route `cp_Response__c` (/response, Public) + view `Response` with LWC `campaignResponse` (NL/EN, choice → confirm click, quarter choice for Not now; load only reads). Guest Apex `Ctrl_CampaignResponseGuest` (getResponse cacheable, submit). Dev site published. Verified as real guest via /hub/webruntime/api/apex/execute: getResponse OK, submit callme → member Call me/Call requested/Stopped + Case MI00234195 in "Case - Sales - Callback (NL)", created by Customer Hub Site Guest User, due Wed 11-11 08:30.
- **Call side**: screen flow `scr_Case_Callback_Reached` + quick action `Case.Callback_Reached` (on rp_Case_Default, repo + dev variant scratchpad/cb/fpdeploy): Offer (Case stays open → Create Opportunity) / Not now (date) / Not interested → close Succesfull / Other → close Succesfull without member change. `scr_Case_Create_Opportunity`: repo file was stale (dev = prod differ from repo) → replaced by the prod version + CampaignId = Case.Campaign__c + name from Callback Label (API 68.0).
- **Mail schedule**: Campaign.MailScheduleDays__c (text "5,12,20", days after the release; last value = closing day; needs MaxMailAttempts__c values, 2G = 3), Campaign.FollowUpCampaign__c (renamed from NotInterestedCampaign__c). afl_CampaignMember_Mail_Cycle: fScheduleDayText, next step = MailBatchReleasedOn__c + day; empty schedule = old Mail Interval logic; on Completed adds the contact to the follow-up campaign (if not yet a member).
- Tests: Test_Svc_CampaignResponse 15, Test_Svc_SalesCallback 10, Test_afl_CampaignMember_Mail_Cycle 11 → 36/36 pass in dev.
- FLS + guest class per org: `sf apex run -o <org> -f ".scratch/20261103 - 2gMigratieCampaign/fls_campaignresponse.apex"` (dev done; also grants Ctrl_CampaignResponseGuest on ps_miCustomerHub_Guest by SetupEntityAccess; the repo permission set file has it too — don't deploy the whole set).
- Deploy list (on top of block (3)): CustomField Campaign.FollowUpCampaign__c, Campaign.MailScheduleDays__c, CampaignMember.ResponseToken__c, CampaignMember.ResponseUrl__c; ApexTrigger CampaignMember; ApexClass Svc_CampaignResponse, Ctrl_CampaignResponseGuest, Test_Svc_CampaignResponse, Svc_SalesCallback, Test_afl_CampaignMember_Mail_Cycle; LWC campaignResponse; DigitalExperience site/Customer_Hub1 route cp_Response__c + view Response (deploy only these two folders; Customer_Hub1 has other uncommitted changes) then `sf community publish -n "Customer Hub"`; Flow scr_Case_Callback_Reached, scr_Case_Create_Opportunity, afl_CampaignMember_Mail_Cycle; QuickAction Case.Callback_Reached; ListView Case.gqCaseSalesCallback1_Case; FlexiPage rp_Case_Default.
- Dev leftovers: field Campaign.NotInterestedCampaign__c still exists in dev (orphan, delete via Setup or destructive deploy); test data ZZ Test Response + ZZ Test Response - Not interested campaigns, member 00vbd000009fJUXAA2, Case MI00234195 (keep for the browser check, then delete).
- **RESUME (next) — superseded by block (5):** 1) update the report 9hs4zdZ… (v20: blocks (4), schedule, Offer decision) — NOT done yet; 2) open the dev page in a browser (`/hub/response?token=8901429e…&a=notnow`) and check layout/texts; 3) ask user: Offer via call-back Case OK? mail 4 dropped? Follow-up campaign = same for Not interested and no reaction?; 4) memory + commit only when asked; 5) acc only on explicit go (then manager mail, voice fix call, button as non-admin, guest page).

**2026-11-06 (5): STAGED CAMPAIGN rebuild in dev (replaces "one campaign" + Follow-up Campaign of block (4)).**
- Decision (user): 1 parent + 5 child campaigns by `Campaign.CampaignRole__c` (restricted picklist): **Source** (all members to migrate, priority, recontact date for Not now; maintained: 0 subs → removed) → **Operational** (released batch, mail cycle) → **Offer** (offer made = finished) / **Not interested** / **Not reacted** (after day 20, makes room in Operational).
- `Svc_CampaignMove` (invocable "Move Campaign Member"): move = delete + insert in the sister campaign (same parent) with every custom member field (describe, not FLS-based: the guest sees none), so ResponseToken__c moves along and links in sent mails keep working; contact already in target → that member is updated; open call-back Cases follow (CampaignMemberId__c + Campaign__c); savepoint. Bulk.
- `Svc_CampaignRelease` + screen flow `scr_Campaign_Release_Batch` + quick action `Campaign.Release_Batch` (on rp_Campaign, visible when Role = Source; repo = dev = prod before): next N (default 500) by Priority__c asc, skips RecontactFrom__c in the future; sets Due / mail 1 / Released On today / next MailBatch__c.
- Answers (`Svc_CampaignResponse`): Call me / Offer → Operational (back from Source / Not interested / Not reacted) + call-back; Not now → Source (stage/mail number cleared, RecontactFrom); Not interested → Not interested. Offer campaign is reached only when the rep makes the Opportunity: `scr_Case_Create_Opportunity` looks up the Offer sister (CampaignId) and moves the member after saving the Case.
- Mail cycle: on Completed in an Operational campaign → `Svc_CampaignMove` role Not reacted. Schedule stays `MailScheduleDays__c` "5,12,20" (2G: MaxMailAttempts__c 3) — set on the Operational campaign.
- Removed: Campaign.FollowUpCampaign__c (+ NotInterestedCampaign__c) — deleted in dev (after deleting obsolete flow version 2 of afl_CampaignMember_Mail_Cycle). FLS script now grants CampaignRole__c.
- Tests: Test_Svc_CampaignMove 7, Test_Svc_CampaignResponse 18, Test_Svc_SalesCallback 10, Test_afl_CampaignMember_Mail_Cycle 12 → 46/46 (+ fix for guest) pass in dev.
- Live dev (as real guest, /hub/webruntime/api/apex/execute): staged "ZZ 2G Test" (parent + 5), 3 members in Source; release 2 → Operational Due/1 batch 1; guest notnow 2027-04-01 → Source; guest callme → Case MI00234196; guest notinterested → member + open Case to Not interested; release 5 → only priority 3 (batch 2), Not now skipped. First guest try failed (empty field list) → fixed.
- Not run live: Create Opportunity move to Offer (screen flow), mail cycle day-20 move (covered by test only).
- OPEN: source maintenance job (add new 2G customers, remove members with 0 active 2G subs — also from Operational?) = the population job (§5), waits on the scope questions; an open call-back after "Not interested" stays open with a note (rep decides) — confirm.
- Deploy list additions: CustomField Campaign.CampaignRole__c; ApexClass Svc_CampaignMove, Svc_CampaignRelease, Test_Svc_CampaignMove; Flow scr_Campaign_Release_Batch; QuickAction Campaign.Release_Batch; FlexiPage rp_Campaign. Drop Campaign.FollowUpCampaign__c from block (4)'s list. Deploy classes before the flows that call them (same-deploy "can't find action").
- Dev test data: ZZ 2G Test (+5 children), Case MI00234196 (old ZZ Test Response data deleted).

**Open questions for 2026-11-04:**
1. Beacon: keep Cellocator (2,024 2G subs), Garmin (135) and "alte compact & light" (187), or only the MI beacons Mi6–Mi13 (462)?
2. With the wider scope, does the 1-2 → Syl/Rox/Jonas/Tom, 3+ → Jonas/Tom rule still apply? Segment basis = all active subs on in-scope hardware (as in the matrix)?
3. The earlier open questions below (mails, capacity/priority, multiple Sales contacts, B2C 3+, non-NL accounts) are still open. Q4 (segment basis) is partly answered by the matrix choice.
4. After that: start the build in dev (plan sections 1–7 below; selection in §1 must be updated to hardware-based).

## Request (business, 2026-11-03)
Security (MiBlack) accounts, customer type End User, with 1+ 2G systems on an active subscription.
Call every customer: Tuesdays, from Direct Sales, from a dashboard. Max 3 calls + 2 mails, tracked per customer.
- 1–2 subscriptions → Syl / Rox / Jonas / Tom
- 3+ subscriptions → Jonas / Tom only

## Decisions taken (user, 2026-11-03)
| # | Question | Decision |
|---|---|---|
| 1 | What is a "2G system" | **2G only** = `Asset.Modem__c = '1'` (not `3` = 2G+4G LTE-M1) |
| 2 | Boundary | **1–2 / 3+** |
| 3 | What to count | **Collect both**: MiBlack total active + MiBlack 2G only |
| 4 | Where tracking lives | **CampaignMember**, fields **generic & reusable** for other campaigns |
| 5 | Who to call | **Sales contact(s)**, fallback **Main** contact |

## Data mapping (verified prod 2026-11-03, read-only)
| Concept | Field |
|---|---|
| Security / MiBlack | Contract.Base_Product__r.Family `Black - Subscription MiBlack` or `BlackR - Subscription MiBlack-R` |
| End user | `Account.Relation_type__c = 'End User'` (NOT `Customer_Type__c`) |
| Active subscription | `Contract.Status = 'Activated' AND Active__c = true` |
| 2G | `Contract.Hardware__r.Modem__c = '1'` (values: 1 2G only, 3 2G+4G LTE-M1, 2/8 4G only, 4–7 LoRa, 9 2G+4G LTE, 0 unknown). All MiBlack hardware = Mi50, so product name is useless |
| Sales contact | ACR `Roles` includes `Sales` / `AccountContactRelation.isSalesContact__c` (also `Contact.Sales_Contact__c` boolean — check which is leading) |
| Callers | Sylvana Geeve 005bR0000003SUQQA2, Roxanne Vogelzang 005bR000005IACZQA4, Tom Beekmans 005bR0000038onXQAQ, Jonas Maassen 0051t0000011zHZAAY — all miSales, all in Call Center "Moving Intelligence" (04vbR0000000KZpQAM) |

## Sizing (prod 2026-11-03, 2G only)
- **16,378 accounts** (10.3k B2C / 6.1k B2B), almost all NL, ~37 without any phone
- Bucket by ALL active subs: 1–2 = 15,502 / 3+ = 876
- Bucket by MiBlack active subs: 1–2 = 15,984 / 3+ = 394
- Bucket by MiBlack 2G subs: 1–2 = 16,263 / 3+ = 115
- (2G + 2G/4G would be 36,650 accounts — rejected)
- ⚠ Capacity: 16k × 3 calls by 4 people on Tuesdays only = years → prioritisation needed (open Q2)

## Matrix (prod 2026-11-03) — selection incl. `Modem__c` null
Selection widened (user 2026-11-03): active MiBlack and/or MiBlack-R with `Modem__c = '1'` **or null**.
Result: no change, because no active End User MiBlack contract has a null modem or lacks hardware (only modem 1 = 17,234 and 3 = 23,126 contracts).
B2C/B2B = Account record type. B2B is split by 1–2 vs 3+ contracts (the user preferred this over a split on financial holding). Basis = MiBlack total active. Rows = establishment/billing country.

Cell = accounts (MiBlack active subscriptions / of which 2G subscriptions)

| Country | B2C | B2B (1-2) | B2B (3+) | Total |
|---|---:|---:|---:|---:|
| NL | 10,232 (11,168 / 10,561) | 5,782 (6,483 / 5,994) | 252 (1,108 / 563) | 16,266 (18,759 / 17,118) |
| BE | 45 (55 / 47) | 26 (28 / 27) | 0 | 71 (83 / 74) |
| GB | 9 (9 / 9) | 3 (4 / 4) | 1 (3 / 1) | 13 (16 / 14) |
| ES | 7 (12 / 9) | 0 | 0 | 7 (12 / 9) |
| IT | 2 (3 / 3) | 1 (1 / 1) | 0 | 3 (4 / 4) |
| PT | 3 (3 / 3) | 0 | 0 | 3 (3 / 3) |
| DE | 1 (1 / 1) | 2 (2 / 2) | 0 | 3 (3 / 3) |
| FR | 2 (2 / 2) | 1 (1 / 1) | 0 | 3 (3 / 3) |
| LU | 0 | 2 (2 / 2) | 0 | 2 (2 / 2) |
| MC | 1 (2 / 2) | 0 | 0 | 1 (2 / 2) |
| NO, SK, AN, AT, TR | 1 (1 / 1) each | 0 | 0 | 1 (1 / 1) each |
| CZ | 0 | 1 (1 / 1) | 0 | 1 (1 / 1) |
| **Total** | **10,307 (11,260 / 10,642)** | **5,818 (6,522 / 6,032)** | **253 (1,111 / 564)** | **16,378 (18,893 / 17,238)** |

- If the basis is MiBlack 2G only, B2B (1-2) = 5,994 and B2B (3+) = 77. The other columns stay the same.
- 141 B2C accounts have 3+ MiBlack. Open: should they go to Jonas/Tom too (3+ rule) or stay in the B2C pool?

## Matrix v2 (prod 2026-11-03): based on HARDWARE, any active subscription
Selection (user 2026-11-03): End User accounts with ≥1 Activated + active Contract on hardware **Hardware_Type__c = 43 (Mi50)** with `Modem__c = '1'` or null, **any** subscription family (no longer MiBlack only).
Cell = accounts (active subscriptions on Mi50 / of which 2G). B2B split on active Mi50 subscriptions (1–2 vs 3+). Rows = establishment/billing country.

| Country | B2C | B2B (1-2) | B2B (3+) | Total |
|---|---:|---:|---:|---:|
| NL | 11,732 (12,984 / 12,242) | 7,040 (8,013 / 7,432) | 884 (10,641 / 6,639) | 19,656 (31,638 / 26,313) |
| BE | 57 (67 / 59) | 34 (36 / 35) | 1 (3 / 3) | 92 (106 / 97) |
| DE | 55 (62 / 59) | 14 (16 / 16) | 9 (63 / 61) | 78 (141 / 136) |
| GR | 18 (19 / 19) | 7 (8 / 8) | 1 (114 / 114) | 26 (141 / 141) |
| GB | 9 (9 / 9) | 3 (4 / 4) | 1 (3 / 1) | 13 (16 / 14) |
| ES | 12 (18 / 14) | 0 | 0 | 12 (18 / 14) |
| IT | 4 (5 / 5) | 3 (3 / 3) | 0 | 7 (8 / 8) |
| FR | 4 (5 / 5) | 1 (1 / 1) | 0 | 5 (6 / 6) |
| PT | 4 (4 / 4) | 0 | 0 | 4 (4 / 4) |
| LU | 1 (1 / 1) | 2 (2 / 2) | 0 | 3 (3 / 3) |
| PL | 2 (2 / 2) | 1 (1 / 1) | 0 | 3 (3 / 3) |
| AT | 2 (2 / 2) | 0 | 1 (5 / 5) | 3 (7 / 7) |
| RO | 2 (2 / 2) | 0 | 0 | 2 (2 / 2) |
| MC | 1 (2 / 2) | 0 | 0 | 1 (2 / 2) |
| CH, NO, BG, SK, AN, LV, FI, TR | 1 (1 / 1) each | 0 | 0 | 1 (1 / 1) each |
| CZ, AD | 0 | 1 (1 / 1) each | 0 | 1 (1 / 1) each |
| **Total** | **11,911 (13,190 / 12,433)** | **7,107 (8,086 / 7,504)** | **897 (10,829 / 6,823)** | **19,915 (32,105 / 26,760)** |

- 16,582 accounts have MiBlack (some carry MiBlack on 4G Mi50 next to another subscription on 2G Mi50). 3,333 accounts have **no MiBlack**: MiGreen, SCM Plus, MiOrange, Wagenparkbeheer, etc.
- Hardware type 43 also includes 74 contracts on product **T.FMC640 (Teltonika)** with modem null and no base product. FMC = LTE, so probably not 2G. 16 accounts enter the list only through these. Open: exclude them? (A filter on Product2 = Mi50 would exclude them.)
- Other families on 2G Mi50 (contracts): MiGreen 4,761, SCM Plus 1,045, MiOrange 827, MiSpecials 624, Wagenparkbeheer 526, MiOrange-R 414, Beveiligingspakket 405, Rittenadmin 245, MiYellow 160, Export 141, etc.

## Observations
- CampaignMember has no custom fields in dev yet; `LeadOrContactId` can reference Account but `AccountId` is not SOQL-queryable → store own `Account__c` lookup
- Default CampaignMember statuses: New, Ready, Sent, Responded, Connected (statuses are per-campaign data)
- 0 call Tasks (CallType set) logged in prod last 30 days → CTI doesn't log calls; attempts must be logged by the caller
- CampaignMember has no tab/list views and reports aren't click-to-dial → LWC needed for the call list

## Plan

### 1. Selection
End User accounts with ≥1 active MiBlack/MiBlack-R contract on hardware `Modem__c = '1'`.
Per account: `CountTotal__c` = MiBlack total active, `CountInScope__c` = MiBlack 2G only.
`Segment__c` = `1-2` / `3+` (basis: see open Q4 — assumed MiBlack total active).
One member per account: Sales contact (ACR role Sales, active), else Main contact.

### 2. One campaign "2G Migratie MiBlack" (segment on the member, no child campaigns)

### 3. Generic fields
CampaignMember:
| API name | Label | Type |
|---|---|---|
| Account__c | Account | Lookup(Account) |
| AssignedTo__c | Assigned To | Lookup(User) |
| Segment__c | Segment | Text(40) |
| CountTotal__c | Count (Total) | Number |
| CountInScope__c | Count (In Scope) | Number |
| SelectedVia__c | Selected Via | Text (Sales/Main) |
| CallAttempts__c | Attempts (Call) | Number, default 0 |
| MailAttempts__c | Attempts (Mail) | Number, default 0 |
| LastCallAttemptOn__c | Last Attempt On (Call) | DateTime |
| LastMailAttemptOn__c | Last Attempt On (Mail) | DateTime |
| AttemptsCompleted__c | Attempts Completed | Formula checkbox vs Campaign max |

Campaign:
| API name | Label | Type |
|---|---|---|
| MaxCallAttempts__c | Max Attempts (Call) | Number (here 3) |
| MaxMailAttempts__c | Max Attempts (Mail) | Number (here 2) |
| CountTotalLabel__c | Label (Count Total) | Text ("MiBlack active") |
| CountInScopeLabel__c | Label (Count In Scope) | Text ("MiBlack 2G") |

Member statuses (campaign data): New → Not reached → Call back → Interested → Migration scheduled / Declined / Unreachable.

### 4. Tuesday tooling
- LWC "My call list" (home / app page): members assigned to running user, active campaigns, not finished; sorted by attempts + last attempt; click-to-dial via Amazon Connect; button → log attempt. Check LWC naming in reference_experience_cloud_naming / existing conventions.
- Screen flow "Log contact attempt" (quick action on CampaignMember + from LWC): Call/Mail + outcome → increment counter, stamp date, set Status, create Task (Who=Contact, What=Account). Flow element naming per reference_flow_element_naming memory.
- Report + dashboard for Jonas/Tom: progress per caller × segment.

### 5. Population (reusable)
Apex batch / script: build members from selection, fill counts/segment/contact/Account__c, round-robin `AssignedTo__c`:
- `1-2` → Syl, Rox, Jonas, Tom
- `3+` → Jonas, Tom
Accounts without phone → separate status / mail-only.

### 6. Permissions
New `ps_miCampaignCalling` (fields edit, flow, Apex/LWC classes) → in `pg_miSales`. Admin + miModifyAllData edit on new fields (standard). Remember: permset deploy REPLACES the whole set; new fields have zero FLS by default. apiVersion 68.0.

### 7. Rollout
1. dev build + test data
2. acc deploy + test with Syl/Rox
3. prod deploy — **only on explicit go-ahead**
4. prod population (16k members) — **only on explicit go-ahead**

## Open questions (ask first on 2026-11-04)
1. **Mails**: sent from Salesforce (template, flow raises mail counter) or by marketing via their mailflow (then load back who got mailed)?
2. **Capacity / priority**: order to work in (3+ first? B2B before B2C? oldest hardware?) and release in batches?
3. **Multiple Sales contacts** on one account: pick one (most recently modified) — OK?
4. **Segment basis**: MiBlack total active (assumed) or MiBlack 2G only?
5. Which sales-contact flag is leading: ACR role `Sales` / `isSalesContact__c` vs `Contact.Sales_Contact__c`?

6. **B2C with 3+ MiBlack** (141 accounts): Jonas/Tom, or the B2C pool?
7. **Non-NL accounts** (112): include them in the NL call team, or exclude them / handle them separately?

## Log
- 2026-11-04: CSV export platform 1 (System_Platform__c='1'), active End User contracts on hardware modem 1/empty, Teltonika + no hardware product out → 37,452 rows (one per contract), newest First Installation Date first; ExtIds stripped of -hw-1/-in-1/-1. Files: 2G_hardware_platform1_last250.csv (checked by user) + _rest.csv (37,202) + _all.csv. UTF-8 BOM, ';'. Script build_export.py; query: Contract WHERE Status='Activated' AND Active__c=true AND Account.Relation_type__c='End User' AND System_Platform__c='1' AND Hardware__c!=null AND (Hardware__r.Modem__c='1' OR =null).
- 2026-11-03: hardware check. All active End User MiBlack/MiBlack-R contracts are on Asset record type Hardware, Product2 = **Mi50**, Hardware_Type__c = 43 (modem 1: 17,234 contracts, modem 3: 23,127). No other hardware types. A Mi50 filter excludes nothing, but add it to the selection as a safeguard.
- 2026-11-03 — selection widened to Modem null (0 extra); country × B2C/B2B(1-2)/B2B(3+) matrix added.
- 2026-11-03 — analysis + plan, decisions 1–5 taken, nothing built. Scratch exports (contracts.csv / black.csv) were in the session scratchpad, not kept; re-run the queries above if needed.

## Matrix v3 (prod 2026-11-03): hardware type as main column
File: `.scratch/20261103 - 2gMigratieCampaign/2G_matrix_hardware.xlsx` (countries as rows; columns Mi50 / Mi40 / Mi04 / Mi01 / Rest / Total × B2C / B2B (1-2) / B2B (3+)).
Selection: End User, Activated + active Contract, hardware with modem 1 or empty, any subscription. Cell = accounts (active subs on that hardware / of which 2G).
B2B 1-2 vs 3+ now on ALL active subs of the account over all hardware in scope, so each account lands in one bucket. That's why the Mi50 B2B split differs from v2.

| Hardware | B2C | B2B (1-2) | B2B (3+) |
|---|---:|---:|---:|
| Mi50 | 11,911 (13,190 / 12,433) | 6,717 (7,462 / 7,012) | 1,271 (11,379 / 7,241) |
| Mi40 | 141 (203 / 174) | 785 (900 / 851) | 663 (5,506 / 2,852) |
| Mi04 (FMB003) | 0 | 2 (4 / 4) | 90 (967 / 967) |
| Mi01 (FMB001) | 0 | 3 (4 / 4) | 60 (342 / 342) |
| Rest | 3,757 (4,203 / 3,917) | 1,984 (2,171 / 2,091) | 1,105 (15,220 / 14,302) |
| **Total (unique accounts)** | **15,506 (18,220 / 16,524)** | **9,289 (10,878 / 9,962)** | **2,486 (34,670 / 25,704)** |

27,281 unique accounts.
- Mapping: Mi04 = "FMB003 / mi004 (Teltonika)" (type 32); Mi01 = "FMB001 (Teltonika)" (type 14). Both always have an empty modem.
- ⚠ Rest includes ~3,733 contracts on **FMC** devices (FMC880 1,704 / T.FMC130 1,058 / FMC003 868 / T.FMC640 74 / T.FMC001 29) with an empty modem. FMC = 4G, so they are counted as 2G only because the modem is empty. Open: exclude them?
- Biggest Rest groups (2G contracts): MiTracer modem 1 6,410, FMT100 2,064, FMB120 1,597, CR-200 1,095, FMB010 1,056, FMB020 923, CR-300 758, FMP100 612.
- Excluded: contracts without known hardware (no product / type 0, ~26k, mostly UK platform).
- Open: is "Rest" in scope for this campaign, or only Mi50/Mi40/Mi04/Mi01?

## Matrix v4 (prod 2026-11-03): Mi50 / Mi40 / Teltonika / (Mi01/Mi04?)
User 2026-11-03: hardware starting with F = Teltonika → one overall column. Only the named types are in scope (no Rest); Mi50 probably gets priority. Mi01/Mi04 = beacons developed by Moving Intelligence. They are NOT FMB003/FMB001 (that v3 mapping was wrong).
File updated: `2G_matrix_hardware.xlsx`.

| Hardware | B2C | B2B (1-2) | B2B (3+) |
|---|---:|---:|---:|
| Mi50 | 11,911 (13,190 / 12,433) | 6,725 (7,474 / 7,023) | 1,263 (11,367 / 7,230) |
| Mi40 | 141 (203 / 174) | 786 (901 / 852) | 662 (5,505 / 2,851) |
| Teltonika | 59 (82 / 80) | 215 (276 / 274) | 726 (12,092 / 12,034) |
| MiTracer (Mi01/Mi04?) | 3,589 (3,983 / 3,717) | 1,683 (1,796 / 1,725) | 322 (1,734 / 968) |
| MiRetreever (Mi01/Mi04?) | 5 (5 / 5) | 0 | 1 (15 / 15) |
| **Total (unique)** | **15,412 (18,096 / 16,409)** | **9,208 (10,783 / 9,874)** | **2,401 (32,024 / 23,098)** |

27,021 unique accounts.
- Teltonika = every hardware with "(Teltonika)" in the name (incl. T.FM*, TAT, TMT). ~3,733 of its "2G" contracts are FMC (4G) with an empty modem. Open: exclude FMC?
- No hardware asset named Mi01/Mi04 exists. Candidates: **MiTracer** (type 73, MiWhite, modem 1 = 6,410 active contracts) and **MiRetreever** (type 87, Product2 family "7200 - Mi01", historic WhiteMi04 subscriptions, 20 active). Open: which hardware is Mi01 / Mi04, or are beacons out of scope (no SIM → no 2G)?
- 2026-11-03: user confirmed **Mi04 = MiRetreever** (type 87): 6 accounts / 20 active subs, all 2G. Excel column renamed "Mi04 (MiRetreever)". Still open: is MiTracer the Mi01?

## Matrix v5 (prod 2026-11-03), current
User 2026-11-03: Teltonika out. Mi01 and Mi04 are separate columns. Remaining (non-Teltonika) hardware is grouped as "Beacon". File `2G_matrix_hardware.xlsx` overwritten.

| Hardware | B2C | B2B (1-2) | B2B (3+) |
|---|---:|---:|---:|
| Mi50 | 11,911 (13,190 / 12,433) | 6,730 (7,479 / 7,028) | 1,258 (11,362 / 7,225) |
| Mi40 | 141 (203 / 174) | 792 (912 / 860) | 656 (5,494 / 2,843) |
| Mi01 | 3,589 (3,983 / 3,717) | 1,683 (1,796 / 1,725) | 322 (1,734 / 968) |
| Mi04 (MiRetreever) | 5 (5 / 5) | 0 | 1 (15 / 15) |
| Beacon | 112 (115 / 115) | 153 (171 / 171) | 215 (2,523 / 2,523) |
| **Total (unique)** | **15,457 (18,121 / 16,444)** | **9,160 (10,690 / 9,784)** | **1,926 (22,375 / 13,574)** |

26,543 unique accounts.
- Mi01 = the hardware called "MiTracer" in Salesforce; the user does not want "(MiTracer)" in the label → column/row "Mi01" (2026-11-03).
- Beacon (2G contracts): MI beacons Mi6–Mi13 / Mi7 Flextrack = 462. Also **Cellocator** CR-200/CR-300/CelloIQ = 2,024, **Garmin** Compact = 135, "alte compact & light" 187, PicoTrack 1. Those are third-party trackers, not MI beacons. Open: keep them under Beacon or exclude them?
- 2026-11-03: Excel: every hardware group now has a 4th column "Total" (B2C + B2B 1-2 + B2B 3+). The separate "Total (all)" column was dropped; it is the same as Total → Total. Grand total 26,543 (51,186 / 39,802).
- 2026-11-03: prod campaign cleanup done (see `.scratch/20261103 - campaignCleanup/RUNBOOK.md`): 209 closed, all pre-2024 campaigns deleted, only the UTM 2026 tree (25) still open. The new "2G Migratie" campaign starts in a cleaned-up set.

## 2026-11-07 (6): Offer = Opportunity with .M lines (dev)
User decision (G15): "Make an offer" creates an Opportunity with the equivalent products: Mi50 → Mi50.M, Mi01 → Mi01.M, quantity = the customer's number of that hardware. The Opportunity is linked to the campaign AFTER the member moved to the Offer campaign.
- New field `Product2.MigrationProduct__c` (Lookup Product2, SetNull), set on the hardware (Platform) product: Mi50 01t3W000000hz3lQAA, MiTracer 01t3W000000hz4GQAQ, Mi40 01t3W000000hz3vQAA, MiRetreever 01tAO000000HIuoYAG.
- New `Svc_CampaignOffer.createOffer(contactId, campaignId, source)`: Opportunity (RT Standard_Opportunity explicit — guest has no default RT; owner = account owner if active Standard user; LeadSource Telephone for Call, else E-mail; CloseDate +30; Option_Require_Signature__c) + lines: COUNT of Contracts Activated + Active__c + Hardware modem '1'/null grouped by Hardware__r.Product2.MigrationProduct__c. Price book from rbc_Opportunity; missing price → listed in Description. Open Opp for same account+campaign is reused.
- `Svc_CampaignResponse`: Offer → targetRole Offer (move first), then createOffer; no call-back; with caseId (Callback Reached) the Case gets Opportunity__c and closes Succesfull; an open call-back gets Opportunity__c + note. Result.opportunityId added.
- `Svc_SalesCallback.backToMailCycle`: only 'Call me' (Offer has an Opportunity, no mails again).
- Tests: Test_Svc_CampaignOffer (4, quantityOverride), Test_Svc_CampaignResponse updated (offer_movesToOfferWithOpportunity, offer_onCallback_linksAndClosesCase, callMeCallbackNotReached_memberBackInCycle). 51/51 in dev.
- FLS: fls_campaignresponse.apex now also grants Product2.MigrationProduct__c (run in dev).
- Live dev (guest over HTTP): A.J.W. de Witte (001bd00000GAWfEAAX, 1 active 2G MiRetreever + 3 closed) → member in ZZ 2G Test - Offer, Opp 006bd00000TpD5lAAF "2G/4G conversion - A.J.W. de Witte", NL Direct Sales, 1× Mi04.M €165.
- Dev test data (clean up later): Product2 Mi50.M + Mi04.M (ZZ.MI04.M, dev only) with prices; MigrationProduct__c set on Mi50 and MiRetreever; Opp 006bd00000TpD5lAAF; guest TraceFlag 7tfbd000000Odt3AAC (expires itself).
- Prod prerequisites: Mi50.M exists (01tTx00000DdURlIAN, 800.050.0015, €165 NL 2024 books). Mi01.M / Mi40.M / Mi04.M don't exist yet → business creates them, then fill Migration Product on the 4 hardware products.
- Deploy list additions: CustomField Product2.MigrationProduct__c, ApexClass Svc_CampaignOffer + Test_Svc_CampaignOffer; Svc_CampaignResponse, Test_Svc_CampaignResponse, Svc_SalesCallback changed.
- Report v20 written (9hs4zdZ…), process scheme v2 (XFhtKsXg…).

## 2026-11-07 (7): Not interested closes the call-back + Source job (dev)
- User: "on 3 close the case" → `Svc_CampaignResponse`: "Not interested" on the page closes an open call-back (Status Succesfull, note "(answered on the page, closed)", no CallbackLastAgent). closeReached → closeCallback(caseId, answer, note, byAgent). Close side effects checked: only rau_Case_Notification (platform notification, needs Notification__c) and rab_Case_Callback_Due (skips IsClosed) → no customer mail. Live guest dev: callme → MI00234197, notinterested → closed Succesfull, member in Not interested. Offer on the page with an open call-back still only notes the Case (asked user).
- **Source job** `Batch_CampaignSource` (Day dispatcher step `JobDispatcherStep.Day_CampaignSourceSync`, order 80; needs Subscription25__Schedulable_Class__c record per org — created in dev) + `Svc_CampaignSource`:
  - Runs for active Campaigns with CampaignRole Source + `SourceSelection__c` = "2G migration" (new restricted picklist) + ParentId; optional `SourceCountryCodes__c` ("NL,BE", empty = all).
  - Selection: Account End User + Contract Activated, Active__c, System_Platform__c '1', Hardware__r.Product2.MigrationProduct__c != null, modem '1'/null (prod read-only count with the 4 hardware names: 26,059 accounts, ~25 s).
  - Phase 1 (accounts): Main contact = active ACR Roles INCLUDES 'Main', oldest; new → Source member with `Account__c` + `UnitCount__c` (2G units) + Priority__c; existing in Source → priority/units updated, RecontactFrom kept; in Operational → units; Offer / Not interested / Not reacted → left alone; one member per contact.
  - Priority = Product2.`MigrationPriority__c` of the best 2G hardware (empty 9) × 10 + segment (1 B2B 3+ units on mapped hardware, 2 B2B 1-2, 3 B2C) = G2 proposal as data (Mi50 1, Mi40 2, MiTracer 3, MiRetreever 4).
  - Phase 2 (Source + Operational members): account without 2G units → deleted from Source; Operational only counted (pending user decision).
  - Totals in the debug log of phase 2 finish; dry run `new Batch_CampaignSource(true)`.
  - Gotcha: a Number field can't be grouped in SOQL → group by Hardware__r.Product2Id and read MigrationPriority__c after.
- New fields: Product2.MigrationPriority__c, Campaign.SourceSelection__c, Campaign.SourceCountryCodes__c, CampaignMember.Account__c (lookup), CampaignMember.UnitCount__c; FLS via fls_campaignresponse.apex (run in dev, 30 inserted).
- Tests: Test_Svc_CampaignSource 7/7 (scopeOverride), with Test_Util_JobDispatcher 20/20; campaign suite 51/51.
- Live dev: dry run found de Witte + Mostert (1 unit, rank 4); real run (2 phases, 0 errors): nothing added (both already in Offer / Not interested), test member "Afdeling Administratie" removed from Source (its account has no 2G), Operational member of that account only counted.
- Dev data changed: MigrationPriority on Mi50 (1) + MiRetreever (4); ZZ 2G Test - Source SourceSelection 2G migration, countries NL; Mostert's ACR got role Main; Schedulable_Class record Batch_CampaignSource.
- Go-live: the Campaign layout isn't in the repo → add Campaign Role, Mail Schedule, Source Selection, Source Country Codes to the Campaign page (or set by data); Data Cloud stream: add Account__c, UnitCount__c.
- Deploy list additions: fields above, ApexClass Svc_CampaignSource, Batch_CampaignSource, Test_Svc_CampaignSource, CustomMetadata JobDispatcherStep.Day_CampaignSourceSync.

## 2026-11-08 (8): Offer closes the call-back + Closed Lost → Source (dev)
- User: "on 6 close the case too, once the opportunity has been made, it follows the opportunity path, when opp on close lost, customer to base que again".
- `Svc_CampaignResponse`: Offer with an open call-back now always closes it (closeCallback, byAgent = caseId given; on the page the note gets "(answered on the page, closed)").
- `Svc_CampaignOffer.afterUpdate` (called from `Trigger_Opportunity` after update): StageName changes to `Closed Lost` (STAGE_LOST; not Closed Unqualified / Closed Swapped) on an Opportunity whose CampaignId is an Offer campaign with a parent → the account's member in that campaign (Account__c or Contact.AccountId) moves to Source via Svc_CampaignMove with Response__c, MailStage__c, MailNumber__c, MailDueOn__c, RecontactFrom__c = null (old links work again: same answer would otherwise be "unchanged"). Skipped when another open Opp of the account is on that campaign. Exceptions are caught + debug-logged (closing the Opp must not fail).
- rau_Opportunity NOT touched (has someone else's uncommitted Fitting Service change).
- Tests: Test_Svc_CampaignResponse +3 (offer_onPage_closesOpenCallback, offerClosedLost_memberBackToSource, offerClosedUnqualified_memberStaysInOffer); deploy with Response/Offer/Move/SalesCallback/Source tests 49/49; Test_Util_OrderConfirmation (Opportunity trigger) 100%.
- Live dev: Opp 006bd00000TpD5lAAF → Closed Lost → de Witte member in ZZ 2G Test - Source, Response/MailStage null.
- Deploy list additions: ApexClass Trigger_Opportunity (changed), Svc_CampaignMove (comment).

## 2026-11-08 (9): page layouts + acc deploy package (dev; acc NOT deployed — waits for an explicit go)
- **Layouts (new in repo, prod-based):** `Campaign-Campaign Layout` + section "Staged Campaign" (CampaignRole, CallbackLabel, SourceSelection, SourceCountryCodes | MailScheduleDays, MailIntervalDays, MaxMailAttempts, MailCompletedStatus); `CampaignMember-Campaign Member Page Layout` + section "Staged Campaign" (Account, UnitCount, Priority (edit), Response, ResponseOn, RecontactFrom (edit) | MailStage, MailNumber, MailDueOn, MailBatch, MailBatchReleasedOn, ResponseUrl; rest read-only, token left out); `Product2-Platform` (layout of the hardware record type Platform) + section "2G Migration" (MigrationProduct__c, MigrationPriority__c) above MDM. Deployed to dev. Dev = acc for the Campaign layout except prod lacks the Campaign Influence related list → the prod-based file drops it in dev/acc (accepted). CampaignMember + Product2-Platform layouts were identical dev = acc/prod.
- **acc check (read-only, 2026-11-08):** Util_JobDispatcher, JobDispatcherStep__mdt, PreferenceTokenConfig__c, Case.Opportunity__c, Subscription25 2.66 (Job_AbstractBatch2) present. acc = HEAD for Trigger_Opportunity, rab_Voice_Call, rp_Campaign. scr_Case_Create_Opportunity: acc = prod (repo file is prod-based → OK). **rp_Case_Default: acc lacks the Einstein classification component (like dev) → deploy the acc variant `acc-deploy/step3-casepage` (= acc page + the 2 buttons only, 38 added lines), never the repo file.**
- **Package** in `acc-deploy/` (verified with `sf project convert source -x`: step 1 = 14 classes, trigger, 29 fields, label, CMDT, LWC, queue, routing; step 2 = flows, quick actions, layouts, list view, rp_Campaign, Customer Hub route/view, Test_afl_CampaignMember_Mail_Cycle). Classes first: a flow and its invocable Apex in one deploy gives "can't find action".
- **acc run order (only after the go):**
  1. `git status` clean-check of the files above; before-snapshot: `sf project retrieve start -o acc -m "CustomObject:Case" -m "CustomObject:Campaign" -m "CustomObject:CampaignMember" -m "CustomObject:Product2" --target-metadata-dir <scratch>/acc_before` (compare compactLayoutAssignment etc. afterwards, see partial object deploy gotcha).
  2. `sf project deploy start -o acc -x ".scratch/20261103 - 2gMigratieCampaign/acc-deploy/step1-package.xml" -l RunSpecifiedTests -t Test_Svc_CampaignMove -t Test_Svc_CampaignOffer -t Test_Svc_CampaignResponse -t Test_Svc_CampaignSource -t Test_Svc_SalesCallback -t Test_Util_OrderConfirmation --wait 30` (optionally `--dry-run` first).
  3. FLS + guest class: `sf apex run -o acc -f` fls_salescallback.apex, fls_mailcycle.apex, fls_campaignresponse.apex (in that order).
  4. `sf project deploy start -o acc -x ".scratch/20261103 - 2gMigratieCampaign/acc-deploy/step2-package.xml" -l RunSpecifiedTests -t Test_afl_CampaignMember_Mail_Cycle --wait 30`.
  5. `sf project deploy start -o acc --metadata-dir ".scratch/20261103 - 2gMigratieCampaign/acc-deploy/step3-casepage" --wait 10` (Case page buttons).
  6. `sf community publish -o acc -n "Customer Hub"`; check PreferenceTokenConfig__c Base_Url__c = acc Customer Hub URL (ResponseUrl__c).
  7. Data: Subscription25__Schedulable_Class__c record Name/Unique_Name__c = Batch_CampaignSource; flows active (stf_CampaignMember_Mail_Cycle schedule, rab_Case_Callback_Due); queue members (role group rg_miCustomerBaseNL_Management + subordinates).
  8. Re-retrieve the 4 objects and diff against the before-snapshot.
  9. Test in acc: staged test campaign (parent + 5, roles), release, page answers as guest, Callback Reached/Not Reached as a sales rep (non-admin), manager mail, one outbound voice call on a call-back, Offer → Opportunity, Closed Lost → Source, Source job dry run (`new Batch_CampaignSource(true)`).
- **Live dev: day-20 move checked** (was test-only): Mart van den Heuvel member 00vbd000009fMdhAAE set to Due / mail 3 / released today-20, `afl_CampaignMember_Mail_Cycle` started by anonymous Apex (Flow.Interview, recordId) → new member 00vbd000009glGfAAI in ZZ 2G Test - Not reacted, Completed, mail 3. (Stage "Waiting" = not released yet → the flow restarts at mail 1; use "Due" to simulate.) Script: scratchpad day20.apex.
- Still open for go-live: Data Cloud CampaignMember stream (prod Data Cloud = prod change → explicit go), the Source choices (left open by user 2026-11-08), .M products + Migration fields (business).

## 2026-11-08 (10): DEPLOYED TO acc (user: "deploy to acc")
- Before-snapshot scratchpad acc_before (4 objects, 3 layouts, rp_Case_Default, rp_Campaign).
- Step 1: validated 0AfG500000TQs7JKAT (49 components, 57/57 tests) → quick deploy 0AfG500000TQrb4KAD, 0 errors.
- FLS: fls_salescallback (6 sets, 42), fls_mailcycle (2 sets, 24), fls_campaignresponse (6 sets, 60 + guest class granted).
- Step 2: validated 0AfG500000TQsFNKA1 (19 components, 12/12 tests) → quick deploy, Succeeded. All 8 flows active.
- Step 3: first try refused ("Your org doesn't have access to component opencti:recordPhoneCallControls") — the dev variant had dev's phone component; removed it → acc page now = acc before + the 2 buttons only (diff: 0 removed lines). Deployed.
- `sf community publish -n "Customer Hub"` (acc). PreferenceTokenConfig Base_Url__c = https://movingintelligence--acc.sandbox.my.site.com/hub (OK). Queue gqCaseSalesCallback1 has its role group member. Schedulable_Class record Batch_CampaignSource created (a1YG5000004UvplMAC). After-retrieve: top-level settings of Case/Campaign/CampaignMember/Product2 unchanged.
- Safety: acc email deliverability is ON; 2,056 of 2,095 contact emails are masked (.invalid). No new Account created in acc (NL administration syncs to Exact, token can reach prod) → test on own company account Moving Intelligence B.V. 001G500000sb025IAA, Main contact "afd. administratie" 003G500000sl4nuIAA (contactinfo@demo.com.invalid), 4 active 2G Mi50 contracts.
- **Live acc test (guest over HTTP, class id must be 15 chars: @udd/01pG500000GM8de):** staged ZZ 2G Test (parent 701G500001Vq0zGIAR + 5) → member in Source → release → Operational Due/1, ResponseUrl on the acc /hub domain; getResponse OK; callme → Case MI00273391 in "Case - Sales - Callback (NL)", created by the site guest, due 11-11 08:30; offer → member in Offer, Opp 006G500000aQfijIAC "2G/4G conversion - Moving Intelligence B.V." (Preparation, 2024 - NL - All - Direct Sales, LeadSource E-mail, no lines: Mi50.M doesn't exist in acc), Case closed Succesfull with Opportunity link; Closed Lost → member back in Source, answer cleared, same token; notinterested → Not interested. Source job dry run: completed, 0 items (no Source Selection / mapping in acc).
- **Finding (owner):** the Opp owner = account owner "Platform Integration" (miAPIIntegration, active Standard user → passes the code's check). Prod 2G accounts by owner: Lisa Vos 15,006, Platform Integration 6,738, Jonas Maassen 2,574, Ron Plomp 538, Security Platform 536, rest small → ~7,300 Opps would be owned by integration users. Decision needed (e.g. a fixed sales owner / queue, or the agent on a call).
- Still for people in acc: buttons as a sales rep (Callback Reached / Not Reached, Release Batch, Create Opportunity), manager mail on Not Reached, one outbound voice call on a call-back, the page in a browser.
- acc test data (clean up after the business test): ZZ 2G Test (+5) and its member, Case MI00273391, Opp 006G500000aQfijIAC.

## 2026-11-08 (11): Opportunity owner decided (dev)
- User: "owner is the agent on a call, otherwise it is the account owner". `Svc_CampaignOffer`: source 'Call' (SOURCE_CALL) + running user Standard → OwnerId = running user (the agent); else account owner when active Standard user (integration owners included, per user). Tests +2 (offer_fromCall_ownerIsAgent, offer_fromPage_ownerIsAccountOwner); dev deploy 27/27 (Offer + Response tests). acc NOT yet (needs a go).
- No email templates exist for 2G in dev/acc: customer mails are Growth (marketing, prod); the manager mail is plain text in Svc_SalesCallback.

## 2026-11-08 (12) — owner rule DEPLOYED TO acc
- Deployed Svc_CampaignOffer + Test_Svc_CampaignOffer to acc: deploy 0AfG500000TQvA1KAL, RunSpecifiedTests (Test_Svc_CampaignOffer + Test_Svc_CampaignResponse) 27/27 passed.
- Live body in acc checked: it contains SOURCE_CALL (agent on a call, otherwise account owner).
- acc package step1 already had both classes; for a prod deploy the package doesn't change.
