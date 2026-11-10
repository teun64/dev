"""Build the 2G Migratie Growth email drafts (mail 1-3) from marketing's own prod mail "2g-4gvervangen".

Usage: python3 build_drafts.py <base content.json> <out dir>
Writes <out>/<env>/digitalExperiences/... (mdapi layout, one item per mail) for dev and prod image refs,
plus <out>/preview.html (same texts, for review by marketing).
"""
import copy, html, json, os, re, sys, uuid

BASE, OUT = sys.argv[1], sys.argv[2]
WS = 'Default_Content_Workspace'
FOLDER = {'dev': 'Moving Intelligence/Campaigns/Year 2026/M20261109 2G Migratie',
          'prod': 'Emails/M20261109 2G Migratie'}
# header "Mailing switch 2g 4g header" and logo "Logo_Moving intelligence_Black_Red_RGB[33]" per org
IMAGES = {'dev': {'MCJQ2MS5XXGJE6LFIRM34WVVWSNE': 'MCCYOX7B4IKZGYLA65VTJXO3NZLM',
                  'MC2N2AWKSBK5B6DENZ5S2WTZCK5M': 'MCP4BBR4BDUFHRVHZDUTJ5CPPZ4Q'},
          'prod': {}}

# Growth only accepts real URLs, so TOKEN marks where the personal token goes. Marketing replaces the whole link with
# the merge field once Growth can read CampaignMember.ResponseUrl__c / Contact.Preference_Center_Url__c (Data Cloud).
HUB = {'dev': 'https://movingintelligence--dev.sandbox.my.site.com/hub', 'prod': 'https://customer.movingintelligence.com'}
RESPONSE_URL = {e: h + '/response?token=TOKEN' for e, h in HUB.items()}
PREFERENCE_URL = {e: h + '/preferences?token=TOKEN' for e, h in HUB.items()}

HARDWARE = [
    ('Mi50', 'Uw <strong>Mi50</strong> verbindt via 2G. Wij vervangen hem door de 4G-versie van de Mi50, met dezelfde functies als u nu gebruikt.'),
    ('Mi40', 'Uw <strong>Mi40</strong> verbindt via 2G. Wij vervangen hem door de 4G-versie van de Mi40, met dezelfde functies als u nu gebruikt.'),
    ('Mi01', 'Uw <strong>Mi01</strong> verbindt via 2G. Wij vervangen hem door de 4G-versie van de Mi01, met dezelfde functies als u nu gebruikt.'),
    ('Mi04', 'Uw <strong>Mi04</strong> verbindt via 2G. Wij vervangen hem door de 4G-versie van de Mi04, met dezelfde functies als u nu gebruikt.'),
]

INTRO_2G = ('<strong>Telecomproviders hebben aangekondigd dat het 2G-netwerk medio 2027 definitief wordt uitgefaseerd.</strong>'
            '<br /><br />')
CHOICE_TEXT = ('Kies hieronder wat u het beste past. U ziet uw keuze daarna nog op een bevestigingspagina, '
               'en pas als u daar bevestigt, verwerken wij hem.')
BUTTONS = [('Bel mij terug', 'callme', 'primary'),
           ('Stuur mij een offerte', 'offer', 'primary'),
           ('Nu niet, later', 'notnow', 'secondary')]
NOT_INTERESTED = ('Geen interesse', 'notinterested', 'secondary')

MAILS = [
    {'n': 1, 'day': 0,
     'subject': 'Uw 2G-hardware stopt medio 2027: kies hoe u overstapt naar 4G',
     'preheader': 'Laat ons weten wat u wilt: wij bellen u terug, sturen een offerte of nemen later contact op.',
     'intro': INTRO_2G + 'Volgens onze gegevens gebruikt u nog hardware die via 2G verbinding maakt. Zonder vervanging kunnen '
              'uw voertuigen op termijn geen data meer verzenden en kunnen wij ze niet meer volgen. Hieronder ziet u om welke '
              'hardware het gaat.',
     'buttons': BUTTONS},
    {'n': 2, 'day': 3,
     'subject': 'Herinnering: kies hoe u overstapt van 2G naar 4G',
     'preheader': 'Wij hebben uw keuze nog niet ontvangen. Met één klik laat u weten wat u wilt.',
     'intro': INTRO_2G + 'Een paar dagen geleden schreven wij u hierover. Wij hebben uw keuze nog niet ontvangen. Uw hardware '
              'hieronder verbindt nog via 2G en moet vóór die tijd vervangen worden.',
     'buttons': BUTTONS},
    {'n': 3, 'day': 8,
     'subject': 'Laatste herinnering: uw 2G-hardware en de overstap naar 4G',
     'preheader': 'Kies hoe u overstapt, of laat ons weten dat u geen interesse heeft.',
     'intro': INTRO_2G + 'Dit is onze laatste mail hierover. Uw hardware hieronder verbindt nog via 2G. Kies hoe u wilt '
              'overstappen. Heeft u geen interesse, laat het ons dan ook weten: dan mailen wij u hier niet meer over.',
     'buttons': BUTTONS + [NOT_INTERESTED]},
]

base = json.load(open(BASE))
root = base['contentBody']['sfdc_cms:block']
s0 = root['children'][0]
blocks0 = s0['children'][0]['children']
T = {  # block templates from the base mail
    'image': blocks0[0], 'intro': blocks0[1], 'heading': blocks0[2], 'paragraph': blocks0[3], 'list': blocks0[4],
    'button': blocks0[7],
}


def fresh(node):
    """Deep copy with new block ids, so nothing points back at the original mail."""
    n = copy.deepcopy(node)
    def walk(x):
        if isinstance(x, dict):
            if 'id' in x and x.get('type') == 'block':
                x['id'] = str(uuid.uuid4())
            for v in x.values(): walk(v)
        elif isinstance(x, list):
            for v in x: walk(v)
    walk(n)
    return n


def text_block(kind, text):
    b = fresh(T[kind])
    b['attributes']['text'] = text
    return b


def button(label, answer, style, env):
    b = fresh(T['button'])
    a = b['attributes']
    url = RESPONSE_URL[env] + '&a=' + answer
    act = a['lightning:click']['actions'][0]
    act['attributes']['url'] = url
    act['generatedUrl'] = url
    a['text'] = label
    if style != 'primary':
        for k, v in list(a.items()):
            if isinstance(v, str): a[k] = v.replace('buttonStyleGroup.primary', 'buttonStyleGroup.' + style)
    return b


def section(children):
    s = fresh(s0)
    s['children'] = s['children'][:1]
    s['children'][0]['children'] = children
    return s


def build(mail, env):
    body = copy.deepcopy(base['contentBody'])
    r = body['sfdc_cms:block']
    main = [fresh(T['image']), text_block('intro', mail['intro']), text_block('heading', 'Uw hardware op 2G')]
    sections = [section(main)]
    # one section per hardware type; marketing sets the visibility rule on each ("has <type>")
    for hw, txt in HARDWARE:
        sections.append(section([text_block('paragraph', txt)]))
    sections.append(section([
        text_block('heading', 'Waarom nu overstappen naar 4G?'),
        text_block('paragraph', 'Met moderne 4G-hardware bent u verzekerd van:'),
        fresh(T['list']),
        text_block('heading', 'Wat wilt u?'),
        text_block('paragraph', CHOICE_TEXT),
    ] + [button(*b, env) for b in mail['buttons']]))
    tail = [fresh(x) for x in root['children'][1:]]  # greeting, logo, contact, divider, footer
    tail[-1]['children'][0]['children'][0]['attributes']['text'] = (
        '{!$organization.Address} | <a href="' + PREFERENCE_URL[env] + '">E-mailvoorkeuren beheren</a><br />')
    r['children'] = sections + tail
    r['id'] = str(uuid.uuid4())
    title = f'M20261109 2G Migratie - mail {mail["n"]}'
    body.update({'subjectLine': mail['subject'], 'preheader': mail['preheader'], 'sfdc_cms:title': title,
                 'sfdc_cms:description': f'2G Migratie campaign, mail {mail["n"]} (business day {mail["day"]}). DRAFT for marketing.'})
    body.pop('sfdc_cms:urlName', None)
    s = json.dumps({'type': 'sfdc_cms__email', 'title': title, 'urlName': f'm20261109-2g-migratie-mail-{mail["n"]}',
                    'contentBody': body}, indent=2, ensure_ascii=False)
    for old, new in IMAGES[env].items():
        s = s.replace(old, new)
    return s


for env in ('dev', 'prod'):
    members = []
    for m in MAILS:
        api = f'M20261109_2GMigratie_Mail{m["n"]}'
        d = os.path.join(OUT, env, 'digitalExperiences', 'marketing', WS, 'sfdc_cms__email', api)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'content.json'), 'w').write(build(m, env))
        open(os.path.join(d, '_meta.json'), 'w').write(json.dumps(
            {'apiName': api, 'type': 'sfdc_cms__email', 'path': FOLDER[env]}, indent=2))
        members.append(f'marketing/{WS}.sfdc_cms__email/{api}')
    open(os.path.join(OUT, env, 'package.xml'), 'w').write(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Package xmlns="http://soap.sforce.com/2006/04/metadata">\n    <types>\n'
        + ''.join(f'        <members>{x}</members>\n' for x in members)
        + '        <name>DigitalExperience</name>\n    </types>\n    <version>68.0</version>\n</Package>\n')


# ---------- preview (same texts) ----------
def li_items():
    return [p for p in re.findall(r'"text"\s*:\s*"([^"]+)"', json.dumps(T['list'], ensure_ascii=False))]


def preview_mail(m):
    btns = ''.join(
        f'<a class="btn {s}" href="#" title="{RESPONSE_URL['prod']}&amp;a={a}">{html.escape(l)}</a>'
        for l, a, s in m['buttons'])
    hw = ''.join(f'<div class="hw"><span class="rule">Alleen tonen als de klant {h} heeft</span><p>{t}</p></div>'
                 for h, t in HARDWARE)
    items = ''.join(f'<li>{t}</li>' for t in li_items())
    return f'''
<article class="mail" id="mail{m["n"]}">
  <div class="meta">
    <div><span class="k">Mail {m["n"]}</span> werkdag {m["day"]}{' · alleen zonder reactie' if m['n'] > 1 else ''}</div>
    <div><span class="k">Onderwerp</span> {html.escape(m["subject"])}</div>
    <div><span class="k">Preheader</span> {html.escape(m["preheader"])}</div>
  </div>
  <div class="frame">
    <div class="header-img">Header: “Mailing switch 2g 4g header”</div>
    <div class="body">
      <p class="intro">{m["intro"]}</p>
      <h3>Uw hardware op 2G</h3>
      {hw}
      <h3>Waarom nu overstappen naar 4G?</h3>
      <p>Met moderne 4G-hardware bent u verzekerd van:</p>
      <ul>{items}</ul>
      <h3>Wat wilt u?</h3>
      <p>{CHOICE_TEXT}</p>
      <div class="btns">{btns}</div>
      <p>Met vriendelijke groet,</p>
      <div class="logo">Logo Moving Intelligence</div>
      <p class="contact"><strong>T</strong>&nbsp; +31 88 99 00 000<br><strong>E</strong>&nbsp; sales@movingintelligence.nl</p>
      <hr>
      <p class="footer">Adres van de organisatie | <a href="#" title="{PREFERENCE_URL['prod']}">E-mailvoorkeuren beheren</a></p>
    </div>
  </div>
</article>'''


open(os.path.join(OUT, 'mails.html'), 'w').write(''.join(preview_mail(m) for m in MAILS))
print('ok')
