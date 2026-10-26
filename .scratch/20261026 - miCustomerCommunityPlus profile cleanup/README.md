# miCustomerCommunityPlus profile cleanup (dev, 2026-10-26)

Goal: one generic Experience Cloud base profile without object access; the dealer access is in pg_DealerPortal (see the 3-profile target model).

- Before: the profile had 14 ObjectPermissions and 2,648 FieldPermissions in dev (clone leftovers: Account/Contact/Contract read, Seller/SurveyResponse edit, FLS on ~130 objects).
- The Dealer Portal does not need them: the dealer LWCs only call Ctrl_DealerPortal / Ctrl_DealerShop (Authenticated_DealerPortal), and all their SOQL/DML is SYSTEM_MODE.
- All 2,648 FieldPermissions and 14 ObjectPermissions on the profile PermissionSet (0PSbd000000tacLGAQ) were deleted via the Data API. SurveyInvitation has to go before Survey (dependency).
- Kept on the profile (profile-only or harmless): 4 userPermissions (AccessOrchestrationObjects, EnableNotifications, SelectFilesFromSalesforce, ShareFilesWithNetworks), 4 recordTypeVisibilities, 6 app visibilities.
- The repo profile file had no FLS or object permissions, so it is unchanged.
- New: pg_DealerPortal (Authenticated_DealerPortal). Svc_DealerUserSetup assigns the group instead of the permission set.
- Dealer Portal membership: Authenticated_DealerPortal added as a member (NetworkMemberGroup 0DLbd0000002gj7GAA).
- The dev dealer user (005bd00000O2tNeAAJ) has the group instead of the direct permission set assignment (0Pabd00000ZSOfxCAH deleted).

Open:
- Remove the miCustomerCommunityPlus profile as a Dealer Portal member. This only works in the Setup UI (Digital Experiences → Dealer Portal → Administration → Members).
- Then log in as the dev dealer user and check whether membership through a permission set inside a group works. If not, Svc_DealerUserSetup also assigns Authenticated_DealerPortal directly.

Rollback: insert profile_fls_backup.csv / profile_obj_backup.csv again (ParentId, SobjectType, Field, permissions) on 0PSbd000000tacLGAQ. Insert the ObjectPermissions first.
