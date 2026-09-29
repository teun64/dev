# Usage: python3 copy_fls.py <org> <workdir> <SrcObj.SrcField> <TgtObj.TgtField> [...pairs]
import json,subprocess,sys,csv,os
org,wd=sys.argv[1],sys.argv[2]; pairs=sys.argv[3:]
def q(soql):
    r=subprocess.run(['sf','data','query','-o',org,'-q',soql,'--json'],capture_output=True,text=True); return json.loads(r.stdout)['result']['records']
for i in range(0,len(pairs),2):
    src,tgt=pairs[i],pairs[i+1]; obj=tgt.split('.')[0]
    have={r['ParentId'] for r in q(f"SELECT ParentId FROM FieldPermissions WHERE Field='{tgt}'")}
    rows=[r for r in q(f"SELECT ParentId, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE Field='{src}' AND PermissionsRead=true") if r['ParentId'] not in have]
    f=os.path.join(wd,'fls_'+tgt.replace('.','_')+'.csv')
    with open(f,'w',newline='') as h:
        w=csv.writer(h,lineterminator='\n'); w.writerow(['ParentId','SobjectType','Field','PermissionsRead','PermissionsEdit'])
        READONLY={'Account.StatusChangedBy__c','Account.StatusIcon__c','Account.StatusPrevious__c','Account.StatusChangedOn__c'}
        for r in rows: w.writerow([r['ParentId'],obj,tgt,'true','false' if (tgt in READONLY or tgt.endswith('Icon__c')) else str(r['PermissionsEdit']).lower()])
    if rows: subprocess.run(['sf','data','import','bulk','-o',org,'-s','FieldPermissions','--file',f,'--wait','10','--line-ending','LF'],capture_output=True,cwd=wd)
    n=len(q(f"SELECT Id FROM FieldPermissions WHERE Field='{tgt}' AND PermissionsRead=true"))
    print(f"{src} -> {tgt}: source grants {len(rows)+len(have)}, now {n}")
