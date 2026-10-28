"""Standard letterheads (2026-10-28): every image on a fixed prod URL, same header image style, echoes link fixed.
usage: python3 -I standardize_lh.py <this dir> <org> [--write] [--classic-only NAME]"""
import json,sys,re,datetime,subprocess,tempfile,os
D=sys.argv[1]; org=sys.argv[2]; write='--write' in sys.argv
only=sys.argv[sys.argv.index('--classic-only')+1] if '--classic-only' in sys.argv else None
PROD_OID='00D1t000000uTfK'; PROD_FILE='https://movingintelligence.file.force.com'
HEADER_IMG_STYLE='max-width:600px; width:100%; height:auto; display:block; border:0;'
def req(method,path,body=None):
    cmd=['sf','api','request','rest',path,'--method',method,'-o',org]
    if body is not None:
        fd,fp=tempfile.mkstemp(suffix='.json',dir=D); os.write(fd,json.dumps(body).encode()); os.close(fd); cmd+=['--body','@'+fp]
    out=subprocess.run(cmd,capture_output=True,text=True)
    if body is not None: os.remove(fp)
    if out.returncode!=0: raise SystemExit('ERR %s %s\n%s%s'%(method,path,out.stdout[-800:],out.stderr[-800:]))
    s=out.stdout.strip(); return json.loads(s) if s else None
def q(soql,o=None):
    global org
    if o: prev,org=org,o
    try: return req('GET','/services/data/v66.0/query?q='+__import__('urllib.parse').parse.quote(soql))['records']
    finally:
        if o: org=prev
stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')

def fix_lightning(html, header):
    h=re.sub(r'https://movingintelligence--\w+\.sandbox\.file\.force\.com/file-asset-public/(\w+)\?oid=\w+', lambda m: '%s/file-asset-public/%s?oid=%s'%(PROD_FILE,m.group(1),PROD_OID), html)
    if header:
        h=re.sub(r'(<img\b[^>]*?\sstyle=")[^"]*(")', lambda m: m.group(1)+HEADER_IMG_STYLE+m.group(2), h, count=1)
    return h.replace('https://echeos.solution','https://echoes.solutions')

# Classic letterheads can only show a Document of their own org (an absolute prod URL renders empty).
# Point every ImageServer reference to the Document with the same DeveloperName in THIS org.
prod_docs={r['Id'][:15]:r['DeveloperName'] for r in q('SELECT Id,DeveloperName FROM Document WHERE IsPublic=true',o='prod')}
org_docs={r['DeveloperName']:r['Id'][:15] for r in q('SELECT Id,DeveloperName FROM Document WHERE IsPublic=true')}
org_docs_ids=set(org_docs.values())
org_oid=q('SELECT Id FROM Organization')[0]['Id'][:15]
def fix_classic(name, val):
    def rep(m):
        i=m.group(1)
        dev_name=prod_docs.get(i) if i not in org_docs_ids else None
        target=org_docs.get(dev_name, i) if dev_name else i
        if target not in org_docs_ids: print('  !! %s: no Document for %s in %s, left as is'%(name,i,org)); return m.group(0)
        return '/servlet/servlet.ImageServer?id=%s&%soid=%s'%(target,m.group(2) or '',org_oid)
    return re.sub(r'(?:https://[^\]\s"]*)?/servlet/servlet\.ImageServer\?id=(\w+)&(amp;)?oid=\w+', rep, val)

changes=[]
if not only:
    lh=q('SELECT Id,Name,LetterheadHeader,LetterheadFooter FROM EnhancedLetterhead')
    json.dump(lh,open(f'{D}/backups/backup_lh_{org}_{stamp}_std.json','w'),indent=1)
    for r in lh:
        body={}
        for f,hdr in [('LetterheadHeader',True),('LetterheadFooter',False)]:
            if r.get(f):
                t=fix_lightning(r[f],hdr)
                if t!=r[f]: body[f]=t
        if body: changes.append(('EnhancedLetterhead',r['Id'],r['Name'],body))
bt=q('SELECT Id,Name,Value FROM BrandTemplate'+(" WHERE Name='%s'"%only if only else ''))
json.dump(bt,open(f'{D}/backups/backup_bt_{org}_{stamp}.json','w'),indent=1)
for r in bt:
    t=fix_classic(r['Name'],r['Value'] or '')
    if t!=r['Value']: changes.append(('BrandTemplate',r['Id'],r['Name'],{'Value':t}))
for obj,i,name,body in changes:
    if not write: print('would change',obj,name,list(body)); continue
    req('PATCH','/services/data/v66.0/sobjects/%s/%s'%(obj,i),body)
    back=req('GET','/services/data/v66.0/sobjects/%s/%s?fields=%s'%(obj,i,','.join(body)))
    print('WROTE' if all(back[k]==v for k,v in body.items()) else 'READBACK DIFFERS',obj,name,list(body))
print('changes',len(changes),'write',write)
