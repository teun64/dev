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
        terms: 'Algemene voorwaarden',
        contact: 'Contact',
        phone: 'Telefoon',
        email: 'E-mail',
        website: 'Website',
        coc: 'KvK-nummer',
        vat: 'BTW-nummer',
        managingDirectors: 'Directie',
        iban: 'IBAN',
        bic: 'BIC',
        sortCode: 'Sortcode',
        accountNumber: 'Rekeningnummer'
    },
    en: {
        privacy: 'Privacy Policy',
        terms: 'Terms & Conditions',
        contact: 'Contact',
        phone: 'Phone',
        email: 'Email',
        website: 'Website',
        coc: 'Chamber of Commerce No.',
        vat: 'VAT No.',
        managingDirectors: 'Managing Director',
        iban: 'IBAN',
        bic: 'BIC',
        sortCode: 'Sort Code',
        accountNumber: 'Account Number'
    },
    de: {
        privacy: 'Datenschutz',
        terms: 'Allgemeine Geschäftsbedingungen',
        contact: 'Kontakt',
        phone: 'Telefon',
        email: 'E-Mail',
        website: 'Webseite',
        coc: 'Handelsregisternummer',
        vat: 'USt-IdNr.',
        managingDirectors: 'Geschäftsführer',
        iban: 'IBAN',
        bic: 'BIC',
        sortCode: 'Sortcode',
        accountNumber: 'Kontonummer'
    },
    fr: {
        privacy: 'Politique de confidentialité',
        terms: 'Conditions générales',
        contact: 'Contact',
        phone: 'Téléphone',
        email: 'E-mail',
        website: 'Site web',
        coc: "N° d'immatriculation",
        vat: 'N° TVA',
        managingDirectors: 'Directeur général',
        iban: 'IBAN',
        bic: 'BIC',
        sortCode: 'Code guichet',
        accountNumber: 'Numéro de compte'
    }
};

const GERMANY_COUNTRY_NAMES = ['germany', 'deutschland'];
const UK_COUNTRY_NAMES = ['united kingdom', 'uk', 'great britain', 'england', 'scotland', 'wales', 'northern ireland'];

const SUPPORTED_LANGS = Object.keys(LABELS);

export default class DealerFooter extends LightningElement {
    @track config = {};
    @track footer = {};
    @track isContactModalOpen = false;

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
        return this.footer.privacyPolicyUrl || null;
    }

    get termsUrl() {
        return this.footer.termsConditionsUrl || null;
    }

    get privacyLabel() {
        return this.labels.privacy;
    }

    get termsLabel() {
        return this.labels.terms;
    }

    get contactLabel() {
        return this.labels.contact;
    }

    get phoneLabel() {
        return this.labels.phone;
    }

    get emailLabel() {
        return this.labels.email;
    }

    get websiteLabel() {
        return this.labels.website;
    }

    get cocLabel() {
        return this.labels.coc;
    }

    get vatLabel() {
        return this.labels.vat;
    }

    get managingDirectorsLabel() {
        return this.labels.managingDirectors;
    }

    get contactAddress() {
        const postalCity = [this.footer.postalCode, this.footer.city].filter(Boolean).join(' ');
        const parts = [this.footer.street, postalCity, this.footer.country].filter(Boolean);
        return parts.join(', ');
    }

    get isGermany() {
        const country = (this.footer.country || '').toLowerCase();
        return GERMANY_COUNTRY_NAMES.some((name) => country.includes(name));
    }

    get showManagingDirectors() {
        return this.isGermany && !!this.footer.managingDirectors;
    }

    get isUK() {
        const country = (this.footer.country || '').toLowerCase();
        return UK_COUNTRY_NAMES.some((name) => country.includes(name));
    }

    get showIbanBic() {
        return !this.isUK && !!(this.footer.iban || this.footer.bic);
    }

    get showUkBankDetails() {
        return this.isUK && !!(this.footer.bankSortCode || this.footer.bankAccountNumber);
    }

    get ibanLabel() {
        return this.labels.iban;
    }

    get bicLabel() {
        return this.labels.bic;
    }

    get sortCodeLabel() {
        return this.labels.sortCode;
    }

    get accountNumberLabel() {
        return this.labels.accountNumber;
    }

    get phoneHref() {
        return this.footer.phone ? `tel:${this.footer.phone.replace(/\s+/g, '')}` : null;
    }

    get emailHref() {
        return this.footer.email ? `mailto:${this.footer.email}` : null;
    }

    get websiteHref() {
        if (!this.footer.website) return null;
        return this.footer.website.startsWith('http') ? this.footer.website : `https://${this.footer.website}`;
    }

    handleContactClick() {
        this.isContactModalOpen = true;
    }

    handleCloseModal() {
        this.isContactModalOpen = false;
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }
}
