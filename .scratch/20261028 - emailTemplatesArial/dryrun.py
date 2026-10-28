import json,sys,re
S=sys.argv[1]; org=sys.argv[2]
sys.path.insert(0,S)
from arialfix import transform, normalize
P={r['DeveloperName']:r for r in json.load(open(f'{S}/et2_{org}.json'))['result']['records']}
used=json.load(open(f'{S}/scope.json'))
NA=re.compile(r'(?<![-\w])font-family:(?!\s*arial)',re.I)
bad=0
for n in used:
    if n not in P: print('MISSING', n); continue
    r=P[n]; ch=r['TemplateType']=='html'
    for fld in ['HtmlValue','Markup']:
        h=r.get(fld)
        if not h: continue
        t=transform(h,ch)
        ok=normalize(h)==normalize(t); bad+=not ok
        idem=transform(t,ch)==t
        add=t.count('font-family:Arial,Helvetica')-h.count('font-family:Arial,Helvetica')
        print('OK ' if ok else 'BAD', 'idem=%s'%idem, '%-52s %-9s +%-4d nonArialBefore=%d after=%d' % (n[:52],fld,add,len(NA.findall(h)),len(NA.findall(t))))
print('bad',bad)
