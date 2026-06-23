import { LightningElement, wire, track } from 'lwc';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import submitSignupRequest from '@salesforce/apex/Ctrl_DealerPortal.submitSignupRequest';

export default class DealerHome extends LightningElement {
    @track config = { isAuthenticated: false };
    @track form = { companyName: '', contactName: '', email: '', phone: '', country: '', message: '' };
    @track signupLoading = false;
    @track signupSuccess = false;
    @track signupError = '';

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    get heroStyle() {
        const color = this.config.primaryColor || '#cc0000';
        return `background: linear-gradient(135deg, #1a1a1a 0%, ${color} 100%);`;
    }

    get ctaBtnStyle() {
        return this.config.primaryColor ? `background:${this.config.primaryColor};` : '';
    }

    get welcomeParagraphs() {
        const text = this.config.homeWelcome || '';
        return text.split('\n').filter(p => p.trim().length > 0);
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
        .catch(err => {
            this.signupError = err.body?.message || 'Submission failed. Please try again.';
        })
        .finally(() => {
            this.signupLoading = false;
        });
    }
}
