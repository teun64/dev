import { LightningElement, track } from 'lwc';
import getOrderHistory from '@salesforce/apex/Ctrl_DealerShop.getOrderHistory';
import getOrderDetail from '@salesforce/apex/Ctrl_DealerShop.getOrderDetail';
import { mergeItemsIntoCart } from 'c/dealerCartStorage';

export default class DealerOrderHistory extends LightningElement {
    @track orders = [];
    @track isLoading = false;
    @track onlyMine = true;
    @track addingOrderId = null;

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
                    formattedAmount: this._formatAmount(o.amount),
                    detailUrl: `/dealers/order-detail?id=${o.id}`
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

    handleAddToCart(event) {
        const orderId = event.currentTarget.dataset.orderId;
        if (this.addingOrderId) return;
        this.addingOrderId = orderId;

        getOrderDetail({ opportunityId: orderId })
            .then((result) => {
                const items = (result.lines || [])
                    .filter((l) => l.product)
                    .map((l) => ({
                        productId: l.productId,
                        quantity: l.quantity,
                        unitPrice: l.product.unitPrice,
                        priceTiers: l.product.priceTiers || [],
                        pricesHidden: l.product.pricesHidden,
                        productName: l.product.displayName || l.product.name,
                        imageUrl: l.product.imageUrl
                    }));
                mergeItemsIntoCart(items);
                if (typeof window !== 'undefined') {
                    window.location.href = '/dealers/shop?openCart=1';
                }
            })
            .catch(() => {
                this.addingOrderId = null;
            });
    }
}
