import { LightningElement, api } from 'lwc';

const CATEGORIES = [
    { value: '',         label: 'Alle producten' },
    { value: 'Fleet',    label: 'Fleet' },
    { value: 'Security', label: 'Security' },
    { value: 'Beacon',   label: 'Beacon' }
];

export default class DealerCategoryNav extends LightningElement {

    @api activeCategory = '';

    get categoryItems() {
        return CATEGORIES.map(cat => ({
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
