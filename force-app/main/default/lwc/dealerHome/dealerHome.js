import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import getHomeText from '@salesforce/apex/Ctrl_DealerPortal.getHomeText';
import submitSignupRequest from '@salesforce/apex/Ctrl_DealerPortal.submitSignupRequest';
import isEmailRegistered from '@salesforce/apex/Ctrl_DealerPortal.isEmailRegistered';

const HERO_IMAGE_PATH = 'Branding/2024/img/home-hero.png';
const EMPTY_FORM = {
    companyName: '', contactName: '', email: '', cocNumber: '', vatNumber: '', phone: '',
    street: '', postalCode: '', city: '', country: '', message: ''
};
const REQUIRED_FIELDS = ['companyName', 'contactName', 'email', 'cocNumber', 'vatNumber', 'street', 'postalCode', 'city', 'country'];

// English fallbacks shown until getHomeText returns the DealerHome_* labels in the visitor's language.
const HOME_DEFAULT_LABELS = {
    DealerPortal_HomeTitle: '', DealerPortal_HomeWelcome: '',
    DealerHome_ShopHeading: 'Dealer Shop', DealerHome_ShopCta: 'Go to the shop', DealerHome_ShopButton: 'Shop',
    DealerHome_LoginHeading: 'Dealer login', DealerHome_LoginButton: 'Log in',
    DealerHome_NotADealer: 'Not a dealer yet?', DealerHome_BecomeDealer: 'Become a dealer',
    DealerHome_SignupTitle: 'Request a dealer account', DealerHome_Close: 'Close',
    DealerHome_SignupSuccess: 'Your request has been submitted. We will contact you shortly.',
    DealerHome_CompanyName: 'Company name', DealerHome_ContactName: 'Your name', DealerHome_Email: 'Email',
    DealerHome_CocNumber: 'CoC number', DealerHome_VatNumber: 'VAT number', DealerHome_Phone: 'Phone',
    DealerHome_VisitingAddress: 'Visiting address', DealerHome_Street: 'Street', DealerHome_PostalCode: 'Postal code',
    DealerHome_City: 'City', DealerHome_Country: 'Country', DealerHome_Message: 'Message',
    DealerHome_Submit: 'Submit request', DealerHome_Submitting: 'Submitting...',
    DealerHome_ErrorRequired: 'Please fill in all required fields.',
    DealerHome_ErrorRegistered: 'This email address is already registered. Please log in instead.',
    DealerHome_ErrorSubmit: 'Submission failed. Please try again.',
    DealerHome_ErrorEmailCheck: 'Could not validate the email address. Please try again.'
};

// Domain TLD determines the visitor's language - dealer.movingintelligence.nl -> nl_NL,
// .de -> de, .fr -> fr, everything else (.com, .co.uk, the my.site.com sandbox domain,
// localhost during dev) falls back to en. Values must match this org's actual registered
// translation locale codes (see force-app/main/default/translations/*.translation-meta.xml
// file names) - Dutch is registered as nl_NL, not nl.
const HOSTNAME_LANGUAGE_MAP = { '.nl': 'nl_NL', '.de': 'de', '.fr': 'fr' };
function resolveLanguageFromHostname() {
    const host = window.location.hostname;
    for (const [suffix, lang] of Object.entries(HOSTNAME_LANGUAGE_MAP)) {
        if (host.endsWith(suffix)) return lang;
    }
    return 'en';
}

export default class DealerHome extends LightningElement {
    @track config = { isAuthenticated: false };
    @track homeText = HOME_DEFAULT_LABELS;
    @track form = { ...EMPTY_FORM };
    @track isSignupModalOpen = false;
    @track signupLoading = false;
    @track signupSuccess = false;
    @track signupError = '';

    language = resolveLanguageFromHostname();

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    @wire(getHomeText, { language: '$language' })
    wiredHomeText({ data }) {
        if (data) this.homeText = { ...HOME_DEFAULT_LABELS, ...data };
    }

    get homeTitle() {
        return this.homeText.DealerPortal_HomeTitle;
    }

    get heroStyle() {
        return `background-image: url('${BRANDING}/${HERO_IMAGE_PATH}'); background-size: 100% 100%; background-repeat: no-repeat;`;
    }

    get ctaBtnStyle() {
        return 'background: #ff0000;';
    }

    get welcomeParagraphs() {
        const text = this.homeText.DealerPortal_HomeWelcome || '';
        return text.split('\n').filter(p => p.trim().length > 0);
    }

    handleBecomeDealerClick() {
        this.form = { ...EMPTY_FORM };
        this.signupSuccess = false;
        this.signupError = '';
        this.isSignupModalOpen = true;
    }

    handleCloseSignupModal() {
        this.isSignupModalOpen = false;
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }

    handleFormChange(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
    }

    handleSignupSubmit() {
        this.signupError = '';
        const missing = REQUIRED_FIELDS.some((field) => !this.form[field]);
        if (missing) {
            this.signupError = this.homeText.DealerHome_ErrorRequired;
            return;
        }

        this.signupLoading = true;
        isEmailRegistered({ email: this.form.email })
            .then((alreadyRegistered) => {
                if (alreadyRegistered) {
                    this.signupError = this.homeText.DealerHome_ErrorRegistered;
                    this.signupLoading = false;
                    return;
                }
                submitSignupRequest({
                    companyName: this.form.companyName,
                    contactName: this.form.contactName,
                    email:       this.form.email,
                    cocNumber:   this.form.cocNumber,
                    vatNumber:   this.form.vatNumber,
                    phone:       this.form.phone,
                    street:      this.form.street,
                    postalCode:  this.form.postalCode,
                    city:        this.form.city,
                    country:     this.form.country,
                    message:     this.form.message
                })
                .then(() => {
                    this.signupSuccess = true;
                })
                .catch(() => {
                    // The Apex messages are English only, so always show the translated text.
                    this.signupError = this.homeText.DealerHome_ErrorSubmit;
                })
                .finally(() => {
                    this.signupLoading = false;
                });
            })
            .catch(() => {
                this.signupError = this.homeText.DealerHome_ErrorEmailCheck;
                this.signupLoading = false;
            });
    }
}
