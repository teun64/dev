# Permissions alignment — runbook (started 2026-10-29)

Goal: every permission set (ps) and permission set group (pg) is **the same in dev, acc and prod**, **tracked in the repo**,
named by the convention and placed according to the target model. Work it in small, reviewed steps; prod only on an explicit go.

## Rules (from earlier work)
- **Naming:** permission sets `ps_mi<Name>` (label `mi<Name> (ps)`), groups `pg_mi<Name>` (label `mi<Name> (pg)`).
- **Target model:** 3 profiles only (Admin / User / Integration) without object access; all access through groups and sets.
  General permissions go in the general group (e.g. `pg_miSales`), country specifics in the country group (`pg_miSales1`).
- **A ps deploy REPLACES the whole set.** Never deploy a partial file; always start from the org copy (prod first).
- **New field:** zero FLS by default; standard grants = Admin profile + `miModifyAllData` edit (+ finance read where relevant).
- `viewAllFields` is read-only; required fields reject FLS; `modifyAllRecords` is ignored on objects without sharing.
- Check **all** assignments (incl. Guest users) before removing or renaming a set.
- `sf project retrieve` overwrites uncommitted work: check `git status` first.

## Inventory (2026-10-29)
Source: `ps_<org>.csv` / `psg_<org>.csv` in this folder (custom only: no namespace, not group-owned).
"Naming": ok = follows the convention, rename? = doesn't, platform = Salesforce/managed (`force__`, `sfdcInternalInt__`, `sf_devops*`, `sflabs_*`): never rename or track.

| | Total | In all 3 orgs | Tracked | Untracked local file | Not in repo | Naming not ok |
|---|---|---|---|---|---|---|
| Permission sets | 181 | 132 | 38 | 121 | 22 | 48 |
| Permission set groups | 43 | 16 | 10 | 23 | 10 | 11 |

The untracked local files are org downloads from earlier retrieves (which org and when is unknown), so they are **not** a source of truth.

## Phases
1. **Baseline (repo = prod).** Retrieve every custom ps/pg from prod into the repo (explicit names, not wildcards) and commit as
   "prod baseline". Untracked local files are replaced by the prod copy; sets that only exist in dev/acc are retrieved from dev.
2. **Differences per org.** Compare dev and acc against the prod baseline; list per set: missing, extra grants, missing grants.
   Decide per set: prod wins, dev wins (unreleased work), or merge.
3. **Clean up.** Sets only in one sandbox (test leftovers) or without assignments: propose delete. Platform sets: leave.
4. **Naming.** Rename the "rename?" sets to `ps_mi*` / `pg_mi*`: create the new set, move assignments, then delete the old one
   (a rename isn't possible via metadata). One small batch per run, prod on go.
5. **Target model.** Move profile access into sets/groups (3-profile model), user by user group.
6. **Keep it in line.** Every ps/pg change: start from the prod copy, deploy dev → acc → prod, commit the same file.

## Status
- 2026-10-29: inventory made (this file). Phase 1 not started.

## Permission sets
| Name | Naming | dev / acc / prod | Repo |
|---|---|---|---|
| `Allow_Dealer_Locator` | rename? | D A P | untracked |
| `Allow_managing_public_list_views` | rename? | D A P | untracked |
| `Allow_to_delete_Contacts_for_merging_duplicates` | rename? | D A · | not in repo |
| `Allow_to_edit_Custom_Labels` | rename? | D A P | untracked |
| `Approve_credit_requests` | rename? | D A P | untracked |
| `Badge_Object_Acces` | rename? | D A P | untracked |
| `Check_product_as_Target_related` | rename? | D A P | untracked |
| `Create_Audit_Fields` | rename? | D A P | untracked |
| `E_mail_template_user` | rename? | D A P | untracked |
| `Guest_Payment` | rename? | D · · | not in repo |
| `History` | rename? | D A · | untracked |
| `Komma_Trace_Extension_Read` | rename? | D A P | untracked |
| `Manage_Campaigns` | rename? | D A P | untracked |
| `Manage_Letterheads` | rename? | D A P | untracked |
| `Manage_Surveys` | rename? | D A P | untracked |
| `OmniPresenceStatusPermissionSet` | rename? | D A P | untracked |
| `Omni_Channel_Supervisor` | rename? | D A P | untracked |
| `Omni_Channel_User` | rename? | D A P | untracked |
| `PDF_Butler_Admin_Local` | rename? | D A P | untracked |
| `PartnerTelephonyCustomPsl` | rename? | D A P | untracked |
| `Sales_User` | rename? | D A · | not in repo |
| `Service_Cloud_Voice_Presence_Status` | rename? | D A · | not in repo |
| `Service_Messaging_Admin` | rename? | D A P | untracked |
| `Service_Messaging_Agent` | rename? | D A P | untracked |
| `USF_Flow_Screen_Component_Custom_Objects` | rename? | D A P | not in repo |
| `USF_Flow_Screen_Component_Datatable` | rename? | D A P | not in repo |
| `Use_Lightning_Content_Builder_With_CMS` | rename? | D A P | untracked |
| `miDataTranslations` | ok | D A P | tracked |
| `miModifyAllData` | ok | D A P | untracked |
| `miMulti_Factor_Authentication_Enabled` | ok | D A P | untracked |
| `miPayments_ps` | ok | · A P | tracked |
| `miPriceAgreements` | ok | D A P | untracked |
| `miProducts` | ok | D A · | not in repo |
| `miView_and_Edit_Converted_Leads` | ok | D A P | untracked |
| `miWebsiteHooks` | ok | D A P | untracked |
| `ps_AdministrationFooterLinksAdmin` | rename? | D · · | tracked |
| `ps_Allow_Email_Template_Builder` | rename? | D A P | untracked |
| `ps_BusinessEntitiesAdmin` | rename? | D A P | tracked |
| `ps_BusinessEntitiesReadOnly` | rename? | · · P | tracked |
| `ps_CallCenterBusinessHours_Deltaforce` | rename? | D A P | tracked |
| `ps_CommunciationPreferenceAdmin` | rename? | D A P | untracked |
| `ps_DealerProductFavoriteAdmin` | rename? | D A P | tracked |
| `ps_DealerShopHidePricesAdmin` | rename? | D A P | tracked |
| `ps_EN16931_Invoicing` | rename? | D A P | tracked |
| `ps_MessagingAdmin` | rename? | · A P | untracked |
| `ps_MessagingUser` | rename? | · A P | untracked |
| `ps_MiManage_Dashboards` | rename? | D A P | untracked |
| `ps_ProductShippingAdmin` | rename? | D A P | tracked |
| `ps_ShopActionAdmin` | rename? | D A P | tracked |
| `ps_Subscription25View` | rename? | D A P | tracked |
| `ps_Subscription25_VisualForce` | rename? | D A P | untracked |
| `ps_View_Alarm_Contacts` | rename? | D A P | untracked |
| `ps_View_Current_Location` | rename? | D A P | untracked |
| `ps_View_Incidents` | rename? | D A P | untracked |
| `ps_View_Login_As` | rename? | D A P | untracked |
| `ps_mOmnChanneliMessaging_User` | rename? | D · · | not in repo |
| `ps_mi123FromBuilderAdditional` | ok | · · P | not in repo |
| `ps_miAPEXControlClasses` | ok | D A P | untracked |
| `ps_miAPEXOperationalClasses` | ok | D A P | tracked |
| `ps_miAPEXRestPointClasses` | ok | D A P | tracked |
| `ps_miAPIAmazonIntegration` | ok | D A P | untracked |
| `ps_miAPIArchiveIntegration` | ok | D A P | untracked |
| `ps_miAPIBackupIntegration` | ok | D A P | untracked |
| `ps_miAPIBackupIntegrationAdditional` | ok | D A P | untracked |
| `ps_miAPIBusinessAnalyticsIntegration` | ok | D A P | untracked |
| `ps_miAPIDioroLicenceAnalysis` | ok | D A P | untracked |
| `ps_miAPILeadIntegration` | ok | D A P | untracked |
| `ps_miAPILeadIntegration1` | ok | D A P | untracked |
| `ps_miAPIPlatformIntegration` | ok | D A P | untracked |
| `ps_miAPIPlatformIntegrationAdditional` | ok | D A P | untracked |
| `ps_miAPIPlatformIntegrationEvents` | ok | D · P | untracked |
| `ps_miAPIPwrBAIntegration` | ok | D A · | not in repo |
| `ps_miAPIShopIntegration` | ok | D A P | untracked |
| `ps_miAPI_Platform_Integration_Events` | ok | · A · | not in repo |
| `ps_miAccountContactRelation` | ok | D · · | not in repo |
| `ps_miAccountContactRelationFull` | ok | D A P | untracked |
| `ps_miAccountContactRelationSF` | ok | D A P | untracked |
| `ps_miAccountPaymentMethodContracts` | ok | D A P | untracked |
| `ps_miAccountPaymentMethodOpportunities` | ok | D A P | untracked |
| `ps_miAccountPaymentMethod_Change` | ok | D A P | tracked |
| `ps_miAccountRelationTypeDistributor` | ok | D A P | untracked |
| `ps_miAccountRelationTypeFleetEndUser` | ok | D A P | untracked |
| `ps_miAccountRelationTypeInterCompany` | ok | D A P | untracked |
| `ps_miAccountRelationTypeLeasing` | ok | D A P | untracked |
| `ps_miAccountReplaceDebtorNumber` | ok | D A P | untracked |
| `ps_miAccountStatus_Admin` | ok | D A P | tracked |
| `ps_miAdminHardDelete` | ok | D A P | untracked |
| `ps_miAllowFinancialEntityChange` | ok | D A P | tracked |
| `ps_miAllowMergeAccountContact` | ok | D · P | untracked |
| `ps_miAssetReportIssue` | ok | D A P | untracked |
| `ps_miClaudeAccessUser` | ok | · · P | not in repo |
| `ps_miCommunicationPreferences` | ok | D A P | untracked |
| `ps_miConnectedAppAmazon` | ok | D A P | untracked |
| `ps_miConnectedAppBusinessAnalytics` | ok | D · P | untracked |
| `ps_miConnectedAppPlatform` | ok | D A P | untracked |
| `ps_miConnectedAppPlatform01` | ok | D A P | untracked |
| `ps_miConnectedAppPlatform02` | ok | D · P | untracked |
| `ps_miConnectedAppPlatform03` | ok | D · P | untracked |
| `ps_miConnectedAppPlatform05` | ok | D · P | untracked |
| `ps_miConnectedAppPlatform06` | ok | D · P | untracked |
| `ps_miContentDeliveries` | ok | D A P | tracked |
| `ps_miContractUndoTermination` | ok | D A P | tracked |
| `ps_miCustomerHub_Guest` | ok | D A P | tracked |
| `ps_miCustomerHub_User` | ok | D A P | tracked |
| `ps_miDataAccountArchived` | ok | D · · | not in repo |
| `ps_miDataSensitivityLevel` | ok | D · · | not in repo |
| `ps_miDealerPortal_Guest` | ok | D A P | tracked |
| `ps_miDealerPortal_User` | ok | D A P | tracked |
| `ps_miDealerShopInternal` | ok | D A P | tracked |
| `ps_miExperienceCloudCustomer_Admin` | ok | D A P | tracked |
| `ps_miExperienceCloudKnowledge` | ok | D A P | untracked |
| `ps_miFORM_Butler_Admin` | ok | D A P | untracked |
| `ps_miFORM_Butler_User` | ok | D A P | untracked |
| `ps_miFinancialSystem` | ok | D A P | tracked |
| `ps_miFinancialSystem_Admin` | ok | D A P | tracked |
| `ps_miHistory_Admin` | ok | · · P | not in repo |
| `ps_miIntegrationSkipDataCheck` | ok | D A P | untracked |
| `ps_miInvoiceCreditCreate` | ok | D A P | untracked |
| `ps_miInvoiceCreditFull` | ok | D A P | untracked |
| `ps_miKickBack` | ok | D A P | untracked |
| `ps_miKnowledgeManager_ps` | ok | D A P | untracked |
| `ps_miLeadIntegrationAdmin` | ok | D A P | untracked |
| `ps_miLeadIntegrationUser` | ok | D A P | untracked |
| `ps_miLightningLoginUser` | ok | · · P | not in repo |
| `ps_miMacroMultipleRecords` | ok | D · P | untracked |
| `ps_miManageCases` | ok | D A P | untracked |
| `ps_miManageCommunicationPreferences` | ok | D · · | not in repo |
| `ps_miMarketingEmailTemplates` | ok | D A P | untracked |
| `ps_miMobileApp` | ok | D · P | untracked |
| `ps_miNotificationAdministrator` | ok | D A P | untracked |
| `ps_miNotificationSupervisor` | ok | D A P | untracked |
| `ps_miOLDFinancialSystem` | ok | D · P | untracked |
| `ps_miOmniChannelMessaging_Admin` | ok | D · · | not in repo |
| `ps_miOperatingHours` | ok | D A P | tracked |
| `ps_miOportunityAllowClosedStageChangeAfterSync` | ok | D A P | untracked |
| `ps_miOportunityAllowSwap` | ok | D A P | untracked |
| `ps_miOportunityManagement` | ok | D A P | untracked |
| `ps_miOpportunityPaymentMethod` | ok | D A P | untracked |
| `ps_miOpportunityPaymentMethod_Change` | ok | D A P | tracked |
| `ps_miOrderChangeStatus` | ok | D A P | untracked |
| `ps_miOrderManagement` | ok | D A P | tracked |
| `ps_miPDF_Butler_Admin` | ok | D A P | untracked |
| `ps_miPDF_Butler_User` | ok | D A P | untracked |
| `ps_miPaymentCheckout` | ok | D A P | tracked |
| `ps_miPaymentCheckoutAdmin` | ok | D A P | tracked |
| `ps_miPaymentProviderStripe` | ok | D A P | untracked |
| `ps_miPayments` | ok | D · · | not in repo |
| `ps_miPlatform1ContactViewEmail` | ok | D A P | tracked |
| `ps_miPlatform1ViewIncidents` | ok | D A P | untracked |
| `ps_miPlatform_1_Sync` | ok | D A P | untracked |
| `ps_miPrices` | ok | D A P | untracked |
| `ps_miProductPricebookEntry_Admin` | ok | D A P | tracked |
| `ps_miProducts` | ok | D A P | tracked |
| `ps_miReadonly` | ok | D A P | untracked |
| `ps_miRelationManagement` | ok | D A P | untracked |
| `ps_miSIGN_Butler_Admin` | ok | D A P | untracked |
| `ps_miSIGN_Butler_User` | ok | D A P | untracked |
| `ps_miSalesDirector` | ok | D A · | untracked |
| `ps_miScheduleDashboardsReports` | ok | D A · | not in repo |
| `ps_miScheduleReportsAndDashboards` | ok | D · P | untracked |
| `ps_miServiceCloudSetup` | ok | D A P | untracked |
| `ps_miServiceCloudVoice` | ok | D · P | tracked |
| `ps_miServiceMarkEmail` | ok | D A P | tracked |
| `ps_miShopActionAdmin` | ok | D · · | not in repo |
| `ps_miSingleSignOnEnabled` | ok | D · P | untracked |
| `ps_miSubscribeDashboardsReports` | ok | D A P | untracked |
| `ps_miSubscription25_User` | ok | D A P | tracked |
| `ps_miSyncFinancialSystem` | ok | D A P | untracked |
| `ps_miTeunTest` | ok | · · · | untracked |
| `ps_miWMFA` | ok | D A P | untracked |
| `sf_devops_InitializeEnvironments` | platform | D A P | untracked |
| `sf_devops_NamedCredentials` | platform | D A P | untracked |
| `sfdcInternalInt__sfdc_a360` | platform | · · · | untracked |
| `sfdcInternalInt__sfdc_a360_sfcrm_data_extract` | platform | · · · | untracked |
| `sfdcInternalInt__sfdc_activityplatform` | platform | · · · | untracked |
| `sfdcInternalInt__sfdc_chatbot` | platform | · · · | untracked |
| `sfdcInternalInt__sfdc_einsteinagent` | platform | · · · | untracked |
| `sfdcInternalInt__sfdc_nc_constraints_engine_deploy` | platform | · · · | untracked |
| `sfdcInternalInt__sfdc_scrt2` | platform | · · · | untracked |
| `sfdc_aiplanner_service_permset` | platform | D A P | untracked |
| `sflabs_cms_ct__CMS_Content_Types` | platform | · · · | untracked |

## Permission set groups
| Name | Naming | dev / acc / prod | Repo |
|---|---|---|---|
| `force__CopilotSalesforceAdminPSG` | platform | · · · | untracked |
| `force__CopilotSalesforceUserPSG` | platform | · · · | untracked |
| `force__PartnerCloudChannelManagerPsg` | platform | · · · | untracked |
| `force__PartnerCloudPartnerUserPsg` | platform | · · · | untracked |
| `force__PartnerEmailAndFlowAccessPsg` | platform | · · · | untracked |
| `force__SalesCloudCallCoachingSeller` | platform | · · · | untracked |
| `force__SalesCloudSeller` | platform | · · · | untracked |
| `force__SalesWorkspacePSG` | platform | · · · | untracked |
| `force__ScaleCenterUsers` | platform | · · · | untracked |
| `force__UnifiedCatalogAdminPsl` | platform | · · · | untracked |
| `force__UnifiedCatalogAgentPsl` | platform | · · · | untracked |
| `force__UnifiedCatalogCommunityUserPsl` | platform | · · · | untracked |
| `pg_AccountRelationType` | rename? | D A P | untracked |
| `pg_CCC_User` | rename? | D A · | tracked |
| `pg_CCC_User_NL` | rename? | D A · | tracked |
| `pg_Finance_NL` | rename? | D A · | tracked |
| `pg_Pardot` | rename? | D A · | not in repo |
| `pg_PardotEmail` | rename? | D A · | not in repo |
| `pg_Platform_1_Access` | rename? | D A P | untracked |
| `pg_Sales1` | rename? | D A · | untracked |
| `pg_Subscription25Admin` | rename? | D A P | tracked |
| `pg_Subscription25User` | rename? | D A P | tracked |
| `pg_Subscription25View` | rename? | D A P | tracked |
| `pg_miAPIAmazonIntegration` | ok | D A P | untracked |
| `pg_miAPIArchiveIntegration` | ok | D A P | untracked |
| `pg_miAPIBackUpIntegration` | ok | D A P | untracked |
| `pg_miAPIBussinesAnalyticsIntegration` | ok | D A P | untracked |
| `pg_miAPILeadIntegration` | ok | D A P | untracked |
| `pg_miAPIPlatformIntegration` | ok | D A P | tracked |
| `pg_miAPIPwrBAIntegration` | ok | D A · | not in repo |
| `pg_miAPIShopIntegration` | ok | D A P | untracked |
| `pg_miAPI_Dioro_Licence_Analytics` | ok | · · P | not in repo |
| `pg_miCustomerHub` | ok | D A P | tracked |
| `pg_miDealerPortal` | ok | D A P | tracked |
| `pg_miDevOpsCenter_Full` | ok | · A P | untracked |
| `pg_miFinance` | ok | · · P | not in repo |
| `pg_miFinance_NL` | ok | · · P | not in repo |
| `pg_miSales` | ok | D A P | tracked |
| `pg_miSales1` | ok | · · P | not in repo |
| `pg_miSalesDirector` | ok | D A · | not in repo |
| `pg_miSupport` | ok | · · P | not in repo |
| `pg_miSupport_NL` | ok | · · P | not in repo |
| `pg_miWorkSpace` | ok | D A P | untracked |
