"""2G hardware export (platform 1). Input: bulk CSV of active End User contracts with System_Platform__c='1'
and hardware Modem__c '1' or empty (query in RUNBOOK). Usage: build_export.py <in.csv> <out.csv> [limit] [offset]
Corrected type = same grouping as matrix v5 (Mi50/Mi40/Mi01/Mi04 (MiRetreever)/Beacon); Teltonika + no hardware product dropped.
ExtIds stripped of platform suffix (-hw-1 / -in-1 / -1). Sorted by First Installation Date, newest first."""
import csv, re, sys
strip = lambda v, suf: re.sub(re.escape(suf) + '$', '', v)
LABEL = {'Mi50': 'Mi50', 'Mi40': 'Mi40', 'MiTracer': 'Mi01', 'MiRetreever': 'Mi04 (MiRetreever)'}
src, out = sys.argv[1], sys.argv[2]
lim = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != '0' else None
off = int(sys.argv[4]) if len(sys.argv) > 4 else 0
rows = []
for x in csv.DictReader(open(src)):
    p = x['Hardware__r.Product2.Name']
    if not p or 'Teltonika' in p:
        continue
    ht = x['Hardware__r.Hardware_Type__c']
    rows.append({
        'Hardware ExtId': strip(x['Hardware__r.extId__c'], '-hw-1'),
        'Hardware Type': ht[:-2] if ht.endswith('.0') else ht,
        'Hardware Product': p,
        'Corrected Type': LABEL.get(p, 'Beacon'),
        'Modem': x['Hardware__r.Modem__c'] or '(empty)',
        'First Installation Date': x['Hardware__r.First_Installation_Date__c'][:10],
        'Entity ExtId': strip(x['Entity__r.extId__c'], '-in-1'),
        'Entity Name': x['Entity__r.Name'],
        'Account extId_1__c': x['Account.extId_1__c'],
        'Debtor Number': x['Account.FinancialDebtorNumber__c'],
        'Account Name': x['Account.Name'],
        'B2C/B2B': x['Account.RecordType.DeveloperName'],
        'Contract ExtId': strip(x['extId__c'], '-1'),
        'Base Product': x['Base_Product__r.Name'],
    })
rows.sort(key=lambda r: r['First Installation Date'], reverse=True)
rows = rows[off:off + lim] if lim else rows[off:]
with open(out, 'w', newline='', encoding='utf-8-sig') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]), delimiter=';')
    w.writeheader(); w.writerows(rows)
print(len(rows), 'rows ->', out)
