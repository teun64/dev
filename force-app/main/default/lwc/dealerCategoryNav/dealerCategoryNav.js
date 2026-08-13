import { LightningElement, api, track } from 'lwc';
import getPlatformTabs from '@salesforce/apex/Ctrl_DealerShop.getPlatformTabs';

const TAB_ALL       = { value: '',          label: 'Alle producten' };
const TAB_FAVORITES = { value: 'favorites', label: 'Mijn favorieten' };

export default class DealerCategoryNav extends LightningElement {

    @api activeCategory = '';
    @track _categories = [TAB_ALL, TAB_FAVORITES];

    connectedCallback() {
        getPlatformTabs()
            .then((tabs) => {
                this._categories = [TAB_ALL, ...(tabs || []), TAB_FAVORITES];
            })
            .catch(() => {
                this._categories = [TAB_ALL, TAB_FAVORITES];
            });
    }

    get categoryItems() {
        return this._categories.map(cat => ({
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
