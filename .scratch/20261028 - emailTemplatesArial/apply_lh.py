import json,sys,datetime
S=sys.argv[1]; org=sys.argv[2]; write='--write' in sys.argv
sys.path.insert(0,S)
exec(open(f'{S}/apply.py').read().split("scope=[n")[0].replace("write=len(sys.argv)>3 and sys.argv[3]=='--write'","write='--write' in sys.argv"))
from arialfix import transform, normalize
recs=req('GET','/services/data/v66.0/query?q='+urllib.parse.quote('SELECT Id,Name,LetterheadHeader,LetterheadFooter FROM EnhancedLetterhead'))['records']
stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
json.dump(recs,open(f'{S}/backups/backup_lh_{org}_{stamp}.json','w'),indent=1); print('backup',len(recs))
for r in recs:
    body={}
    for f in ['LetterheadHeader','LetterheadFooter']:
        h=r.get(f)
        if not h: continue
        t=transform(h); assert normalize(h)==normalize(t)
        if t!=h: body[f]=t
    if not body: print('unchanged',r['Name']); continue
    if write:
        req('PATCH','/services/data/v66.0/sobjects/EnhancedLetterhead/'+r['Id'],body)
        back=req('GET','/services/data/v66.0/sobjects/EnhancedLetterhead/%s?fields=LetterheadHeader,LetterheadFooter'%r['Id'])
        print('WROTE' if all(back[k]==v for k,v in body.items()) else 'READBACK DIFFERS', r['Name'], list(body))
    else: print('would change',r['Name'],list(body))
