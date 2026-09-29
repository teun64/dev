# Usage: python3 address_migration.py <org> <workdir> [--apply]
# Account: Invoice := Billing (or Visiting when Billing empty); Billing := Visiting;
#          useInvoiceAddress := useBillingAddress OR Invoice <> new Billing;
#          FinancialIdInvoiceAddress := FinancialIdBillingAddress; FinancialIdBillingAddress := FinancialIdVisitingAddress
# Debtor/Historic: Exact_Invoice_Address_ID := Exact_Billing_Address_ID; Exact_Billing_Address_ID := Exact_Visiting_Address_ID (or empty)
import csv,subprocess,sys,os,json,collections,re,unicodedata
def norm(v): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',(v or '')).lower())
org,wd=sys.argv[1],sys.argv[2]; apply='--apply' in sys.argv; os.makedirs(wd,exist_ok=True)
def export(name,soql):
    f=os.path.join(wd,f'{org}_{name}.csv')
    r=subprocess.run(['sf','data','export','bulk','-o',org,'--query',soql,'--output-file',f,'--result-format','csv','--wait','30'],capture_output=True,text=True)
    if r.returncode: sys.exit(r.stderr[-500:])
    return list(csv.DictReader(open(f,encoding='utf-8')))
def fields(obj):
    r=subprocess.run(['sf','sobject','describe','-o',org,'-s',obj,'--json'],capture_output=True,text=True); return {f['name'] for f in json.loads(r.stdout)['result']['fields']}
def update(name,obj,header,rows):
    f=os.path.join(wd,f'{org}_{name}_update.csv')
    with open(f,'w',newline='',encoding='utf-8') as h:
        w=csv.writer(h,lineterminator='\n'); w.writerow(header); w.writerows(rows)
    print(f'{obj}: {len(rows)} rows -> {f}')
    if apply and rows:
        r=subprocess.run(['sf','data','update','bulk','-o',org,'-s',obj,'--file',f,'--wait','120','--line-ending','LF','--json'],capture_output=True,text=True)
        try: res=json.loads(r.stdout).get('result',{}); print('  applied:',{k:res.get(k) for k in ('processedRecords','successfulRecords','failedRecords')})
        except Exception: print(r.stdout[-800:],r.stderr[-400:])
N=lambda v: v if v not in (None,'') else '#N/A'
parts=['Street','City','PostalCode','CountryCode','StateCode']
af=fields('Account'); hasFV='FinancialIdVisitingAddress__c' in af
acc=export('accounts','SELECT Id, useBillingAddress__c, BillingStreet, BillingCity, BillingPostalCode, BillingCountryCode, BillingStateCode, VisitingAddress__Street__s, VisitingAddress__City__s, VisitingAddress__PostalCode__s, VisitingAddress__CountryCode__s, VisitingAddress__StateCode__s, FinancialIdBillingAddress__c, InvoiceAddress__Street__s, InvoiceAddress__City__s, InvoiceAddress__PostalCode__s'+(', FinancialIdVisitingAddress__c' if hasFV else '')+' FROM Account')
stats=collections.Counter(); rows=[]
for a in acc:
    # idempotent: an Account that already has an invoice address was migrated before - never recalculate it
    if any(a.get(f'InvoiceAddress__{p}__s') for p in ('Street','City','PostalCode')): stats['alreadyMigrated']+=1; continue
    bill={p:a['Billing'+p] for p in parts}; vis={p:a[f'VisitingAddress__{p}__s'] for p in parts}
    same=all(norm(bill[p])==norm(vis[p]) for p in parts)
    useOld=a['useBillingAddress__c'].lower()=='true'
    # real separate invoice address: checkbox was on, or Billing really differs (not only formatting) -> keep old Billing
    use=any(bill.values()) and (useOld or not same)
    inv=bill if use else vis
    stats['useInvoice' if use else 'sameAsBilling']+=1; stats['drift']+= (not useOld and any(bill.values()) and not same)
    stats['finIdMoved']+=bool(a['FinancialIdBillingAddress__c'])
    rows.append([a['Id']]+[N(inv[p]) for p in parts]+[N(vis[p]) for p in parts]+[str(use).lower(), N(a['FinancialIdBillingAddress__c']), N(a.get('FinancialIdVisitingAddress__c',''))])
print(org,'accounts',len(acc),dict(stats))
update('accounts','Account',['Id']+[f'InvoiceAddress__{p}__s' for p in parts]+['Billing'+p for p in parts]+['useInvoiceAddress__c','FinancialIdInvoiceAddress__c','FinancialIdBillingAddress__c'],rows)
for obj,name in (('Subscription25__Debtor_Number__c','debtors'),('Historic_Debtor_Number__c','historic')):
    fs=fields(obj); hv='Exact_Visiting_Address_ID__c' in fs
    recs=export(name,f'SELECT Id, Exact_Billing_Address_ID__c'+(', Exact_Visiting_Address_ID__c' if hv else '')+f' FROM {obj} WHERE Exact_Invoice_Address_ID__c = null AND (Exact_Billing_Address_ID__c != null'+(' OR Exact_Visiting_Address_ID__c != null' if hv else '')+')')
    update(name,obj,['Id','Exact_Invoice_Address_ID__c','Exact_Billing_Address_ID__c'],[[r['Id'],N(r['Exact_Billing_Address_ID__c']),N(r.get('Exact_Visiting_Address_ID__c',''))] for r in recs])
