import json,sys,subprocess,urllib.parse,re
S=sys.argv[1]; org=sys.argv[2]
def req(path):
    out=subprocess.run(['sf','api','request','rest',path,'-o',org],capture_output=True,text=True)
    return json.loads(out.stdout)
scope=json.load(open(f'{S}/scope.json'))
names=','.join("'%s'"%n for n in scope)
q="SELECT Id,DeveloperName,Name,TemplateType,UiType,HtmlValue,Markup,BrandTemplateId,EnhancedLetterheadId,FolderName FROM EmailTemplate WHERE NamespacePrefix=null AND DeveloperName IN (%s)"%names
recs=req('/services/data/v66.0/query?q='+urllib.parse.quote(q))['records']
lh={r['Id']:r for r in req('/services/data/v66.0/query?q='+urllib.parse.quote("SELECT Id,Name,LetterheadHeader,LetterheadFooter FROM EnhancedLetterhead"))['records']}
bt={r['Id']:r for r in req('/services/data/v66.0/query?q='+urllib.parse.quote("SELECT Id,DeveloperName,Value FROM BrandTemplate"))['records']}
json.dump({'t':recs,'lh':lh,'bt':bt},open(f'{S}/survey/{org}.json','w'),indent=1)
IMG=re.compile(r'<img[^>]*src\s*=\s*["\']([^"\']+)',re.I)
for r in sorted(recs,key=lambda r:r['DeveloperName']):
    body=r.get('HtmlValue') or r.get('Markup') or ''
    hdr=''
    if r.get('EnhancedLetterheadId'): hdr='LH:'+lh.get(r['EnhancedLetterheadId'],{}).get('Name','?')
    elif r.get('BrandTemplateId'): hdr='BT:'+bt.get(r['BrandTemplateId'],{}).get('DeveloperName','?')
    imgs=[re.sub(r'oid=\w+','oid=…',i)[-70:] for i in IMG.findall(body)][:2]
    print(f"{r['DeveloperName'][:55]:55} {r['UiType']:6} {r['TemplateType']:7} {hdr:28} {imgs}")
