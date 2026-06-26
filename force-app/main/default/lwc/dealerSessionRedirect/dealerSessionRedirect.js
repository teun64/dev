import { LightningElement } from 'lwc';

export default class DealerSessionRedirect extends LightningElement {
    connectedCallback() {
        if (typeof window === 'undefined') return;

        const path = window.location.pathname;
        if (!path.includes('session/receive')) return;

        const params = new URLSearchParams(window.location.search);
        let startURL = params.get('startURL');
        if (!startURL) return;

        try {
            startURL = decodeURIComponent(startURL);
        } catch (e) {
            return;
        }

        // Prevent redirect loops
        if (startURL.includes('session/receive')) return;

        // Salesforce encodes site-relative paths as //sitePath/...
        // Convert //dealer/path → /dealer/path (same-origin absolute path)
        if (startURL.startsWith('//')) {
            startURL = startURL.substring(1);
        }

        // Only allow same-origin redirects
        try {
            const target = new URL(startURL, window.location.origin);
            if (target.origin !== window.location.origin) return;
            window.location.href = target.href;
        } catch (e) {
            // Invalid URL — do nothing
        }
    }
}
