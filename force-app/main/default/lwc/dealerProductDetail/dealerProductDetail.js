import { LightningElement, api, wire, track } from 'lwc';
import getProductDetail from '@salesforce/apex/Ctrl_DealerShop.getProductDetail';
import toggleFavorite    from '@salesforce/apex/Ctrl_DealerShop.toggleFavorite';

const CURRENCY_FORMAT = new Intl.NumberFormat('nl-NL', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
});

export default class DealerProductDetail extends LightningElement {
    @api productId;

    @track quantity = 1;
    @track product = null;
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    @wire(getProductDetail, { productId: '$productId' })
    wiredProduct({ data, error }) {
        if (data) {
            this.product = this._enrichProduct(data);
            this.hasError = false;
            this.isLoading = false;
        } else if (error) {
            this.hasError = true;
            this.errorMessage = (error.body && error.body.message)
                ? error.body.message
                : 'Er is een fout opgetreden bij het laden van het product.';
            this.isLoading = false;
        }
    }

    _enrichProduct(raw) {
        const enriched = Object.assign({}, raw);
        if (enriched.priceTiers && enriched.priceTiers.length > 0) {
            enriched.priceTiers = enriched.priceTiers.map(tier => ({
                ...tier,
                formattedPrice: tier.price != null ? CURRENCY_FORMAT.format(tier.price) : '—'
            }));
        }
        return enriched;
    }

    get isFavorite() {
        return !!this.product?.isFavorite;
    }

    get favoriteButtonClass() {
        return 'btn-favorite-detail' + (this.isFavorite ? ' btn-favorite-detail--active' : '');
    }

    get favoriteButtonLabel() {
        return this.isFavorite ? '♥ Favoriet' : '♡ Markeer als favoriet';
    }

    handleToggleFavorite() {
        if (!this.productId) return;
        toggleFavorite({ productId: this.productId })
            .then((isFavorite) => {
                this.product = { ...this.product, isFavorite };
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Failed to toggle favorite', error);
            });
    }

    get hasPriceTiers() {
        return this.product && this.product.priceTiers && this.product.priceTiers.length > 0;
    }

    get formattedUnitPrice() {
        if (!this.product || this.product.unitPrice == null) return '—';
        return CURRENCY_FORMAT.format(this.product.unitPrice);
    }

    get formattedCalculatedPrice() {
        if (!this.product || this.product.unitPrice == null) return '—';
        const price = this.calculatePriceForQty(this.quantity);
        return CURRENCY_FORMAT.format(price * this.quantity);
    }

    calculatePriceForQty(qty) {
        if (!this.product) return 0;
        const tiers = this.product.priceTiers;
        if (!tiers || tiers.length === 0) return this.product.unitPrice || 0;

        let applicablePrice = this.product.unitPrice || 0;
        for (const tier of tiers) {
            if (tier.fromQty != null && qty >= tier.fromQty) {
                applicablePrice = tier.price != null ? tier.price : applicablePrice;
            }
        }
        return applicablePrice;
    }

    handleQuantityChange(event) {
        const val = parseInt(event.target.value, 10);
        this.quantity = (!isNaN(val) && val >= 1) ? val : 1;
    }

    get pricesHidden() {
        return !!this.product?.pricesHidden;
    }

    handleAddToCart() {
        // A hidden-price product never had a real unitPrice to begin with (Ctrl_DealerShop nulls
        // it out) - calculatePriceForQty would otherwise silently default to 0 here, which reads
        // to placeOrder as a genuine client-supplied €0 price rather than "no price supplied,
        // resolve it yourself". Send null explicitly so the server always re-resolves the real,
        // currently discounted price.
        const unitPrice = this.pricesHidden ? null : this.calculatePriceForQty(this.quantity);
        this.dispatchEvent(new CustomEvent('addtocart', {
            detail: {
                productId: this.productId,
                quantity: this.quantity,
                unitPrice,
                priceTiers: this.product?.priceTiers || [],
                pricesHidden: this.pricesHidden,
                productName: this.product?.displayName || this.product?.name || '',
                imageUrl: this.product?.imageUrl || null
            },
            bubbles: true,
            composed: true
        }));
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('backtoshop', {
            bubbles: true,
            composed: true
        }));
    }
}
