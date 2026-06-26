import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent }                     from 'lightning/platformShowToastEvent';
import { refreshApex }                        from '@salesforce/apex';
import { CurrentPageReference }               from 'lightning/navigation';
import userId                                 from '@salesforce/user/Id';
import isGuestUser                            from '@salesforce/user/isGuest';
import BRANDING_URL                           from '@salesforce/resourceUrl/Branding';

import getPreferences   from '@salesforce/apex/Ctrl_PreferenceCenter.getPreferences';
import savePreferences  from '@salesforce/apex/Ctrl_PreferenceCenter.savePreferences';
import getAuditHistory  from '@salesforce/apex/Ctrl_PreferenceCenter.getAuditHistory';
import getBrandTheme    from '@salesforce/apex/Ctrl_PreferenceCenter.getBrandTheme';
import getMCBrandAssets from '@salesforce/apex/Ctrl_PreferenceCenter.getMCBrandAssets';

const LANG_EVENTS = ['mi:languagechange', 'echoes:languagechange', 'tds:languagechange'];

const I18N = {
    nl: {
        save:       'Voorkeuren opslaan',
        saving:     'Bezig met opslaan…',
        showAudit:  'Auditlog tonen',
        hideAudit:  'Auditlog verbergen',
        optedIn:    'aangemeld',
        categories: {
            MARKETING: { label: 'Marketingcommunicatie',    description: 'Blijf op de hoogte van nieuws, aanbiedingen en productaankondigingen.' },
            PRODUCT:   { label: 'Productupdates',           description: 'Ontvang informatie over verbeteringen en nieuwe functionaliteit.' },
            PARTNER:   { label: 'Partnernetwerk',           description: 'Ontvang communicatie van ons partnerecosysteem.' },
            RESEARCH:  { label: 'Onderzoek & Feedback',     description: 'Help ons onze producten en diensten te verbeteren.' },
            SERVICE:   { label: 'Essentiële communicatie',  description: 'Vereist voor de levering en beveiliging van uw diensten — kan niet worden uitgeschakeld.' }
        }
    },
    de: {
        save:       'Einstellungen speichern',
        saving:     'Wird gespeichert…',
        showAudit:  'Protokoll anzeigen',
        hideAudit:  'Protokoll verbergen',
        optedIn:    'eingewilligt',
        categories: {
            MARKETING: { label: 'Marketingkommunikation',   description: 'Bleiben Sie über Neuigkeiten, Aktionen und Produktankündigungen informiert.' },
            PRODUCT:   { label: 'Produkt-Updates',          description: 'Erhalten Sie Informationen über Produktverbesserungen und neue Funktionen.' },
            PARTNER:   { label: 'Partnernetzwerk',          description: 'Erhalten Sie Mitteilungen aus unserem Partnerökosystem.' },
            RESEARCH:  { label: 'Forschung & Feedback',     description: 'Helfen Sie uns, unsere Produkte und Dienstleistungen zu verbessern.' },
            SERVICE:   { label: 'Wesentliche Mitteilungen', description: 'Erforderlich für die Bereitstellung und Sicherung Ihrer Dienste — kann nicht deaktiviert werden.' }
        }
    },
    fr: {
        save:       'Enregistrer les préférences',
        saving:     'Enregistrement…',
        showAudit:  'Afficher l\'historique',
        hideAudit:  'Masquer l\'historique',
        optedIn:    'abonné(s)',
        categories: {
            MARKETING: { label: 'Communications marketing',   description: 'Restez informé des actualités, promotions et annonces de produits.' },
            PRODUCT:   { label: 'Mises à jour produit',       description: 'Recevez des informations sur les améliorations et nouvelles fonctionnalités.' },
            PARTNER:   { label: 'Réseau de partenaires',      description: 'Recevez les communications de notre écosystème de partenaires.' },
            RESEARCH:  { label: 'Recherche & Retours',        description: 'Aidez-nous à améliorer nos produits et services.' },
            SERVICE:   { label: 'Communications essentielles', description: 'Nécessaires pour fournir et sécuriser vos services — ne peuvent pas être désactivées.' }
        }
    },
    en: {
        save:       'Save Preferences',
        saving:     'Saving…',
        showAudit:  'Show audit trail',
        hideAudit:  'Hide audit trail',
        optedIn:    'opted in',
        categories: {
            MARKETING: { label: 'Marketing Communications',        description: 'Stay informed about news, promotions and product announcements.' },
            PRODUCT:   { label: 'Product Updates',                 description: 'Receive information about product improvements and new functionality.' },
            PARTNER:   { label: 'Partner Network',                 description: 'Receive communications from our partner ecosystem.' },
            RESEARCH:  { label: 'Research & Feedback',             description: 'Help us improve our products and services.' },
            SERVICE:   { label: 'Essential Service Communications', description: 'Required to provide and secure your services — cannot be disabled.' }
        }
    }
};

const BRAND_LABELS = {
    E: 'Echoes',
    M: 'Moving Intelligence',
    T: 'TDS Ultra'
};

const CATEGORY_META = {
    MARKETING: {
        label:       'Marketing Communications',
        description: 'Stay informed about news, promotions and product announcements.',
        iconName:    'utility:email',
        order:       1
    },
    PRODUCT: {
        label:       'Product Updates',
        description: 'Receive information about product improvements and new functionality.',
        iconName:    'utility:refresh',
        order:       2
    },
    PARTNER: {
        label:       'Partner Network',
        description: 'Receive communications from our partner ecosystem.',
        iconName:    'utility:partner_fund_claim',
        order:       3
    },
    RESEARCH: {
        label:       'Research & Feedback',
        description: 'Help us improve our products and services.',
        iconName:    'utility:survey',
        order:       4
    },
    SERVICE: {
        label:       'Essential Service Communications',
        description: 'Required to provide and secure your services — cannot be disabled.',
        iconName:    'utility:shield',
        order:       5
    }
};

const TYPE_LABELS = {
    NEWSLETTER:             'Newsletter',
    PROMOTIONS:             'Promotions & Offers',
    PRODUCT_ANNOUNCEMENTS:  'Product Announcements',
    WEBINAR_INVITATIONS:    'Webinar Invitations',
    CUSTOMER_EVENTS:        'Customer Events',
    SERVICE_NOTIFICATION:   'Service Notifications',
    PLATFORM_REMINDERS:     'Platform Maintenance Notices',
    SECURITY_ALERTS:        'Security Alerts',
    THEFT_RECOVERY_ALERTS:  'Theft Recovery Alerts',
    INSURANCE_NEWSLETTER:   'Insurance Partner Updates',
    INSTALLER_UPDATES:      'Installer News & Updates',
    'DEALER  EVENTS':       'Dealer Events',
    'DEALER UPDATES':       'Dealer News & Updates',
    'DEALER PROMOTIONS':    'Dealer Promotions',
    PRODUCT_UPDATE:         'Product Updates',
    APP_UPDATES:            'Mobile App Updates',
    PLATFORM_UPDATES:       'Platform Updates',
    FEATURE_RELEASES:       'New Features',
    CUSTOMER_SURVEYS:       'Customer Surveys',
    FEEDBACK_REQUESTS:      'Product & Service Feedback Requests'
};

export default class PreferenceCenter extends LightningElement {

    /** Fixed brand for landing-page / Experience Cloud use — shows only that brand, no tabs. */
    @api brand = '';

    /**
     * recordId as a getter/setter so _contextId (the wire param) stays in sync.
     * On record pages (Contact / Case) the platform wires this automatically.
     * On Experience Cloud landing pages it is never set, so connectedCallback
     * falls back to the current user Id — Apex resolves the linked Contact.
     */
    @api
    get recordId() { return this._recordId; }
    set recordId(val) {
        this._recordId = val;
        if (val) this._contextId = val;
    }
    _recordId;

    // ── State ─────────────────────────────────────────────────────────────────
    @track _contextId   = null;   // wire param — recordId on record pages, userId on landing pages
    @track _urlBrand    = '';     // brand read from URL query param (?brand=M)
    @track _prefsMap    = {};
    @track sections     = [];
    @track _activeBrand = '';
    @track isLoading    = true;
    @track isSaving     = false;
    @track hasError     = false;
    @track errorMessage = '';
    @track showToast    = false;
    @track showAudit    = false;
    @track contactName  = '';
    @track contactEmail = '';
    @track contactPhone = '';
    @track _channel     = '';     // channel from ?chan= URL param (email / sms / phone)
    @track _lang        = 'nl';   // driven by hub header language selector
    @track _pageRef     = null;
    @track lastAuditLabel = '';
    @track auditRows    = [];
    @track _brandTheme  = null;   // from BrandThemeConfig__mdt (+ optional MC override)

    _wiredResult;
    _resolvedContactId   = null;   // real Contact Id — may differ from recordId on Case pages
    _showPartnerCategory = false;  // determined per-contact from Account RecordType + ACR Roles
    _sessionId = this._uuid();
    _requestId = null;

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    connectedCallback() {
        // _contextId is intentionally NOT set here for Experience Cloud pages.
        // handlePageRef fires during init and sets it from ?cid= or falls back to
        // userId — ensuring the getPreferences wire only fires once with the right id.
        if (this.brand) {
            this._fetchBrandTheme(this.brand);
        }
        this._langHandler = (e) => { this._lang = e.detail?.language || this._lang; };
        LANG_EVENTS.forEach(k => window.addEventListener(k, this._langHandler));
        // Sync with any language already set by the hub header on the same page
        try {
            const h = window.location.hostname;
            if (h.endsWith('.de')) this._lang = 'de';
            else if (h.endsWith('.fr')) this._lang = 'fr';
            else if (h.endsWith('.co.uk') || h.endsWith('.com')) this._lang = 'en';
        } catch (_) {}
    }

    disconnectedCallback() {
        if (this._langHandler) {
            LANG_EVENTS.forEach(k => window.removeEventListener(k, this._langHandler));
        }
    }

    // ── Wire ──────────────────────────────────────────────────────────────────

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        this._pageRef = ref;
        const urlBrand = ref?.state?.brand || ref?.state?.c__brand;
        if (urlBrand && urlBrand !== this._urlBrand) {
            this._urlBrand = urlBrand;
            this._fetchBrandTheme(urlBrand);
        }
        const chan = ref?.state?.chan || ref?.state?.c__chan;
        if (chan) this._channel = chan;

        // ?cid= param: used by guest users (tokenised email link) AND authenticated users
        // who don't have a Contact linked to their org User (e.g. admins testing).
        const cid = ref?.state?.cid || ref?.state?.c__cid;
        if (isGuestUser) {
            if (cid) {
                this._contextId = cid;
            } else {
                this.isLoading    = false;
                this.hasError     = true;
                this.errorMessage = 'No contact token found. Please use the link from your email.';
            }
        } else {
            // On record pages recordId setter already set _contextId — don't overwrite it.
            // On Experience Cloud landing pages (no recordId) use ?cid= or fall back to userId.
            if (!this._recordId) {
                this._contextId = cid || userId;
            } else if (cid) {
                this._contextId = cid;
            }
        }
    }

    // contextId accepts a Contact, Case or User Id — Apex resolves the real contact
    @wire(getPreferences, { contextId: '$_contextId' })
    wiredPage(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data) {
            // Store the resolved Contact Id — on Case pages this differs from recordId
            this._resolvedContactId   = data.contactId;
            this._showPartnerCategory = !!data.showPartnerCategory;
            this.contactName  = data.contactName;
            this.contactEmail = data.contactEmail;
            this.contactPhone = data.contactPhone || '';
            // Existing saved settings are already merged by Apex into the catalog
            this._buildPrefsMap(data.preferences);
            this._buildSections();
            // Default active tab: URL param → Account PrimaryBrand → first brand in catalog
            // Skip when an explicit brand is already fixed (prop or URL)
            if (!this._activeBrand && !this.brand && !this._urlBrand) {
                this._activeBrand = data.primaryBrand
                    || (this.sections.length > 0 ? this.sections[0].brand : '')
                    || 'M';
            }
            this._setLastAuditLabel(data.lastAudit);
            this.isLoading = false;
            this.hasError  = false;
            // Load brand theme once the effective brand is known (covers internal console
            // where brand is resolved from Account, not from a URL param or @api prop).
            if (!this._brandTheme) {
                const resolved = this.brand || this._urlBrand || data.primaryBrand
                    || (this.sections.length > 0 ? this.sections[0].brand : null)
                    || 'M';
                this._fetchBrandTheme(resolved);
            }
        } else if (error) {
            this._setError(error);
        }
    }

    // ── Brand tabs ────────────────────────────────────────────────────────────

    /**
     * True when the brand is fixed — either via @api prop or URL query param.
     * Hides the brand tabs and shows only the single brand.
     */
    get hasBrandProp() { return !!(this.brand || this._urlBrand); }

    /** The brand currently being displayed. */
    get effectiveBrand() {
        return this.brand || this._urlBrand || this._activeBrand;
    }

    /** Tab items derived from the unique brands in the catalog. */
    get brandTabs() {
        const seen = new Set();
        return this.sections
            .filter(s => { if (seen.has(s.brand)) return false; seen.add(s.brand); return true; })
            .map(s => {
                const logoUrl = s.brand === 'M'
                    ? `${BRANDING_URL}/Branding/2024/img/mi-logo-black-black-rgb.png`
                    : s.brand === 'E'
                        ? `${BRANDING_URL}/Branding/2026/img/echoes-logo-black-blue-rgb.png`
                        : null;
                const isTds = s.brand === 'T';
                return {
                    brand:     s.brand,
                    label:     s.brandLabel,
                    logoUrl,
                    isTds,
                    hasVisual: !!(logoUrl || isTds),
                    isActive:  s.brand === this._activeBrand,
                    cssClass:  'slds-tabs_default__item' + (s.brand === this._activeBrand ? ' slds-is-active' : '')
                };
            });
    }

    /** Label for the landing-page brand header. */
    get activeBrandLabel() {
        return BRAND_LABELS[this.effectiveBrand] || this.effectiveBrand;
    }

    /** Sections filtered to the currently active brand. */
    get visibleSections() {
        const b = this.effectiveBrand;
        const raw = b ? this.sections.filter(s => s.brand === b) : this.sections;
        const cats = this._t.categories;
        return raw.map(s => ({
            ...s,
            label:       cats[s.categoryKey]?.label       || s.label,
            description: cats[s.categoryKey]?.description || s.description
        }));
    }

    handleBrandTab(event) {
        event.preventDefault();
        const brand = event.currentTarget.dataset.brand;
        this._activeBrand = brand;
        this._fetchBrandTheme(brand);
    }

    // ── Derived ───────────────────────────────────────────────────────────────

    /** True when running inside an Experience Cloud site (Customer Hub or any community). */
    get isExperienceCloud() { return (this._pageRef?.type || '').startsWith('comm__'); }

    /**
     * Logo URL resolved in priority order:
     *   1. MC BrandCenter live URL (if Named Credential is configured)
     *   2. Static resource path from BrandThemeConfig__mdt
     *   3. Hardcoded fallback paths (for backward compatibility)
     */
    get brandLogoUrl() {
        if (this._brandTheme?.mcLogoUrl)     return this._brandTheme.mcLogoUrl;
        if (this._brandTheme?.logoStaticPath) return `${BRANDING_URL}/Branding/${this._brandTheme.logoStaticPath}`;
        const brand = this.effectiveBrand;
        if (brand === 'E') return `${BRANDING_URL}/Branding/2026/img/echoes-logo-black-blue-rgb.png`;
        if (brand === 'M') return `${BRANDING_URL}/Branding/2024/img/mi-logo-black-black-rgb.png`;
        return null;
    }

    /** Brand tagline shown below the logo on Experience Cloud. */
    get brandTagLine() {
        return this._brandTheme?.tagLine || `Choose how ${this.activeBrandLabel} may contact you.`;
    }

    /**
     * Inline CSS custom properties applied to the root container.
     * Takes precedence over the static .brand-X CSS class colours — allows
     * colors from BrandThemeConfig__mdt (or MC BrandCenter) to override defaults.
     */
    get brandContainerStyle() {
        if (!this._brandTheme) return '';
        const parts = [];
        if (this._brandTheme.primaryColor) parts.push(`--brand-accent: ${this._brandTheme.primaryColor}`);
        if (this._brandTheme.accentColor)  parts.push(`--brand-secondary: ${this._brandTheme.accentColor}`);
        return parts.join('; ');
    }

    /** CSS class applied to the page container to drive brand accent colours (static fallback). */
    get brandCssClass() {
        const brand = this.effectiveBrand;
        const hub = this.isExperienceCloud ? ' is-hub' : '';
        return `pc-container${brand ? ' brand-' + brand : ''}${hub}`;
    }

    get _t() { return I18N[this._lang] || I18N.nl; }

    get contactDisplayLine() {
        if (this._channel === 'email' || (!this._channel && this.contactEmail)) {
            return this.contactEmail || this.contactPhone;
        }
        return this.contactPhone || this.contactEmail;
    }

    get isReady()      { return !this.isLoading && !this.hasError; }
    get saveLabel()    { return this.isSaving ? this._t.saving : this._t.save; }
    get auditToggleLabel() { return this.showAudit ? this._t.hideAudit : this._t.showAudit; }

    get optInLabel() {
        return `${this.selectedCount} / ${this.totalCount} ${this._t.optedIn}`;
    }

    get selectedCount() {
        return this.visibleSections
            .flatMap(s => s.items)
            .filter(i => i.checked && !i.isEssential)
            .length;
    }

    get totalCount() {
        return this.visibleSections
            .flatMap(s => s.items)
            .filter(i => !i.isEssential)
            .length;
    }

    // ── Handlers ──────────────────────────────────────────────────────────────
    handleChange(event) {
        const { compositeKey, checked } = event.detail;
        if (this._prefsMap[compositeKey]) {
            this._prefsMap = {
                ...this._prefsMap,
                [compositeKey]: { ...this._prefsMap[compositeKey], IsEnabled__c: checked }
            };
            this._buildSections();
        }
    }

    handleSelectAll()   { this._setAllEnabled(true);  }
    handleDeselectAll() { this._setAllEnabled(false); }

    async handleSave() {
        this.isSaving   = true;
        this.showToast  = false;
        this._requestId = this._uuid();

        const records = Object.values(this._prefsMap);

        try {
            const auditCount = await savePreferences({
                contactId: this._resolvedContactId,
                incoming:  records,
                sessionId: this._sessionId,
                requestId: this._requestId
            });

            await refreshApex(this._wiredResult);

            this.showToast = true;
            setTimeout(() => { this.showToast = false; }, 5000);

            this.dispatchEvent(new ShowToastEvent({
                title:   'Preferences Saved',
                message: `${this.contactName}'s preferences updated. ${auditCount} change(s) logged.`,
                variant: 'success'
            }));

            if (this.showAudit) this._loadAuditHistory();

        } catch (error) {
            this._setError(error);
            this.dispatchEvent(new ShowToastEvent({
                title:   'Save Failed',
                message: this.errorMessage,
                variant: 'error',
                mode:    'sticky'
            }));
        } finally {
            this.isSaving = false;
        }
    }

    dismissToast() { this.showToast = false; }

    async toggleAuditTrail() {
        this.showAudit = !this.showAudit;
        if (this.showAudit && this.auditRows.length === 0) {
            await this._loadAuditHistory();
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Fetches BrandThemeConfig__mdt data for the given brand code and optionally
     * enriches with live logo/color data from Marketing Cloud BrandCenter.
     */
    _fetchBrandTheme(brand) {
        if (!brand) return;
        getBrandTheme({ brand })
            .then(theme => {
                this._brandTheme = theme;
                if (theme?.mcBrandId) {
                    getMCBrandAssets({ mcBrandId: theme.mcBrandId })
                        .then(mcData => {
                            if (mcData) {
                                this._brandTheme = {
                                    ...this._brandTheme,
                                    primaryColor: mcData.primaryColor || this._brandTheme.primaryColor,
                                    accentColor:  mcData.accentColor  || this._brandTheme.accentColor,
                                    mcLogoUrl:    mcData.mcLogoUrl    || null
                                };
                            }
                        })
                        .catch(() => {}); // MC not configured — silently fall back
                }
            })
            .catch(() => {}); // metadata missing — CSS class fallback remains active
    }

    _buildPrefsMap(prefs) {
        const map = {};
        (prefs || []).forEach(p => { map[p.CompositeKey__c] = { ...p }; });
        this._prefsMap = map;
    }

    _buildSections() {
        const byBrand = {};
        Object.values(this._prefsMap).forEach(p => {
            const brand = p.Brand__c || '';
            const cat   = p.Category__c;
            if (!byBrand[brand])      byBrand[brand] = {};
            if (!byBrand[brand][cat]) byBrand[brand][cat] = [];
            byBrand[brand][cat].push({
                compositeKey: p.CompositeKey__c,
                label:        TYPE_LABELS[p.CommunicationType__c] || p.CommunicationType__c,
                channel:      p.Channel__c,
                checked:      p.IsEnabled__c,
                isEssential:  cat === 'SERVICE',
                legalBasis:   p.LegalBasis__c
            });
        });

        const sections = [];
        Object.keys(byBrand).sort().forEach(brand => {
            Object.keys(CATEGORY_META)
                .filter(cat => byBrand[brand][cat])
                .filter(cat => cat !== 'PARTNER' || this._showPartnerCategory)
                .sort((a, b) => CATEGORY_META[a].order - CATEGORY_META[b].order)
                .forEach(cat => {
                    sections.push({
                        key:         brand + '_' + cat,
                        brand:       brand,
                        brandLabel:  BRAND_LABELS[brand] || brand,
                        categoryKey: cat,
                        label:       CATEGORY_META[cat].label,
                        description: CATEGORY_META[cat].description,
                        iconName:    CATEGORY_META[cat].iconName,
                        isEssential: cat === 'SERVICE',
                        items:       byBrand[brand][cat]
                    });
                });
        });
        this.sections = sections;
    }

    /** Select/deselect all non-essential items in the currently visible brand only. */
    _setAllEnabled(val) {
        const visibleKeys = new Set(
            this.visibleSections.flatMap(s => s.items).map(i => i.compositeKey)
        );
        const updated = {};
        Object.entries(this._prefsMap).forEach(([key, p]) => {
            if (visibleKeys.has(key) && p.Category__c !== 'SERVICE') {
                updated[key] = { ...p, IsEnabled__c: val };
            } else {
                updated[key] = p;
            }
        });
        this._prefsMap = updated;
        this._buildSections();
    }

    _setLastAuditLabel(audit) {
        if (!audit) { this.lastAuditLabel = ''; return; }
        const d   = new Date(audit.EventTimestamp__c);
        const fmt = d.toLocaleDateString('en-GB', { day:'2-digit', month:'short', year:'numeric' });
        const who = audit.Changed_By__r?.Name || 'an agent';
        this.lastAuditLabel = `Last updated by ${who} on ${fmt} via ${audit.Change_Source__c}`;
    }

    async _loadAuditHistory() {
        try {
            const rows = await getAuditHistory({ contactId: this._resolvedContactId, limitRows: 50 });
            this.auditRows = (rows || []).map(r => ({
                id:           r.Id,
                timestamp:    r.EventTimestamp__c
                    ? new Date(r.EventTimestamp__c).toLocaleString('en-GB')
                    : '',
                type:         TYPE_LABELS[r.CommunicationType__c] || r.CommunicationType__c,
                channel:      r.Channel__c,
                brand:        r.Brand__c,
                oldVal:       r.Old_Value__c ? 'Enabled' : 'Disabled',
                newVal:       r.New_Value__c ? 'Enabled' : 'Disabled',
                changed:      r.Changed_By__r?.Name || '—',
                source:       r.Change_Source__c,
                reason:       r.Change_Reason__c,
                isOverride:   r.IsAdminOverride__c,
                overrideNote: r.OverrideReason__c
            }));
        } catch (e) {
            console.error('Audit load failed', e);
        }
    }

    _setError(error) {
        this.isLoading    = false;
        this.hasError     = true;
        this.errorMessage = error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    _uuid() {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0;
            return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
        });
    }
}
