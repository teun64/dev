import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import LOCALE          from '@salesforce/i18n/locale';
import PAYMENT_PROVIDER from '@salesforce/resourceUrl/paymentProvider';
import BRANDING_URL    from '@salesforce/resourceUrl/Branding';
import getPaymentData          from '@salesforce/apex/Ctrl_Payment.getPaymentData';
import finalizeCheckout        from '@salesforce/apex/Ctrl_Payment.finalizeCheckout';
import getBrandTheme            from '@salesforce/apex/Ctrl_PreferenceCenter.getBrandTheme';
import createPaymentFailureCase from '@salesforce/apex/Ctrl_PaymentCase.createPaymentFailureCase';

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

    localeOptions = [
        { label: 'English 🇬🇧', value: 'en_GB' },
        { label: 'Deutsch 🇩🇪', value: 'de_DE' },
        { label: 'Français 🇫🇷', value: 'fr_FR' },
        { label: 'Nederlands 🇳🇱', value: 'nl_NL' },
    ];

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
        getBrandTheme({ brand })
            .then(theme => { this._brandTheme = theme; })
            .catch(() => {});
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

    handleLocaleChange(event) {
        this._applyLocale(event.detail.value);
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
