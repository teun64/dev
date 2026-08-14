import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import submitSignupRequest from '@salesforce/apex/Ctrl_DealerPortal.submitSignupRequest';
import isEmailRegistered from '@salesforce/apex/Ctrl_DealerPortal.isEmailRegistered';

const HERO_IMAGE_PATH = 'Branding/2024/img/home-hero.png';
const EMPTY_FORM = { companyName: '', contactName: '', email: '', phone: '', country: '', message: '' };

export default class DealerHome extends LightningElement {
    @track config = { isAuthenticated: false };
    @track form = { ...EMPTY_FORM };
    @track isSignupModalOpen = false;
    @track signupLoading = false;
    @track signupSuccess = false;
    @track signupError = '';

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    get heroStyle() {
        return `background-image: url('${BRANDING}/${HERO_IMAGE_PATH}'); background-size: 100% 100%; background-repeat: no-repeat;`;
    }

    get ctaBtnStyle() {
        return 'background: #ff0000;';
    }

    get welcomeParagraphs() {
        const text = this.config.homeWelcome || '';
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
        if (!this.form.companyName || !this.form.email) {
            this.signupError = 'Company name and email are required.';
            return;
        }

        this.signupLoading = true;
        isEmailRegistered({ email: this.form.email })
            .then((alreadyRegistered) => {
                if (alreadyRegistered) {
                    this.signupError = 'This email address is already registered. Please log in instead.';
                    this.signupLoading = false;
                    return;
                }
                submitSignupRequest({
                    companyName:  this.form.companyName,
                    contactName:  this.form.contactName,
                    email:        this.form.email,
                    phone:        this.form.phone,
                    country:      this.form.country,
                    message:      this.form.message
                })
                .then(() => {
                    this.signupSuccess = true;
                })
                .catch((err) => {
                    this.signupError = err.body?.message || 'Submission failed. Please try again.';
                })
                .finally(() => {
                    this.signupLoading = false;
                });
            })
            .catch((err) => {
                this.signupError = err.body?.message || 'Could not validate the email address. Please try again.';
                this.signupLoading = false;
            });
    }
}
