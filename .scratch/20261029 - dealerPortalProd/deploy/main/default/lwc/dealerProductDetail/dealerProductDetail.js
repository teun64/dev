import { LightningElement, api, wire, track } from 'lwc';
import getProductDetail from '@salesforce/apex/Ctrl_DealerShop.getProductDetail';
import toggleFavorite    from '@salesforce/apex/Ctrl_DealerShop.toggleFavorite';
import { resolveNumberLocale } from 'c/dealerLanguage';

export default class DealerProductDetail extends LightningElement {
    @api productId;
    @api dealerAccountId = null;
    @api shopLabels = {};
    @api language = 'en';

    @track quantity = 1;
    @track product = null;
    @track isLoading = true;
    @track hasError = false;
    @track errorMessage = '';

    // Recomputed per language rather than a cached module constant, so it always reflects the
    // current @api language (only the number formatting - decimal/grouping separators - not the
    // currency symbol, which still needs the account's real CurrencyIsoCode).
    get _currencyFormat() {
        return new Intl.NumberFormat(resolveNumberLocale(this.language), {
            style: 'currency',
            currency: 'EUR',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    @wire(getProductDetail, { productId: '$productId', dealerAccountId: '$dealerAccountId' })
    wiredProduct({ data, error }) {
        if (data) {
            this.product = this._enrichProduct(data);
            this.hasError = false;
            this.isLoading = false;
        } else if (error) {
            this.hasError = true;
            this.errorMessage = (error.body && error.body.message)
                ? error.body.message
                : this.shopLabels.DealerShop_ProductLoadError;
            this.isLoading = false;
        }
    }

    _enrichProduct(raw) {
        const enriched = Object.assign({}, raw);
        if (enriched.priceTiers && enriched.priceTiers.length > 0) {
            enriched.priceTiers = enriched.priceTiers.map(tier => ({
                ...tier,
                formattedPrice: tier.price != null ? this._currencyFormat.format(tier.price) : '—'
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
        return this.isFavorite ? this.shopLabels.DealerShop_FavoriteActive : this.shopLabels.DealerShop_FavoriteInactive;
    }

    handleToggleFavorite() {
        if (!this.productId) return;
        toggleFavorite({ productId: this.productId, dealerAccountId: this.dealerAccountId })
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

    // Account.Show_List_Prices__c - the server only fills listPrice when that's on.
    get hasListPrice() {
        return this.product?.listPrice != null;
    }

    get formattedListPrice() {
        return this.hasListPrice ? this._currencyFormat.format(this.product.listPrice) : '';
    }

    // Same rule as the product card: equal to the list price = empty line instead of the same number.
    get unitPriceRowClass() {
        const same = this.hasListPrice && Number(this.product.listPrice) === Number(this.product.unitPrice);
        return 'unit-price-row' + (same ? ' unit-price-row--blank' : '');
    }

    get formattedUnitPrice() {
        if (!this.product || this.product.unitPrice == null) return '—';
        return this._currencyFormat.format(this.product.unitPrice);
    }

    get formattedCalculatedPrice() {
        if (!this.product || this.product.unitPrice == null) return '—';
        const price = this.calculatePriceForQty(this.quantity);
        return this._currencyFormat.format(price * this.quantity);
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
        // The base unit price, not the tier price for the chosen quantity: the cart applies the
        // tiers itself for whatever quantity the line ends up with (a stored tier price would stay
        // too low once the quantity is lowered in the cart). placeOrder prices every line
        // server-side anyway; a hidden-price product has no price (Ctrl_DealerShop nulls it out).
        const unitPrice = this.pricesHidden ? null : this.product?.unitPrice;
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
