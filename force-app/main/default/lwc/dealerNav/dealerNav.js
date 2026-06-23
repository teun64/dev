import { LightningElement, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import userId from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import BRANDING from '@salesforce/resourceUrl/Branding';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';

export default class DealerNav extends LightningElement {
    @track config = {};

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    @wire(getRecord, { recordId: userId, fields: [NAME_FIELD] })
    currentUser;

    get userName() {
        return getFieldValue(this.currentUser?.data, NAME_FIELD) || '';
    }

    get logoUrl() {
        return this.config.logoPath ? `${BRANDING}/${this.config.logoPath}` : null;
    }

    get navStyle() {
        return this.config.primaryColor
            ? `--brand-primary: ${this.config.primaryColor};`
            : '';
    }

    get ctaStyle() {
        return this.config.primaryColor
            ? `background:${this.config.primaryColor};`
            : '';
    }

    get currentPath() {
        return window.location.pathname;
    }

    get homeClass() {
        return this.currentPath === '/dealer' || this.currentPath === '/dealer/' ? 'nav-link active' : 'nav-link';
    }

    get shopClass() {
        return this.currentPath.includes('/dealer/shop') ? 'nav-link active' : 'nav-link';
    }
}
