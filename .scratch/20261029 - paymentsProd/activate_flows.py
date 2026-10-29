# Activate the flow versions created by the payments deploy 2026-10-29 (prod deploys flows as Draft).
# Only versions created by this user after SINCE are activated; prints before/after.
import json,subprocess,sys
org='prod'; SINCE=sys.argv[1]  # e.g. 2026-09-29T17:00:00Z
flows=['rbb_Payment','rbu_Subscription25_Invoice_c','rbb_Order','rab_Payment_Action_Required','rau_Subscription25_Invoice_c_Due_Date_Payment']
def q(s): r=subprocess.run(['sf','data','query','-o',org,'--use-tooling-api','-q',s,'--json'],capture_output=True,text=True); return json.loads(r.stdout)['result']['records']
for f in flows:
    d=q(f"SELECT Id, ActiveVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName='{f}'")[0]
    v=q(f"SELECT VersionNumber, Status, CreatedDate FROM Flow WHERE Definition.DeveloperName='{f}' AND CreatedDate > {SINCE} ORDER BY VersionNumber DESC LIMIT 1")
    before=(d.get('ActiveVersion') or {}).get('VersionNumber')
    if not v: print(f'{f:<48} active {before} (no new version, unchanged)'); continue
    n=v[0]['VersionNumber']
    if before==n: print(f'{f:<48} active {before} (already the new version)'); continue
    body=json.dumps({'Metadata':{'activeVersionNumber':n}})
    r=subprocess.run(['sf','api','request','rest',f"/services/data/v67.0/tooling/sobjects/FlowDefinition/{d['Id']}",'--method','PATCH','--body',body,'-o',org],capture_output=True,text=True)
    after=(q(f"SELECT ActiveVersion.VersionNumber FROM FlowDefinition WHERE Id='{d['Id']}'")[0].get('ActiveVersion') or {}).get('VersionNumber')
    print(f'{f:<48} {before} -> {after}' + ('' if after==n else '  !! NOT ACTIVATED: '+r.stdout.strip()[:200]))
