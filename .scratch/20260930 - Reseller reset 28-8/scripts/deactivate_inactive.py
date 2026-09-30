"""Set Status__c = 'deactivated' on the reset accounts that are active now, except the
'closed won, no active contract' group (kept for investigation).
Usage: python3 deactivate_inactive.py <org>
Reads the live status first; writes a before-snapshot and a run log next to the csv files."""
import csv, json, subprocess, sys, os, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
org = sys.argv[1]
KEEP = 'closed won, no active contract'


def call(method, path, body=None):
    # sf CLI handles auth; the script never touches the access token
    args = ["sf", "api", "request", "rest", "/services/data/v66.0" + path, "--method", method, "-o", org]
    if body is not None:
        args += ["--body", "-"]
    out = subprocess.run(args, input=json.dumps(body) if body is not None else None, capture_output=True, text=True)
    txt = out.stdout
    start = min([i for i in (txt.find('['), txt.find('{')) if i >= 0])
    return json.loads(txt[start:])


def query(soql):
    o = subprocess.run(["sf", "data", "query", "-o", org, "-q", soql, "--json"], capture_output=True, text=True).stdout
    return json.loads(o[o.index('{'):])['result']['records']


rows = [r for r in csv.DictReader(open(BASE + '/affected_accounts_activity.csv')) if r['Category'] != KEEP]
live = {}
ids = [r['AccountId'] for r in rows]
for i in range(0, len(ids), 200):
    for x in query("SELECT Id, Status__c FROM Account WHERE Id IN ('" + "','".join(ids[i:i + 200]) + "')"):
        live[x['Id']] = x['Status__c']

stamp = f'{datetime.datetime.now():%Y%m%d_%H%M%S}'
with open(BASE + f'/deactivate_before_{org}_{stamp}.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['AccountId', 'Name', 'Category', 'Status_Before'])
    for r in rows:
        w.writerow([r['AccountId'], r['Name'], r['Category'], live.get(r['AccountId'])])

todo = [r for r in rows if live.get(r['AccountId']) == 'active']
print('candidates', len(rows), 'active now', len(todo))
log = open(BASE + f'/deactivate_run_{org}_{stamp}.csv', 'w', newline='')
w = csv.writer(log)
w.writerow(['AccountId', 'Name', 'Category', 'success', 'errors'])
fails = 0
for i in range(0, len(todo), 50):
    chunk = todo[i:i + 50]
    res = call('PATCH', '/composite/sobjects', {'allOrNone': False, 'records': [
        {'attributes': {'type': 'Account'}, 'Id': r['AccountId'], 'Status__c': 'deactivated'} for r in chunk]})
    for r, s in zip(chunk, res):
        err = '; '.join(e['message'] for e in s.get('errors', []))
        w.writerow([r['AccountId'], r['Name'], r['Category'], s['success'], err])
        if not s['success']:
            fails += 1
            print('FAIL', r['Name'], err)
    log.flush()
log.close()
print('done', len(todo), 'failures', fails)
