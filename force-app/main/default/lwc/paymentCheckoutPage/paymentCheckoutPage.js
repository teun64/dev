import { LightningElement, api, track, wire } from 'lwc';
import { FlowNavigationFinishEvent, FlowNavigationNextEvent, FlowAttributeChangeEvent } from 'lightning/flowSupport';
import LOCALE from '@salesforce/i18n/locale';
//--- Static Resources ---
import PAYMENT_PROVIDER from '@salesforce/resourceUrl/paymentProvider'
//--- Apex ---
import getCustomLabels from '@salesforce/apex/Util_System.getCustomLabels';

export default class PaymentIntentPage extends LightningElement {
    // -------- Flow Inputs --------
    @api publishableKey;
    @api clientSecret;
    @api mode = 'payment';
    @api theme = 'stripe';
    @api themeVariant = 'auto'; // Flow-controlled: 'light' | 'dark' | 'auto'
    @api customer = 'Klantnaam b.v.'
    @api currency = 'EUR';
    @api description = 'Payment';
    @api reference = 'order123';
    @api beneficiary = "Moving Intelligence B.V."
    // -------- Flow Output --------
    _intentStatus;
    _intentMode;
    _intentId;
    _intentMessage;
    _paymentMethodId;
    _mandateId;

    @api get intentStatus() { return this._intentStatus; }
    @api get intentMode() { return this._intentMode; }
    @api get intentId() { return this._intentId; }
    @api get intentMessage() { return this._intentMessage; }
    @api get paymentMethodId() { return this._paymentMethodId; }
    @api get mandateId() { return this._mandateId; }

    // -------- Flow Output (old) --------
    @api intentType;

    @api
    get locale() {
        return this.localeSet;
    }
    set locale(value) {
        this._applyLocale(value);
    }

    _applyLocale(value) {
        const newLocale = (((value) && (value !== 'auto')) ? value : LOCALE).replace('_US','_GB');
        console.log('✅ paymentCheckoutPage - newLocale = ', newLocale);

        if ((newLocale) && (newLocale !== this.localeSet)) {
            this.localeSet = newLocale.replace('-','_');
        } else if (!this.localeSet) {
            this.localeSet = 'en_GB';
        }
        if (this.localeSet) {
            this.languageSet = this.getLanguage(this.localeSet);
        }

        console.log('✅ paymentCheckoutPage - locale = ', this.localeSet);
        console.log('✅ paymentCheckoutPage - language = ', this.languageSet);
    }

    @api 
    get orderDate() {
        return this.orderDateSet;
    }
    set orderDate(value) {
        if ((value) && (value !== this.orderDateSet)) {
            this.orderDateSet = value;
        } else if (!this.orderDateSet) {
            this.orderDateSet = '2025-11-22';
        }
    }
   
    @api 
    get amount() {
        return this.amountTotalSet;
    }
    set amount(value) {
        if ((value) && (value !== this.amountTotalSet)) {
            this.amountTotalSet = this.getNumericAmount(value);
        } else if (!this.amountTotalSet) {
            this.amountTotalSet = 0;
        }
    }

    @track localeSet;
    @track languageSet;
    @track amountTotalSet;
    @track orderDateSet;

    get isCheckout() { return this.viewState === 'checkout'; }
    get isSuccess() { return this.viewState === 'success'; }
    get isError() { return this.viewState === 'error'; }
    get isCancelled() { return this.viewState === 'cancelled'; }
    get isProcessing() { return this.viewState === 'processing'; }
    get amountTotalFormatted() {
        return this.getFormattedAmount(this.amountTotalSet, this.locale);
    }

    get orderDateFormatted() {
        return this.getFormattedDate(this.orderDateSet, this.locale);
    }

    // labels
    labelPageTitle = 'Checkout';
    labelColumnOrder = 'Order summary';
    labelColumnProvider = 'Secure Payment';
    paymentPageText = 'Please review your order details below, before you complete your secure payment on the right or below when using your phone or tablet.';
    labelCustomer = 'Your Name';
    labelReference = 'Reference';
    labelDescription = 'Description';
    labelBeneficiary  = 'Beneficiary';
    labelCurrency = 'Currency';
    labelDate = 'Date';
    labelAmount = 'Total Amount';
    // Define the list of labels to retrieve
    labelList = [
        'PaymentPageTitle',
        'PaymentPageColumnOrder',
        'PaymentPageColumnProvider',
        'PaymentPagePayText',
        'PaymentPageCustomerName',
        'PaymentPageReference', 
        'PaymentPageDescription', 
        'PaymentPageBeneficiary', 
        'PaymentPageCurrency',
        'PaymentPageDate', 
        'PaymentPageAmountTotal'
    ];
    // Use @wire to call the Apex method
    @wire(getCustomLabels, { 
        labels: '$labelList', 
        language: '$languageSet' 
    })
    wiredLabels({ error, data }) {
        if (data) {
            console.log('✅ fetching labels language = ', this.languageSet);
            console.log('✅ fetching labels succeded', data);

            this.labelPageTitle = data.PaymentPageTitle;
            this.labelColumnOrder = data.PaymentPageColumnOrder;
            this.labelColumnProvider = data.PaymentPageColumnProvider;
            this.paymentPageText = data.PaymentPagePayText;
            this.labelCustomer = data.PaymentPageCustomerName;
            this.labelReference = data.PaymentPageReference;
            this.labelDescription = data.PaymentPageDescription;
            this.labelBeneficiary = data.PaymentPageBeneficiary;
            this.labelDate = data.PaymentPageDate;
            this.labelCurrency = data.PaymentPageCurrency;
            this.labelAmount = data.PaymentPageAmountTotal;

            console.log('✅ fetching labels notifyIframeOfLabels()');
        } else if (error) {
            console.error('❌ Error fetching labels:', error);
        }
    }

    viewState = 'checkout'; // checkout | success | error | cancelled | processing
    providerLogo = `${PAYMENT_PROVIDER}/providerIcon.svg`;
    //@track iframeBase = `${PAYMENT_PROVIDER}/paymentCheckoutHtml.html`; // not used directly, child handles posting to static resource

    isFlowContext = false;

    // A reactive property to hold the locale (based on the locale of the Provider when auto or empty, then English)
    localeOptions = [
        { label: 'English 🇬🇧', value: 'en_GB' },
        { label: 'Deutsch 🇩🇪', value: 'de_DE' },
        { label: 'Français 🇫🇷', value: 'fr_FR' },
        { label: 'Nederlands 🇳🇱', value: 'nl_NL' },
    ];

    // -------- Computed values --------
    getNumericAmount(amount) {
        const numericCents = parseInt(amount, 10);
        const numericAmount = numericCents / 100;
        return isNaN(numericAmount) ? 0 : numericAmount;
    }

    getFormattedAmount(amount, locale) {
        const toNumericAmount = amount || 0;
        const toLanguage = this.getLanguage((locale || LOCALE).replace('-','_'));
        const toCurrency = (this.currency || 'EUR').toUpperCase();

        try { 
            console.log('✅ PaymentCheckoutPage - formattedAmount : toCurrency = ', toCurrency, 'toLanguage = ', toLanguage, 'toNumericAmount = ', toNumericAmount);
            return new Intl.NumberFormat(toLanguage, {
                style: 'currency',
                currency: toCurrency,
                currencyDisplay: 'narrowSymbol'
            }).format(toNumericAmount);
        } catch (err) {
            return `${toNumericAmount}`;
        }
    }

    getFormattedDate(dateStr, locale) {
        const toDate = ((!dateStr) || (!isNaN(new Date(dateStr)))) ?  new Date() : new Date(dateStr);
        const toLanguage = this.getLanguage((locale || LOCALE).replace('-','_'));

        return toDate.toLocaleDateString(toLanguage, {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });

    }

    /*get summaryItems() {
        return [
            { label: 'Reference', value: this.reference },
            { label: 'Product', value: this.description },
            { label: 'Currency', value: this.currency?.toUpperCase() }
        ];
    } */

    connectedCallback() {
        // Detect if running inside a Flow
        try {
            // Salesforce sets a special context for Flow screen components
            // If Flow-specific navigation events exist, we’re in Flow context
            if ((typeof FlowNavigationFinishEvent === 'function') && (typeof FlowNavigationNextEvent === 'function')) {
                this.isFlowContext = true;
            }
        } catch (err) {
            this.isFlowContext = false;
            console.warn('⚠️ FlowNavigationFinishEvent, FlowNavigationNextEvent check error', err);
        }
    }

    // lifecycle: apply themeVariant on host
    renderedCallback() {
        // set data-theme attribute on host for CSS if needed
        if (this.template && this.template.host) {
            this.template.host.setAttribute('data-theme', this.themeVariant || 'auto');
        }
    }

    disconnectedCallback() {
        //window.removeEventListener('message', this.handleMessage.bind(this));
    }

    dispatchFlowOutputChange() {
        this.dispatchEvent(new FlowAttributeChangeEvent('intentStatus', this.intentStatus));
        this.dispatchEvent(new FlowAttributeChangeEvent('intentMode', this.intentMode));
        this.dispatchEvent(new FlowAttributeChangeEvent('intentId', this.intentId));
        this.dispatchEvent(new FlowAttributeChangeEvent('intentMessage', this.intentMessage));
        this.dispatchEvent(new FlowAttributeChangeEvent('paymentMethodId', this.paymentMethodId));
        this.dispatchEvent(new FlowAttributeChangeEvent('mandateId', this.mandateId));
    }

    getLanguage(locale) {
        return locale?.split('_')[0];
    }

    // -------- Handle messages from the Provider iframe --------
    handleCheckoutResult = (event) => {
        const d = event.detail;

        console.log('✅ handleCheckoutResult - assign Flow vars', d);

        this._intentStatus = d.intentStatus;
        this._intentMode = d.intentMode;
        this._intentId = d.intentId;
        this._intentMessage = d.intentMessage;
        this._paymentMethodId = d.paymentMethodId;
        this._mandateId = d.mandateId;


        console.log('✅ handleCheckoutResult - intentStatus & isFlowContext', this.intentStatus, this.isFlowContext);

        if (this.isFlowContext && this.intentStatus) {
            try {
                console.log('✅ handleCheckoutResult - dispatchFlowOutputChange()');
                this.dispatchFlowOutputChange();
                console.log('✅ handleCheckoutResult - FlowNavigationNextEvent');
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {this.dispatchEvent(new FlowNavigationNextEvent());}, 0);

            } catch (e) {
                console.error('❌ handleCheckoutResult - Flow error:', e);
            }
            
        }
    }
    
    handleLocaleChange(event) {
        this._applyLocale(event.detail.value);
    }
}
