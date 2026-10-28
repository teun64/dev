"""Classic letterheads lh2023_Styling600/660/883 -> standard red-› header (miemailheader, 600x118).
A Classic BrandTemplate only shows a public Document of its own org (relative ImageServer URL + own oid),
so the image is uploaded as Document MiEmailHeader600_2024 into the folder of the current header Document.
python3 -I header_bt.py <dir> <org> [--write]"""
import json,sys,subprocess,urllib.parse,tempfile,os,re,base64,datetime
S=sys.argv[1]; org=sys.argv[2]; write='--write' in sys.argv
V='v66.0'; DEV='MiEmailHeader600_2024'; BTS=('lh2023_Styling600','lh2023_Styling660','lh2023_Styling883')
def req(method,path,body=None):
    cmd=['sf','api','request','rest',path,'--method',method,'-o',org]
    if body is not None:
        fd,fp=tempfile.mkstemp(suffix='.json',dir=S); os.write(fd,json.dumps(body).encode()); os.close(fd); cmd+=['--body','@'+fp]
    out=subprocess.run(cmd,capture_output=True,text=True)
    if body is not None: os.remove(fp)
    if out.returncode!=0: raise SystemExit('ERR %s %s\n%s%s'%(method,path,out.stdout[-800:],out.stderr[-800:]))
    return json.loads(out.stdout) if out.stdout.strip() else None
q=lambda s: req('GET','/services/data/%s/query?q=%s'%(V,urllib.parse.quote(s)))['records']
HDR=re.compile(r'(bLabel="headerImage" id="r1sp1">\s*<!\[CDATA\[)/servlet/servlet\.ImageServer\?id=(\w+)&(?:amp;)?oid=(\w+)(\]\]>)')
bts=q("SELECT Id,DeveloperName,Value FROM BrandTemplate WHERE DeveloperName IN (%s)"%','.join("'%s'"%b for b in BTS))
stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
json.dump(bts,open(f'{S}/backups/backup_bthdr_{org}_{stamp}.json','w'),indent=1)
cur=HDR.search(bts[0]['Value']); oid=cur.group(3)
doc=q(f"SELECT Id FROM Document WHERE DeveloperName='{DEV}'")
if doc: did=doc[0]['Id'][:15]; print('Document exists',did)
else:
    folder=q(f"SELECT FolderId FROM Document WHERE Id='{cur.group(2)}'")[0]['FolderId']
    print('upload into folder',folder)
    if write:
        did=req('POST','/services/data/%s/sobjects/Document'%V,{'Name':DEV,'DeveloperName':DEV,'FolderId':folder,'IsPublic':True,'ContentType':'image/png','Type':'png',
            'Description':'Standard email header (red ›), 600x118. Same image as file-asset-public/miemailheader. 2026-10-28.',
            'Body':base64.b64encode(open(f'{S}/miemailheader.png','rb').read()).decode()})['id'][:15]
        print('uploaded',did)
    else: did='<new>'
for b in bts:
    m=HDR.search(b['Value']); assert m, b['DeveloperName']
    new=b['Value'][:m.start()]+m.group(1)+f'/servlet/servlet.ImageServer?id={did}&oid={oid}'+m.group(4)+b['Value'][m.end():]
    print(b['DeveloperName'],m.group(2),'->',did, '(unchanged)' if new==b['Value'] else '')
    if write and new!=b['Value']:
        req('PATCH','/services/data/%s/sobjects/BrandTemplate/%s'%(V,b['Id']),{'Value':new})
        back=req('GET','/services/data/%s/sobjects/BrandTemplate/%s?fields=Value'%(V,b['Id']))['Value']
        print('   WROTE' if back==new else '   READBACK DIFFERS')
