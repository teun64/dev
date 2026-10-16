#!/usr/bin/env python3
"""
Replay test of the role rules (user 2026-10-15): N random accounts whose last platform call was BEFORE the fix
(Rest_UpsertAccount roles, prod 2026-10-15 09:15 UTC) and none after; repair their lookup-implied roles; replay the
logged request body; compare before / after.

  python3 replay_test.py select 10     choose + snapshot (read-only)
  python3 replay_test.py repair        backfill the roles of the selected accounts (variant A rules)
  python3 replay_test.py replay        replay the logged bodies, snapshot again, write compare.csv

Output: run/prod/<plan>/replay_test_<ts>/ (log, selection, snapshots, request/response per account, compare.csv).
"""
import csv, json, os, sys, time, random, glob, collections, calendar
import run_datafix as R

FIX = '2026-10-15T09:15:00.000+0000'


def rdir():
    if sys.argv[1] == 'select':
        d = os.path.join(R.latest_run(), 'replay_test_' + time.strftime('%H%M%S'))
        os.makedirs(d)
        return d
    return sorted(glob.glob(os.path.join(R.latest_run(), 'replay_test_*')))[-1]


def state(account_ids):
    accs = R.q("SELECT Id, Name, LastModifiedDate, LastModifiedBy.Name, Contact_person__c, Contact_Billing__c, Contact_Shipping__c, "
               "Subscription25__Reminder_Contact__c, Subscription25__UBL_Billing_Attendant_To__c, BillingStreet, BillingPostalCode, BillingCity, "
               "ShippingStreet, InvoiceAddress__Street__s, Bank_Account_Number__c, Payment_Method_Contracts__c FROM Account WHERE Id IN " + R.ids_in(account_ids))
    acrs = R.q("SELECT Id, AccountId, ContactId, Contact.Name, Contact.Email, Contact.LastModifiedDate, Roles, IsDirect, LastModifiedDate, LastModifiedBy.Name, "
               "extId_1__c, extId_2__c, extId_3__c, extId_5__c, isAdministrator_1__c, isVisible_1__c, isDeleted_1__c "
               "FROM AccountContactRelation WHERE AccountId IN " + R.ids_in(account_ids))
    out = {}
    for a in accs:
        a.pop('attributes', None)
        out[a['Id']] = {'account': a, 'relations': {}}
    for r in acrs:
        r.pop('attributes', None)
        out[r['AccountId']]['relations'][r['Id']] = r
    return out


def needed_roles(st):
    """Variant A on one account's state: relation id -> roles to add."""
    a, rels = st['account'], list(st['relations'].values())
    holder = collections.defaultdict(set)
    for r in rels:
        for x in R.roles_of(r['Roles']):
            holder[x].add(r['Id'])
    by_contact = {r['ContactId']: r for r in rels}
    add = {}
    for role, field in R.LOOK:
        r = by_contact.get(a.get(field.split('.')[1]))
        if not r or role in R.roles_of(r['Roles']):
            continue
        if role in R.EMAIL_ROLES and not (r.get('Contact') or {}).get('Email'):
            continue
        if holder[role] - {r['Id']}:
            continue
        add.setdefault(r['Id'], set()).add(role)
    return add


def select():
    d = rdir()
    n = int(sys.argv[2])
    logs = R.export("SELECT Id, CreatedDate, Endpoint__c, Record_Id__c, Status_Code__c, Request_Body__c, Response_Body__c, Event_Log__r.CreatedBy.Name "
                    "FROM OAuth_Log__c WHERE Event_Log__r.Action__c = 'RestUpsertAccount' AND Method__c = 'POST'", d + '/platform_calls.csv')
    by_acc = collections.defaultdict(list)
    for l in logs:
        try:
            body = json.loads(l['Request_Body__c'])
        except Exception:
            continue
        acc = body.get('salesforceId') or l['Record_Id__c']
        if acc and acc.startswith('001'):
            by_acc[acc[:15]].append((l, body))
    merged = set()
    for f in glob.glob(os.path.join(R.latest_run(), 'merge_round_*', 'groups.json')):
        merged |= {g['account'][:15] for g in json.load(open(f))}
    cands = []
    for acc, calls in by_acc.items():
        calls.sort(key=lambda x: x[0]['CreatedDate'])
        last, body = calls[-1]
        if last['CreatedDate'] >= FIX or acc in merged or last['Status_Code__c'] not in ('200', '200.0'):
            continue
        cands.append((acc, last, body, len(calls)))
    R.log(d, 'accounts with a platform call before the fix and none after: %d (of %d with calls)' % (len(cands), len(by_acc)))
    random.seed()
    random.shuffle(cands)
    chosen, rejected = [], collections.Counter()
    for i in range(0, len(cands), 50):
        batch = cands[i:i + 50]
        st = state([c[0] for c in batch])
        st15 = {k[:15]: v for k, v in st.items()}
        for acc, last, body, ncalls in batch:
            s = st15.get(acc)
            if not s:
                rejected['account gone'] += 1
                continue
            t = last['CreatedDate'][:19]
            # guard: nothing changed after the logged call (2 min margin for the call's own async work)
            limit = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(calendar.timegm(time.strptime(t, '%Y-%m-%dT%H:%M:%S')) + 120))
            stamps = [s['account']['LastModifiedDate'][:19]] + [r['LastModifiedDate'][:19] for r in s['relations'].values()] \
                + [((r.get('Contact') or {}).get('LastModifiedDate') or '')[:19] for r in s['relations'].values()]
            if max(stamps) > limit:
                rejected['changed after the call'] += 1
                continue
            add = needed_roles(s)
            if not add:
                rejected['no role missing'] += 1
                continue
            payload_rel = {(c.get('salesforceId') or '')[:15] for c in (body.get('contactDTOs') or [])}
            if not any(rid[:15] in payload_rel for rid in add):
                rejected['repaired relation not in payload'] += 1
                continue
            chosen.append({'account': s['account']['Id'], 'name': s['account']['Name'], 'callId': last['Id'], 'callDate': last['CreatedDate'],
                           'caller': last['Event_Log__r.CreatedBy.Name'], 'endpoint': last['Endpoint__c'], 'callsInLog': ncalls,
                           'add': {k: sorted(v) for k, v in add.items()}, 'body': body, 'originalResponse': last['Response_Body__c']})
            if len(chosen) == n:
                break
        if len(chosen) == n:
            break
    json.dump(chosen, open(d + '/selection.json', 'w'), indent=1)
    json.dump(state([c['account'] for c in chosen]), open(d + '/state_0_before_repair.json', 'w'), indent=1)
    R.log(d, 'selected %d accounts; rejected while sampling: %s' % (len(chosen), dict(rejected)))
    for c in chosen:
        R.log(d, '  %s %s | last call %s by %s (%s) | roles to add: %s' % (c['account'], c['name'], c['callDate'], c['caller'], c['endpoint'],
              {k: v for k, v in c['add'].items()}))


def repair():
    d = rdir()
    chosen = json.load(open(d + '/selection.json'))
    st = state([c['account'] for c in chosen])
    rows = []
    for c in chosen:
        add = needed_roles(st[c['account']])  # recomputed on the live state
        for rid, roles in add.items():
            cur = R.roles_of(st[c['account']]['relations'][rid]['Roles'])
            rows.append({'Id': rid, 'Roles': ';'.join(cur + [x for x in ['Main', 'Invoice', 'Shipping', 'Reminder', 'Digital'] if x in roles and x not in cur])})
    start = R.utcnow()
    apex = ("List<Object> f = (List<Object>) JSON.deserializeUntyped('%s');\nList<AccountContactRelation> upd = new List<AccountContactRelation>();\n"
            "for (Object o : f) { Map<String, Object> m = (Map<String, Object>) o; upd.add(new AccountContactRelation(Id = (Id) m.get('Id'), Roles = (String) m.get('Roles'))); }\n"
            "for (Database.SaveResult r : Database.update(upd, false)) System.debug('RESULT ' + r.isSuccess() + ' ' + r.getId() + ' ' + (r.isSuccess() ? '' : r.getErrors()[0].getMessage()));\n") % json.dumps(rows).replace("'", "\\'")
    open(d + '/repair.apex', 'w').write(apex)
    out = R.sf(['apex', 'run', '-o', R.ORG, '-f', d + '/repair.apex'], parse=False)
    res = [l.split('RESULT ', 1)[1] for l in out.splitlines() if '|DEBUG|RESULT ' in l]
    open(d + '/repair_results.txt', 'w').write('\n'.join(res) + '\n')
    if len(res) != len(rows):
        open(d + '/repair_output.txt', 'w').write(out)
    errs = R.error_logs(start)
    json.dump(errs, open(d + '/repair_error_logs.json', 'w'), indent=1)
    json.dump(state([c['account'] for c in chosen]), open(d + '/state_1_after_repair.json', 'w'), indent=1)
    R.log(d, 'repair: %d relations, ok %d, failed %d, Event_Log errors %d' % (len(rows), sum(r.startswith('true') for r in res), sum(r.startswith('false') for r in res), len(errs)))


def replay():
    d = rdir()
    chosen = json.load(open(d + '/selection.json'))
    os.makedirs(d + '/calls', exist_ok=True)
    start = R.utcnow()
    for c in chosen:
        path = d + '/calls/%s_request.json' % c['account']
        json.dump(c['body'], open(path, 'w'))
        out = R.sf(['api', 'request', 'rest', '/services/apexrest' + c['endpoint'], '--method', 'POST', '--body', '@' + path, '-o', R.ORG], parse=False)
        open(d + '/calls/%s_response.txt' % c['account'], 'w').write(out)
        R.log(d, 'replayed %s %s -> %s' % (c['account'], c['name'], out.strip().replace('\n', ' ')[:200]))
    time.sleep(20)  # let the call's own async work (queueables) finish
    errs = R.error_logs(start)
    json.dump(errs, open(d + '/replay_error_logs.json', 'w'), indent=1)
    before = json.load(open(d + '/state_1_after_repair.json'))
    orig = json.load(open(d + '/state_0_before_repair.json'))
    after = state([c['account'] for c in chosen])
    json.dump(after, open(d + '/state_2_after_replay.json', 'w'), indent=1)
    look = ['Contact_person__c', 'Contact_Billing__c', 'Contact_Shipping__c', 'Subscription25__Reminder_Contact__c', 'Subscription25__UBL_Billing_Attendant_To__c']
    fields = ['Roles', 'extId_1__c', 'extId_2__c', 'extId_3__c', 'extId_5__c', 'isAdministrator_1__c', 'isVisible_1__c', 'isDeleted_1__c']
    ok_all = True
    with open(d + '/compare.csv', 'w', newline='') as f:
        w = csv.writer(f, lineterminator='\n')
        w.writerow(['Account', 'AccountId', 'Relation', 'Contact', 'RolesOriginal', 'RolesAfterRepair', 'RolesAfterReplay', 'RolesKept',
                    'OtherRelationFieldChanges', 'RelationsBefore/After', 'AccountLookupChanges', 'AccountFieldChanges', 'Url'])
        for c in chosen:
            a = c['account']
            b, x, o = before[a], after[a], orig[a]
            lk = ['%s: %s -> %s' % (k, b['account'].get(k), x['account'].get(k)) for k in look if b['account'].get(k) != x['account'].get(k)]
            af = ['%s: %s -> %s' % (k, b['account'].get(k), x['account'].get(k)) for k in b['account']
                  if k not in look and k not in ('LastModifiedDate', 'LastModifiedBy') and b['account'].get(k) != x['account'].get(k)]
            for rid in sorted(set(b['relations']) | set(x['relations'])):
                rb, rx, ro = b['relations'].get(rid, {}), x['relations'].get(rid, {}), o['relations'].get(rid, {})
                kept = set(R.roles_of(rb.get('Roles'))) <= set(R.roles_of(rx.get('Roles')))
                ok_all &= kept
                other = ['%s: %s -> %s' % (k, rb.get(k), rx.get(k)) for k in fields[1:] if rb.get(k) != rx.get(k)]
                w.writerow([b['account']['Name'], a, rid, ((rx or rb).get('Contact') or {}).get('Name'), ro.get('Roles'), rb.get('Roles'), rx.get('Roles'),
                            'yes' if kept else 'NO', '; '.join(other), '%d/%d' % (len(b['relations']), len(x['relations'])), '; '.join(lk), '; '.join(af),
                            'https://movingintelligence.lightning.force.com/lightning/r/Account/%s/view' % a])
    R.log(d, 'replay done: all repaired roles kept = %s | Event_Log errors during replay (any source): %d | compare.csv written' % (ok_all, len(errs)))


if __name__ == '__main__':
    {'select': select, 'repair': repair, 'replay': replay}[sys.argv[1]]()
