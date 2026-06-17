import { LightningElement, api, track, wire } from 'lwc';
//--- Static Resources ---
import PAYMENT_PROVIDER from '@salesforce/resourceUrl/paymentProvider'
//--- Apex ---
import getCustomLabels from '@salesforce/apex/Util_System.getCustomLabels';

export default class PaymentCheckout extends LightningElement {
    @api publishableKey;
    @api clientSecret;
    @api mode = 'payment';
    @api theme = 'stripe';
    @api amount; 

    @api
    get locale() {
        return this.localeSet;
    }
    set locale(value) {
        if ((value) && (value !== this.localeSet)) {
            this.localeSet = value;
        } else if (!this.localeSet) {
            this.localeSet = 'en_GB'; 
        }
        if (this.localeSet) {
            this.languageSet = this.getLanguage(this.localeSet);
        }
    }

    // A reactive property to hold the language (based on the locale of the Provider when auto or empty, then English)
    @track languageSet = 'en';
    @track localeSet;

    cancelLabel = 'Cancel';
    cancelConfirmLabel = 'Are you sure you want to cancel this checkout session?';
    processingLabel = 'Processing';
    submitPaymentLabel = 'Pay';
    submitSetupLabel = 'Validate';
 
    // Define the list of labels to retrieve
    labelList = [
        'PaymentCheckoutCancelButton',
        'PaymentCheckoutCancelConfirm', 
        'PaymentCheckoutProcessing', 
        'PaymentCheckoutSubmitButtonPayment',
        'PaymentCheckoutSubmitButtonSetup'
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

            this.cancelLabel = data.PaymentCheckoutCancelButton;
            this.cancelConfirmLabel = data.PaymentCheckoutCancelConfirm;
            this.processingLabel = data.PaymentCheckoutProcessing;
            this.submitPaymentLabel = data.PaymentCheckoutSubmitButtonPayment;
            this.submitSetupLabel = data.PaymentCheckoutSubmitButtonSetup;

            console.log('✅ fetching labels notifyIframeOfLabels()');
            // When labels change → notify iframe
            this.notifyIframeOfLanguage();
        } else if (error) {
            console.error('❌ Error fetching labels:', error);
        }
    }

    iframe;
    iframeSrc = `${PAYMENT_PROVIDER}/paymentCheckoutHtml.html`;


    // --- Computed Properties ---

    connectedCallback() {
        console.log('✅ paymentCheckout - connectedCallback() - Start');
        //window.addEventListener('message', this.handleMessage.bind(this));
        window.addEventListener('message', this.handleMessage);
        console.log('✅ paymentCheckout - connectedCallback() - End');
    }

    disconnectedCallback() {
        console.log('✅ paymentCheckout - disconnectedCallback() - Start');
        //window.removeEventListener('message', this.handleMessage.bind(this));
        window.removeEventListener('message', this.handleMessage);
        console.log('✅ paymentCheckout - disconnectedCallback() - End');
    }

    renderedCallback() {
        if (!this.iframe) {

            this.iframe = this.template.querySelector('iframe');
            this.iframe.addEventListener('load', () => {
                this.iframe.contentWindow.postMessage({
                    type: 'initProvider',
                    publishableKey: this.publishableKey,
                    clientSecret: this.clientSecret,
                    mode: this.mode,
                    theme: this.theme,
                    locale: this.localeSet,
                    cancelLabel: this.cancelLabel,
                    cancelConfirmLabel: this.cancelConfirmLabel,
                    processingLabel: this.processingLabel,
                    submitPaymentLabel: this.submitPaymentLabel,
                    submitSetupLabel: this.submitSetupLabel,
                    amount: this.amount
                }, '*');
            });
        }
    }

    /** Send updated translations to the iframe */
    notifyIframeOfLanguage() {
        if (!this.iframe) return;

        this.iframe.contentWindow.postMessage({
            type: 'localeUpdate',
            locale: this.localeSet,
            cancelLabel: this.cancelLabel,
            cancelConfirmLabel: this.cancelConfirmLabel,
            processingLabel: this.processingLabel,
            submitPaymentLabel: this.submitPaymentLabel,
            submitSetupLabel: this.submitSetupLabel
        }, '*');
    }

    getLanguage(locale) {
        return locale?.split('_')[0];
    }

    handleMessage = (event) => {
        console.log('✅ paymentCheckout - handleMessage - start', event);

        // 🔐 Secure origin check
        //if (!event.origin.includes('movingintelligence')) return;
        const allowedOrigins = [
            'https://movingintelligence--dev.sandbox.lightning.force.com',
            'https://movingintelligence--dev.sandbox.my.site.com',
            'https://movingintelligence--acc.sandbox.lightning.force.com',
            'https://movingintelligence--acc.sandbox.my.site.com',
            'https://movingintelligence.lightning.force.com',
            'https://movingintelligence.my.site.com'
        ];

        if (!allowedOrigins.includes(event.origin)) {
            console.warn('Blocked message from origin:', event.origin);
            return;
        }

        const data = event.data;
        if (!data || !data.type) return;

        console.log('✅ paymentCheckout - handleMessage - data.type', data.type);

        switch (data.type) {
            case 'providerResult':
                if (!data.result) {
                    console.warn('⚠️ Missing result in providerResult');
                    return;
                }

                console.log('✅ paymentCheckout - handleMessage - providerResult', data.result);
                this.dispatchEvent(new CustomEvent('checkoutresult', {detail: data.result}));
                break;

            case 'resizeIframe':
                if (this.iframe && data.height) {
                    this.iframe.style.height = `${data.height}px`;
                }
                return; // no event

            default:
                console.warn('⚠️ Unknown message type:', data.type);
                break;
        }

        console.log('✅ paymentCheckout - handleMessage - end');
    }
}
