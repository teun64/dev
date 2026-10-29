# Adds the DealerShop_Error* labels (en base) + nl_NL/de/fr: dealer-facing placeOrder errors that
# Ctrl_DealerShop throws as label names and dealerCart translates (2026-10-29).
import sys
from xml.sax.saxutils import escape
ROOT = 'force-app/main/default/'
L = [
 # name, description, en, nl, de, fr
 ('DealerShop_ErrorCartEmpty','Cart error: nothing orderable','Your cart has no products that can be ordered.','Uw winkelwagen bevat geen producten die besteld kunnen worden.','Ihr Warenkorb enthält keine bestellbaren Produkte.','Votre panier ne contient aucun produit pouvant être commandé.'),
 ('DealerShop_ErrorNoPricebook','Cart error: no dealer pricebook','Your company has no shop prices yet. Please contact us.','Voor uw bedrijf zijn nog geen shopprijzen ingesteld. Neem contact met ons op.','Für Ihr Unternehmen sind noch keine Shop-Preise hinterlegt. Bitte kontaktieren Sie uns.','Aucun prix boutique n\'est encore défini pour votre entreprise. Veuillez nous contacter.'),
 ('DealerShop_ErrorContactNotLinked','Cart error: contact person not on the account','The chosen contact person is not linked to your company.','De gekozen contactpersoon is niet gekoppeld aan uw bedrijf.','Der gewählte Ansprechpartner ist nicht mit Ihrem Unternehmen verknüpft.','La personne de contact choisie n\'est pas liée à votre entreprise.'),
 ('DealerShop_ErrorAddressIncomplete','Cart error: delivery address incomplete','The delivery address is incomplete.','Het afleveradres is niet volledig.','Die Lieferadresse ist unvollständig.','L\'adresse de livraison est incomplète.'),
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
