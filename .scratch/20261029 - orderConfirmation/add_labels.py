# Adds the OrderConfirm_* labels (en base) + nl_NL/de/fr for the Webshop order confirmation email
# (template Opportunity_OrderConfirmation, component orderConfirmationDetails), 2026-10-29.
import sys
from xml.sax.saxutils import escape
ROOT = 'force-app/main/default/'
L = [
 # name, description, en, nl, de, fr
 ('OrderConfirm_Subject','Order confirmation email subject (followed by the order number)','Thank you for your order','Bedankt voor uw bestelling','Vielen Dank für Ihre Bestellung','Merci pour votre commande'),
 ('OrderConfirm_Intro','Order confirmation intro, {0} = order number','Thank you for your order with order number {0}. We are working on it to get it delivered to you as soon as possible.','Bedankt voor uw bestelling met bestelnummer {0}. Wij gaan ermee aan de slag om deze zo snel mogelijk bij u te bezorgen.','Vielen Dank für Ihre Bestellung mit der Bestellnummer {0}. Wir kümmern uns darum, dass sie Ihnen so schnell wie möglich geliefert wird.','Merci pour votre commande n° {0}. Nous la préparons afin de vous la livrer dans les plus brefs délais.'),
 ('OrderConfirm_YourReference','Order confirmation: the dealer reference, {0}','Your reference: {0}','Uw referentie: {0}','Ihre Referenz: {0}','Votre référence : {0}'),
 ('OrderConfirm_LinesTitle','Order confirmation: heading above the order lines','Your order','Uw bestelling','Ihre Bestellung','Votre commande'),
 ('OrderConfirm_ShipsToday','Order confirmation: shipped today, {0} = date','Your order will be shipped today, {0}.','Uw bestelling wordt vandaag, {0}, verzonden.','Ihre Bestellung wird heute, {0}, versandt.','Votre commande sera expédiée aujourd\'hui, le {0}.'),
 ('OrderConfirm_ShipsNext','Order confirmation: shipped on the next working day, {0} = date','Your order will be shipped on the next working day, {0}.','Uw bestelling wordt de eerstvolgende werkdag, {0}, verzonden.','Ihre Bestellung wird am nächsten Werktag, {0}, versandt.','Votre commande sera expédiée le prochain jour ouvré, le {0}.'),
 ('OrderConfirm_Cutoff','Order confirmation: shipping cut-off rule, {0} = time','Orders placed and processed before {0} on a working day are shipped the same day; otherwise they are shipped on the next working day.','Bestellingen die op een werkdag vóór {0} zijn geplaatst en verwerkt, worden dezelfde dag verzonden; anders op de eerstvolgende werkdag.','Bestellungen, die an einem Werktag vor {0} Uhr eingehen und bearbeitet werden, werden am selben Tag versandt, andernfalls am nächsten Werktag.','Les commandes passées et traitées un jour ouvré avant {0} sont expédiées le jour même ; sinon, elles sont expédiées le jour ouvré suivant.'),
 ('OrderConfirm_Questions','Order confirmation: questions line (Reply-To = the business entity sales email)','Questions about your order? Simply reply to this email.','Vragen over uw bestelling? Beantwoord dan gewoon deze e-mail.','Fragen zu Ihrer Bestellung? Antworten Sie einfach auf diese E-Mail.','Des questions sur votre commande ? Répondez simplement à cet e-mail.'),
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
