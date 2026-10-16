#!/usr/bin/env python3
"""
Account-contact data fix, prod (prepared 2026-10-15; run only on the user's explicit go).

  python3 run_datafix.py plan     export fresh data, write the plans + backups to ./run/<timestamp>/
  python3 run_datafix.py merge    merge the duplicate contacts of the latest plan (chunks of 20 groups, anonymous Apex)
  python3 run_datafix.py ids      restore the real platform ids known from the request logs
  python3 run_datafix.py roles    re-export and bulk-update the lookup-implied roles (variant A)
  python3 run_datafix.py recount  count what is left

Order: code fix live first (Rest_UpsertAccount 64f920c), then plan → merge → ids → roles → recount.
DATAFIX_ORG=acc runs the same against acc (test). A duplicate platform id makes that one update fail (unique field), logged.
Everything reads prod fresh; nothing is taken from an older export.
"""
import csv, json, os, subprocess, sys, time, collections, glob

csv.field_size_limit(10 ** 9)
ORG = os.environ.get('DATAFIX_ORG', 'prod')
HERE = os.path.dirname(os.path.abspath(__file__))
RUNS = os.path.join(HERE, 'run', ORG)
UNIQUE = ['Main', 'Invoice', 'Shipping', 'Reminder', 'Digital', 'Payment']
EMAIL_ROLES = {'Main', 'Invoice', 'Digital', 'Reminder', 'Payment'}
LOOK = [('Main', 'Account.Contact_person__c'), ('Invoice', 'Account.Contact_Billing__c'),
        ('Shipping', 'Account.Contact_Shipping__c'), ('Reminder', 'Account.Subscription25__Reminder_Contact__c'),
        ('Digital', 'Account.Subscription25__UBL_Billing_Attendant_To__c')]


def sf(args, parse=True):
    r = subprocess.run(['sf'] + args, capture_output=True, text=True)
    if not parse:
        return r.stdout + r.stderr
    out = r.stdout[r.stdout.find('{'):]
    return json.loads(out) if out else {}


def export(soql, path):
    sf(['data', 'export', 'bulk', '-o', ORG, '-q', soql, '--output-file', path, '--result-format', 'csv', '--wait', '30'], parse=False)
    return list(csv.DictReader(open(path, encoding='utf-8')))


def latest_run():
    runs = sorted(glob.glob(os.path.join(RUNS, '*')))
    if not runs:
        sys.exit('no plan yet: run "plan" first')
    return runs[-1]


def roles_of(value):
    return [x for x in (value or '').split(';') if x]


def plan():
    d = os.path.join(RUNS, time.strftime('%Y%m%d-%H%M%S'))
    os.makedirs(d)
    contacts = export("SELECT Id, AccountId, Email, Name, CreatedDate, CreatedBy.Name FROM Contact WHERE Email != null AND AccountId != null", d + '/contacts.csv')
    acrs = export("SELECT Id, AccountId, ContactId, Roles, extId_1__c, extId_2__c, extId_3__c, extId_4__c, extId_5__c, extId_6__c, "
                  "isAdministrator_1__c, isAdministrator_2__c, isAdministrator_3__c, isAdministrator_4__c, isAdministrator_5__c, isAdministrator_6__c "
                  "FROM AccountContactRelation", d + '/backup_relations.csv')
    acr = {(r['AccountId'], r['ContactId']): r for r in acrs}

    def info(c):
        a = acr.get((c['AccountId'], c['Id'])) or {}
        ext = {i: a.get('extId_%d__c' % i) for i in range(1, 7) if a.get('extId_%d__c' % i)}
        return {'roles': roles_of(a.get('Roles')), 'real': {i: x for i, x in ext.items() if not x.endswith('a')}}

    groups = collections.defaultdict(list)
    for c in contacts:
        groups[(c['AccountId'], c['Email'].strip().lower())].append(c)
    auto, review = [], []
    for v in groups.values():
        if len(v) < 2:
            continue
        inf = {c['Id']: info(c) for c in v}
        names = {(c['Name'] or '').strip().lower() for c in v}
        master = sorted(v, key=lambda c: (-len(inf[c['Id']]['real']), -len(inf[c['Id']]['roles']), c['CreatedDate']))[0]
        reasons = []
        if len(names) > 1:
            reasons.append('different names')
        if any(len([c for c in v if p in inf[c['Id']]['real']]) > 1 for p in range(1, 7)):
            reasons.append('two real platform ids on one platform')
        entry = {'account': master['AccountId'], 'email': master['Email'], 'name': master['Name'], 'master': master['Id'],
                 'losers': [c['Id'] for c in v if c is not master], 'reasons': reasons}
        (review if reasons else auto).append(entry)
    json.dump(auto, open(d + '/merge_plan.json', 'w'))
    with open(d + '/merge_review.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['AccountId', 'Email', 'Name', 'ContactIds', 'Reason'])
        for e in review:
            w.writerow([e['account'], e['email'], e['name'], ';'.join([e['master']] + e['losers']), ', '.join(e['reasons'])])
    print('plan', d)
    print('merge automatically:', len(auto), 'groups,', sum(len(e['losers']) for e in auto), 'contacts | review:', len(review))


def merge():
    d = latest_run()
    groups = json.load(open(d + '/merge_plan.json'))
    template = open(os.path.join(HERE, 'merge', 'merge_template.apex')).read()
    log = open(d + '/merge_results.txt', 'a')
    counts = collections.Counter()
    for i in range(0, len(groups), 20):
        chunk = groups[i:i + 20]
        body = json.dumps([{'account': g['account'], 'master': g['master'], 'losers': g['losers']} for g in chunk])
        path = d + '/chunk.apex'
        open(path, 'w').write(template.replace('__PLAN__', body.replace("'", "\\'")))
        out = sf(['apex', 'run', '-o', ORG, '-f', path], parse=False)
        lines = [l.split('RESULT ', 1)[1].replace('&#124;', '|') for l in out.splitlines() if '|DEBUG|RESULT ' in l]
        if len(lines) != len(chunk):
            lines.append('CHUNKERROR|%d|%s' % (i, out[-300:].replace('\n', ' ')))
        for l in lines:
            log.write(l + '\n')
            counts[l.split('|')[0]] += 1
        log.flush()
        print('groups %d-%d: %s' % (i + 1, i + len(chunk), dict(counts)), flush=True)
        if counts['FAIL'] + counts['CHUNKERROR'] > 50:
            sys.exit('stopped: more than 50 failures, see merge_results.txt')


def ids():
    d = latest_run()
    logs = export("SELECT Id, CreatedDate, Request_Body__c FROM OAuth_Log__c WHERE Event_Log__r.Action__c = 'RestUpsertAccount'", d + '/oauth.csv')
    real = {}
    for r in logs:
        try:
            p = json.loads(r['Request_Body__c'])
        except Exception:
            continue
        low = {k.lower(): v for k, v in p.items()}
        for c in low.get('contactdtos') or []:
            cl = {k.lower(): v for k, v in c.items()}
            if cl.get('salesforceid') and cl.get('id') and not str(cl['id']).endswith('a'):
                key = (str(low.get('platformid')), cl['salesforceid'][:15])
                if key not in real or r['CreatedDate'] > real[key][2]:
                    real[key] = (str(cl['id']), bool(cl.get('isadministrator')), r['CreatedDate'])
    acrs = export("SELECT Id, ContactId, extId_1__c, extId_2__c, extId_3__c, extId_5__c FROM AccountContactRelation "
                  "WHERE extId_1__c LIKE '%a' OR extId_2__c LIKE '%a' OR extId_3__c LIKE '%a' OR extId_5__c LIKE '%a'", d + '/synthetic.csv')
    fixes = []
    for a in acrs:
        for p in ('1', '2', '3', '5'):
            v = a['extId_%s__c' % p]
            if v and v.endswith('a') and (p, a['ContactId'][:15]) in real:
                rid, adm, _ = real[(p, a['ContactId'][:15])]
                fixes.append({'id': a['Id'], 'p': p, 'ext': rid, 'adm': adm})
    print('platform ids to restore:', len(fixes))
    if not fixes:
        return
    apex = ("List<Object> f = (List<Object>) JSON.deserializeUntyped('%s');\nList<AccountContactRelation> upd = new List<AccountContactRelation>();\n"
            "for (Object o : f) { Map<String, Object> m = (Map<String, Object>) o; String p = (String) m.get('p');\n"
            "  AccountContactRelation a = new AccountContactRelation(Id = (Id) m.get('id')); a.put('extId_' + p + '__c', m.get('ext')); a.put('isAdministrator_' + p + '__c', m.get('adm')); upd.add(a); }\n"
            "for (Database.SaveResult r : Database.update(upd, false)) System.debug('RESULT ' + r.isSuccess() + ' ' + r.getId() + ' ' + (r.isSuccess() ? '' : r.getErrors()[0].getMessage()));\n") % json.dumps(fixes).replace("'", "\\'")
    path = d + '/ids.apex'
    open(path, 'w').write(apex)
    out = sf(['apex', 'run', '-o', ORG, '-f', path], parse=False)
    res = [l.split('RESULT ', 1)[1] for l in out.splitlines() if '|DEBUG|RESULT ' in l]
    open(d + '/ids_results.txt', 'w').write('\n'.join(res))
    print('ids restored:', sum(1 for r in res if r.startswith('true')), '| failed:', sum(1 for r in res if r.startswith('false')))


def roles():
    d = latest_run()
    rows = export("SELECT Id, AccountId, ContactId, Roles, Contact.Email, Account.Contact_person__c, Account.Contact_Billing__c, "
                  "Account.Contact_Shipping__c, Account.Subscription25__Reminder_Contact__c, Account.Subscription25__UBL_Billing_Attendant_To__c "
                  "FROM AccountContactRelation", d + '/roles_export.csv')
    by = collections.defaultdict(list)
    for r in rows:
        by[r['AccountId']].append(r)
    add = {}
    for acc, rs in by.items():
        a = rs[0]
        holder = collections.defaultdict(set)
        for r in rs:
            for x in roles_of(r['Roles']):
                holder[x].add(r['Id'])
        contacts = {r['ContactId']: r for r in rs}
        for role, field in LOOK:
            r = contacts.get(a[field])
            if not r or role in roles_of(r['Roles']):
                continue
            if role in EMAIL_ROLES and not r['Contact.Email']:
                continue
            if holder[role] - {r['Id']}:
                continue
            add.setdefault(r['Id'], set()).add(role)
    byid = {r['Id']: r for r in rows}
    ordered = sorted(add, key=lambda rid: byid[rid]['AccountId'])
    with open(d + '/roles_backup.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['Id', 'Roles'])
        for rid in ordered:
            w.writerow([rid, byid[rid]['Roles'] or ''])
    with open(d + '/roles_update.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['Id', 'Roles'])
        for rid in ordered:
            cur = roles_of(byid[rid]['Roles'])
            w.writerow([rid, ';'.join(cur + [x for x in ['Main', 'Invoice', 'Shipping', 'Reminder', 'Digital'] if x in add[rid] and x not in cur])])
    print('relations to update:', len(ordered))
    if not ordered:
        return
    res = sf(['data', 'update', 'bulk', '-o', ORG, '--sobject', 'AccountContactRelation', '--file', d + '/roles_update.csv', '--column-delimiter', 'COMMA', '--line-ending', 'LF', '--wait', '60', '--json'])
    json.dump(res, open(d + '/roles_bulk_output.json', 'w'))
    r = res.get('result', {})
    print('bulk job', r.get('jobId'), '| processed', r.get('processedRecords'), '| successful', r.get('successfulRecords'), '| failed', r.get('failedRecords'))
    if r.get('failedRecords'):
        print('failed rows: sf data bulk results -o %s --job-id %s' % (ORG, r.get('jobId')))


def recount():
    d = latest_run()
    contacts = export("SELECT Id, AccountId, Email FROM Contact WHERE Email != null AND AccountId != null", d + '/recount_contacts.csv')
    g = collections.Counter((c['AccountId'], c['Email'].strip().lower()) for c in contacts)
    print('accounts + email with 2 or more contacts:', sum(1 for v in g.values() if v > 1))
    for p in ('1', '2', '3', '5'):
        n = sf(['data', 'query', '-o', ORG, '-q', "SELECT COUNT() FROM AccountContactRelation WHERE extId_%s__c LIKE '%%a'" % p, '--json'])
        print('platform %s synthetic ids:' % p, n.get('result', {}).get('totalSize'))


if __name__ == '__main__':
    {'plan': plan, 'merge': merge, 'ids': ids, 'roles': roles, 'recount': recount}[sys.argv[1]]()
