# Prod cutover for the invoice email + payment block (package B). Run step by step: python3 -I cutover.py <step> [--write]
# Steps 1-4 back-to-back, outside Job_EmailInvoice (prod 21:16 UTC). Package A (0AfTx0000014KkLKAU) must be deployed first.
import json, subprocess, sys, os
ORG = 'prod'; HERE = os.path.dirname(os.path.abspath(__file__)); WRITE = '--write' in sys.argv
def sf(*a): r = subprocess.run(['sf', *a, '-o', ORG, '--json'], capture_output=True, text=True); return json.loads(r.stdout or '{}')
def q(s, tooling=False): return sf('data', 'query', '-q', s, *(['--use-tooling-api'] if tooling else []))['result']['records']
def upd(obj, rid, vals):
    print(f'  {obj} {rid} <- {vals}' + ('' if WRITE else '  (dry run)'))
    if WRITE: print('   ', sf('data', 'update', 'record', '-s', obj, '-i', rid, '-v', ' '.join(f'{k}={v}' for k, v in vals.items())).get('status'))
step = sys.argv[1]
if step == '1':   # rename Classic folder + templates (Ids kept; Administrations keep pointing at InvoiceNL/UK/DE = the Lightning ones after step 2)
    for f in q("SELECT Id, DeveloperName, Name FROM Folder WHERE DeveloperName = 'Invoicing' AND Type = 'Email'"):
        upd('Folder', f['Id'], {'DeveloperName': 'Invoicing_Classic', 'Name': "'Invoicing (Classic)'"})
    for t in q("SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN ('InvoiceNL','InvoiceUK','InvoiceDE') AND UIType = 'Aloha'"):
        n = t['DeveloperName'] + '_Classic'; upd('EmailTemplate', t['Id'], {'DeveloperName': n, 'Name': n})
elif step == '2':  # deploy the Lightning folder + InvoiceNL/UK/DE
    cmd = ['sf', 'project', 'deploy', 'start', '-o', ORG, '--source-dir', 'packageB_copy', '--test-level', 'RunSpecifiedTests', '--tests', 'Test_Svc_InvoicePaymentBlock', '--wait', '30']
    print('copy packageB to a non-dot path as packageB_copy (sf skips dot folders), then run:\n  ' + ' '.join(cmd))
elif step == '3':  # letterheads + link
    have = {x['Name']: x['Id'] for x in q("SELECT Id, Name FROM EnhancedLetterhead WHERE Name LIKE 'lh_M_Preferences%'")}
    for lh in json.load(open(os.path.join(HERE, 'letterheads_from_dev.json'))):
        if lh['Name'] in have: print('  exists', lh['Name']); continue
        print('  create', lh['Name'] + ('' if WRITE else '  (dry run)'))
        if WRITE:
            r = subprocess.run(['sf', 'api', 'request', 'rest', '/services/data/v67.0/sobjects/EnhancedLetterhead/', '--method', 'POST', '--body', json.dumps(lh), '-o', ORG], capture_output=True, text=True); print('   ', r.stdout.strip()[:120])
    have = {x['Name']: x['Id'] for x in q("SELECT Id, Name FROM EnhancedLetterhead WHERE Name LIKE 'lh_M_Preferences%'")}
    for tpl, lh in (('InvoiceUK', 'lh_M_Preferences_EN'), ('InvoiceNL', 'lh_M_Preferences_NL'), ('InvoiceDE', 'lh_M_Preferences_DE')):
        t = q(f"SELECT Id FROM EmailTemplate WHERE DeveloperName = '{tpl}' AND UIType = 'SFX'")
        if t and lh in have: upd('EmailTemplate', t[0]['Id'], {'EnhancedLetterheadId': have[lh]})
        else: print('  !! missing', tpl, lh)
elif step == '4':  # activate the flow versions created by package A
    for f in ['afl_Payment_Direct_Debit_Setup', 'rau_Subscription25_Invoice_c_Email_Status_Payment', 'rab_Payment_Direct_Debit_Awaiting_Invoice', 'rab_Payment_Direct_Debit_Processed', 'rab_Payment_Direct_Debit_Escalation']:
        d = q(f"SELECT Id, ActiveVersion.VersionNumber, LatestVersion.VersionNumber FROM FlowDefinition WHERE DeveloperName = '{f}'", True)[0]
        a = (d.get('ActiveVersion') or {}).get('VersionNumber'); n = d['LatestVersion']['VersionNumber']
        print(f'  {f}: {a} -> {n}' + ('' if WRITE else '  (dry run)'))
        if WRITE and a != n:
            subprocess.run(['sf', 'api', 'request', 'rest', f"/services/data/v67.0/tooling/sobjects/FlowDefinition/{d['Id']}", '--method', 'PATCH', '--body', json.dumps({'Metadata': {'activeVersionNumber': n}}), '-o', ORG], capture_output=True, text=True)
elif step == 'check':
    for t in q("SELECT DeveloperName, Folder.DeveloperName, UIType, EnhancedLetterhead.Name FROM EmailTemplate WHERE DeveloperName LIKE 'Invoice%' AND (DeveloperName LIKE '%_Classic' OR DeveloperName IN ('InvoiceNL','InvoiceUK','InvoiceDE'))"): print(' ', t['DeveloperName'], (t.get('Folder') or {}).get('DeveloperName'), t.get('UiType'), (t.get('EnhancedLetterhead') or {}).get('Name'))
