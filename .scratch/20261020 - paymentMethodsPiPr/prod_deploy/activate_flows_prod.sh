#!/bin/bash
# Activate the latest version of the flows from the pi/pr + EN16931 prod deploy (prod deploys flows as Draft).
# Only activates when the latest version is newer than the active one.
cd /Users/teun/MVSC/dev
for f in rac_Order rbb_Payment rab_Payment_Direct_Debit_Setup afl_PaymentDirectDebitSetup_SendMail rbb_OrderItem; do
  read -r id active latest < <(sf data query -o prod --use-tooling-api -q "SELECT Id, ActiveVersion.VersionNumber, LatestVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName='$f'" --json 2>/dev/null \
    | python3 -c "import json,sys;r=json.load(sys.stdin)['result']['records'][0];print(r['Id'],(r['ActiveVersion'] or {}).get('VersionNumber'),(r['LatestVersion'] or {}).get('VersionNumber'))")
  if [ "$active" = "$latest" ]; then echo "$f: already active v$active"; continue; fi
  sf data update record -o prod --use-tooling-api -s FlowDefinition -i "$id" -v "Metadata='{\"activeVersionNumber\":$latest}'" >/dev/null 2>&1 \
    && echo "$f: v$active -> v$latest activated" || echo "$f: ACTIVATION FAILED (v$latest)"
done
