"""Adds Salesforce XML/JSON metadata to the graphify graph (graphify cannot read .xml/.json).

Run from anywhere after a graphify build/update:  python3 scripts/graphify/add_salesforce_xml.py
Adds (all deterministic, no tokens): objects + fields, flows (triggered_by/reads/creates/updates/
deletes/calls_apex/calls_flow), LWC -> Apex import edges, and the Dealer Portal site (routes ->
views -> c: components, backed_by Ctrl_Dealer* classes). Idempotent: removes earlier _origin=xml
nodes first. Then re-clusters and writes graphify-out/graph.json; run 'graphify export html' and
'graphify export obsidian' afterwards. Community labels are regenerated (name of best-connected node).
Not covered: permission sets, layouts, other XML types, Customer_Hub1 site.
"""
import json,re,glob,os,sys
import xml.etree.ElementTree as ET
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','..')); MD=ROOT+'/force-app/main/default'
G=json.load(open(ROOT+'/graphify-out/graph.json'))
G['nodes']=[n for n in G['nodes'] if n.get('_origin')!='xml']
G['links']=[e for e in G['links'] if e.get('_origin')!='xml']
# existing apex/lwc nodes by repo file (force-app only)
byfile={}
for n in G['nodes']:
    sf=n.get('source_file','')
    if sf.startswith('force-app/main/default/lwc/') and n.get('_callable_class'): byfile[sf]=n['id']
    if sf.startswith('force-app/main/default/classes/') and n.get('label')==os.path.basename(sf)[:-4]: byfile.setdefault(sf,n['id'])
def apex(name):
    p=f'force-app/main/default/classes/{name}.cls'
    if p in byfile: return byfile[p]
    if os.path.exists(os.path.join(ROOT,p)): return N('apex:'+name,name,'code',p,'apex')  # class not in the AST graph yet
    return None
def lwc(name): return byfile.get(f'force-app/main/default/lwc/{name}/{name}.js')
nodes={};edges=[]
def N(i,label,ft,sf,kind):
    nodes.setdefault(i,{'id':i,'label':label,'file_type':ft,'source_file':sf,'source_location':'L1','_origin':'xml','metadata':{'kind':kind}})
    return i
def E(a,b,rel,sf,conf='EXTRACTED'):
    if a and b: edges.append({'source':a,'target':b,'relation':rel,'confidence':conf,'confidence_score':1.0 if conf=='EXTRACTED' else 0.7,'source_file':sf,'source_location':'L1','weight':1.0,'_origin':'xml'})
def obj(name): return N('sobject:'+name,name,'code','', 'sobject')
def strip(t): return re.sub(r'^\{[^}]*\}','',t)
# ---- objects & fields
for od in sorted(glob.glob(MD+'/objects/*/')):
    o=os.path.basename(od.rstrip('/')); sf=f'force-app/main/default/objects/{o}'
    obj(o); nodes['sobject:'+o]['source_file']=sf
    for f in glob.glob(od+'fields/*.field-meta.xml'):
        fn=os.path.basename(f).replace('.field-meta.xml',''); fid=N(f'field:{o}.{fn}',f'{o}.{fn}','code',sf+'/fields/'+fn+'.field-meta.xml','field')
        E('sobject:'+o,fid,'has_field',sf)
        try: r=ET.parse(f).getroot()
        except Exception: continue
        ref=[c.text for c in r if strip(c.tag)=='referenceTo']
        for t in ref: E(fid,obj(t),'references',sf)
# ---- flows
for f in sorted(glob.glob(MD+'/flows/*.flow-meta.xml')):
    name=os.path.basename(f).replace('.flow-meta.xml',''); sf='force-app/main/default/flows/'+os.path.basename(f)
    fid=N('flow:'+name,name,'code',sf,'flow')
    try: r=ET.parse(f).getroot()
    except Exception: continue
    for el in r:
        t=strip(el.tag)
        if t=='start':
            for c in el:
                if strip(c.tag)=='object': E(fid,obj(c.text),'triggered_by',sf)
        elif t in('recordLookups','recordCreates','recordUpdates','recordDeletes'):
            for c in el:
                if strip(c.tag)=='object': E(fid,obj(c.text),{'recordLookups':'reads','recordCreates':'creates'}.get(t,'updates' if t=='recordUpdates' else 'deletes'),sf)
        elif t=='actionCalls':
            at=an=None
            for c in el:
                if strip(c.tag)=='actionType': at=c.text
                if strip(c.tag)=='actionName': an=c.text
            if at=='apex' and an: E(fid,apex(an) or N('apex:'+an,an,'code','', 'apex-external'),'calls_apex',sf)
        elif t=='subflows':
            for c in el:
                if strip(c.tag)=='flowName': E(fid,N('flow:'+c.text,c.text,'code','', 'flow'),'calls_flow',sf)
# ---- LWC -> Apex imports (all lwc)
for js in glob.glob(MD+'/lwc/*/*.js'):
    n=os.path.basename(os.path.dirname(js)); src=lwc(n)
    if not src: continue
    for m in set(re.findall(r"@salesforce/apex/(\w+)\.\w+",open(js,encoding='utf-8',errors='replace').read())):
        E(src,apex(m),'calls_apex',f'force-app/main/default/lwc/{n}/{n}.js')
# ---- Dealer Portal site
SITE='Dealer_Portal1'; base=f'{MD}/digitalExperiences/site/{SITE}'; sfb=f'force-app/main/default/digitalExperiences/site/{SITE}'
site=N('site:'+SITE,'Dealer Portal (Experience site)','code',sfb,'site')
views={}
for p in glob.glob(base+'/sfdc_cms__view/*/content.json'):
    d=os.path.basename(os.path.dirname(p)); j=json.load(open(p))
    vid=N('view:'+d,f"View: {j.get('title',d)}",'code',f'{sfb}/sfdc_cms__view/{d}/content.json','view'); views[j.get('urlName',d)]=vid; views[d]=vid
    E(site,vid,'contains',f'{sfb}/sfdc_cms__view/{d}')
    comps=set(re.findall(r'"definition"\s*:\s*"c:(\w+)"',open(p).read()))
    for c in comps: E(vid,lwc(c),'uses_component',f'{sfb}/sfdc_cms__view/{d}/content.json')
for p in glob.glob(base+'/sfdc_cms__route/*/content.json'):
    d=os.path.basename(os.path.dirname(p)); j=json.load(open(p)); cb=j.get('contentBody',{})
    rid=N('route:'+d,f"Route: {j.get('title',d)} (/{cb.get('urlPrefix','')})",'code',f'{sfb}/sfdc_cms__route/{d}/content.json','route')
    E(site,rid,'contains',f'{sfb}/sfdc_cms__route/{d}')
    E(rid,views.get(cb.get('activeViewId')),'renders',f'{sfb}/sfdc_cms__route/{d}/content.json')
# connect the site to its apex entry points
for c in ('Ctrl_DealerShop','Ctrl_DealerPortal','Ctrl_DealerPortalLogin','Ctrl_DealerPortalEmail','Svc_DealerUserSetup'): E(site,apex(c),'backed_by',sfb,'INFERRED')
# dedupe edges
seen=set();ed=[]
for e in edges:
    k=(e['source'],e['target'],e['relation'])
    if k not in seen: seen.add(k);ed.append(e)
ids=set(nodes)|{n['id'] for n in G['nodes']}
ed=[e for e in ed if e['source'] in ids and e['target'] in ids]
from collections import Counter
print(len(nodes),'nodes',len(ed),'edges',dict(Counter(e['relation'] for e in ed)))
print('unresolved apex (package/namespaced, not in repo):',sorted(n['label'] for n in nodes.values() if n['metadata']['kind']=='apex-external'))
from networkx.readwrite import json_graph
from graphify.cluster import cluster
from graphify.export import to_json
NX=json_graph.node_link_graph(G,edges='links')
for n in nodes.values():
    i=n['id']; NX.add_node(i,**{k:v for k,v in n.items() if k!='id'})
for e in ed:
    if not NX.has_edge(e['source'],e['target']): NX.add_edge(e['source'],e['target'],**{k:v for k,v in e.items() if k not in('source','target')})
comms=cluster(NX)
labels={c:str(NX.nodes[max(m,key=NX.degree)].get('label'))[:40] for c,m in comms.items()}
print('written',to_json(NX,comms,os.path.join(ROOT,'graphify-out','graph.json'),community_labels=labels,force=True),NX.number_of_nodes(),'nodes',len(comms),'communities')
