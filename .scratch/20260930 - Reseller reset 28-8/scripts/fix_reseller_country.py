"""Restore Reseller_Name__c and set the correct country on accounts hit by the 2026-08-28 reset.
Usage: python3 fix_reseller_country.py <org> [AccountId ...]   (no ids = all rows with Action=fix)
Pass 1 sets BillingCountryCode (+Visiting/Shipping/Invoice); rbb_Account (prod v63) derives the reseller from it.
Pass 2 sets Reseller_Name__c explicitly where the flow result differs (BE -> flow gives 1, should be 3).
Chunks of 5: the WSONE_DATA trigger hits the CPU limit above ~5 address changes per transaction."""
import csv, json, subprocess, sys, os, urllib.request, urllib.parse, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
org = sys.argv[1]
only = set(sys.argv[2:])

def call(method, path, body=None):
    # sf CLI handles auth; the script never touches the access token
    args = ["sf", "api", "request", "rest", "/services/data/v66.0" + path, "--method", method, "-o", org]
    if body is not None:
        args += ["--body", "-"]
    out = subprocess.run(args, input=json.dumps(body) if body is not None else None, capture_output=True, text=True)
    txt = out.stdout
    start = min([i for i in (txt.find('['), txt.find('{')) if i >= 0])
    return json.loads(txt[start:])


rows = [r for r in csv.DictReader(open(BASE + '/affected_accounts.csv'))
        if r['Action'] == 'fix' and (not only or r['AccountId'] in only)]
log = open(BASE + f'/run_{org}_{datetime.datetime.now():%Y%m%d_%H%M%S}.csv', 'w', newline='')
w = csv.writer(log)
w.writerow(['pass', 'AccountId', 'Name', 'values', 'success', 'errors'])


def patch(passname, recs):
    for i in range(0, len(recs), 5):
        chunk = recs[i:i + 5]
        res = call('PATCH', '/composite/sobjects',
                   {'allOrNone': False, 'records': [dict(attributes={'type': 'Account'}, **v) for _, v in chunk]})
        for (r, v), s in zip(chunk, res):
            w.writerow([passname, r['AccountId'], r['Name'], json.dumps(v), s['success'],
                        '; '.join(e['message'] for e in s.get('errors', []))])
            if not s['success']:
                print('FAIL', passname, r['Name'], s['errors'])
        log.flush()


c = 'Target_Country'
p1 = [(r, {'Id': r['AccountId'], 'BillingCountryCode': r[c], 'VisitingAddress__CountryCode__s': r[c],
           'ShippingCountryCode': r[c], 'InvoiceAddress__CountryCode__s': r[c]}) for r in rows]
patch('1-country', p1)
print('pass 1 done', len(p1))

cur = {}
ids = [r['AccountId'] for r in rows]
for i in range(0, len(ids), 200):
    q = "SELECT Id, Reseller_Name__c FROM Account WHERE Id IN ('" + "','".join(ids[i:i + 200]) + "')"
    for x in call('GET', '/query?q=' + urllib.parse.quote(q))['records']:
        cur[x['Id']] = x['Reseller_Name__c']
p2 = [(r, {'Id': r['AccountId'], 'Reseller_Name__c': r['Reseller_Before_28_8']})
      for r in rows if cur.get(r['AccountId']) != r['Reseller_Before_28_8']]
patch('2-reseller', p2)
print('pass 2 done', len(p2))
log.close()
