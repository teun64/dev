import json,sys,subprocess,urllib.request,datetime
S=sys.argv[1]; org=sys.argv[2]; write=len(sys.argv)>3 and sys.argv[3]=='--write'
sys.path.insert(0,S)
from arialfix import transform, normalize
V='v66.0'
import tempfile,os
def req(method,path,body=None):
    cmd=['sf','api','request','rest',path,'--method',method,'-o',org]
    if body is not None:
        fd,fp=tempfile.mkstemp(suffix='.json',dir=S); os.write(fd,json.dumps(body).encode()); os.close(fd)
        cmd+=['--body','@'+fp]
    out=subprocess.run(cmd,capture_output=True,text=True)
    if body is not None: os.remove(fp)
    if out.returncode!=0: raise SystemExit('ERR %s %s\n%s%s'%(method,path,out.stdout[-800:],out.stderr[-800:]))
    s=out.stdout.strip()
    return json.loads(s) if s else None
scope=[n for n in json.load(open(f'{S}/scope.json')) if not n.startswith('DealerPortal_')]
names=','.join("'%s'"%n for n in scope)
q="SELECT Id,DeveloperName,TemplateType,UiType,HtmlValue,Markup,LastModifiedDate FROM EmailTemplate WHERE NamespacePrefix=null AND DeveloperName IN (%s)"%names
recs=req('GET','/services/data/%s/query?q=%s'%(V,urllib.parse.quote(q)))['records']
stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
json.dump(recs,open(f'{S}/backups/backup_{org}_{stamp}.json','w'),indent=1)
print('backup',f'backups/backup_{org}_{stamp}.json',len(recs),'of',len(scope),'missing:',sorted(set(scope)-{r['DeveloperName'] for r in recs}))
changed=0
for r in recs:
    ch=r['TemplateType']=='html'; body={}
    for fld in ['HtmlValue']:
        h=r.get(fld)
        if not h: continue
        t=transform(h,ch)
        assert normalize(h)==normalize(t), r['DeveloperName']
        if t!=h: body[fld]=t
    if not body: continue
    changed+=1
    if write:
        req('PATCH','/services/data/%s/sobjects/EmailTemplate/%s'%(V,r['Id']),body)
        back=req('GET','/services/data/%s/sobjects/EmailTemplate/%s?fields=HtmlValue'%(V,r['Id']))['HtmlValue']
        print('WROTE' if back==body['HtmlValue'] else 'READBACK DIFFERS', r['DeveloperName'])
print('changed',changed,'write',write)
