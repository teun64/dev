# Usage: python3 status_backfill.py <org> <workdir> [--apply]
# Priority: bankrupt > blocked > deactivated > active
import csv, subprocess, sys, os, collections
org, wd = sys.argv[1], sys.argv[2]; apply = '--apply' in sys.argv
os.makedirs(wd, exist_ok=True)
src = os.path.join(wd, f'{org}_accounts.csv')
subprocess.run(['sf','data','export','bulk','-o',org,'--query',
    'SELECT Id, IsBankrupt__c, Is_Blocked__c, Deactivated__c, Status__c FROM Account',
    '--output-file',src,'--result-format','csv','--wait','30'],check=True,capture_output=True)
t = lambda v: str(v).lower() == 'true'
def target(r):
    if t(r['IsBankrupt__c']): return 'bankrupt'
    if t(r['Is_Blocked__c']): return 'blocked'
    if t(r['Deactivated__c']): return 'deactivated'
    return 'active'
rows = list(csv.DictReader(open(src)))
dist = collections.Counter(target(r) for r in rows)
changes = [(r['Id'], target(r)) for r in rows if r['Status__c'] != target(r)]
print(org, 'total', len(rows), 'target', dict(dist), 'to update', len(changes))
out = os.path.join(wd, f'{org}_status_update.csv')
with open(out,'w',newline='') as f:
    w = csv.writer(f, lineterminator='\n'); w.writerow(['Id','Status__c']); w.writerows(changes)
if apply and changes:
    r = subprocess.run(['sf','data','update','bulk','-o',org,'-s','Account','--file',out,'--wait','120','--line-ending','LF'],capture_output=True,text=True)
    print(r.stdout[-1500:], r.stderr[-800:])
