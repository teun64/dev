# Adds the DealerOrder_* / DealerNav_* custom labels (en base) + nl_NL/de/fr translations to the repo files.
# nl_NL values are the exact Dutch strings the order pages hardcoded before (2026-10-29).
import sys, re
from xml.sax.saxutils import escape
ROOT = 'force-app/main/default/'
L = [
 # name, description, en, nl, de, fr
 ('DealerOrder_HistoryTitle','Order history page title','Order history','Bestelgeschiedenis','Bestellverlauf','Historique des commandes'),
 ('DealerOrder_MyOrders','Order history toggle: own orders','My orders','Mijn bestellingen','Meine Bestellungen','Mes commandes'),
 ('DealerOrder_AllOrders','Order history toggle: all account orders','All orders','Alle bestellingen','Alle Bestellungen','Toutes les commandes'),
 ('DealerOrder_Loading','Order pages spinner text','Loading...','Laden...','Wird geladen...','Chargement...'),
 ('DealerOrder_NoOrders','Order history empty state','No orders found','Geen bestellingen gevonden','Keine Bestellungen gefunden','Aucune commande trouvée'),
 ('DealerOrder_OrderNumber','Order history column','Order number','Bestelnummer','Bestellnummer','Numéro de commande'),
 ('DealerOrder_Date','Order history column','Date','Datum','Datum','Date'),
 ('DealerOrder_Status','Order history column','Status','Status','Status','Statut'),
 ('DealerOrder_PlacedBy','Order history column','Ordered by','Besteld door','Bestellt von','Commandé par'),
 ('DealerOrder_Total','Order history column','Total','Totaal','Gesamt','Total'),
 ('DealerOrder_Reorder','Order history button: order again','Order again','Opnieuw bestellen','Erneut bestellen','Commander à nouveau'),
 ('DealerOrder_BackToHistory','Order detail back link','Back to order history','Terug naar bestelgeschiedenis','Zurück zum Bestellverlauf','Retour à l\'historique des commandes'),
 ('DealerOrder_NoOrderGiven','Order detail: no id in URL','No order specified.','Geen bestelling opgegeven.','Keine Bestellung angegeben.','Aucune commande indiquée.'),
 ('DealerOrder_LoadError','Order detail load error','An error occurred while loading the order.','Er is een fout opgetreden bij het laden van de bestelling.','Beim Laden der Bestellung ist ein Fehler aufgetreten.','Une erreur s\'est produite lors du chargement de la commande.'),
 ('DealerOrder_ReorderAll','Order detail button: whole order again','Order the whole order again','Volledige bestelling opnieuw bestellen','Gesamte Bestellung erneut bestellen','Commander à nouveau toute la commande'),
 ('DealerOrder_NoProducts','Order detail empty state','No products found for this order','Geen producten gevonden voor deze bestelling','Keine Produkte für diese Bestellung gefunden','Aucun produit trouvé pour cette commande'),
 ('DealerOrder_Product','Order detail column','Product','Product','Produkt','Produit'),
 ('DealerOrder_Quantity','Order detail column','Quantity','Aantal','Menge','Quantité'),
 ('DealerOrder_PriceThen','Order detail column: price paid','Price at the time','Prijs destijds','Preis damals','Prix à l\'époque'),
 ('DealerOrder_PriceNow','Order detail column: current price','Current price','Huidige prijs','Aktueller Preis','Prix actuel'),
 ('DealerOrder_Add','Order detail button: add line to cart','Add','Toevoegen','Hinzufügen','Ajouter'),
 ('DealerOrder_Status_Webshop','Order status for stage Webshop','Received','Ontvangen','Eingegangen','Reçue'),
 ('DealerOrder_Status_Administration','Order status for stage Administration','In progress','In behandeling','In Bearbeitung','En cours'),
 ('DealerOrder_Status_ClosedWon','Order status for stage Closed Won','Processed','Verwerkt','Bearbeitet','Traitée'),
 ('DealerOrder_Status_ClosedLost','Order status for stage Closed Lost','Cancelled','Geannuleerd','Storniert','Annulée'),
 ('DealerNav_Home','Dealer Portal menu','Home','Home','Startseite','Accueil'),
 ('DealerNav_Shop','Dealer Portal menu','Shop','Shop','Shop','Boutique'),
 ('DealerNav_OrderHistory','Dealer Portal menu','Order History','Bestelgeschiedenis','Bestellverlauf','Historique des commandes'),
 ('DealerNav_Logout','Dealer Portal menu','Log out','Uitloggen','Abmelden','Se déconnecter'),
 ('DealerNav_Login','Dealer Portal menu','Log in','Inloggen','Anmelden','Se connecter'),
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
