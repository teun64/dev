import { LightningElement, wire, track } from 'lwc';
import BRANDING from '@salesforce/resourceUrl/Branding';
import LOCALE_LANG from '@salesforce/i18n/lang';
import getBrandConfig from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import getFooterInfo from '@salesforce/apex/Ctrl_DealerPortal.getFooterInfo';

const LANG_STORAGE_KEY = 'dealerPortalLang';
const DEFAULT_LANG = 'en';

const LABELS = {
    nl: {
        name: 'Nederlands',
        privacy: 'Privacybeleid',
        legal: 'Wettelijke vermeldingen',
        offer: 'Aanbod',
        careers: 'Bij ons komen werken'
    },
    en: {
        name: 'English',
        privacy: 'Privacy Policy',
        legal: 'Legal Notices',
        offer: 'Offer',
        careers: 'Careers'
    },
    de: {
        name: 'Deutsch',
        privacy: 'Datenschutz',
        legal: 'Impressum',
        offer: 'Angebot',
        careers: 'Karriere'
    },
    fr: {
        name: 'Français',
        privacy: 'Politique de confidentialité',
        legal: 'Mentions légales',
        offer: 'Offre',
        careers: 'Carrières'
    }
};

const FLAG_GRADIENTS = {
    nl: 'linear-gradient(to bottom, #AE1C28 0 33%, #ffffff 33% 66%, #21468B 66% 100%)',
    de: 'linear-gradient(to bottom, #000000 0 33%, #DD0000 33% 66%, #FFCE00 66% 100%)',
    fr: 'linear-gradient(to right, #0055A4 0 33%, #ffffff 33% 66%, #EF4135 66% 100%)',
    en: 'linear-gradient(135deg, #00247d 0 45%, #ffffff 45% 55%, #cf142b 55% 100%)'
};

const SUPPORTED_LANGS = Object.keys(LABELS);

export default class DealerFooter extends LightningElement {
    @track config = {};
    @track footer = {};
    @track lang = DEFAULT_LANG;
    @track isLangMenuOpen = false;

    currentYear = new Date().getFullYear();
    _handleDocumentClick;

    @wire(getBrandConfig)
    wiredConfig({ data }) {
        if (data) this.config = data;
    }

    @wire(getFooterInfo)
    wiredFooter({ data }) {
        if (data) this.footer = data;
    }

    connectedCallback() {
        this.lang = this.resolveInitialLang();
        this._handleDocumentClick = (event) => {
            if (this.isLangMenuOpen && !this.template.contains(event.target)) {
                this.isLangMenuOpen = false;
            }
        };
        document.addEventListener('click', this._handleDocumentClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._handleDocumentClick);
    }

    resolveInitialLang() {
        try {
            const stored = window.localStorage.getItem(LANG_STORAGE_KEY);
            if (stored && SUPPORTED_LANGS.includes(stored)) {
                return stored;
            }
        } catch (e) {
            // localStorage unavailable (private browsing, etc.)
        }
        const browserLang = (LOCALE_LANG || '').slice(0, 2).toLowerCase();
        return SUPPORTED_LANGS.includes(browserLang) ? browserLang : DEFAULT_LANG;
    }

    get labels() {
        return LABELS[this.lang] || LABELS[DEFAULT_LANG];
    }

    get brandName() {
        return this.config.brandName || '';
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

    get currentLangName() {
        return this.labels.name;
    }

    get currentFlagStyle() {
        return `background: ${FLAG_GRADIENTS[this.lang]};`;
    }

    get languageOptions() {
        return SUPPORTED_LANGS.map((code) => ({
            code,
            name: LABELS[code].name,
            flagStyle: `background: ${FLAG_GRADIENTS[code]};`
        }));
    }

    toggleLangMenu() {
        this.isLangMenuOpen = !this.isLangMenuOpen;
    }

    handleLangSelect(event) {
        const code = event.currentTarget.dataset.code;
        if (SUPPORTED_LANGS.includes(code)) {
            this.lang = code;
            this.isLangMenuOpen = false;
            try {
                window.localStorage.setItem(LANG_STORAGE_KEY, code);
            } catch (e) {
                // localStorage unavailable (private browsing, etc.)
            }
        }
    }
}