# Runbook: Marketing Cloud / Data Cloud segments (inventory)

Status: inventory only, read-only. Source: prod, `GET /services/data/v68.0/ssot/segments` on 2026-11-25. Nothing was changed.
Segments are not in the repo (no metadata type retrieved). This file is the only record of them.

## 1. Summary

- 35 segments in prod, all ACTIVE, all type UI (built by hand, no API/code).
- 31 segments are on `UnifiedIndividual__dlm`. 4 are on other objects: `Account - NL` and `Account - NL - Contract miBlack(R) / miOrange(R)` (Account), `Contract - NL - miBlack(R) / miOrange(R) - 1` and `tst` (Contract).
- Only 3 segments refresh on a schedule: `Account - NL` (every 24 h), `Basic: Preferences - Product Updates - Moving Intelligence` (every 12 h), everything else is `NO_REFRESH` (static snapshot from its last manual publish).
- 16 segments were never published (no publish status).
- Member counts below are `lastSegmentMemberCount` and are stale for every `NO_REFRESH` segment.

## 2. Inventory

### 2.1 Live / scheduled (the ones that matter)

| Segment | On | Refresh | Last publish | Members | Filter |
|---|---|---|---|---|---|
| Account - NL | Account | 24 h | 2026-11-24 | 67,076 | Reseller_Name = 1 and Subscriptions_Activated >= 1 |
| Basic: Preferences - Product Updates - Moving Intelligence | Individual | 12 h | 2026-11-25 | 183,238 | CommunicationPreference enabled, type PRODUCT_UPDATE, brand M, channel EMAIL, via ACR `MarketingAccountEligible` |

The second one is the Communication Preference Center segment (see memory: communication preference center). It is the only segment built on the new preference model.

### 2.2 Contract segments (static, NO_REFRESH)

All: Account.Reseller_Name = 1 and Contract.Status in the listed values, joined Individual -> Account -> Contract (-> Product).

| Segment | Last publish | Members | Products / extra filter | Status |
|---|---|---|---|---|
| Contract - NL - All contracts | never | 64,424 | all (`Active_Contract_Products`) | Activated |
| Contract - NL - everything except for MiRed | 2025-12-24 | 61,859 | not MiRed, `HasPriceAgreement` | Activated |
| Contract - NL - miBlack | 2025-11-18 | 27,022 | MiBlack | Activated |
| Contract - NL - miBlack(R) / miOrange(R) v2 | 2025-02-20 | 34,999 | MiBlack, MiBlack-R, MiOrange, MiOrange-R | Activated + Closed |
| Contract - NL - miBlack(R) / miOrange(R) - Immobilizer | 2026-07-07 | 28,155 | same four products | Activated |
| Contract - NL - miBlack(R) / miOrange(R) - 1 | never | 40,864 | same four, on Contract | Activated + Closed |
| Contract - NL - miBlack(R) BMW | never | 33,672 | MiBlack, MiBlack-R | Activated + Closed |
| Contract - NL - miBlack(R) - BMW | never | 11,377 | miBlack, Asset.Brand BMW (+ object types) | Activated + Closed |
| Account - NL - Contract miBlack(R) / miOrange(R) | never | 34,993 | four products, on Account | Activated + Closed |
| Contract - NL - miGreen | 2025-05-12 | 1,569 | MiGreen | Activated + Closed |
| Contract - NL - miGreen + miRed | 2025-11-26 | 5,160 | MiGreen, MiRed | Activated + Closed |
| Contract - NL - MiRed | 2026-11-20 | 3,239 | `Product.ProductCode` = Red. | Activated + Closed |
| Contract - NL - miWhite | 2026-04-03 | 14,002 | MiWhite, `HasPriceAgreement` | Activated |
| Contract - NL - miWhite - oldtimers | never | 1,365 | MiWhite, object types 4/6/9, Year_of_Manufacture_Object | Activated + Closed |
| Contract - NL - Engagement Journey Mi01 | never | 8,278 | MiWhite, End User, IsBusiness, Relation_Type, object types 1/2 | Activated + Closed |
| Contract - NL - miAzure | 2026-01-05 | 15 | MiAzure Blue | Activated |
| Contract - NL - miBlues | never | 3 | MiNavy Blue | Activated |
| Contract - NL - miNavy-Blue | never | 3 | MiNavy Blue | Activated |

Several of these overlap (the miBlack(R)/miOrange(R) family has five variants, miBlues and miNavy-Blue are identical). Candidates to merge or delete.

### 2.3 Account / market segments

| Segment | Last publish | Members | Filter |
|---|---|---|---|
| Fleet NL | 2025-03-18 | 3,445 | Active, IsBusiness, Market, Sales_Channel = fleet, reseller Europetrack / SlimmGPS / Moving Intelligence, Subscriptions_Activated |
| 20251021 - Fleet | 2025-11-03 | 610 | same fields as Fleet NL |
| 23092025 - Dealermailing | 2025-10-03 | 2,084 | Reseller_Name = 1, Relation_Type = Dealer |
| Summer campaign | never | 20,738 | Market = Security, Subscriptions_Activated |
| Noodcommunicatie lijst - security | never | 52,704 | Contract.System_Platform = 1, Activated + Closed |
| Noodcommunicatie lijst - fleet | never | 2,320 | Contract.System_Platform = 5, Activated + Closed |

### 2.4 Campaign-based

All filter on `CampaignMember.CampaignId` (a hard-coded Campaign Id) and `CampaignMember.Id`.

| Segment | Last publish | Members | Campaign |
|---|---|---|---|
| 20250807 - Follow-up incorrecte mail Segment 1754576225333 | 2025-08-07 | 0 | 701bR00000WnQOrQAN |
| 20250807 - Follow-up incorrecte mail Segment 1754576325924 | 2025-08-07 | 1,541 | 701bR00000WnQOrQAN |
| 20260519 - Yearly invoicing Carbon 24 Months Segment 1779277386678 | 2026-05-20 | 152 | 701bR00000vsh2LQAQ |

Note: the 2G Migratie campaign keeps its segment on the CampaignMember (see `.scratch/20261103 - 2gMigratieCampaign/RUNBOOK.md`), not in a Data Cloud segment from this list. The `dg_EmailResponse` data graph reads CampaignMember.

### 2.5 Legacy opt-in, tests and empty

| Segment | Last publish | Members | Note |
|---|---|---|---|
| Bacis: Marketing Opted-in | 2024-12-25 | 46,578 | CommunicationSubscription consent OPT_IN (old model, typo "Bacis") |
| Bacis: Product Updates Opted-in | never | 46,660 | same, old model |
| Basic: Product Updates Opted-in | never | 190,453 | no filter stored (all individuals) |
| Basic Test Email List | 2025-02-26 | 1 | test, single hard-coded email |
| tst | never | 38 | test, on Contract |
| tst2 | never | 222,506 | test, no filter |

## 3. Fields the segments depend on (keep-list)

These fields must stay in the Data Cloud streams / DMOs, otherwise the segments break or silently go empty. This extends the Account keep-list noted on 2026-11-06 (dataCloudActions).

| Object | Fields used |
|---|---|
| Account | `Reseller_Name__c` (almost all), `Subscriptions_Activated__c`, `Market__c`, `Relation_Type__c`, `Sales_Channel__c`, `Active__c`, `IsBusiness__c`, `Id` |
| Contract | `Status`, `Active_Contract_Products__c`, `HasPriceAgreement__c`, `System_Platform__c`, `Id` |
| Product | `Base_Product_Reporting__c`, `ProductCode` |
| Asset | `Object_Type__c`, `Brand__c`, `Year_of_Manufacture_Object__c` |
| ACR / preferences | `AccountContactRelation.MarketingAccountEligible`, `CommunicationPreference.IsEnabled`, `CommunicationPreferenceConfig.Brand / Channel / CommunicationType` |
| Legacy consent | `CommunicationSubscription`, `CommunicationSubscriptionConsent.ConsentStatus` |
| Campaign | `CampaignMember.CampaignId`, `CampaignMember.Id` |
| Identity | `UnifiedIndividual.Id`, `IndividualIdentityLink`, `UnifiedContactPointEmail.EmailAddress` |

Gaps vs the 2026-11-06 note: Asset (3 fields), Contract.System_Platform__c, Contract.HasPriceAgreement__c, Product.ProductCode and the preference/ACR fields are not on that list. Add them before any stream trim or Account/Contact recreate.

## 4. Findings and open points

1. Staleness: 33 of 35 segments never refresh. Any mailing from them uses an old member list (e.g. Contract - NL - miBlack was last published 2025-11-18, 27,022 members).
2. Only `Basic: Preferences - Product Updates - Moving Intelligence` honours the new preference model. The contract segments have no opt-out/preference filter, so they must not be used for marketing mails without a preference check in the flow or journey.
3. The 16 never-published segments: Account - NL - Contract miBlack(R)/miOrange(R), Bacis: Product Updates, Basic: Product Updates, All contracts, Engagement Journey Mi01, miBlack(R) - BMW, miBlack(R) BMW, miBlack(R)/miOrange(R) - 1, miBlues, miNavy-Blue, miWhite oldtimers, Noodcommunicatie fleet and security, Summer campaign, tst, tst2.
4. Cleanup candidates: tst, tst2, Basic Test Email List (hard-coded private email address), the two 20250807 follow-up segments, duplicate miBlues/miNavy-Blue, the "Bacis" legacy pair.
5. Not yet checked (needs Setup UI or another API call): which segments have activations, which flows/journeys/Campaign mails use each segment, and whether the daily segment-triggered flows from the MiWhite/Growth plan exist.

## 5. How this was retrieved (repeat)

```
sf api request rest -o prod "/services/data/v68.0/ssot/segments?batchSize=200"
```
Fields used: `displayName`, `segmentOnApiName`, `includeCriteria` (HTML-escaped JSON), `lastSegmentMemberCount`, `publishInterval`, `publishStatus`, `lastPublishedEndDateTime`, `lastModifiedDate`. `MarketSegment` is not queryable via SOQL/Tooling.
