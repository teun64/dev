import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import LOCALE_LANG from '@salesforce/i18n/lang';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import getFooterInfo from '@salesforce/apex/Ctrl_DealerPortal.getFooterInfo';

const DEFAULT_LANG = 'en';
const CAR_IMAGE_PATH = 'Branding/2024/img/car-silhouette-dark.png';

const LABELS = {
    nl: {
        privacy: 'Privacybeleid',
        legal: 'Wettelijke vermeldingen',
        offer: 'Aanbod',
        careers: 'Bij ons komen werken'
    },
    en: {
        privacy: 'Privacy Policy',
        legal: 'Legal Notices',
        offer: 'Offer',
        careers: 'Careers'
    },
    de: {
        privacy: 'Datenschutz',
        legal: 'Impressum',
        offer: 'Angebot',
        careers: 'Karriere'
    },
    fr: {
        privacy: 'Politique de confidentialité',
        legal: 'Mentions légales',
        offer: 'Offre',
        careers: 'Carrières'
    }
};

const SUPPORTED_LANGS = Object.keys(LABELS);

export default class DealerFooter extends LightningElement {
    @track config = {};
    @track footer = {};

    lang = DEFAULT_LANG;
    currentYear = new Date().getFullYear();

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    @wire(getFooterInfo)
    wiredFooter({ data }) {
        if (data) this.footer = data;
    }

    connectedCallback() {
        const browserLang = (LOCALE_LANG || '').slice(0, 2).toLowerCase();
        this.lang = SUPPORTED_LANGS.includes(browserLang) ? browserLang : DEFAULT_LANG;
    }

    get labels() {
        return LABELS[this.lang] || LABELS[DEFAULT_LANG];
    }

    get brandName() {
        return this.config.brandName || '';
    }

    get carImageUrl() {
        return `${BRANDING}/${CAR_IMAGE_PATH}`;
    }

    get logoUrl() {
        const path = this.config.logoPathDark || this.config.logoPath;
        return path ? `${BRANDING}/${path}` : null;
    }

    get logoNeedsWhiteFilter() {
        return !this.config.logoPathDark;
    }

    get legalLogoClass() {
        return this.logoNeedsWhiteFilter
            ? 'footer-legal-logo-img footer-legal-logo-img--filtered'
            : 'footer-legal-logo-img';
    }

    get footerStyle() {
        return this.config.primaryColor
            ? `--brand-primary: ${this.config.primaryColor};`
            : '';
    }

    get privacyUrl() {
        return this.config.privacyPolicyUrl || null;
    }

    get legalUrl() {
        return this.config.legalNoticeUrl || null;
    }

    get offerUrl() {
        return this.config.offerUrl || null;
    }

    get careersUrl() {
        return this.config.careersUrl || null;
    }

    get privacyLabel() {
        return this.labels.privacy;
    }

    get legalLabel() {
        return this.labels.legal;
    }

    get offerLabel() {
        return this.labels.offer;
    }

    get careersLabel() {
        return this.labels.careers;
    }
}
