# Account roles – prod package – DEPLOYED 2026-10-15 09:15 UTC (user: yes)

Quick deploy `0AfTx0000013IUTKA2` (9/9); rab_AccountContactRelation_Roles deactivated right after (was v2; afl_ stays active but is only its subflow).

Contents (9, from commits 5ac2c98..833c9fa; prod versions checked = the bases, nothing prod-only overwritten):
- `Rest_UpsertAccount` + `Test_Rest_UpsertAccount` – platform updates no longer strip roles (platformRoles rules).
- `Svc_AccountContactRelationRoles` + test, `Trigger_AccountContactRelation`, trigger `AccountContactRelation`
  (before delete, after insert, after update) – one owner per role per account in Apex, replaces the roles flow.
- `Test_Svc_FinancialSystemContactRemoval` – flag reset after contact creation.
- `Util_FinancialSystemAccount` + test – the account sync writes only its own relation fields (no stale Roles).

Validation: `0AfTx0000013ISrKAM` – Succeeded, 9/9, 80/80 (Test_Rest_UpsertAccount, Test_Svc_AccountContactRelationRoles,
Test_Svc_FinancialSystemContactRemoval, Test_Util_FinancialSystemAccount, Test_Batches_FinancialSystem,
Test_Svc_FinancialSystemSyncAlert). Coverage: Svc 90%, Rest_UpsertAccount 82%, Trigger handler 86%, trigger 100%,
Util_FinancialSystemAccount 86%.

Go-live (only on the user's explicit go), back to back:
1. `sf project deploy quick -o prod --job-id 0AfTx0000013ISrKAM --wait 30` (valid ~10 days)
2. Immediately: deactivate rab_AccountContactRelation_Roles (FlowDefinition 300bR00000tndv4QAA, active v2):
   `sf api request rest "/services/data/v67.0/tooling/sobjects/FlowDefinition/300bR00000tndv4QAA" --method PATCH --body '{"Metadata":{"activeVersionNumber":0}}' -o prod`
   (between 1 and 2 both the flow and the Apex act on role changes – keep it seconds)
3. Check: FlowDefinition active version empty; one real platform call afterwards (Event_Log RestUpsertAccount) →
   roles per the rules, Sales/Service/ASR untouched, lookups on the owners.
Rollback: reactivate rab v2 + redeploy the previous Rest_UpsertAccount / trigger (prod copies in the session scratchpad
`rolesprod/p`, = the base commits).
After go-live: backfill of the 72,952 relations (separate, skip contacts without email).
