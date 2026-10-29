# Adds DealerShop_ContactPerson (en base) + nl_NL/de/fr: the contact person choice in the cart's order
# options (Sales_Contact__c = the offer signer), 2026-10-29. Same mechanics as ../20261029 - dealerHomeLabels.
import sys
from xml.sax.saxutils import escape
ROOT = 'force-app/main/default/'
L = [
 # name, description, en, nl, de, fr
 ('DealerShop_ContactPerson','Cart order options: contact person (signer) choice','Contact person for this order','Contactpersoon voor deze bestelling','Ansprechpartner für diese Bestellung','Personne de contact pour cette commande'),
]
lp = ROOT + 'labels/CustomLabels.labels-meta.xml'
s = open(lp, encoding='utf-8').read()
add = ''
for n, d, en, *_ in L:
    if f'<fullName>{n}</fullName>' in s: continue
    add += (f'    <labels>\n        <fullName>{n}</fullName>\n        <categories>Dealer Portal</categories>\n'
            f'        <language>en_US</language>\n        <protected>false</protected>\n'
            f'        <shortDescription>{escape(d)}</shortDescription>\n        <value>{escape(en)}</value>\n    </labels>\n')
s = s.replace('</CustomLabels>', add + '</CustomLabels>')
open(lp, 'w', encoding='utf-8').write(s)
out = sys.argv[1] if len(sys.argv) > 1 else None
for i, lang in ((3, 'nl_NL'), (4, 'de'), (5, 'fr')):
    tp = ROOT + f'translations/{lang}.translation-meta.xml'
    t = open(tp, encoding='utf-8').read()
    block = ''
    for row in L:
        if f'<name>{row[0]}</name>' in t: continue
        block += f'    <customLabels>\n        <label>{escape(row[i])}</label>\n        <name>{row[0]}</name>\n    </customLabels>\n'
    # customLabels come first in the file; insert after the last one
    idx = t.rfind('</customLabels>\n') + len('</customLabels>\n')
    t = t[:idx] + block + t[idx:]
    open(tp, 'w', encoding='utf-8').write(t)
    if out:
        open(f'{out}/{lang}.translation-meta.xml', 'w', encoding='utf-8').write(
            '<?xml version="1.0" encoding="UTF-8"?>\n<Translations xmlns="http://soap.sforce.com/2006/04/metadata">\n'
            + ''.join(f'    <customLabels>\n        <label>{escape(r[i])}</label>\n        <name>{r[0]}</name>\n    </customLabels>\n' for r in L)
            + '</Translations>\n')
print(len(L), 'labels')
