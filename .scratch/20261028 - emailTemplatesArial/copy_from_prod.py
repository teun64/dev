"""Copy in-scope templates that only exist in prod into a sandbox (create only, never overwrite).
python3 -I copy_from_prod.py <dir> <org> [--write]"""
import json,sys,subprocess,urllib.parse,tempfile,os
S=sys.argv[1]; org=sys.argv[2]; write='--write' in sys.argv
assert org!='prod'
V='v66.0'
def req(o,method,path,body=None):
    cmd=['sf','api','request','rest',path,'--method',method,'-o',o]
    if body is not None:
        fd,fp=tempfile.mkstemp(suffix='.json',dir=S); os.write(fd,json.dumps(body).encode()); os.close(fd); cmd+=['--body','@'+fp]
    out=subprocess.run(cmd,capture_output=True,text=True)
    if body is not None: os.remove(fp)
    if out.returncode!=0: raise SystemExit('ERR %s %s\n%s%s'%(method,path,out.stdout[-800:],out.stderr[-800:]))
    return json.loads(out.stdout) if out.stdout.strip() else None
q=lambda o,s: req(o,'GET','/services/data/%s/query?q=%s'%(V,urllib.parse.quote(s)))['records']
scope=[n for n in json.load(open(f'{S}/scope.json')) if not n.startswith('DealerPortal_')]
have={r['DeveloperName'] for r in q(org,"SELECT DeveloperName FROM EmailTemplate WHERE DeveloperName IN (%s)"%','.join("'%s'"%n for n in scope))}
miss=[n for n in scope if n not in have]
F='Name,DeveloperName,FolderId,TemplateType,UiType,Subject,HtmlValue,Body,RelatedEntityType,IsActive,Encoding,Description'
src=q('prod',"SELECT %s FROM EmailTemplate WHERE DeveloperName IN (%s)"%(F,','.join("'%s'"%n for n in miss))) if miss else []
SHARED='00lbR0000001Y9KQAU'  # Email Templates from Salesforce: private (user-Id) folders can't be written by another user
for r in src:
    r.pop('attributes',None)
    if r['FolderId'].startswith('005'): r['FolderId']=SHARED
    print('CREATE' if write else 'would create',r['DeveloperName'],r['FolderId'])
    if write: print('  ->',req(org,'POST','/services/data/%s/sobjects/EmailTemplate'%V,r)['id'])
print('missing',len(miss),'write',write)
