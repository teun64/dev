# Usage: python3 backfill_ext.py <org> <workdir>  -> extStatus_N__c = active where extId_N__c is filled and extStatus_N__c is empty
import csv,subprocess,sys,os,json
org,wd=sys.argv[1],sys.argv[2]; os.makedirs(wd,exist_ok=True)
src=os.path.join(wd,f'{org}_ext.csv')
flds=', '.join(f'extId_{n}__c, extStatus_{n}__c' for n in range(1,7))
cond=' OR '.join(f'(extId_{n}__c != null AND extStatus_{n}__c = null)' for n in range(1,7))
r=subprocess.run(['sf','data','export','bulk','-o',org,'--query',f'SELECT Id, {flds} FROM Account WHERE {cond}','--output-file',src,'--result-format','csv','--wait','30'],capture_output=True,text=True)
rows=list(csv.DictReader(open(src,encoding='utf-8')))
out=os.path.join(wd,f'{org}_ext_update.csv'); cnt=[0]*7
with open(out,'w',newline='') as f:
    w=csv.writer(f,lineterminator='\n'); w.writerow(['Id']+[f'extStatus_{n}__c' for n in range(1,7)])
    for x in rows:
        vals=[]
        for n in range(1,7):
            v='active' if x[f'extId_{n}__c'].strip() and not x[f'extStatus_{n}__c'].strip() else ''
            if v: cnt[n]+=1
            vals.append(v)
        w.writerow([x['Id']]+vals)
print(org,'accounts',len(rows),'| set active per platform:',{f'p{n}':cnt[n] for n in range(1,7)})
if rows:
    r=subprocess.run(['sf','data','update','bulk','-o',org,'-s','Account','--file',out,'--wait','60','--line-ending','LF','--json'],capture_output=True,text=True)
    try: res=json.loads(r.stdout).get('result',{}); print('  applied:',{k:res.get(k) for k in ('processedRecords','successfulRecords','failedRecords')})
    except Exception: print(r.stdout[-600:],r.stderr[-300:])
