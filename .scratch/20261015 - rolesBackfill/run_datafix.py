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
import csv, json, os, subprocess, sys, time, collections, glob, random

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


def log(d, msg):
    line = time.strftime('%Y-%m-%d %H:%M:%S') + ' ' + msg
    print(line, flush=True)
    with open(os.path.join(d, 'datafix.log'), 'a') as f:
        f.write(line + '\n')


def q(soql, all_rows=False):
    args = ['data', 'query', '-o', ORG, '-q', soql, '--json']
    if all_rows:
        args.append('--all-rows')
    res = sf(args)
    if res.get('status') not in (0, None):
        raise RuntimeError('query failed: %s' % res.get('message'))
    return res.get('result', {}).get('records', [])


def ids_in(ids):
    return "('" + "','".join(sorted(set(ids))) + "')"


def snapshot(account_ids, contact_ids):
    """Accounts (lookups), contacts (incl. deleted / merged), their relations and preference counts."""
    accs = q("SELECT Id, Name, Contact_person__c, Contact_Billing__c, Contact_Shipping__c, Subscription25__Reminder_Contact__c, "
             "Subscription25__UBL_Billing_Attendant_To__c FROM Account WHERE Id IN " + ids_in(account_ids))
    cons = q("SELECT Id, Name, Email, AccountId, IsDeleted, MasterRecordId FROM Contact WHERE Id IN " + ids_in(contact_ids), all_rows=True)
    acrs = q("SELECT Id, AccountId, ContactId, Roles, FinancialIdContact__c, extId_1__c, extId_2__c, extId_3__c, extId_4__c, extId_5__c, extId_6__c, "
             "isAdministrator_1__c, isAdministrator_2__c, isAdministrator_3__c, isAdministrator_4__c, isAdministrator_5__c, isAdministrator_6__c "
             "FROM AccountContactRelation WHERE AccountId IN " + ids_in(account_ids) + " AND ContactId IN " + ids_in(contact_ids))
    prefs = q("SELECT Contact__c c, COUNT(Id) n FROM CommunicationPreference__c WHERE Contact__c IN " + ids_in(contact_ids) + " GROUP BY Contact__c")
    strip = lambda rs: [{k: v for k, v in r.items() if k != 'attributes'} for r in rs]
    return {'accounts': {r['Id']: r for r in strip(accs)}, 'contacts': {r['Id']: r for r in strip(cons)},
            'relations': {r['ContactId']: r for r in strip(acrs)}, 'prefs': {r['c']: r['n'] for r in prefs}}


def error_logs(since_iso):
    return q("SELECT Id, CreatedDate, Action__c, Context_Id__c, Result_Status__c, Message__c FROM Event_Log__c "
             "WHERE CreatedDate >= " + since_iso + " AND Result_Status__c IN ('ERROR','UNHANDLED_EXCEPTION')")


def utcnow():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


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


def done_masters(d):
    """Groups already handled (OK / SKIP) in an earlier round; FAIL groups are retried."""
    path = d + '/merge_results.txt'
    if not os.path.exists(path):
        return set()
    return {l.split('|')[1] for l in open(path) if l.split('|')[0] in ('OK', 'SKIP')}


def merge():
    """merge [N]: N random groups not handled yet (a test round), or all remaining groups without N."""
    d = latest_run()
    only_failed = len(sys.argv) > 2 and sys.argv[2] == 'failed'
    n = int(sys.argv[2]) if len(sys.argv) > 2 and not only_failed else None
    groups = json.load(open(d + '/merge_plan.json'))
    done = done_masters(d)
    todo = [g for g in groups if g['master'] not in done]
    if only_failed:
        failed = {l.split('|')[1] for l in open(d + '/merge_results.txt') if l.split('|')[0] in ('FAIL', 'CHUNKERROR')}
        todo = [g for g in todo if g['master'] in failed]
    if n:
        random.seed()
        todo = random.sample(todo, min(n, len(todo)))
    rnd = os.path.join(d, 'merge_round_%s_%s' % (time.strftime('%H%M%S'), 'failed' if only_failed else (n or 'all')))
    os.makedirs(rnd)
    log(d, 'merge round %s: %d groups (%d of %d already handled) -> %s' % (n or 'all', len(todo), len(done), len(groups), rnd))
    json.dump(todo, open(rnd + '/groups.json', 'w'), indent=1)
    sample = n is not None or only_failed
    account_ids = [g['account'] for g in todo]
    contact_ids = [c for g in todo for c in [g['master']] + g['losers']]
    if sample:
        before = snapshot(account_ids, contact_ids)
        json.dump(before, open(rnd + '/before.json', 'w'), indent=1)
    start = utcnow()
    template = open(os.path.join(HERE, 'merge', os.environ.get('DATAFIX_TEMPLATE', 'merge_template.apex'))).read()
    out_all = open(d + '/merge_results.txt', 'a')
    out_rnd = open(rnd + '/results.txt', 'w')
    counts = collections.Counter()
    results = {}
    def run_chunk(chunk, tag):
        body = json.dumps([{'account': g['account'], 'master': g['master'], 'losers': g['losers']} for g in chunk])
        path = rnd + '/chunk.apex'
        open(path, 'w').write(template.replace('__PLAN__', body.replace("'", "\\'")))
        out = sf(['apex', 'run', '-o', ORG, '-f', path], parse=False)
        lines = [l.split('RESULT ', 1)[1].replace('&#124;', '|') for l in out.splitlines() if '|DEBUG|RESULT ' in l]
        if len(lines) != len(chunk):
            open(rnd + '/chunk_%s_output.txt' % tag, 'w').write(out)
            return None, out
        return lines, out

    CHUNK = 5
    for i in range(0, len(todo), CHUNK):
        chunk = todo[i:i + CHUNK]
        lines, out = run_chunk(chunk, i)
        if lines is None:
            # whole transaction rolled back (e.g. SOQL limit): retry the groups one by one
            lines = []
            for j, g in enumerate(chunk):
                one, out1 = run_chunk([g], '%d_%d' % (i, j))
                lines += one if one is not None else ['CHUNKERROR|%s|%s' % (g['master'], out1[-200:].replace('\n', ' '))]
        for l in lines:
            out_all.write(l + '\n')
            out_rnd.write(l + '\n')
            counts[l.split('|')[0]] += 1
            results[l.split('|')[1]] = l
        out_all.flush()
        out_rnd.flush()
        if i % 200 == 0 or i + CHUNK >= len(todo):
            log(d, 'groups %d-%d: %s' % (i + 1, i + len(chunk), dict(counts)))
        if counts['FAIL'] + counts['CHUNKERROR'] > 50:
            log(d, 'STOPPED: more than 50 failures, see merge_results.txt')
            sys.exit(1)
    errs = error_logs(start)
    json.dump(errs, open(rnd + '/error_logs_during_run.json', 'w'), indent=1)
    log(d, 'merge round done: %s | Event_Log errors during the run (any source): %d' % (dict(counts), len(errs)))
    if sample:
        after = snapshot(account_ids, contact_ids)
        json.dump(after, open(rnd + '/after.json', 'w'), indent=1)
        write_merge_check(rnd, todo, before, after, results)
        log(d, 'check file: ' + rnd + '/check.csv')


def write_merge_check(rnd, todo, before, after, results):
    look = ['Contact_person__c', 'Contact_Billing__c', 'Contact_Shipping__c', 'Subscription25__Reminder_Contact__c', 'Subscription25__UBL_Billing_Attendant_To__c']
    ext = lambda r: ' '.join('p%d=%s' % (p, r.get('extId_%d__c' % p)) for p in range(1, 7) if r and r.get('extId_%d__c' % p))
    with open(rnd + '/check.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['Result', 'Account', 'AccountId', 'Email', 'Master', 'MasterId', 'LoserIds', 'LosersMergedIntoMaster',
                    'MasterRolesBefore', 'LoserRolesBefore', 'MasterRolesAfter', 'MasterPlatformIdsBefore', 'LoserPlatformIdsBefore',
                    'MasterPlatformIdsAfter', 'LookupsPointingToLosersBefore', 'LookupsPointingToLosersAfter',
                    'PreferencesBefore(master+losers)', 'PreferencesAfter(master)', 'RelationUrl'])
        for g in todo:
            m, ls = g['master'], g['losers']
            acc_b, acc_a = before['accounts'].get(g['account'], {}), after['accounts'].get(g['account'], {})
            merged = all(after['contacts'].get(x, {}).get('IsDeleted') and after['contacts'][x].get('MasterRecordId') == m for x in ls)
            mr_b, mr_a = before['relations'].get(m), after['relations'].get(m)
            w.writerow([
                (results.get(m) or 'NO RESULT').split('|')[0] + ('' if (results.get(m) or '').startswith('OK') else ': ' + (results.get(m) or '').split('|')[-1]),
                acc_b.get('Name'), g['account'], g.get('email', g.get('masterEmail')), g['name'], m, ';'.join(ls), 'yes' if merged else 'NO',
                (mr_b or {}).get('Roles'), ' | '.join('%s' % ((before['relations'].get(x) or {}).get('Roles')) for x in ls), (mr_a or {}).get('Roles'),
                ext(mr_b), ' | '.join(ext(before['relations'].get(x)) for x in ls), ext(mr_a),
                ';'.join(k for k in look if acc_b.get(k) in ls), ';'.join(k for k in look if acc_a.get(k) in ls),
                sum(before['prefs'].get(x, 0) for x in [m] + ls), after['prefs'].get(m, 0),
                'https://movingintelligence.lightning.force.com/lightning/r/AccountContactRelation/%s/view' % (mr_a or {}).get('Id', '')])


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
    """roles [N]: N random relations (a test round), or all without N."""
    d = latest_run()
    n = int(sys.argv[2]) if len(sys.argv) > 2 else None
    rnd = os.path.join(d, 'roles_round_%s_%s' % (time.strftime('%H%M%S'), n or 'all'))
    os.makedirs(rnd)
    rows = export("SELECT Id, AccountId, ContactId, Roles, Contact.Email, Account.Contact_person__c, Account.Contact_Billing__c, "
                  "Account.Contact_Shipping__c, Account.Subscription25__Reminder_Contact__c, Account.Subscription25__UBL_Billing_Attendant_To__c "
                  "FROM AccountContactRelation", rnd + '/roles_export.csv')
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
    log(d, 'roles round %s: %d relations need a role' % (n or 'all', len(ordered)))
    if n:
        random.seed()
        ordered = sorted(random.sample(ordered, min(n, len(ordered))), key=lambda rid: byid[rid]['AccountId'])
    start = utcnow()
    with open(rnd + '/roles_backup.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['Id', 'Roles'])
        for rid in ordered:
            w.writerow([rid, byid[rid]['Roles'] or ''])
    with open(rnd + '/roles_update.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['Id', 'Roles'])
        for rid in ordered:
            cur = roles_of(byid[rid]['Roles'])
            w.writerow([rid, ';'.join(cur + [x for x in ['Main', 'Invoice', 'Shipping', 'Reminder', 'Digital'] if x in add[rid] and x not in cur])])
    log(d, 'roles round: updating %d relations -> %s' % (len(ordered), rnd))
    if not ordered:
        return
    res = sf(['data', 'update', 'bulk', '-o', ORG, '--sobject', 'AccountContactRelation', '--file', rnd + '/roles_update.csv', '--column-delimiter', 'COMMA', '--line-ending', 'LF', '--wait', '60', '--json'])
    json.dump(res, open(rnd + '/roles_bulk_output.json', 'w'), indent=1)
    r = res.get('result', {})
    log(d, 'bulk job %s | processed %s | successful %s | failed %s' % (r.get('jobId'), r.get('processedRecords'), r.get('successfulRecords'), r.get('failedRecords')))
    if r.get('failedRecords'):
        out = sf(['data', 'bulk', 'results', '-o', ORG, '--job-id', r.get('jobId')], parse=False)
        open(rnd + '/bulk_results_output.txt', 'w').write(out)
        log(d, 'failed rows saved via: sf data bulk results -o %s --job-id %s (output in bulk_results_output.txt)' % (ORG, r.get('jobId')))
    errs = error_logs(start)
    json.dump(errs, open(rnd + '/error_logs_during_run.json', 'w'), indent=1)
    log(d, 'Event_Log errors during the run (any source): %d' % len(errs))
    if n:
        after = {r['Id']: r for r in q("SELECT Id, Account.Name, AccountId, Contact.Name, Roles FROM AccountContactRelation WHERE Id IN " + ids_in(ordered))}
        with open(rnd + '/check.csv', 'w', newline='') as f:
            w = csv.writer(f, lineterminator='\n')
            w.writerow(['Account', 'AccountId', 'Contact', 'RelationId', 'RolesBefore', 'RolesAdded', 'RolesAfter', 'AsExpected', 'RelationUrl'])
            for rid in ordered:
                a = after.get(rid, {})
                want = set(roles_of(byid[rid]['Roles'])) | add[rid]
                w.writerow([(a.get('Account') or {}).get('Name'), byid[rid]['AccountId'], (a.get('Contact') or {}).get('Name'), rid, byid[rid]['Roles'],
                            ';'.join(sorted(add[rid])), a.get('Roles'), 'yes' if set(roles_of(a.get('Roles'))) == want else 'NO',
                            'https://movingintelligence.lightning.force.com/lightning/r/AccountContactRelation/%s/view' % rid])
        log(d, 'check file: ' + rnd + '/check.csv')


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
