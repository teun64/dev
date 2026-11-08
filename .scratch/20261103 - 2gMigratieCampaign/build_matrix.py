"""Rebuild the 2G matrix (v5 + Total columns) from prod.

1. Export (prod, read-only):
   sf data export bulk -o prod --result-format csv --wait 10 --output-file <scratch>/eu.csv --query \
   "SELECT Id, AccountId, Account.RecordType.DeveloperName, Account.BillingCountryCode, Base_Product__r.Family, \
    Hardware__c, Hardware__r.Product2.Name, Hardware__r.Hardware_Type__c, Hardware__r.Modem__c \
    FROM Contract WHERE Status='Activated' AND Active__c=true AND Account.Relation_type__c='End User'"
2. python3 build_matrix.py <scratch>/eu.csv "2G_matrix_hardware.xlsx"

Rules: Teltonika excluded; contracts without hardware product excluded; 2G = Modem__c '1' or empty;
account in scope when >=1 in-scope contract is 2G; B2C/B2B = Account record type;
B2B 1-2 vs 3+ on all in-scope active contracts of the account.
"""
import csv, collections, sys
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter

src, out = sys.argv[1], sys.argv[2]
LABEL = {'Mi50': 'Mi50', 'Mi40': 'Mi40', 'MiTracer': 'Mi01', 'MiRetreever': 'Mi04 (MiRetreever)'}
G = ['Mi50', 'Mi40', 'Mi01', 'Mi04 (MiRetreever)', 'Beacon']
G2 = G + ['Total']
B = ['B2C', 'B2B (1-2)', 'B2B (3+)']


def grp(x):
    p = x['Hardware__r.Product2.Name']
    if not p or 'Teltonika' in p:
        return None
    return LABEL.get(p, 'Beacon')


is2 = lambda x: x['Hardware__r.Modem__c'] in ('1', '')
acc = collections.defaultdict(list)
for x in csv.DictReader(open(src)):
    g = grp(x)
    if g:
        acc[x['AccountId']].append((g, x))
tgt = {a: v for a, v in acc.items() if any(is2(x) for _, x in v)}

A, S, T = (collections.defaultdict(collections.Counter) for _ in range(3))
for v in tgt.values():
    n = len(v)
    b = 'B2C' if v[0][1]['Account.RecordType.DeveloperName'] == 'B2C' else ('B2B (1-2)' if n <= 2 else 'B2B (3+)')
    c = v[0][1]['Account.BillingCountryCode'] or '(empty)'
    for g in G2:
        sub = [x for gg, x in v if gg == g or g == 'Total']
        if any(is2(x) for x in sub):
            A[c][(g, b)] += 1
            S[c][(g, b)] += len(sub)
            T[c][(g, b)] += sum(is2(x) for x in sub)

fm = lambda a, s, t: f"{a:,} ({s:,} / {t:,})" if a else '0'
wb = Workbook()
ws = wb.active
ws.title = '2G matrix'
ws['A1'] = '2G accounts per hardware type — End User, active subscription, modem 2G only or empty'
ws['A1'].font = Font(bold=True, size=12)
ws['A2'] = 'Cell = accounts (active subscriptions on that hardware / of which 2G). Total row = unique accounts. Teltonika excluded.'
hdr = PatternFill('solid', fgColor='DDEBF7')
ws.cell(4, 1, 'Country').font = Font(bold=True)
for gi, g in enumerate(G2):
    c0 = 2 + gi * 4
    ws.merge_cells(start_row=4, start_column=c0, end_row=4, end_column=c0 + 3)
    cell = ws.cell(4, c0, g)
    cell.font, cell.fill, cell.alignment = Font(bold=True), hdr, Alignment(horizontal='center')
    for bi, b in enumerate(B + ['Total']):
        cell = ws.cell(5, c0 + bi, b)
        cell.font, cell.fill, cell.alignment = Font(bold=True), hdr, Alignment(horizontal='center')

countries = sorted(A, key=lambda k: -sum(v for kk, v in A[k].items() if kk[0] == 'Total'))
tot = [collections.Counter() for _ in range(3)]
for c in countries:
    for i, d in enumerate((A, S, T)):
        tot[i] += d[c]
rows = [(c, A[c], S[c], T[c]) for c in countries] + [('Total', *tot)]
for ri, (c, a, s, t) in enumerate(rows):
    r = 6 + ri
    ws.cell(r, 1, c).font = Font(bold=(c == 'Total'))
    for gi, g in enumerate(G2):
        vals = [(a[(g, b)], s[(g, b)], t[(g, b)]) for b in B]
        vals.append(tuple(map(sum, zip(*vals))))
        for bi, v in enumerate(vals):
            cell = ws.cell(r, 2 + gi * 4 + bi, fm(*v))
            cell.alignment = Alignment(horizontal='right')
            cell.font = Font(bold=(c == 'Total' or bi == 3))
ws.column_dimensions['A'].width = 10
for i in range(2, 2 + len(G2) * 4):
    ws.column_dimensions[get_column_letter(i)].width = 22
ws.freeze_panes = 'B6'
wb.save(out)
print('accounts', len(tgt))
