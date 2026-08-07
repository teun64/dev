import { LightningElement, track } from 'lwc';
import getOrderHistory from '@salesforce/apex/Ctrl_DealerShop.getOrderHistory';

export default class DealerOrderHistory extends LightningElement {
    @track orders = [];
    @track isLoading = false;
    @track onlyMine = true;

    connectedCallback() {
        this.loadOrders();
    }

    loadOrders() {
        this.isLoading = true;
        getOrderHistory({ onlyMine: this.onlyMine })
            .then((result) => {
                this.orders = (result || []).map((o) => ({
                    ...o,
                    formattedDate: this._formatDate(o.placedDate),
                    formattedAmount: this._formatAmount(o.amount)
                }));
            })
            .catch(() => {
                this.orders = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    _formatDate(value) {
        if (!value) return '';
        return new Date(value).toLocaleDateString('nl-NL', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric'
        });
    }

    _formatAmount(value) {
        if (value === null || value === undefined) return '-';
        return new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR' }).format(value);
    }

    get isEmpty() {
        return !this.isLoading && (!this.orders || this.orders.length === 0);
    }

    get mineButtonClass() {
        return this.onlyMine ? 'toggle-btn toggle-btn--active' : 'toggle-btn';
    }

    get allButtonClass() {
        return !this.onlyMine ? 'toggle-btn toggle-btn--active' : 'toggle-btn';
    }

    handleShowMine() {
        if (this.onlyMine) return;
        this.onlyMine = true;
        this.loadOrders();
    }

    handleShowAll() {
        if (!this.onlyMine) return;
        this.onlyMine = false;
        this.loadOrders();
    }
}
