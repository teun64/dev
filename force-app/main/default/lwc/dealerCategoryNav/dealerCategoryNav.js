import { LightningElement, api, track } from 'lwc';
import getPlatformTabs from '@salesforce/apex/Ctrl_DealerShop.getPlatformTabs';

const ALL_VALUE       = '';
const FAVORITES_VALUE = 'favorites';

export default class DealerCategoryNav extends LightningElement {

    @api activeCategory = '';
    @api dealerAccountId = null;
    @api shopLabels = {};
    // Platform tabs (from getPlatformTabs) are excluded here - their labels come from the
    // System_Platform__c picklist entry, not from Custom Labels/shopLabels.
    @track _platformTabs = [];

    connectedCallback() {
        getPlatformTabs({ dealerAccountId: this.dealerAccountId })
            .then((tabs) => { this._platformTabs = tabs || []; })
            .catch(() => { this._platformTabs = []; });
    }

    get categoryItems() {
        const all = [
            { value: ALL_VALUE, label: this.shopLabels.DealerShop_AllProducts },
            ...this._platformTabs,
            { value: FAVORITES_VALUE, label: this.shopLabels.DealerShop_MyFavorites }
        ];
        return all.map(cat => ({
            ...cat,
            isActive: cat.value === this.activeCategory,
            cssClass: 'cat-nav__item' + (cat.value === this.activeCategory ? ' cat-nav__item--active' : '')
        }));
    }

    handleTabClick(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.activeCategory) return;
        this.dispatchEvent(new CustomEvent('categorychange', {
            detail:  { category: value },
            bubbles: true
        }));
    }
}
