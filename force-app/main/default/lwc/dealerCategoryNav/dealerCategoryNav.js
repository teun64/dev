import { LightningElement, api } from 'lwc';

const CATEGORIES = [
    { value: 'All',                label: 'Alle producten' },
    { value: 'Hardware Security',  label: 'Hardware Security' },
    { value: 'Hardware Fleet',     label: 'Hardware Fleet' },
    { value: 'Services',           label: 'Services' },
    { value: 'Subscriptions',      label: 'Abonnementen' },
    { value: 'Accessories',        label: 'Accessoires' },
    { value: 'Promotions',         label: 'Promoties' }
];

export default class DealerCategoryNav extends LightningElement {

    @api activeCategory = 'All';

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
