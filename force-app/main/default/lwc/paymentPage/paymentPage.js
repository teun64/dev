import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import LOCALE          from '@salesforce/i18n/locale';
import PAYMENT_PROVIDER from '@salesforce/resourceUrl/paymentProvider';
import BRANDING_URL    from '@salesforce/resourceUrl/Branding';
import CUSTOMER_HUB_FAVICON from '@salesforce/resourceUrl/CustomerHubFavicon';
import isGuestUser              from '@salesforce/user/isGuest';
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
    labelPageTitle       = 'Checkout';
    labelColumnOrder     = 'Order summary';
    labelColumnProvider  = 'Secure Payment';
    paymentPageText      = 'Please review your order details below, then complete your secure payment on the right.';
    labelCustomer        = 'Name';
    labelReference       = 'Reference';
    labelBeneficiary     = 'Beneficiary';
    labelCurrency        = 'Currency';
    labelDate            = 'Date';
    labelAmount          = 'Total';
    labelSuccessTitle    = 'Payment received';
    labelSuccessBody     = 'Thank you. Your payment has been processed successfully.';
    labelLineNumber      = 'Line';
    labelProductCode     = 'Code';
    labelProductName     = 'Product';
    labelProductAmount   = 'Amount';
    labelInvoiceCycle    = 'Invoice cycle';

    // -------- Assets --------
    providerLogo = `${PAYMENT_PROVIDER}/providerIcon.svg`;

    // -------- Derived state --------
    get isReady()        { return !this.isLoading && !this.hasError && this.viewState === 'checkout' && !!this.payment; }
    get isSuccess()      { return this.viewState === 'success'; }
    get isPaymentError() { return this.viewState === 'error'; }
    get isResolved()     { return this.viewState !== 'checkout'; }
    get isPaymentMode()  { return this.payment?.mode === 'payment'; }

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
    // instead. Drives containerClass below so the full-bleed page styling (paymentPage.css)
    // never applies inside a Flow screen's modal/panel.
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
                    this.labelSuccessTitle = 'Already completed';
                    this.labelSuccessBody  = 'This payment has already been processed. No further action is needed.';
                    this.viewState         = 'success';
                } else if (data.errorMessage) {
                    this.hasError     = true;
                    this.errorMessage = data.errorMessage;
                } else {
                    this.payment = data;
                    this._applyLocale(LOCALE);
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
            this.viewState = 'success';
            finalizeCheckout({
                token:      this._token,
                intentMode: d?.intentMode
            }).catch(() => {});
        } else if (status === 'canceled' || status === 'requires_payment_method') {
            this.intentMessage = d?.intentMessage || 'Payment was not completed.';
            this.viewState     = 'error';
            if (this.payment?.paymentId) {
                createPaymentFailureCase({
                    paymentId: this.payment.paymentId,
                    reason: d?.intentMessage || status
                }).catch(() => {});
            }
        }
    }
}
