import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';

const FAVICON_PATH = 'Branding/2024/img/favicon.png';

export default class DealerNav extends LightningElement {
    @track config = {};

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    connectedCallback() {
        this.setFavicon();
    }

    // headMarkup can't reliably reference a static resource by raw URL on this site (the usual
    // "/sfsites/c/resource/..." path 404s here), but @salesforce/resourceUrl already resolves
    // correctly for every other Branding asset - reuse that instead of guessing a URL format.
    setFavicon() {
        if (typeof document === 'undefined') return;
        const href = `${BRANDING}/${FAVICON_PATH}`;
        let link = document.querySelector("link[rel~='icon']");
        if (!link) {
            link = document.createElement('link');
            link.rel = 'icon';
            document.head.appendChild(link);
        }
        link.type = 'image/png';
        link.href = href;
    }

    get userName() {
        return this.config.userName || '';
    }

    get logoUrl() {
        const path = this.config.logoPathColor || this.config.logoPath;
        return path ? `${BRANDING}/${path}` : null;
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

    // "/dealers/secur/logout.jsp" isn't a page this LWR site's client-side router knows about, so
    // a plain <a> click gets intercepted as SPA navigation and shows "Invalid Page" instead of
    // reaching the server. Forcing a full browser navigation bypasses the router entirely.
    handleLogoutClick(event) {
        event.preventDefault();
        if (typeof window !== 'undefined') {
            window.location.href = '/dealers/secur/logout.jsp?retUrl=/dealers/login';
        }
    }
}
