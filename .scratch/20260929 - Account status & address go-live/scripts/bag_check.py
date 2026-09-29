import csv,re,sys,json,time,urllib.request,urllib.parse,difflib,unicodedata,collections
d=sys.argv[1]
rows=[r for r in csv.DictReader(open(d+'/near_identical_invoice_addresses.csv',encoding='utf-8-sig'),delimiter=';') if r['Category'].startswith('2 ')]
def norm(v): return re.sub(r'[^a-z0-9]','',unicodedata.normalize('NFKD',(v or '')).encode('ascii','ignore').decode().lower())
def parse(street):
    s=(street or '').strip().replace('\n',' ')
    m=re.match(r'^(.*?)[\s,]+(\d+)\s*([a-zA-Z])?(?:[\s\-/]+([0-9a-zA-Z]{1,6}))?\s*$',s)
    if not m: return None
    return {'street':m.group(1).strip(),'nr':m.group(2),'letter':(m.group(3) or '').upper(),'add':(m.group(4) or '').upper()}
def pdok(pc,nr):
    q=f'postcode:{pc} and huisnummer:{nr}'
    url='https://api.pdok.nl/bzk/locatieserver/search/v3_1/free?'+urllib.parse.urlencode({'q':q,'fq':'type:adres','rows':20,'fl':'straatnaam,huisnummer,huisletter,huisnummertoevoeging,postcode,woonplaatsnaam,weergavenaam'})
    for i in range(3):
        try: return json.load(urllib.request.urlopen(url,timeout=15))['response']['docs']
        except Exception: time.sleep(1)
    return None
def pick(docs,p):
    if not docs: return None
    c=[x for x in docs if (x.get('huisletter') or '').upper()==p['letter'] and (x.get('huisnummertoevoeging') or '').upper()==p['add']]
    if len(c)==1: return c[0]
    if not c and p['add'] and not p['letter']:
        c=[x for x in docs if (x.get('huisletter') or '').upper()==p['add'] and not x.get('huisnummertoevoeging')]
        if len(c)==1: return c[0]
    if not p['letter'] and not p['add']:
        c=[x for x in docs if not x.get('huisletter') and not x.get('huisnummertoevoeging')]
        if len(c)==1: return c[0]
    return None
out=[]; stats=collections.Counter()
for r in rows:
    res={'status':'review','reason':'','street':'','pc':'','city':''}
    cands=[]
    for side in ('Establishment','Invoice'):
        p=parse(r[side+' street']); pc=re.sub(r'\s','',(r[side+' postcode'] or '')).upper()
        if not p or not re.match(r'^\d{4}[A-Z]{2}$',pc): continue
        doc=pick(pdok(pc,p['nr']),p)
        if doc and difflib.SequenceMatcher(None,norm(doc['straatnaam']),norm(p['street'])).ratio()>=0.6: cands.append(doc)
        time.sleep(0.15)
    keys={(c['straatnaam'],c['huisnummer'],c.get('huisletter') or '',c.get('huisnummertoevoeging') or '',c['postcode']) for c in cands}
    if not cands: res['reason']='no clear BAG match (non-NL, missing postcode or ambiguous number)'
    elif len(keys)>1: res['reason']='both addresses match a different official address'
    else:
        c=cands[0]; nr=str(c['huisnummer'])+(c.get('huisletter') or '')+(('-'+c['huisnummertoevoeging']) if c.get('huisnummertoevoeging') else '')
        res={'status':'ok','reason':'','street':f"{c['straatnaam']} {nr}",'pc':c['postcode'],'city':c['woonplaatsnaam']}
    stats[res['status']]+=1
    out.append((r,res))
with open(d+'/group2_bag_proposal.csv','w',newline='',encoding='utf-8-sig') as f:
    w=csv.writer(f,delimiter=';'); w.writerow(['Result','Reason','Account','Link','Establishment street (now)','Establishment postcode','Establishment city','Invoice street (now)','Invoice postcode','Invoice city','BAG street','BAG postcode','BAG city'])
    for r,res in out: w.writerow([res['status'],res['reason'],r['Account'],r['Link'],r['Establishment street'],r['Establishment postcode'],r['Establishment city'],r['Invoice street'],r['Invoice postcode'],r['Invoice city'],res['street'],res['pc'],res['city']])
print(dict(stats))
print('review reasons:', collections.Counter(res['reason'] for _,res in out if res['status']!='ok').most_common())
for r,res in [x for x in out if x[1]['status']=='ok'][:8]:
    print(f"  {r['Account'][:26]:<26} | {r['Establishment street']}, {r['Establishment postcode']} {r['Establishment city']}  <>  {r['Invoice street']}, {r['Invoice postcode']} {r['Invoice city']}  ==> {res['street']}, {res['pc']} {res['city']}")
