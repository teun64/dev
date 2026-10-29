#!/usr/bin/env python3
"""Backfill Opportunity.Sales_Contact__c (the offer PDF signer) for opportunities created this year
or last year where it is empty: the account's active Main role contact (AccountContactRelation,
isMainContact__c, newest LastModifiedDate) - the same rule rbc/rbu_Opportunity apply since 2026-10-29.

Usage (from this folder):
  python3 backfill.py <org>            dry run: writes plan.csv + before.csv, changes nothing
  python3 backfill.py <org> --apply    bulk update, then after.csv, changed_fields.csv, failures

The update also runs rbu/rau_Opportunity, so key fields are snapshotted before and after and every
difference other than Sales_Contact__c is listed in changed_fields.csv.
"""
import csv, json, os, subprocess, sys

ORG = sys.argv[1]
APPLY = '--apply' in sys.argv
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'run_' + ORG)
os.makedirs(OUT, exist_ok=True)

SNAPSHOT_FIELDS = ['Id', 'Name', 'AccountId', 'StageName', 'Amount', 'CloseDate', 'Pricebook2Id', 'OwnerId',
                   'isAccountFinancialReady__c', 'Payment_Method__c', 'Payment_Reference__c',
                   'Payment_Amount_Gross__c', 'Administration__c', 'Sales_Contact__c']
WHERE = "(CreatedDate = THIS_YEAR OR CreatedDate = LAST_YEAR) AND Sales_Contact__c = null AND AccountId != null"


def sf(*args):
    r = subprocess.run(['sf', *args, '--json'], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except ValueError:
        sys.exit('sf failed: ' + r.stdout[-2000:] + r.stderr[-2000:])


def export(query, path):
    res = sf('data', 'export', 'bulk', '-o', ORG, '--query', query, '--output-file', path,
             '--result-format', 'csv', '--wait', '30')
    if res.get('status') != 0:
        sys.exit('export failed: ' + json.dumps(res)[:2000])
    with open(path, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


opps = export(f"SELECT {', '.join(SNAPSHOT_FIELDS)} FROM Opportunity WHERE {WHERE}", f'{OUT}/before.csv')
acrs = export("SELECT AccountId, ContactId, LastModifiedDate FROM AccountContactRelation "
              "WHERE IsActive = true AND isMainContact__c = true", f'{OUT}/main_contacts.csv')

main = {}
for a in sorted(acrs, key=lambda r: r['LastModifiedDate']):
    main[a['AccountId']] = a['ContactId']          # newest wins

plan = [{'Id': o['Id'], 'Sales_Contact__c': main[o['AccountId']]} for o in opps if o['AccountId'] in main]
with open(f'{OUT}/plan.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['Id', 'Sales_Contact__c'], lineterminator='\n')
    w.writeheader(); w.writerows(plan)
print(f'{ORG}: {len(opps)} opportunities without Sales Contact, {len(plan)} have a Main contact, '
      f'{len(opps) - len(plan)} have none (stay empty, the formula falls back to Contact_person__c)')

if not APPLY:
    print(f'dry run - nothing changed. Files in {OUT}')
    sys.exit(0)
if not plan:
    sys.exit(0)

res = sf('data', 'update', 'bulk', '-o', ORG, '--sobject', 'Opportunity', '--file', f'{OUT}/plan.csv', '--wait', '60')
json.dump(res, open(f'{OUT}/update_result.json', 'w'), indent=1)
r = res.get('result', {})
print('bulk update:', res.get('status'), 'processed', r.get('processedRecords'), 'failed', r.get('failedRecords'),
      'job', (r.get('jobInfo') or {}).get('id'))
job = (r.get('jobInfo') or {}).get('id')
if job and r.get('failedRecords'):
    # writes <job>-failed-records.csv (with sf__Error) into the run folder
    subprocess.run(['sf', 'data', 'bulk', 'results', '-o', ORG, '--job-id', job], cwd=OUT)

ids = [p['Id'] for p in plan]
after = []
for i in range(0, len(ids), 300):
    chunk = "','".join(ids[i:i + 300])
    q = sf('data', 'query', '-o', ORG, '-q',
           f"SELECT {', '.join(SNAPSHOT_FIELDS)} FROM Opportunity WHERE Id IN ('{chunk}')")
    after += q['result']['records']
before = {o['Id']: o for o in opps}
diffs = []
for a in after:
    b = before[a['Id']]
    for f in SNAPSHOT_FIELDS:
        if f == 'Sales_Contact__c':
            continue
        bv, av = (b.get(f) or ''), ('' if a.get(f) is None else str(a.get(f)))
        if f in ('Amount', 'Payment_Amount_Gross__c'):
            bv, av = (str(float(bv)) if bv else ''), (str(float(av)) if av else '')
        if f == 'isAccountFinancialReady__c':
            bv, av = bv.lower(), av.lower()
        if bv != av:
            diffs.append({'Id': a['Id'], 'Name': a['Name'], 'field': f, 'before': bv, 'after': av})
filled = sum(1 for a in after if a.get('Sales_Contact__c'))
with open(f'{OUT}/changed_fields.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['Id', 'Name', 'field', 'before', 'after'], lineterminator='\n')
    w.writeheader(); w.writerows(diffs)
print(f'after: {filled}/{len(plan)} filled; {len(diffs)} other field changes (changed_fields.csv)')
