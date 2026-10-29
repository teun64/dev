import { LightningElement, track } from 'lwc';
import getOrderDetail from '@salesforce/apex/Ctrl_DealerShop.getOrderDetail';
import getPortalLabels from '@salesforce/apex/Ctrl_DealerPortal.getPortalLabels';
import { mergeItemsIntoCart, saveOrderOptions } from 'c/dealerCartStorage';
import { resolveLanguageFromHostname, resolveNumberLocale, ORDER_DEFAULT_LABELS, orderStatusLabel } from 'c/dealerLanguage';

export default class DealerOrderDetail extends LightningElement {
    @track order = null;
    @track isLoading = true;
    @track errorMessage = null;
    @track labels = ORDER_DEFAULT_LABELS;

    orderId;
    language = resolveLanguageFromHostname();
    _rawOrder = null;
    _errorKey = null;

    connectedCallback() {
        getPortalLabels({ language: this.language })
            .then((labels) => {
                this.labels = { ...ORDER_DEFAULT_LABELS, ...labels };
                if (this._rawOrder) this._decorate();
                if (this._errorKey) this.errorMessage = this.labels[this._errorKey];
            })
            .catch(() => {});
        if (typeof window !== 'undefined') {
            const params = new URLSearchParams(window.location.search);
            this.orderId = params.get('id');
        }
        if (this.orderId) {
            this.loadOrder();
        } else {
            this.isLoading = false;
            this._errorKey = 'DealerOrder_NoOrderGiven';
            this.errorMessage = this.labels[this._errorKey];
        }
    }

    loadOrder() {
        this.isLoading = true;
        this.errorMessage = null;
        getOrderDetail({ opportunityId: this.orderId })
            .then((result) => {
                this._rawOrder = result;
                this._decorate();
            })
            .catch(() => {
                // The server messages are English only, so always the translated text here.
                this._errorKey = 'DealerOrder_LoadError';
                this.errorMessage = this.labels[this._errorKey];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Re-run when the labels arrive after the order, so the status text follows the language.
    _decorate() {
        const result = this._rawOrder;
        this.order = {
            ...result,
            statusLabel: orderStatusLabel(this.labels, result.stageName),
            formattedDate: this._formatDate(result.placedDate),
            lines: (result.lines || []).map((line) => ({
                ...line,
                productName: line.product ? (line.product.displayName || line.product.name) : '',
                productCode: line.product ? line.product.productCode : '',
                imageUrl: line.product ? line.product.imageUrl : null,
                formattedOriginalPrice: this._formatPrice(line.originalUnitPrice, result.currencyIsoCode),
                formattedCurrentPrice: this._formatPrice(line.product ? line.product.unitPrice : null, result.currencyIsoCode)
            }))
        };
    }

    _formatDate(value) {
        if (!value) return '';
        return new Date(value).toLocaleDateString(resolveNumberLocale(this.language), { day: '2-digit', month: '2-digit', year: 'numeric' });
    }

    _formatPrice(value, currencyIsoCode) {
        if (value == null) return '—';
        return new Intl.NumberFormat(resolveNumberLocale(this.language), {
            style: 'currency',
            currency: currencyIsoCode || 'EUR'
        }).format(value);
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
        // Ordering again: a fresh reference (blank = the new order's number) but the same delivery
        // address as the original order - still changeable in the cart's order options.
        saveOrderOptions({
            customerReference: '',
            useDifferentShippingAddress: !!this.order.useDifferentShippingAddress,
            shippingAddress: this.order.shippingAddress || null,
            openOptions: !!this.order.useDifferentShippingAddress
        });
        this._goToShopCart();
    }

    _goToShopCart() {
        if (typeof window !== 'undefined') {
            window.location.href = '/dealers/shop?openCart=1';
        }
    }
}
