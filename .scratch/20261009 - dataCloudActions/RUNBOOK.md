# dataCloudActions — prod Data Cloud CRM data streams

Status: **PARKED (2026-10-09)**. Nothing has been changed in prod. Each prod step needs an explicit go-ahead.

## Diagnosis (prod, 2026-10-09)

| Stream | Import | Last successful | Cause |
|---|---|---|---|
| Contact_Home | FAILURE | 2026-08-28 15:02 | A permission set deploy on 2026-08-28 15:08 removed the connector's read access (permission set `sfdc_a360_sfcrm_data_extract`) to Phone, MailingAddress, OtherAddress, Birthdate, AssistantPhone, OtherPhone |
| Account_Home | FAILURE | 2025-02-20 | 9 deleted fields still in the stream: Is_bankrupt__c, Exact_Billing_Address_Id__c, Exact_Id__c, Is_Created_In_Exact__c, Is_bankruptcy__c, Last_Subscription_Date__c, PlatformList48__c, PlatformList24__c, Sync_to_Exact__c |
| Asset_Home | FAILURE | 2025-11-27 | 7 deleted fields: Is_Active__c, ASR__c, ASR_finished__c, Old_Object_Type__c, ASR_status__c, ASR_reason_closed__c, ASR_additional_info__c |
| Product2_Home | FAILURE | 2025-02-25 | 2 deleted fields: Renew_automatically_DefaulA__c, Renew_automatically_default__c |
| Contract_Home (+ EmailMessage, VoiceCall, VideoCall*, CurrencyType) | SUCCESS | daily | Status ERROR only because of an old failed stream update (UPDATE_FAILED, 2025-12-09). Data still flows |

The "Marketing" identity resolution matches only FirstName (fuzzy) + LastName + normalized Email, so removing phone, address and birthdate doesn't change how people are merged.

The Data Cloud stream API (`/ssot/data-streams`) is switched off in acc (FUNCTIONALITY_NOT_ENABLED: CdpDataStreams) even with Data Cloud Architect, so changes can't be tested there. The PATCH body for bulk-disabling fields is undocumented.

## Decisions (user, 2026-10-09)

- **Contact keeps:** Id, AccountId, FirstName, MiddleName, LastName, Name, Email, EmailBouncedDate, EmailBouncedReason, IsEmailBounced, HasOptedOutOfEmail, Language__c, Preference_Center_Url__c, IndividualId, plus system fields (IsDeleted, CreatedDate, LastModifiedDate, SystemModstamp, SfdcOrganizationId). **No Salutation**, phones, addresses, birthdate or title.
- **Account keeps:** Id, Name, BillingStreet, BillingPostalCode, BillingCity, BillingState(Code), BillingCountry(Code), Type, Status__c, isBusiness__c, Customer_Type__c, Sales_Language__c, RecordTypeId, plus system fields. **No** bank/IBAN, payment/direct debit, Subscription25, WSONE, VAT or CoC fields.
- **Purge:** old bank and personal data already in Data Cloud must be removed, so Contact and Account are recreated rather than just having fields disabled.
- **New stream:** CommunicationPreference__c (contact level). 3.1M rows.

## Actions (in order)

1. [ ] **Product2 as a safe trial:** disable the 2 deleted fields via the API, run the stream, check SUCCESS. This proves the request format.
2. [ ] **Asset:** disable the 7 deleted fields the same way, then run the stream. No purge needed.
3. [ ] **Contact and Account:**
   - [ ] Dependency check: segments, calculated insights, activations and DMO mappings that use Contact/Account fields which will disappear. Report before deleting.
   - [ ] Delete Contact_Home and Account_Home **including their stored data** (this is the purge).
   - [ ] Recreate both with the keep-lists above.
   - [ ] Map them again to the data model: Individual and ContactPointEmail for Contact, Account for Account.
   - [ ] Rerun identity resolution "Marketing".
4. [ ] **Communication preferences:**
   - [ ] Give the connector read access to CommunicationPreference__c and CommunicationPreferenceConfig__c, field by field (FieldPermissions/ObjectPermissions inserts), **not** by deploying the whole permission set.
   - [ ] Create the stream and map it.
5. [ ] **Prevention:** add `**/sfdcInternalInt__*` to `.forceignore` so a repo deploy can't overwrite the connector permission set again.
6. [ ] **Full refresh** of all changed streams once, then check every stream shows ACTIVE / SUCCESS. Watch Data Cloud credit use.

Note: until step 3 is finished, Contact/Account data is briefly missing in Data Cloud. All Growth segment-triggered flows are inactive, so nothing is mailed in the meantime.

## Related

- MiWhite mailflow advice: https://claude.ai/artifact/9hs4zdZ4RdNFfprAxDLozT
