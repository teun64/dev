import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import LOCALE          from '@salesforce/i18n/locale';
import PAYMENT_PROVIDER from '@salesforce/resourceUrl/paymentProvider';
import BRANDING_URL    from '@salesforce/resourceUrl/Branding';
import CUSTOMER_HUB_FAVICON from '@salesforce/resourceUrl/CustomerHubFavicon';
import isGuestUser              from '@salesforce/user/isGuest';
import BASE_PATH                from '@salesforce/community/basePath';
import getPaymentData          from '@salesforce/apex/Ctrl_Payment.getPaymentData';
import finalizeCheckout        from '@salesforce/apex/Ctrl_Payment.finalizeCheckout';
import getBrandTheme            from '@salesforce/apex/Ctrl_PreferenceCenter.getBrandTheme';
import getGuestBrandTheme       from '@salesforce/apex/Ctrl_PreferenceCenterGuest.getBrandTheme';
import createPaymentFailureCase from '@salesforce/apex/Ctrl_PaymentCase.createPaymentFailureCase';

// Same site-wide hub header language pills preferenceCenter.js listens to — the payment page
// no longer has its own in-component language switcher (see paymentPage.html's checkout-header).
const LANG_EVENTS = ['mi:languagechange', 'echoes:languagechange', 'tds:languagechange'];

// preferenceCenter's switcher emits short codes (nl/de/fr/en); _applyLocale/Intl need a full
// locale. en_GB (not en_US) matches the pre-existing default below — this payment is in GBP.
const LANG_CODE_TO_LOCALE = {
    nl: 'nl_NL', de: 'de_DE', fr: 'fr_FR', en: 'en_GB'
};

// Same client-side dictionary pattern as preferenceCenter.js's I18N — the order-summary/checkout
// labels below are static text with no server-side (Translation Workbench) source, so they need
// their own translation, keyed the same way as languageSet ('nl'/'de'/'fr'/'en').
const I18N = {
    en: {
        pageTitle: 'Checkout',
        columnOrder: 'Order summary',
        columnProvider: 'Secure Payment',
        pageText: 'Please review your order details below, then complete your secure payment on the right.',
        authenticateText: 'Your bank asks you to confirm this payment. Check the details below, then confirm the payment on the right.',
        dunningPayText: 'We could not collect this payment. Please pay the outstanding amount now on the right. A card is saved for your next invoices; with iDEAL | Wero you also approve a SEPA direct debit, which collects your next invoices. A bank transfer only pays this invoice.',
        dunningRenewText: 'We could not collect this payment: your saved payment details can no longer be used (for example an expired card or a cancelled mandate). Please renew your payment details on the right; the outstanding amount is paid right away and your new details are saved for your next invoices.',
        renewCardText: 'The card you use for this payment expires before the collection date. Please enter new payment details on the right; this payment is collected with them on the collection date.',
        retryScheduledTitle: 'Payment will be retried',
        retryScheduledBody: 'This payment could not be collected. We will try again automatically on {0}. No action is needed.',
        redirectFailed: 'The payment at your bank was not completed. Please try again or choose another payment method.',
        bankTransferTitle: 'Bank transfer chosen',
        bankTransferBody: 'Please transfer the amount using the bank details and reference from the instructions. We register the payment as soon as the transfer arrives.',
        bankTransferLink: 'Show the bank transfer instructions',
        customer: 'Name',
        reference: 'Reference',
        beneficiary: 'Beneficiary',
        currency: 'Currency',
        date: 'Date',
        amount: 'Total',
        successTitle: 'Payment received',
        successBody: 'Thank you. Your payment has been processed successfully.',
        alreadyProcessedTitle: 'Already completed',
        alreadyProcessedBody: 'This payment has already been processed. No further action is needed.',
        alreadyScheduledTitle: 'Automatic payment scheduled',
        alreadyScheduledBody: 'This payment will be collected automatically on {0}. No further action is needed.',
        successSetupTitle: 'Payment method saved',
        successSetupBody: 'Thank you. Your payment method has been saved. This payment will be collected automatically on {0}.',
        successSetupBodyNoDate: 'Thank you. Your payment method has been saved. This payment will be collected automatically.',
        lineNumber: 'Line',
        productCode: 'Code',
        productName: 'Product',
        productAmount: 'Amount',
        invoiceCycle: 'Invoice cycle'
    },
    nl: {
        pageTitle: 'Afrekenen',
        columnOrder: 'Besteloverzicht',
        columnProvider: 'Veilig betalen',
        pageText: 'Controleer hieronder uw bestelgegevens en rond vervolgens rechts uw beveiligde betaling af.',
        authenticateText: 'Uw bank vraagt u deze betaling te bevestigen. Controleer hieronder de gegevens en bevestig rechts de betaling.',
        dunningPayText: 'We konden deze betaling niet incasseren. Betaal het openstaande bedrag nu rechts. Een kaart wordt bewaard voor uw volgende facturen; met iDEAL | Wero geeft u ook een machtiging voor SEPA-incasso, waarmee uw volgende facturen worden geïncasseerd. Een bankoverschrijving betaalt alleen deze factuur.',
        dunningRenewText: 'We konden deze betaling niet incasseren: uw opgeslagen betaalgegevens kunnen niet meer worden gebruikt (bijvoorbeeld een verlopen kaart of een ingetrokken machtiging). Vernieuw rechts uw betaalgegevens; het openstaande bedrag wordt direct betaald en uw nieuwe gegevens worden bewaard voor uw volgende facturen.',
        renewCardText: 'De kaart waarmee u deze betaling doet, verloopt vóór de incassodatum. Vul rechts nieuwe betaalgegevens in; deze betaling wordt daarmee op de incassodatum geïncasseerd.',
        retryScheduledTitle: 'Betaling wordt opnieuw geprobeerd',
        retryScheduledBody: 'Deze betaling kon niet worden geïncasseerd. We proberen het op {0} automatisch opnieuw. U hoeft niets te doen.',
        redirectFailed: 'De betaling bij uw bank is niet afgerond. Probeer het opnieuw of kies een andere betaalmethode.',
        bankTransferTitle: 'Bankoverschrijving gekozen',
        bankTransferBody: 'Maak het bedrag over met de bankgegevens en het kenmerk uit de instructies. Wij verwerken de betaling zodra de overschrijving binnen is.',
        bankTransferLink: 'Toon de instructies voor de overschrijving',
        customer: 'Naam',
        reference: 'Referentie',
        beneficiary: 'Begunstigde',
        currency: 'Valuta',
        date: 'Datum',
        amount: 'Totaal',
        successTitle: 'Betaling ontvangen',
        successBody: 'Bedankt. Uw betaling is succesvol verwerkt.',
        alreadyProcessedTitle: 'Al voltooid',
        alreadyProcessedBody: 'Deze betaling is al verwerkt. Geen verdere actie nodig.',
        alreadyScheduledTitle: 'Automatische betaling gepland',
        alreadyScheduledBody: 'Deze betaling wordt op {0} automatisch afgeschreven. Geen verdere actie nodig.',
        successSetupTitle: 'Betaalmethode opgeslagen',
        successSetupBody: 'Bedankt. Uw betaalmethode is opgeslagen. Deze betaling wordt op {0} automatisch afgeschreven.',
        successSetupBodyNoDate: 'Bedankt. Uw betaalmethode is opgeslagen. Deze betaling wordt automatisch afgeschreven.',
        lineNumber: 'Regel',
        productCode: 'Code',
        productName: 'Product',
        productAmount: 'Bedrag',
        invoiceCycle: 'Factuurcyclus'
    },
    de: {
        pageTitle: 'Kasse',
        columnOrder: 'Bestellübersicht',
        columnProvider: 'Sichere Zahlung',
        pageText: 'Bitte überprüfen Sie unten Ihre Bestelldetails und schließen Sie anschließend rechts Ihre sichere Zahlung ab.',
        authenticateText: 'Ihre Bank bittet Sie, diese Zahlung zu bestätigen. Prüfen Sie unten die Angaben und bestätigen Sie rechts die Zahlung.',
        dunningPayText: 'Wir konnten diese Zahlung nicht einziehen. Bitte bezahlen Sie den offenen Betrag jetzt rechts. Eine Karte wird für Ihre nächsten Rechnungen gespeichert; mit iDEAL | Wero erteilen Sie zugleich ein SEPA-Lastschriftmandat, mit dem Ihre nächsten Rechnungen eingezogen werden. Eine Banküberweisung bezahlt nur diese Rechnung.',
        dunningRenewText: 'Wir konnten diese Zahlung nicht einziehen: Ihre gespeicherten Zahlungsdaten können nicht mehr verwendet werden (zum Beispiel eine abgelaufene Karte oder ein widerrufenes Mandat). Bitte erneuern Sie rechts Ihre Zahlungsdaten; der offene Betrag wird sofort bezahlt und Ihre neuen Daten werden für Ihre nächsten Rechnungen gespeichert.',
        renewCardText: 'Die Karte, mit der Sie diese Zahlung leisten, läuft vor dem Einzugsdatum ab. Bitte geben Sie rechts neue Zahlungsdaten ein; diese Zahlung wird damit am Einzugsdatum eingezogen.',
        retryScheduledTitle: 'Zahlung wird erneut versucht',
        retryScheduledBody: 'Diese Zahlung konnte nicht eingezogen werden. Wir versuchen es am {0} automatisch erneut. Sie müssen nichts tun.',
        redirectFailed: 'Die Zahlung bei Ihrer Bank wurde nicht abgeschlossen. Bitte versuchen Sie es erneut oder wählen Sie eine andere Zahlungsmethode.',
        bankTransferTitle: 'Banküberweisung gewählt',
        bankTransferBody: 'Bitte überweisen Sie den Betrag mit den Bankdaten und dem Verwendungszweck aus der Anleitung. Wir verbuchen die Zahlung, sobald die Überweisung eingegangen ist.',
        bankTransferLink: 'Anleitung für die Überweisung anzeigen',
        customer: 'Name',
        reference: 'Referenz',
        beneficiary: 'Empfänger',
        currency: 'Währung',
        date: 'Datum',
        amount: 'Gesamt',
        successTitle: 'Zahlung erhalten',
        successBody: 'Vielen Dank. Ihre Zahlung wurde erfolgreich verarbeitet.',
        alreadyProcessedTitle: 'Bereits abgeschlossen',
        alreadyProcessedBody: 'Diese Zahlung wurde bereits verarbeitet. Keine weitere Aktion erforderlich.',
        alreadyScheduledTitle: 'Automatische Zahlung geplant',
        alreadyScheduledBody: 'Diese Zahlung wird am {0} automatisch eingezogen. Keine weitere Aktion erforderlich.',
        successSetupTitle: 'Zahlungsmethode gespeichert',
        successSetupBody: 'Vielen Dank. Ihre Zahlungsmethode wurde gespeichert. Diese Zahlung wird am {0} automatisch eingezogen.',
        successSetupBodyNoDate: 'Vielen Dank. Ihre Zahlungsmethode wurde gespeichert. Diese Zahlung wird automatisch eingezogen.',
        lineNumber: 'Zeile',
        productCode: 'Code',
        productName: 'Produkt',
        productAmount: 'Betrag',
        invoiceCycle: 'Rechnungszyklus'
    },
    fr: {
        pageTitle: 'Paiement',
        columnOrder: 'Récapitulatif de la commande',
        columnProvider: 'Paiement sécurisé',
        pageText: 'Veuillez vérifier les détails de votre commande ci-dessous, puis finalisez votre paiement sécurisé à droite.',
        authenticateText: 'Votre banque vous demande de confirmer ce paiement. Vérifiez les détails ci-dessous, puis confirmez le paiement à droite.',
        dunningPayText: 'Nous n\'avons pas pu prélever ce paiement. Veuillez régler le montant dû maintenant à droite. Une carte est enregistrée pour vos prochaines factures ; avec iDEAL | Wero, vous signez aussi un mandat de prélèvement SEPA, utilisé pour vos prochaines factures. Un virement bancaire ne règle que cette facture.',
        dunningRenewText: 'Nous n\'avons pas pu prélever ce paiement : vos coordonnées de paiement enregistrées ne peuvent plus être utilisées (par exemple une carte expirée ou un mandat révoqué). Veuillez renouveler vos coordonnées de paiement à droite ; le montant dû est réglé immédiatement et vos nouvelles coordonnées sont enregistrées pour vos prochaines factures.',
        renewCardText: 'La carte utilisée pour ce paiement expire avant la date de prélèvement. Veuillez saisir de nouvelles coordonnées de paiement à droite ; ce paiement sera prélevé avec celles-ci à la date de prélèvement.',
        retryScheduledTitle: 'Le paiement sera de nouveau tenté',
        retryScheduledBody: 'Ce paiement n\'a pas pu être prélevé. Nous réessaierons automatiquement le {0}. Aucune action n\'est requise.',
        redirectFailed: 'Le paiement auprès de votre banque n\'a pas abouti. Veuillez réessayer ou choisir un autre moyen de paiement.',
        bankTransferTitle: 'Virement bancaire choisi',
        bankTransferBody: 'Veuillez virer le montant avec les coordonnées bancaires et la référence indiquées dans les instructions. Nous enregistrons le paiement dès réception du virement.',
        bankTransferLink: 'Afficher les instructions de virement',
        customer: 'Nom',
        reference: 'Référence',
        beneficiary: 'Bénéficiaire',
        currency: 'Devise',
        date: 'Date',
        amount: 'Total',
        successTitle: 'Paiement reçu',
        successBody: 'Merci. Votre paiement a été traité avec succès.',
        alreadyProcessedTitle: 'Déjà effectué',
        alreadyProcessedBody: 'Ce paiement a déjà été traité. Aucune action supplémentaire n\'est requise.',
        alreadyScheduledTitle: 'Paiement automatique programmé',
        alreadyScheduledBody: 'Ce paiement sera prélevé automatiquement le {0}. Aucune action supplémentaire n\'est requise.',
        successSetupTitle: 'Moyen de paiement enregistré',
        successSetupBody: 'Merci. Votre moyen de paiement a été enregistré. Ce paiement sera prélevé automatiquement le {0}.',
        successSetupBodyNoDate: 'Merci. Votre moyen de paiement a été enregistré. Ce paiement sera prélevé automatiquement.',
        lineNumber: 'Ligne',
        productCode: 'Code',
        productName: 'Produit',
        productAmount: 'Montant',
        invoiceCycle: 'Cycle de facturation'
    }
};

export default class PaymentPage extends LightningElement {

    // -------- State --------
    isLoading  = true;
    hasError   = false;
    errorMessage;

    // checkout | success | error
    viewState = 'checkout';

    @track payment;
    intentMessage;

    // -------- Locale --------
    @track localeSet;
    @track languageSet;

    // -------- Labels --------
    // Reactive on languageSet (@track, updated by _applyLocale) so the order-summary/checkout
    // text actually re-renders on a hub-header language change, instead of being frozen at
    // whatever it was on initial load (the currency/date/amount getters below already did this
    // correctly via Intl formatting — these plain-text labels were the gap).
    _alreadyProcessed = false;
    _alreadyScheduled = false;
    _retryScheduled = false;   // dunning: a failed payment waiting for its automatic retry
    bankTransferUrl;           // dunning: bank transfer chosen, Stripe's hosted instructions
    showRedirectFailed = false; // back from the bank (iDEAL) without paying

    // Stripe adds redirect_status (succeeded / failed / processing) to the return url after a bank redirect (iDEAL)
    get _redirectStatus() {
        try {
            return new URLSearchParams(window.location.search).get('redirect_status');
        } catch (e) {
            return null;
        }
    }
    get labelRedirectFailed() { return this._t.redirectFailed; }
    _methodSaved = false;
    _scheduledDate;

    get _t() { return I18N[this.languageSet] || I18N.en; }

    get labelPageTitle()      { return this._t.pageTitle; }
    get labelColumnOrder()    { return this._t.columnOrder; }
    get labelColumnProvider() { return this._t.columnProvider; }
    get paymentPageText() {
        if (this.isAuthenticateMode) return this._t.authenticateText;
        // dunning (Ctrl_Payment.PaymentData.dunning): the payment failed, or the saved card expires before collection
        const dunning = this.payment?.dunning;
        if (dunning === 'renew')     return this._t.dunningRenewText;
        if (dunning === 'pay')       return this._t.dunningPayText;
        if (dunning === 'renewCard') return this._t.renewCardText;
        return this._t.pageText;
    }
    get labelCustomer()       { return this._t.customer; }
    get labelReference()      { return this._t.reference; }
    get labelBeneficiary()    { return this._t.beneficiary; }
    get labelCurrency()       { return this._t.currency; }
    get labelDate()           { return this._t.date; }
    get labelAmount()         { return this._t.amount; }
    get labelSuccessTitle() {
        if (this.bankTransferUrl) return this._t.bankTransferTitle;
        if (this._alreadyScheduled) return this._retryScheduled ? this._t.retryScheduledTitle : this._t.alreadyScheduledTitle;
        if (this._methodSaved)      return this._t.successSetupTitle;
        return this._alreadyProcessed ? this._t.alreadyProcessedTitle : this._t.successTitle;
    }
    get labelSuccessBody() {
        if (this.bankTransferUrl) return this._t.bankTransferBody;
        if (this._alreadyScheduled) {
            const body = this._retryScheduled ? this._t.retryScheduledBody : this._t.alreadyScheduledBody;
            return body.replace('{0}', this._formatDate(this._scheduledDate));
        }
        // SetupIntent completed: the method is saved, nothing is charged until the collection date
        if (this._methodSaved) {
            const date = this.payment?.collectionDate;
            return date ? this._t.successSetupBody.replace('{0}', this._formatDate(date)) : this._t.successSetupBodyNoDate;
        }
        return this._alreadyProcessed ? this._t.alreadyProcessedBody : this._t.successBody;
    }
    _formatDate(value) {
        const lang = this.languageSet || 'en';
        return value
            ? new Date(value).toLocaleDateString(lang, { day: 'numeric', month: 'long', year: 'numeric' })
            : '';
    }
    get labelBankTransferLink() { return this._t.bankTransferLink; }
    get labelLineNumber()     { return this._t.lineNumber; }
    get labelProductCode()    { return this._t.productCode; }
    get labelProductName()    { return this._t.productName; }
    get labelProductAmount()  { return this._t.productAmount; }
    get labelInvoiceCycle()   { return this._t.invoiceCycle; }

    // -------- Assets --------
    providerLogo = `${PAYMENT_PROVIDER}/providerIcon.svg`;

    // -------- Derived state --------
    get isReady()        { return !this.isLoading && !this.hasError && this.viewState === 'checkout' && !!this.payment; }
    get isSuccess()      { return this.viewState === 'success'; }
    get isPaymentError() { return this.viewState === 'error'; }
    get isResolved()     { return this.viewState !== 'checkout'; }
    // 'authenticate' = an off-session charge waiting for the customer's 3-D Secure confirmation: a real payment too
    get isPaymentMode()  { return this.payment?.mode === 'payment' || this.isAuthenticateMode; }
    get isAuthenticateMode() { return this.payment?.mode === 'authenticate'; }

    get locale() {
        return this.localeSet || LOCALE.replace('_US', '_GB');
    }

    get amountFormatted() {
        if (!this.payment || this.payment.amountCents == null) return '';
        const amount = this.payment.amountCents / 100;
        const lang   = (this.localeSet || 'en_GB').split('_')[0];
        const curr   = (this.payment.currency_x || 'EUR').toUpperCase();
        try {
            return new Intl.NumberFormat(lang, {
                style: 'currency',
                currency: curr,
                currencyDisplay: 'narrowSymbol'
            }).format(amount);
        } catch (e) {
            return `${amount}`;
        }
    }

    get orderDateFormatted() {
        if (!this.payment?.orderDate) return '';
        const lang = (this.localeSet || 'en_GB').split('_')[0];
        return new Date(this.payment.orderDate).toLocaleDateString(lang, {
            year: 'numeric', month: 'short', day: 'numeric'
        });
    }

    get productLineAmountFormatted() {
        const amount = this.payment?.productLine?.amount;
        if (amount == null) return '';
        const lang = (this.localeSet || 'en_GB').split('_')[0];
        const curr = (this.payment.currency_x || 'EUR').toUpperCase();
        try {
            return new Intl.NumberFormat(lang, {
                style: 'currency',
                currency: curr,
                currencyDisplay: 'narrowSymbol'
            }).format(amount);
        } catch (e) {
            return `${amount}`;
        }
    }

    get hasProductLine() { return !!this.payment?.productLine; }

    // Apple Pay: describe the recurring charge so Apple issues a merchant token (MPAN) that keeps working
    // when the customer changes device; without it the saved Apple Pay card is tied to one device.
    // Interval follows the invoice cycle of the product line (default monthly). Other methods ignore it.
    get applePayRequest() {
        const p = this.payment;
        if (!p) return null;
        const months = p.productLine?.periodMonths > 0 ? p.productLine.periodMonths : 1;
        const yearly = months % 12 === 0;
        return {
            recurringPaymentRequest: {
                paymentDescription: p.beneficiary || p.paymentName,
                managementURL: `${window.location.origin}${BASE_PATH || ''}`,
                regularBilling: {
                    amount: p.amountCents || 0,
                    label: p.productLine?.productName || p.paymentName,
                    recurringPaymentIntervalUnit: yearly ? 'year' : 'month',
                    recurringPaymentIntervalCount: yearly ? months / 12 : months
                }
            }
        };
    }

    get billingName() {
        const first = this.payment?.contactFirstName || '';
        const last  = this.payment?.contactLastName  || '';
        return [first, last].filter(Boolean).join(' ') || undefined;
    }

    get invoiceCycleLabel() {
        const months = this.payment?.productLine?.periodMonths;
        if (!months) return null;
        return months === 1 ? '1 month' : `${months} months`;
    }

    // -------- Brand theme --------
    @track _brandTheme = null;

    get brandAccentStyle() {
        const color = this._brandTheme?.primaryColor;
        return color ? `--pp-accent: ${color}` : '';
    }

    get brandLogoUrl() {
        if (this._brandTheme?.mcLogoUrl)      return this._brandTheme.mcLogoUrl;
        if (this._brandTheme?.logoStaticPath)  return `${BRANDING_URL}/Branding/${this._brandTheme.logoStaticPath}`;
        if (this._brand === 'M') return `${BRANDING_URL}/Branding/2024/img/mi-logo-black-black-rgb.png`;
        if (this._brand === 'E') return `${BRANDING_URL}/Branding/2026/img/echoes-logo-black-blue-rgb.png`;
        return null;
    }

    get hasBrandLogo() { return !!this.brandLogoUrl; }
    get isBrandTds()   { return this._brand === 'T'; }
    get hasBrandIdentity() { return this.hasBrandLogo || this.isBrandTds; }

    _fetchBrandTheme(brand) {
        if (!brand) return;
        const fetchTheme = isGuestUser ? getGuestBrandTheme : getBrandTheme;
        fetchTheme({ brand })
            .then(theme => { this._brandTheme = theme; })
            .catch(() => {});
    }

    connectedCallback() {
        this._setFavicon();
        this._langHandler = (e) => {
            const code = e.detail?.language;
            const locale = LANG_CODE_TO_LOCALE[code];
            if (locale) this._applyLocale(locale);
        };
        LANG_EVENTS.forEach(k => window.addEventListener(k, this._langHandler));
    }

    disconnectedCallback() {
        if (this._langHandler) {
            LANG_EVENTS.forEach(k => window.removeEventListener(k, this._langHandler));
        }
    }

    // Raw "/sfsites/c/resource/..." hrefs 404 on this site — @salesforce/resourceUrl is the
    // only reliable way to reference a static resource here (see dealerNav.js for precedent).
    _setFavicon() {
        if (typeof document === 'undefined') return;
        let link = document.querySelector("link[rel~='icon']");
        if (!link) {
            link = document.createElement('link');
            link.rel = 'icon';
            document.head.appendChild(link);
        }
        link.type = 'image/png';
        link.href = CUSTOMER_HUB_FAVICON;
    }

    // -------- Flow inputs --------
    // Lets this component run as a Flow screen component (no CurrentPageReference/site URL
    // there) in addition to the Experience Cloud /hub/payment route. Same _loadPayment/
    // _fetchBrandTheme calls either way — language still comes from LOCALE (the running,
    // internal Flow user's own Salesforce locale) via _applyLocale(LOCALE) in _loadPayment,
    // since there's no hub header to dispatch a languagechange event inside a Flow.
    @api
    get token() { return this._token; }
    set token(value) {
        if (value && value !== this._token) {
            this._isFlowContext = true;
            this._token = value;
            this._loadPayment(value);
        }
    }

    // True only when a Flow assigns `token` directly (see setter above) — never on the
    // standalone Experience Cloud page, which resolves the token via CurrentPageReference
    // instead. Drives containerClass below so the standalone page styling (paymentPage.css's
    // .pp-standalone) never applies inside a Flow screen's modal/panel.
    _isFlowContext = false;

    get containerClass() {
        return this._isFlowContext ? 'pp-container' : 'pp-container pp-standalone';
    }

    @api
    get brand() { return this._brand; }
    set brand(value) {
        if (value && value !== this._brand) {
            this._brand = value;
            this._fetchBrandTheme(value);
        }
    }

    // -------- URL params via CurrentPageReference --------
    _token;
    _brand;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        if (!ref) return;

        const brand = ref.state?.brand || ref.state?.c__brand;
        if (brand && brand !== this._brand) {
            this._brand = brand;
            this._fetchBrandTheme(brand);
        }

        const token = ref.state?.token || ref.state?.c__token;
        if (token && token !== this._token) {
            this._token = token;
            this._loadPayment(token);
        } else if (!token && !this._token) {
            this.isLoading    = false;
            this.hasError     = true;
            this.errorMessage = 'No payment token found. Please use the link from your email.';
        }
    }

    // -------- Apex call --------
    _loadPayment(token) {
        this.isLoading = true;
        this.hasError  = false;
        const language = (LOCALE || 'en_GB').replace('-', '_').split('_')[0];

        getPaymentData({ token, language })
            .then(data => {
                if (!data.found) {
                    this.hasError     = true;
                    this.errorMessage = data.errorMessage || 'Payment not found.';
                } else if (data.alreadyProcessed) {
                    // just back from the bank with a paid iDEAL: "payment received", not "already completed"
                    this._alreadyProcessed = this._redirectStatus !== 'succeeded' && this._redirectStatus !== 'processing';
                    this._applyCustomerLanguage(data.language);
                    this.viewState         = 'success';
                } else if (data.alreadyScheduled) {
                    this._alreadyScheduled = true;
                    this._retryScheduled   = data.dunning === 'retry';
                    this._scheduledDate    = data.collectionDate;
                    this._applyCustomerLanguage(data.language);
                    this.viewState         = 'success';
                } else if (data.bankTransferUrl) {
                    this.bankTransferUrl = data.bankTransferUrl;
                    this._applyCustomerLanguage(data.language);
                    this.viewState       = 'success';
                } else if (data.errorMessage) {
                    this.hasError     = true;
                    this.errorMessage = data.errorMessage;
                } else {
                    this.payment = data;
                    this.showRedirectFailed = this._redirectStatus === 'failed';
                    this._applyCustomerLanguage(data.language);
                }
                this.isLoading = false;
            })
            .catch(err => {
                this.hasError     = true;
                this.errorMessage = err?.body?.message || 'Failed to load payment details.';
                this.isLoading    = false;
            });
    }

    // -------- Locale --------
    // The customer's language (contact, resolved server-side) wins over the hub header's domain guess;
    // the header is told so its pill matches, and a later pill click still switches the page
    _applyCustomerLanguage(code) {
        const locale = LANG_CODE_TO_LOCALE[code];
        if (!locale) {
            this._applyLocale(LOCALE);
            return;
        }
        this._applyLocale(locale);
        window.dispatchEvent(new CustomEvent('mi:languageset', { detail: { language: code } }));
    }

    _applyLocale(value) {
        const raw    = (value && value !== 'auto') ? value : LOCALE;
        const locale = raw.replace('_US', '_GB').replace('-', '_');
        if (locale !== this.localeSet) {
            this.localeSet    = locale;
            this.languageSet  = locale.split('_')[0];
        }
    }

    // -------- Checkout result from child c-payment-checkout --------
    handleCheckoutResult(event) {
        const d = event.detail;
        const status = d?.intentStatus;

        if (status === 'succeeded' || status === 'processing') {
            this._methodSaved = d?.intentMode === 'setup';
            this.viewState = 'success';
            finalizeCheckout({
                token:         this._token,
                intentMode:    d?.intentMode,
                futureConsent: d?.futureConsent === true
            }).catch(() => {});
        } else if (status === 'requires_action' && this.payment?.dunning) {
            // bank transfer: Stripe showed the instructions; reload to keep them on the page (the payment waits for the money)
            this._loadPayment(this._token);
        } else if (status === 'canceled' || status === 'requires_payment_method') {
            this.intentMessage = d?.intentMessage || 'Payment was not completed.';
            this.viewState     = 'error';
            // authenticate mode: the payment stays Action Required and the customer can try again;
            // rab_Payment_Action_Required creates the one Case when it expires
            // dunning: no Case either - the customer can try again and the dunning mails follow up
            if (this.payment?.paymentId && !this.isAuthenticateMode && !this.payment?.dunning) {
                createPaymentFailureCase({
                    paymentId: this.payment.paymentId,
                    reason: d?.intentMessage || status
                }).catch(() => {});
            }
        }
    }
}
