import { LightningElement, api, track } from 'lwc';
import COMMUNITY_BASE from '@salesforce/community/basePath';

const LANGS = [
    { code: 'nl', display: 'NL', tlds: ['.nl'] },
    { code: 'de', display: 'DE', tlds: ['.de'] },
    { code: 'fr', display: 'FR', tlds: ['.fr'] },
    { code: 'en', display: 'EN', tlds: ['.co.uk', '.com'] },
];

const EVENT_KEY = 'tds:languagechange';

export default class TdsHubHeader extends LightningElement {

    /** Optional background image URL — set in Experience Builder */
    @api backgroundImageUrl = '';

    @track _lang = 'en';

    connectedCallback() {
        this._lang = this._detectLang();
        this._emit();
    }

    // ── Getters ───────────────────────────────────────────────────

    get languages() {
        return LANGS.map(l => ({
            code:     l.code,
            display:  l.display,
            isActive: l.code === this._lang,
            cssClass: 'tds-lang' + (l.code === this._lang ? ' is-active' : ''),
        }));
    }

    get homeUrl() {
        return COMMUNITY_BASE || '/';
    }

    get headerStyle() {
        if (!this.backgroundImageUrl) return '';
        return `background-image: linear-gradient(rgba(21,26,11,0.82), rgba(21,26,11,0.82)), url('${this.backgroundImageUrl}'); background-size: cover; background-position: center;`;
    }

    // ── Handlers ──────────────────────────────────────────────────

    handleLangClick(event) {
        const code = event.currentTarget.dataset.lang;
        if (code && code !== this._lang) {
            this._lang = code;
            this._emit();
        }
    }

    // ── Private ───────────────────────────────────────────────────

    _detectLang() {
        try {
            const h = window.location.hostname;
            for (const l of LANGS) {
                if (l.tlds.some(tld => h.endsWith(tld))) return l.code;
            }
        } catch (_) { /* ignore */ }
        return 'en';
    }

    _emit() {
        const detail = { language: this._lang };
        this.dispatchEvent(new CustomEvent('languagechange', { detail, bubbles: true, composed: true }));
        window.dispatchEvent(new CustomEvent(EVENT_KEY, { detail }));
    }
}
