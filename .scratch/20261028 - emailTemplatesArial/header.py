"""Standard email header (user's decision 2026-10-28): the red-› banner miemailheader, 600px, on every template.
python3 -I header.py <dir> <org> [--write]

Per template (in scope.json, minus DealerPortal_* and the echoes brand):
- on an EnhancedLetterhead / Classic BrandTemplate: the letterhead carries the header -> skip (letterheads are done by standardize_lh.py / header_bt.py)
- header <img> from the CMS (white-› bridge MCUVG5, short banner MCRT3A, 3-arrows logo MCTJTU) -> replaced by STD_IMG
- no header at all (paymentDirectDebit*, Noodsleutel*) -> STD block inserted right after <body>
Safety: before with the old header <img> -> placeholder must equal after with the new one -> placeholder.
"""
import json,sys,subprocess,urllib.parse,tempfile,os,re,datetime
STD_SRC='https://movingintelligence.file.force.com/file-asset-public/miemailheader?oid=00D1t000000uTfK'
STD_IMG='<img alt="mi-email-header" src="'+STD_SRC+'" style="max-width:600px; width:100%; height:auto; display:block; border:0;" title="mi-email-header" width="600" />'
STD_BLOCK='<div style="font-family:Arial,Helvetica,sans-serif; max-width:600px; margin:0 0 16px 0;">'+STD_IMG+'</div>'  # font inline = transform() output, so apply.py stays idempotent
OLD_RE=re.compile(r'<img\b[^>]*?src\s*=\s*["\'][^"\']*(?:MCUVG5XJAAUZBFHPCLAUX7NURY7M|MCRT3AHQWZSJC3PJP2RRPHH6GSKU|MCTJTUUDPDIJHBFCB2I2KYOECWMY)[^"\']*["\'][^>]*>',re.I)
BODY_RE=re.compile(r'<body\b[^>]*>',re.I)
INSERT=('paymentDirectDebit','Noodsleutel_')
PH='\x00HEADER\x00'

def fix(name,html):
    """-> (new_html, action)"""
    if 'miemailheader' in html: return html,'already'
    m=OLD_RE.search(html)
    if m:
        new=html[:m.start()]+STD_IMG+html[m.end():]
        assert html[:m.start()]+PH+html[m.end():]==new.replace(STD_IMG,PH,1), name
        return new,'replaced '+re.search(r'MC\w{6}',m.group(0)).group(0)
    if name.startswith(INSERT):
        b=BODY_RE.search(html); assert b, name+': no <body>'
        new=html[:b.end()]+'\n'+STD_BLOCK+html[b.end():]
        assert new.replace('\n'+STD_BLOCK,'',1)==html, name
        return new,'inserted'
    return html,'NO HEADER FOUND'

if __name__=='__main__':
    S=sys.argv[1]; org=sys.argv[2]; write='--write' in sys.argv
    V='v66.0'
    def req(method,path,body=None):
        cmd=['sf','api','request','rest',path,'--method',method,'-o',org]
        if body is not None:
            fd,fp=tempfile.mkstemp(suffix='.json',dir=S); os.write(fd,json.dumps(body).encode()); os.close(fd); cmd+=['--body','@'+fp]
        out=subprocess.run(cmd,capture_output=True,text=True)
        if body is not None: os.remove(fp)
        if out.returncode!=0: raise SystemExit('ERR %s %s\n%s%s'%(method,path,out.stdout[-800:],out.stderr[-800:]))
        return json.loads(out.stdout) if out.stdout.strip() else None
    scope=[n for n in json.load(open(f'{S}/scope.json')) if not n.startswith('DealerPortal_')]
    qs="SELECT Id,DeveloperName,HtmlValue,EnhancedLetterheadId,EnhancedLetterhead.Name,BrandTemplateId FROM EmailTemplate WHERE NamespacePrefix=null AND DeveloperName IN (%s)"%','.join("'%s'"%n for n in scope)
    recs=req('GET','/services/data/%s/query?q=%s'%(V,urllib.parse.quote(qs)))['records']
    stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
    bk=f'{S}/backups/backup_hdr_{org}_{stamp}.json'; json.dump(recs,open(bk,'w'),indent=1); print('backup',bk,len(recs))
    n=0
    for r in sorted(recs,key=lambda r:r['DeveloperName']):
        nm=r['DeveloperName']
        if r.get('EnhancedLetterheadId'): print(f'  skip {nm}: letterhead {r["EnhancedLetterhead"]["Name"]}'); continue
        if r.get('BrandTemplateId'): print(f'  skip {nm}: Classic letterhead'); continue
        new,act=fix(nm,r['HtmlValue'] or '')
        print(f'{"*" if new!=r["HtmlValue"] else " "} {nm}: {act}')
        if new==r['HtmlValue']: continue
        n+=1
        if write:
            req('PATCH','/services/data/%s/sobjects/EmailTemplate/%s'%(V,r['Id']),{'HtmlValue':new})
            back=req('GET','/services/data/%s/sobjects/EmailTemplate/%s?fields=HtmlValue'%(V,r['Id']))['HtmlValue']
            print('    WROTE' if back==new else '    READBACK DIFFERS')
    print('changed',n,'write',write)
