import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';

export default class DealerNav extends LightningElement {
    @track config = {};

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    get userName() {
        return this.config.userName || '';
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
        if (typeof window === 'undefined') return '';
        return window.location.pathname;
    }

    get homeClass() {
        return this.currentPath === '/dealer' || this.currentPath === '/dealer/' ? 'nav-link active' : 'nav-link';
    }

    get shopClass() {
        return this.currentPath.includes('/dealer/shop') ? 'nav-link active' : 'nav-link';
    }

    handleShopClick(event) {
        if (this.config && this.config.isAuthenticated) return;
        event.preventDefault();
        if (typeof window !== 'undefined') {
            window.location.href = '/dealer/login?startURL=/dealer/shop';
        }
    }
}
