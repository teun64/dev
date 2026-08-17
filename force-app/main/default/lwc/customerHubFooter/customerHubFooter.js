import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference }         from 'lightning/navigation';
import BRANDING        from '@salesforce/resourceUrl/Branding';
import getAdminInfo    from '@salesforce/apex/Ctrl_CustomerHub.getAdminInfo';

const EVENT_KEY = 'mi:languagechange';
const LOGO_PATH = 'Branding/2024/img/mi-logo-white-red-rgb.png';
const CAR_IMAGE_PATH = 'Branding/2024/img/car-silhouette-dark.png';

const LABELS = {
    nl: {
        phone: 'Telefoon', email: 'E-mail', address: 'Adres', website: 'Website',
        kvk: 'KvK', vat: 'BTW', privacy: 'Privacyverklaring', terms: 'Algemene voorwaarden',
        contact: 'Contact', managingDirectors: 'Directie', iban: 'IBAN', bic: 'BIC',
        sortCode: 'Sortcode', accountNumber: 'Rekeningnummer'
    },
    de: {
        phone: 'Telefon', email: 'E-Mail', address: 'Adresse', website: 'Website',
        kvk: 'HRB', vat: 'USt', privacy: 'Datenschutzerklärung', terms: 'AGB',
        contact: 'Kontakt', managingDirectors: 'Geschäftsführer', iban: 'IBAN', bic: 'BIC',
        sortCode: 'Sortcode', accountNumber: 'Kontonummer'
    },
    fr: {
        phone: 'Téléphone', email: 'E-mail', address: 'Adresse', website: 'Site web',
        kvk: 'SIRET', vat: 'TVA', privacy: 'Politique de confidentialité', terms: 'Conditions générales',
        contact: 'Contact', managingDirectors: 'Directeur général', iban: 'IBAN', bic: 'BIC',
        sortCode: 'Code guichet', accountNumber: 'Numéro de compte'
    },
    en: {
        phone: 'Phone', email: 'Email', address: 'Address', website: 'Website',
        kvk: 'CoC', vat: 'VAT', privacy: 'Privacy statement', terms: 'Terms & conditions',
        contact: 'Contact', managingDirectors: 'Managing Director', iban: 'IBAN', bic: 'BIC',
        sortCode: 'Sort Code', accountNumber: 'Account Number'
    }
};

const GERMANY_COUNTRY_NAMES = ['germany', 'deutschland'];
const UK_COUNTRY_NAMES = ['united kingdom', 'uk', 'great britain', 'england', 'scotland', 'wales', 'northern ireland'];

export default class CustomerHubFooter extends LightningElement {

    @track _lang     = 'nl';
    @track _admin    = null;
    @track _cid      = '';
    @track _brand    = '';
    @track isLoading = true;
    @track isContactModalOpen = false;

    currentYear = new Date().getFullYear();

    _langHandler;

    // ── Lifecycle ──────────────────────────────────────────────────

    connectedCallback() {
        this._lang = this._detectLang();
        this._langHandler = (e) => { this._lang = e.detail.language; };
        window.addEventListener(EVENT_KEY, this._langHandler);
        // Sync cid + brand before first wire tick so guest users get admin info immediately
        try {
            const params = new URLSearchParams(window.location.search);
            const c = params.get('cid');
            const b = params.get('brand');
            if (c) this._cid   = c;
            if (b) this._brand = b;
        } catch (_) { /* ignore */ }
    }

    disconnectedCallback() {
        window.removeEventListener(EVENT_KEY, this._langHandler);
    }

    // ── Wire ───────────────────────────────────────────────────────

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const c = ref?.state?.cid || ref?.state?.c__cid;
        if (c && c !== this._cid) this._cid = c;
        const b = ref?.state?.brand || ref?.state?.c__brand;
        if (b && b !== this._brand) this._brand = b;
    }

    @wire(getAdminInfo, { contactId: '$_cid', brand: '$_brand' })
    wiredAdmin({ data, error }) {
        this.isLoading = false;
        if (data) this._admin = data;
        if (error) console.error('[customerHubFooter] getAdminInfo error', error);
    }

    // ── Getters ───────────────────────────────────────────────────

    get admin()    { return this._admin; }
    get hasAdmin() { return !!this._admin; }
    get labels()   { return LABELS[this._lang] || LABELS.nl; }

    get logoUrl()     { return `${BRANDING}/${LOGO_PATH}`; }
    get carImageUrl() { return `${BRANDING}/${CAR_IMAGE_PATH}`; }

    get privacyUrl() { return this._admin?.privacyPolicyUrl || null; }
    get termsUrl()   { return this._admin?.termsConditionsUrl || null; }

    get contactAddress() {
        const postalCity = [this._admin?.postalCode, this._admin?.city].filter(Boolean).join(' ');
        const parts = [this._admin?.street, postalCity, this._admin?.country].filter(Boolean);
        return parts.join(', ');
    }

    get isGermany() {
        const country = (this._admin?.country || '').toLowerCase();
        return GERMANY_COUNTRY_NAMES.some((name) => country.includes(name));
    }

    get showManagingDirectors() {
        return this.isGermany && !!this._admin?.managingDirectors;
    }

    get isUK() {
        const country = (this._admin?.country || '').toLowerCase();
        return UK_COUNTRY_NAMES.some((name) => country.includes(name));
    }

    get showIbanBic() {
        return !this.isUK && !!(this._admin?.iban || this._admin?.bic);
    }

    get showUkBankDetails() {
        return this.isUK && !!(this._admin?.bankSortCode || this._admin?.bankAccountNumber);
    }

    get phoneHref()   { return this._admin?.phone ? `tel:${this._admin.phone.replace(/\s+/g, '')}` : null; }
    get emailHref()   { return this._admin?.email ? `mailto:${this._admin.email}` : null; }
    get websiteHref() {
        if (!this._admin?.website) return null;
        return this._admin.website.startsWith('http') ? this._admin.website : `https://${this._admin.website}`;
    }

    // ── Handlers ───────────────────────────────────────────────────

    handleContactClick() {
        this.isContactModalOpen = true;
    }

    handleCloseModal() {
        this.isContactModalOpen = false;
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }

    // ── Private ───────────────────────────────────────────────────

    _detectLang() {
        try {
            const h = window.location.hostname;
            if (h.endsWith('.de'))    return 'de';
            if (h.endsWith('.fr'))    return 'fr';
            if (h.endsWith('.co.uk')) return 'en';
        } catch (_) { /* ignore */ }
        return 'nl';
    }
}
