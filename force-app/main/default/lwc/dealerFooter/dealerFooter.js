import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import getFooterInfo from '@salesforce/apex/Ctrl_DealerPortal.getFooterInfo';

export default class DealerFooter extends LightningElement {
    @track config = {};
    @track footer = {};
    currentYear = new Date().getFullYear();

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    @wire(getFooterInfo)
    wiredFooter({ data }) {
        if (data) this.footer = data;
    }

    get brandName() {
        return this.config.brandName || '';
    }

    get logoUrl() {
        return this.config.logoPath ? `${BRANDING}/${this.config.logoPath}` : null;
    }

    get footerStyle() {
        return this.config.primaryColor
            ? `--brand-primary: ${this.config.primaryColor};`
            : '';
    }

    get phoneHref() {
        return this.footer.phone ? `tel:${this.footer.phone}` : '#';
    }

    get emailHref() {
        return this.footer.email ? `mailto:${this.footer.email}` : '#';
    }

    get websiteHref() {
        const w = this.footer.website;
        if (!w) return '#';
        return w.startsWith('http') ? w : `https://${w}`;
    }
}
