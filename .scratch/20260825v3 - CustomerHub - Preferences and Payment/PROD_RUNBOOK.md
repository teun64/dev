# Prod deployment runbook — Customer Hub: Preferences and Payment

Everything below is exactly what was done against **acc** on 2026-08-25, adapted for **prod**.
Do not run any of this until explicitly told to — this file is prep, not a schedule.

All source fixes referenced here (sharingModel correction, dead-code removals, JSON content
bugs, route renames, the picklist-value gap, the missing GlobalValueSetTranslation files) are
already committed to `force-app/main/default` and folded into the package.xml at
`.scratch/20260825v3 - CustomerHub - Preferences and Payment/package.xml`. Prod does not need
any of those fixes repeated manually — they ship automatically as part of Step 1's deploy.

## Updated 2026-08-26 — what changed since this runbook was written

A full day of further acc testing/fixes happened after this runbook's original 2026-08-25
version. All of it is already folded into the package.xml (no manifest changes needed beyond
the two new permission sets, added below) and into local source. Summary, for context before
running this:

- **Payment checkout page (`paymentPage`/`paymentCheckout` LWC)**: fixed a full-viewport-width
  layout bug (the enclosing card no longer hugs its own content), a flexbox overflow bug that
  cancelled the right-side padding on the "Secure Payment" column, missing i18n on the
  order-summary labels (was hardcoded English), and the Stripe Elements iframe was sending
  Stripe an invalid locale format so it silently never re-localized on a language change.
- **`customerHubHeader`/`echoesHubHeader`/`tdsHubHeader`**: fixed the same "bare `.com` matches
  every sandbox domain" hostname-detection bug already fixed in `preferenceCenter.js` back on
  2026-08-25 — these three sibling components were never patched, so the hub header defaulted
  to English on dev/acc regardless of the visitor's actual language while the page content
  correctly showed their real language. **This bug would also apply to prod** if prod's real
  domain doesn't literally end in `movingintelligence.com` (worth a quick visual check post-deploy —
  see Step 9).
- **`afl_PaymentDirectDebitSetup_SendMail` flow**: fixed a language-selection bug where the DD
  setup/reminder emails picked their language from `Account.Sales_Language__c` (which also
  wasn't reliably reachable in the flow's data context, so it silently defaulted to English
  regardless of the real value) while the Preference Center page derives language from
  `Contact.Language__c` — the two could disagree. Unified on `Contact.Language__c` (added an
  explicit `dgr_03_Contact` re-query, same pattern as the existing `dgr_02_Administration` step)
  so the email and the Preference Center it links to can never disagree again.
- **`lh_M_Payment` EnhancedLetterhead content changed** — see the updated "Still fully manual"
  entry below, this changes what you clone/recreate in Step 10's manual step.
- **DirectDebit email templates** (all 6: SetupInitial/Reminder1/Reminder2 × EN/NL) — content
  and wording changes: added a `{{{Recipient.Preference_Center_Url__c}}}` link in the closing
  paragraph, softened the "if you didn't request this" wording, removed a redundant paragraph
  from the two SetupInitial templates, and moved the MI logo/tagline/website branding block
  (previously in the letterhead footer, which always renders *after* the whole template body so
  could never appear before the closing text) into each template body directly, right before the
  closing paragraphs.
- **Two new permission sets** (`ps_miPaymentCheckout` / `ps_miPaymentCheckoutAdmin`) — added to
  the package.xml, see the new entries there and the new manual-assignment step below.
- **Checked, no action needed for prod:** `rbc_Case`'s `X1_RecordType` step had a real bug in
  acc (a stray old flow version assigned the RecordType lookup's Id to `$Record.Id` instead of
  `$Record.RecordTypeId`, corrupting Case inserts) — **confirmed prod's active version (v27)
  already has the correct assignment**, this was acc-only version drift, not a code gap.
- **Checked, no action needed for prod:** prod's 3 existing `stripeGC__Stripe_Webhook_Endpoint__c`
  records (UK/NL/DE, all live-mode) are already clean — no `payment_method.*`/`checkout.session.*`
  noise events like acc had before today's trim. One thing worth a separate, deliberate look
  sometime (not blocking, not touched today): none of the three have `payment_intent.processing`
  enabled, which `Svc_StripeEventProcessor` does act on — possibly a pre-existing gap, unrelated
  to this deploy, your call whether it's worth investigating.

## Prerequisites / facts gathered today

- Prod org Id: `00Dbd000000...` — check via `SELECT Id FROM Organization` (not re-confirmed here for prod specifically; re-run before use).
- Prod domain: `movingintelligence.my.salesforce.com` / site domain `movingintelligence.my.site.com` (no `--env` suffix, unlike the sandboxes). Confirmed via the existing `payment` site: `https://movingintelligence.my.site.com/payment`.
- Prod's `Subscription25` package is on `2.66.0.1` (same as acc, one version behind dev's `2.67.0.1`) — not expected to matter for this deploy's scope, already checked.
- Prod's `stripeGC` package matches dev/acc exactly (`1.26.0.1`) — no drift.
- Prod schema gaps confirmed absent (same as acc pre-deploy): `Payment__c` missing 18 fields including `externalId__c`; `Account` missing the 2 consent fields; `Contact` missing `Preference_Token_Key__c`/`Preference_Center_Url__c`; `Subscription25__Administration__c` missing `Privacy_Policy_URL__c`/`Terms_Conditions_URL__c`; `stripeGC__Stripe_Event__c` missing all 10 custom fields; `BrandThemeConfig__mdt` and `DirectDebit_Method_Setting__mdt` entirely absent; `Payment__c.Status__c` missing `Setup`/`Processing` picklist values. All of these are already in the package.xml.
- Prod has **no** Customer Hub Network/site (confirmed 2026-08-24/25, re-verify before Step 4 in case it changed).
- **`Contact.trigger`, `Trigger_Contact.cls`, and `Util_ContactMarketing.cls` were never deployed to acc at all before today** — confirmed via Tooling API, not stale, simply never part of any prior deploy. Without them, no Contact insert/update anywhere gets its `Preference_Token_Key__c`/`Preference_Center_Url__c` stamped, so guest Preference Center links silently never work — not a regression, this was already broken in acc before today's work and is presumably still broken in prod too until Step 1 ships it there. Check prod for the same absence before assuming otherwise.
- **`AccountContactRelation.Marketing__c` (a formula field gating the consent-based marketing exclusion in `Util_ContactMarketing`) didn't exist anywhere, including dev**, despite a local field definition already existing in source — it had simply never been deployed. Recreated for real (not removed, unlike the other two zombie fields found today) per explicit direction: it's real, intended consent logic (excludes invoice/digital-invoice-only contacts from marketing, feeds the Preference Center prefill), not dead code. Deployed to dev first, then acc, and is now in the package.xml for prod too.

## Step 1 — Deploy the main package (everything except the site shell)

```bash
sf project deploy start \
  --manifest ".scratch/20260825v3 - CustomerHub - Preferences and Payment/package.xml" \
  --target-org prod --test-level NoTestRun
```

This package's `<types>` block for `CustomSite`/`Network`/`DigitalExperienceConfig`/`ExperienceBundle`
(re-added 2026-08-25) will fail here exactly like it failed acc's dry-run the first time, because
prod's site doesn't exist yet either. **Two options:**
- (a) Temporarily comment those four `<types>` blocks back out for this first prod pass, run Steps 1–3, then re-add them before Step 5, or
- (b) Run Step 1 with those four types excluded via a trimmed manifest, and fold them into Step 5's targeted deploy instead (this is what acc actually did, in practice — the two deploys happened as separate commands, not one).
Recommend (b) — it mirrors exactly what worked for acc and avoids editing the package back and forth.

## Step 2 — Wait for schema propagation, then verify before testing

Today's acc deploy took **~50 minutes** for all 31 new fields/CMDT records to become queryable
after a deploy that itself reported success in seconds — object-by-object, not field-by-field
or all-at-once, with one ~10-minute total stall in the middle. No root cause found; no Salesforce
Trust incident covered it. Confirmed NOT a permissions/FLS issue (verified via `FieldPermissions`
query showing near-universal Read/Edit grants immediately after deploy). Expect a similar wait
for prod. Poll with:

```bash
sf api request rest /services/data/v67.0/sobjects/Payment__c/describe --target-org prod \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('externalId__c' in {f['name'] for f in d['fields']})"
```

Repeat for `Contact`, `Subscription25__Administration__c`, and `stripeGC__Stripe_Event__c` (see
the field lists in the Prerequisites section above) until all resolve. Do not proceed to Step 3
until they do — testing against a schema that hasn't caught up produces misleading "No such
column" failures that look like real bugs but aren't (confirmed today).

## Step 3 — Run the test suite

```bash
sf apex run test --target-org prod \
  --class-names Test_Ctrl_Payment --class-names Test_Ctrl_PaymentCase \
  --class-names Test_Ctrl_CustomerHub --class-names Test_Ctrl_PaymentMandate \
  --class-names Test_Ctrl_PreferenceCenter --class-names Test_Ctrl_PreferenceCenterGuest \
  --class-names Test_Svc_StripeEventProcessor --class-names Test_Svc_PicklistTranslationSync \
  --class-names Test_Svc_MCBrandCenter --class-names Test_Util_CommunicationPreferenceToken \
  --class-names Test_Util_System --result-format json --wait 15
```

Note: prod deploys of Apex generally *require* passing tests as part of the deploy itself
(unlike the sandbox `NoTestRun` used above) — this may mean re-running Step 1 with
`--test-level RunSpecifiedTests` and the same class list once schema has settled, rather than
deploying with `NoTestRun` and testing after, the way today's acc pass did it. Confirm Salesforce's
current test-coverage requirement for this prod org before deciding which order to use.

Expect `Test_Ctrl_PreferenceCenterGuest`'s two guest-token tests to still fail with "Invalid
token" until Step 6 (creating the real `PreferenceTokenConfig__c` row) is done — this is not a
code defect, confirmed today via live anonymous Apex.

## Step 4 — Create the Customer Hub site shell

```bash
echo '{
  "name": "Customer Hub",
  "urlPathPrefix": "hubvforcesite",
  "templateName": "Build Your Own (LWR)",
  "description": ""
}' > /tmp/create_site_prod.json

sf api request rest /services/data/v67.0/connect/communities \
  --target-org prod --method POST --body @/tmp/create_site_prod.json
```

**Known bug to check for:** today's acc creation silently doubled the suffix
(`urlPathPrefix` came back as `hubvforcesitevforcesite` instead of `hubvforcesite`) — the API
appears to auto-append `vforcesite`. After creation, re-query and fix if needed:

```bash
sf data query --target-org prod --query "SELECT Id, UrlPathPrefix FROM Network WHERE Name='Customer Hub'"
# if UrlPathPrefix is wrong:
sf data update record --target-org prod --sobject Network --record-id <id> --values "UrlPathPrefix=hubvforcesite"
```

## Step 5 — Deploy the site content

```bash
sf project deploy start --target-org prod \
  --source-dir "force-app/main/default/networks/Customer Hub.network-meta.xml" \
  --source-dir force-app/main/default/sites/Customer_Hub.site-meta.xml \
  --source-dir force-app/main/default/digitalExperienceConfigs/Customer_Hub1.digitalExperienceConfig-meta.xml \
  --source-dir force-app/main/default/digitalExperiences/site/Customer_Hub1 \
  --source-dir force-app/main/default/lwc/npsPage \
  --source-dir force-app/main/default/lwc/npsForm \
  --test-level NoTestRun
```

Run with `--dry-run` first. All the content bugs found and fixed today (duplicate component ID
across `Payment`/`cv_CommunicationPreferences`, dead `prefBrandedLayout` theme layout removed,
`viewType`/`routeType` mismatch on Communication Preferences, missing `__c` suffix on the
`cr_CommunicationPreferences` route folder) are already fixed in source — this should go clean
on the first try, unlike acc's six-attempt debugging loop.

## Step 6 — Publish the site

```bash
echo '{}' > /tmp/empty_body.json
sf api request rest /services/data/v67.0/connect/communities/<networkId>/publish \
  --target-org prod --method POST --body @/tmp/empty_body.json
```

Poll `BackgroundOperation` by the returned `jobId` until `Status = Complete`.

## Step 7 — Org-data configuration (data rows, not metadata — always manual per org)

**`PreferenceTokenConfig__c` org default:**
```bash
sf data query --target-org prod --query "SELECT Id FROM Organization"   # get prod's Org Id
openssl rand -hex 32   # generate a FRESH secret — never reuse dev's or acc's

sf data create record --target-org prod --sobject PreferenceTokenConfig__c \
  --values "SetupOwnerId=<prodOrgId> Secret__c=<freshly-generated-secret> Base_Url__c='https://movingintelligence.my.site.com/hub'"
```

**`CustomerHub__c` org default:**
```bash
sf data create record --target-org prod --sobject CustomerHub__c \
  --values "SetupOwnerId=<prodOrgId> Base_URL__c='https://movingintelligence.my.site.com/hub'"
```

Confirm the exact intended prod URL before running this — `movingintelligence.my.site.com` is
prod's default site domain per the existing `payment` site, but check whether Customer Hub is
meant to get a custom domain (like the `connect.`/`portal.` ones other prod sites use) before
locking this in as `Base_Url__c`/`Base_URL__c`, since guest links are built directly from these
values.

## Step 8 — Sync picklist translations

```bash
echo 'Svc_PicklistTranslationSync.syncAll();' > /tmp/sync_picklists.apex
sf apex run --target-org prod --file /tmp/sync_picklists.apex
sf data query --target-org prod --query "SELECT COUNT() FROM PicklistTranslation__c"
```
Expect ~93 rows (matches acc) once the `GlobalValueSetTranslation` deploy from Step 1 has
propagated.

## Step 9 — Re-run Step 3's guest-token tests

Should now pass with the real `PreferenceTokenConfig__c` row in place.

**Also, while the site is still in `UnderConstruction` preview**: open a guest Preferences or
Payment link in a browser and check the hub header's language pill matches the page content's
language (both should reflect the visiting Contact's `Language__c`/resolved language, not
default to English). Since prod's real domain isn't confirmed to literally end in
`movingintelligence.com` (see the 2026-08-26 update at the top), the header's hostname-based
default could still be wrong here even though the underlying bug is fixed — worth a quick visual
check before Step 10's public activation, not just trusting the fix shipped correctly.

## Step 10 — Decision point: activate the site (not automated, ask first)

The site stays in `UnderConstruction` (preview-only) after publishing until explicitly activated
to `Live`. This makes it publicly reachable by guests — confirm before flipping it, this wasn't
done for acc either, deliberately.

## Still fully manual, no command exists for these

- **Guest user wiring** — Network/Site guest-user membership, profile assignment, and the
  `ps_miCustomerHub`/`ps_miCustomerHub_Payment` `PermissionSetAssignment` all need prod's own
  Guest User Id. The permission sets deploy in Step 1; the assignment does not.
- **`lh_M_Payment` EnhancedLetterhead** — a data record, not metadata. Clone/recreate directly
  in prod's Setup UI. Its two images (`miemailheader`/`milogoblack`) already deploy as part of
  Step 1's `ContentAsset` components. **Updated 2026-08-26: the Footer field should be created
  EMPTY** — the logo/red-line/tagline/website branding block that used to live here has moved
  into each DirectDebit email template's own body instead (a letterhead's footer always renders
  after the whole template body, so it could never appear before the closing "Deel deze..."
  text no matter how the letterhead itself was ordered). Only the Header field (the
  `mi-email-header` banner image) still needs setting.
- **Assign `ps_miPaymentCheckout` / `ps_miPaymentCheckoutAdmin`** — these permission sets deploy
  in Step 1; the assignments don't. `ps_miPaymentCheckoutAdmin` → trietman only.
  `ps_miPaymentCheckout` → trietman, the Customer Hub guest user, and every active `miSales`-profile
  user (same population as acc/dev — re-query `SELECT Id FROM User WHERE Profile.Name='miSales'
  AND IsActive=true` against prod specifically, don't assume the same Ids). Both are meant to
  stay assigned, no "remove after testing" cleanup like `ps_miCommunicationPreferences`.
- **Stripe connect config** — confirm prod's `Subscription25__Administration__c.PayProv_Account__c`
  and underlying `stripeGC` Connect linkage point at the correct **live-mode** Stripe account
  before any real customer can complete a real checkout. This is the one item on this whole list
  where a mistake has real financial/customer impact — verify carefully, this is prod.
  **Also required per Administration, found 2026-08-26 while testing acc's UK Administration:**
  `PayProv_Use__c` must be `true` and `PayProv_DirectDebit_PaymentMethod__c` must be set
  (`bacs_debit` for UK, `sepa_debit` elsewhere) — without both, `afl_Payment_Direct_Debit_Setup`
  faults with `"Payment Provider not marked as ready to use."` and no error surfaces anywhere
  visible (no Case, no log without a manually-added TraceFlag). Linking the Stripe account alone
  is not sufficient. Check/set on every Administration prod expects to actually process Direct
  Debit through, not just UK.
