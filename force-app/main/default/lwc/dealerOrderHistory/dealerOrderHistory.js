import { LightningElement, track } from 'lwc';
import getOrderHistory from '@salesforce/apex/Ctrl_DealerShop.getOrderHistory';
import getOrderDetail from '@salesforce/apex/Ctrl_DealerShop.getOrderDetail';
import getPortalLabels from '@salesforce/apex/Ctrl_DealerPortal.getPortalLabels';
import { mergeItemsIntoCart } from 'c/dealerCartStorage';
import { resolveLanguageFromHostname, resolveNumberLocale, ORDER_DEFAULT_LABELS, orderStatusLabel } from 'c/dealerLanguage';

export default class DealerOrderHistory extends LightningElement {
    @track orders = [];
    @track isLoading = false;
    @track onlyMine = true;
    @track addingOrderId = null;
    @track labels = ORDER_DEFAULT_LABELS;

    language = resolveLanguageFromHostname();
    _rawOrders = [];

    connectedCallback() {
        getPortalLabels({ language: this.language })
            .then((labels) => {
                this.labels = { ...ORDER_DEFAULT_LABELS, ...labels };
                this._decorate();
            })
            .catch(() => {});
        this.loadOrders();
    }

    loadOrders() {
        this.isLoading = true;
        getOrderHistory({ onlyMine: this.onlyMine })
            .then((result) => {
                this._rawOrders = result || [];
                this._decorate();
            })
            .catch(() => {
                this._rawOrders = [];
                this.orders = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Re-run when the labels arrive after the orders, so the status text follows the language.
    _decorate() {
        this.orders = this._rawOrders.map((o) => ({
            ...o,
            statusLabel: orderStatusLabel(this.labels, o.stageName),
            formattedDate: this._formatDate(o.placedDate),
            formattedAmount: this._formatAmount(o.amount, o.currencyIsoCode),
            detailUrl: `/dealers/order-detail?id=${o.id}`
        }));
    }

    _formatDate(value) {
        if (!value) return '';
        return new Date(value).toLocaleDateString(resolveNumberLocale(this.language), {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric'
        });
    }

    _formatAmount(value, currencyIsoCode) {
        if (value === null || value === undefined) return '-';
        return new Intl.NumberFormat(resolveNumberLocale(this.language), {
            style: 'currency',
            currency: currencyIsoCode || 'EUR'
        }).format(value);
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
