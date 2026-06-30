import { LightningElement, api, track } from 'lwc';
import RED_HAT_DISPLAY_URL from '@salesforce/resourceUrl/Red_Hat_Display';
import COMMUNITY_BASE      from '@salesforce/community/basePath';

const LANGS = [
    { code: 'nl', display: 'NL', tlds: ['.nl'] },
    { code: 'de', display: 'DE', tlds: ['.de'] },
    { code: 'fr', display: 'FR', tlds: ['.fr'] },
    { code: 'en', display: 'EN', tlds: ['.co.uk', '.com'] },
];

const EVENT_KEY = 'echoes:languagechange';

export default class EchoesHubHeader extends LightningElement {

    /** Optional background image URL — set in Experience Builder */
    @api backgroundImageUrl = '';

    @track _lang = 'nl';

    connectedCallback() {
        this._injectFont();
        this._lang = this._detectLang();
        this._emit();
    }

    // ── Getters ───────────────────────────────────────────────────

    get languages() {
        return LANGS.map(l => ({
            code:     l.code,
            display:  l.display,
            isActive: l.code === this._lang,
            cssClass: 'echoes-lang' + (l.code === this._lang ? ' is-active' : ''),
        }));
    }

    get homeUrl() {
        return COMMUNITY_BASE || '/';
    }

    get headerStyle() {
        if (!this.backgroundImageUrl) return '';
        return `background-image: linear-gradient(rgba(0,1,34,0.82), rgba(0,1,34,0.82)), url('${this.backgroundImageUrl}'); background-size: cover; background-position: center;`;
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

    _injectFont() {
        if (document.getElementById('echoes-rh-display-face')) return;
        const style = document.createElement('style');
        style.id = 'echoes-rh-display-face';
        style.textContent = `@font-face {
            font-family: 'Red Hat Display';
            font-style: normal;
            font-weight: 100 900;
            font-display: swap;
            src: url('${RED_HAT_DISPLAY_URL}/RedHatDisplay-VariableFont_wght.ttf') format('truetype');
        }`;
        document.head.appendChild(style);
    }

    _detectLang() {
        try {
            const h = window.location.hostname;
            for (const l of LANGS) {
                if (l.tlds.some(tld => h.endsWith(tld))) return l.code;
            }
        } catch (_) { /* ignore */ }
        return 'nl';
    }

    _emit() {
        const detail = { language: this._lang };
        this.dispatchEvent(new CustomEvent('languagechange', { detail, bubbles: true, composed: true }));
        window.dispatchEvent(new CustomEvent(EVENT_KEY, { detail }));
    }
}
