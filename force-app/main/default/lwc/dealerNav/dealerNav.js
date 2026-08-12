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
        return 'background: #0E0F0E;';
    }

    get currentPath() {
        if (typeof window === 'undefined') return '';
        return window.location.pathname;
    }

    get homeClass() {
        return this.currentPath === '/dealers' || this.currentPath === '/dealers/' ? 'nav-link active' : 'nav-link';
    }

    get shopClass() {
        return this.currentPath.includes('/dealers/shop') ? 'nav-link active' : 'nav-link';
    }

    get orderHistoryClass() {
        return this.currentPath.includes('/dealers/order-history') ? 'nav-link active' : 'nav-link';
    }

    handleShopClick(event) {
        if (this.config && this.config.isAuthenticated) return;
        event.preventDefault();
        if (typeof window !== 'undefined') {
            window.location.href = '/dealers/login?startURL=/dealers/shop';
        }
    }

    handleOrderHistoryClick(event) {
        if (this.config && this.config.isAuthenticated) return;
        event.preventDefault();
        if (typeof window !== 'undefined') {
            window.location.href = '/dealers/login?startURL=/dealers/order-history';
        }
    }
}
