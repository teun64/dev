import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference }             from 'lightning/navigation';
import COMMUNITY_BASE from '@salesforce/community/basePath';
import getAdminInfo   from '@salesforce/apex/Ctrl_CustomerHub.getAdminInfo';

const EVENT_KEY = 'tds:languagechange';

const LABELS = {
    nl: { phone:'Telefoon', email:'E-mail',    address:'Adres',   website:'Website', kvk:'KvK',      vat:'BTW',  privacy:'Privacyverklaring',          terms:'Algemene voorwaarden'   },
    de: { phone:'Telefon',  email:'E-Mail',    address:'Adresse', website:'Website', kvk:'HRB',      vat:'USt',  privacy:'Datenschutzerklärung',        terms:'AGB'                    },
    fr: { phone:'Téléphone',email:'E-mail',    address:'Adresse', website:'Site web',kvk:'SIRET',    vat:'TVA',  privacy:'Politique de confidentialité',terms:'Conditions générales'   },
    en: { phone:'Phone',    email:'Email',     address:'Address', website:'Website', kvk:'Reg. No.', vat:'VAT',  privacy:'Privacy policy',              terms:'Terms & conditions'     },
};

export default class TdsHubFooter extends LightningElement {

    /** Relative paths to privacy / terms pages within the Experience Cloud site */
    @api privacyPath = '/privacy';
    @api termsPath   = '/terms';

    @track _lang     = 'en';
    @track _admin    = null;
    @track _cid      = '';
    @track isLoading = true;

    _langHandler;

    // ── Lifecycle ──────────────────────────────────────────────────

    connectedCallback() {
        this._lang = this._detectLang();
        this._langHandler = (e) => { this._lang = e.detail.language; };
        window.addEventListener(EVENT_KEY, this._langHandler);
        try {
            const c = new URLSearchParams(window.location.search).get('cid');
            if (c) this._cid = c;
        } catch (_) {}
    }

    disconnectedCallback() {
        window.removeEventListener(EVENT_KEY, this._langHandler);
    }

    // ── Wire ───────────────────────────────────────────────────────

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const c = ref?.state?.cid || ref?.state?.c__cid;
        if (c && c !== this._cid) this._cid = c;
    }

    @wire(getAdminInfo, { contactId: '$_cid' })
    wiredAdmin({ data, error }) {
        this.isLoading = false;
        if (data) this._admin = data;
        if (error) console.error('[tdsHubFooter] getAdminInfo error', error);
    }

    // ── Getters ───────────────────────────────────────────────────

    get admin()        { return this._admin; }
    get hasAdmin()     { return !!this._admin; }
    get hasAddress()   { return !!(this._admin?.street || this._admin?.city); }
    get hasKvkAndVat() { return !!(this._admin?.kvk && this._admin?.vatNumber); }
    get labels()       { return LABELS[this._lang] || LABELS.en; }

    get currentYear() { return new Date().getFullYear(); }

    get phoneHref()  { return `tel:${this._admin?.phone || ''}`; }
    get emailHref()  { return `mailto:${this._admin?.email || ''}`; }
    get privacyUrl() { return (COMMUNITY_BASE || '') + this.privacyPath; }
    get termsUrl()   { return (COMMUNITY_BASE || '') + this.termsPath; }

    // ── Private ───────────────────────────────────────────────────

    _detectLang() {
        try {
            const h = window.location.hostname;
            if (h.endsWith('.nl'))    return 'nl';
            if (h.endsWith('.de'))    return 'de';
            if (h.endsWith('.fr'))    return 'fr';
        } catch (_) { /* ignore */ }
        return 'en';
    }
}
