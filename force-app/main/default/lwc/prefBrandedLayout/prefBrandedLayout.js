import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference }          from 'lightning/navigation';
import getBrandTheme                     from '@salesforce/apex/Ctrl_PreferenceCenter.getBrandTheme';
import getMCBrandAssets                  from '@salesforce/apex/Ctrl_PreferenceCenter.getMCBrandAssets';

export default class PrefBrandedLayout extends LightningElement {

    @track _theme = null;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        const brand = pageRef?.state?.brand || pageRef?.state?.c__brand;
        if (brand) {
            getBrandTheme({ brand })
                .then(theme => {
                    this._theme = theme;
                    // If a MC brand ID is configured, try to enrich with live MC assets
                    if (theme?.mcBrandId) {
                        getMCBrandAssets({ mcBrandId: theme.mcBrandId })
                            .then(mcData => {
                                if (mcData) {
                                    this._theme = {
                                        ...this._theme,
                                        primaryColor: mcData.primaryColor || this._theme.primaryColor,
                                        accentColor:  mcData.accentColor  || this._theme.accentColor,
                                        mcLogoUrl:    mcData.mcLogoUrl    || null
                                    };
                                }
                            })
                            .catch(() => {}); // silent fallback to metadata values
                    }
                })
                .catch(() => {});
        }
    }

    /** Inline CSS custom properties set at the layout root — cascade into all page content. */
    get brandStyle() {
        if (!this._theme) return '';
        const parts = [];
        if (this._theme.primaryColor) parts.push(`--brand-accent: ${this._theme.primaryColor}`);
        if (this._theme.accentColor)  parts.push(`--brand-secondary: ${this._theme.accentColor}`);
        return parts.join('; ');
    }
}
