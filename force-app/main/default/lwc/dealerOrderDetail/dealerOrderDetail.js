import { LightningElement, track } from 'lwc';
import getOrderDetail from '@salesforce/apex/Ctrl_DealerShop.getOrderDetail';
import { mergeItemsIntoCart } from 'c/dealerCartStorage';

const CURRENCY_FORMAT = new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR' });

export default class DealerOrderDetail extends LightningElement {
    @track order = null;
    @track isLoading = true;
    @track errorMessage = null;

    orderId;

    connectedCallback() {
        if (typeof window !== 'undefined') {
            const params = new URLSearchParams(window.location.search);
            this.orderId = params.get('id');
        }
        if (this.orderId) {
            this.loadOrder();
        } else {
            this.isLoading = false;
            this.errorMessage = 'Geen bestelling opgegeven.';
        }
    }

    loadOrder() {
        this.isLoading = true;
        this.errorMessage = null;
        getOrderDetail({ opportunityId: this.orderId })
            .then((result) => {
                this.order = {
                    ...result,
                    formattedDate: this._formatDate(result.placedDate),
                    lines: (result.lines || []).map((line) => ({
                        ...line,
                        productName: line.product ? (line.product.displayName || line.product.name) : '',
                        productCode: line.product ? line.product.productCode : '',
                        imageUrl: line.product ? line.product.imageUrl : null,
                        formattedOriginalPrice: this._formatPrice(line.originalUnitPrice),
                        formattedCurrentPrice: this._formatPrice(line.product ? line.product.unitPrice : null)
                    }))
                };
            })
            .catch((e) => {
                this.errorMessage = (e && e.body && e.body.message) || 'Er is een fout opgetreden bij het laden van de bestelling.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    _formatDate(value) {
        if (!value) return '';
        return new Date(value).toLocaleDateString('nl-NL', { day: '2-digit', month: '2-digit', year: 'numeric' });
    }

    _formatPrice(value) {
        return value == null ? '—' : CURRENCY_FORMAT.format(value);
    }

    get isEmpty() {
        return !this.isLoading && !this.errorMessage && (!this.order || !this.order.lines || this.order.lines.length === 0);
    }

    handleAddLineToCart(event) {
        const productId = event.currentTarget.dataset.productId;
        const line = this.order.lines.find((l) => l.productId === productId);
        if (!line || !line.product) return;

        mergeItemsIntoCart([{
            productId: line.productId,
            quantity: line.quantity,
            unitPrice: line.product.unitPrice,
            priceTiers: line.product.priceTiers || [],
            pricesHidden: line.product.pricesHidden,
            productName: line.productName,
            imageUrl: line.imageUrl
        }]);
        this._goToShopCart();
    }

    handleReorderAll() {
        if (!this.order || !this.order.lines || this.order.lines.length === 0) return;

        const items = this.order.lines
            .filter((l) => l.product)
            .map((l) => ({
                productId: l.productId,
                quantity: l.quantity,
                unitPrice: l.product.unitPrice,
                priceTiers: l.product.priceTiers || [],
                pricesHidden: l.product.pricesHidden,
                productName: l.productName,
                imageUrl: l.imageUrl
            }));
        mergeItemsIntoCart(items);
        this._goToShopCart();
    }

    _goToShopCart() {
        if (typeof window !== 'undefined') {
            window.location.href = '/dealers/shop?openCart=1';
        }
    }
}
