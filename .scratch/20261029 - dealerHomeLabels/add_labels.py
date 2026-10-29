# Adds the DealerHome_* custom labels (en base) + nl_NL/de/fr translations for the home page
# login/shop cards and the "Become a dealer" sign-up form (2026-10-29). Same mechanics as
# ../20261029 - dealerOrderLabelsPrice/add_labels.py. Run from the repo root; optional arg = folder for subset translations.
import sys
from xml.sax.saxutils import escape
ROOT = 'force-app/main/default/'
L = [
 # name, description, en, nl, de, fr
 ('DealerHome_ShopHeading','Home card heading (logged in)','Dealer Shop','Dealer Shop','Händler-Shop','Boutique revendeur'),
 ('DealerHome_ShopCta','Home card text (logged in)','Go to the shop','Ga naar de shop','Zum Shop','Aller à la boutique'),
 ('DealerHome_ShopButton','Home card button (logged in)','Shop','Shop','Shop','Boutique'),
 ('DealerHome_LoginHeading','Home card heading (guest)','Dealer login','Inloggen voor dealers','Händler-Login','Connexion revendeur'),
 ('DealerHome_LoginButton','Home card button (guest)','Log in','Inloggen','Anmelden','Se connecter'),
 ('DealerHome_NotADealer','Home card prompt (guest)','Not a dealer yet?','Nog geen dealer?','Noch kein Händler?','Pas encore revendeur ?'),
 ('DealerHome_BecomeDealer','Home card button: open sign-up form','Become a dealer','Word dealer','Händler werden','Devenir revendeur'),
 ('DealerHome_SignupTitle','Sign-up form title','Request a dealer account','Dealeraccount aanvragen','Händlerkonto beantragen','Demander un compte revendeur'),
 ('DealerHome_Close','Sign-up form close button','Close','Sluiten','Schließen','Fermer'),
 ('DealerHome_SignupSuccess','Sign-up form sent','Your request has been submitted. We will contact you shortly.','Uw aanvraag is verstuurd. Wij nemen zo snel mogelijk contact met u op.','Ihre Anfrage wurde gesendet. Wir melden uns in Kürze bei Ihnen.','Votre demande a été envoyée. Nous vous contacterons rapidement.'),
 ('DealerHome_CompanyName','Sign-up field','Company name','Bedrijfsnaam','Firmenname','Nom de l\'entreprise'),
 ('DealerHome_ContactName','Sign-up field','Your name','Uw naam','Ihr Name','Votre nom'),
 ('DealerHome_Email','Sign-up field','Email','E-mailadres','E-Mail','E-mail'),
 ('DealerHome_CocNumber','Sign-up field: chamber of commerce number','CoC number','KvK-nummer','Handelsregisternummer','Numéro SIRET'),
 ('DealerHome_VatNumber','Sign-up field','VAT number','Btw-nummer','USt-IdNr.','Numéro de TVA'),
 ('DealerHome_Phone','Sign-up field','Phone','Telefoon','Telefon','Téléphone'),
 ('DealerHome_VisitingAddress','Sign-up field group','Visiting address','Bezoekadres','Besuchsadresse','Adresse de visite'),
 ('DealerHome_Street','Sign-up field','Street','Straat','Straße','Rue'),
 ('DealerHome_PostalCode','Sign-up field','Postal code','Postcode','Postleitzahl','Code postal'),
 ('DealerHome_City','Sign-up field','City','Plaats','Ort','Ville'),
 ('DealerHome_Country','Sign-up field','Country','Land','Land','Pays'),
 ('DealerHome_Message','Sign-up field','Message','Bericht','Nachricht','Message'),
 ('DealerHome_Submit','Sign-up submit button','Submit request','Aanvraag versturen','Anfrage senden','Envoyer la demande'),
 ('DealerHome_Submitting','Sign-up submit button while sending','Submitting...','Bezig met versturen...','Wird gesendet...','Envoi en cours...'),
 ('DealerHome_ErrorRequired','Sign-up error','Please fill in all required fields.','Vul alle verplichte velden in.','Bitte füllen Sie alle Pflichtfelder aus.','Veuillez remplir tous les champs obligatoires.'),
 ('DealerHome_ErrorRegistered','Sign-up error','This email address is already registered. Please log in instead.','Dit e-mailadres is al geregistreerd. Log in met dit adres.','Diese E-Mail-Adresse ist bereits registriert. Bitte melden Sie sich an.','Cette adresse e-mail est déjà enregistrée. Veuillez vous connecter.'),
 ('DealerHome_ErrorSubmit','Sign-up error','Submission failed. Please try again.','Versturen is mislukt. Probeer het opnieuw.','Senden fehlgeschlagen. Bitte versuchen Sie es erneut.','L\'envoi a échoué. Veuillez réessayer.'),
 ('DealerHome_ErrorEmailCheck','Sign-up error','Could not validate the email address. Please try again.','Het e-mailadres kon niet worden gecontroleerd. Probeer het opnieuw.','Die E-Mail-Adresse konnte nicht geprüft werden. Bitte versuchen Sie es erneut.','Impossible de vérifier l\'adresse e-mail. Veuillez réessayer.'),
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
