import sys,json,subprocess
org=sys.argv[1]
def q(s): return json.loads(subprocess.run(['sf','data','query','-o',org,'-q',s,'--json'],capture_output=True,text=True).stdout)['result']['records']
be={r['Reseller__c']:r['Id'] for r in q('SELECT Id, Reseller__c FROM Business_Entities__c')}
for a in q('SELECT Id, Name, Reseller__c, Business_Entity__c FROM Subscription25__Administration__c'):
    t=be.get(a['Reseller__c'])
    if not t or a['Business_Entity__c']==t: print(org,a['Name'],'skip',t); continue
    r=json.loads(subprocess.run(['sf','data','update','record','-o',org,'-s','Subscription25__Administration__c','-i',a['Id'],'-v',f'Business_Entity__c={t}','--json'],capture_output=True,text=True).stdout)
    print(org,a['Name'],'->',t,'OK' if r.get('status')==0 else r.get('message'))
