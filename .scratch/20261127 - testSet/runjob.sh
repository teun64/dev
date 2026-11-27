#!/bin/bash
# usage: runjob.sh <org> <JobName>   (browser session must be open on the org's package JobManagement page; see README)
ORG=$1; JOB=$2
playwright-cli eval "() => { const rows=[...document.querySelectorAll('tr.dataRow')]; const r=rows.find(x=>[...x.querySelectorAll('a')].some(a=>a.textContent.trim()==='$JOB')); const a=[...r.querySelectorAll('a')].find(a=>a.textContent.trim()==='Run Now'); a.click(); return 'clicked'; }" >/dev/null 2>&1
sleep 6
for i in $(seq 1 60); do
  N=$(sf data query -o $ORG -q "SELECT COUNT(Id) c FROM AsyncApexJob WHERE Status IN ('Queued','Processing','Preparing','Holding') AND CreatedDate = TODAY" --json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['result']['records'][0]['c'])" 2>/dev/null)
  [ "$N" = "0" ] && break; sleep 10
done
echo "$JOB done (open async jobs: $N)"
