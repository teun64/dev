import { LightningElement, api, track, wire } from 'lwc';
import placeOrder from '@salesforce/apex/Ctrl_DealerShop.placeOrder';
import getShippingInfo from '@salesforce/apex/Ctrl_DealerShop.getShippingInfo';
import { resolveNumberLocale } from 'c/dealerLanguage';

export default class DealerCart extends LightningElement {
    @api cartItems = [];
    @api dealerAccountId = null;
    @api shopLabels = {};
    @api language = 'en';

    @track isLoading = false;
    @track errorMessage = null;
    @track shippingInfo = null;
    // Internal-only (dealerAccountId set) - lets a Salesforce user waive the shipping fee for this
    // specific order. Defaults off; a portal dealer never sees this control and the server ignores
    // the flag entirely when dealerAccountId is null, regardless of what a client sends.
    @track omitShippingCost = false;

    @wire(getShippingInfo, { dealerAccountId: '$dealerAccountId' })
    wiredShippingInfo({ data }) {
        if (data) this.shippingInfo = data;
    }

    // Only an internal user (Account-embedded quick action) may waive shipping - never a portal dealer.
    get isInternalUser() {
        return !!this.dealerAccountId;
    }

    get currencySymbol() {
        return this.shippingInfo?.currencyIsoCode === 'GBP' ? '£' : '€';
    }

    get showShippingRemark() {
        return !!this.shippingInfo?.configured && !this.omitShippingCost;
    }

    get shippingRemarkText() {
        if (!this.shippingInfo?.configured) return '';
        const currency = this.currencySymbol;
        if (this.shippingInfo.method === 'Fixed') {
            const threshold = `${currency} ${this._formatPrice(this.shippingInfo.freeThreshold)}`;
            if (this.shippingInfo.feeAmount != null) {
                const fee = `${currency} ${this._formatPrice(this.shippingInfo.feeAmount)}`;
                return this.shopLabels.DealerShop_ShippingFixedWithFee
                    .replace('{0}', threshold)
                    .replace('{1}', fee);
            }
            return this.shopLabels.DealerShop_ShippingFixedNoFee.replace('{0}', threshold);
        }
        if (this.shippingInfo.method === 'Weight_Based') {
            return this.shopLabels.DealerShop_ShippingWeightBased;
        }
        return '';
    }

    get omitShippingRemarkText() {
        return this.shopLabels.DealerShop_ShippingOmitRemark;
    }

    get omitShippingLabelText() {
        return this.shopLabels.DealerShop_ShippingOmitLabel;
    }

    handleOmitShippingChange(event) {
        this.omitShippingCost = event.target.checked;
    }

    get cartClass() {
        return 'cart-wrapper';
    }

    get hasError() {
        return this.errorMessage !== null;
    }

    get isEmpty() {
        return !this.cartItems || this.cartItems.length === 0;
    }

    get enrichedCartItems() {
        return (this.cartItems || []).map(item => {
            if (item.pricesHidden) {
                return { ...item, effectivePrice: null, lineTotal: null };
            }
            const effectivePrice = this._effectivePrice(item.unitPrice, item.priceTiers, item.quantity);
            return {
                ...item,
                effectivePrice: this._formatPrice(effectivePrice),
                lineTotal: this._formatPrice(item.quantity * effectivePrice)
            };
        });
    }

    // All items in one dealer's cart belong to the same account, so they share the same
    // Hide_Prices__c status - checking every item (not just the first) is just defensive.
    get pricesHidden() {
        return (this.cartItems || []).some(item => item.pricesHidden);
    }

    get showCartTotal() {
        return !this.isEmpty && !this.pricesHidden;
    }

    get cartTotal() {
        return this._formatPrice(
            (this.cartItems || []).reduce((sum, item) => {
                const ep = this._effectivePrice(item.unitPrice, item.priceTiers, item.quantity);
                return sum + item.quantity * ep;
            }, 0)
        );
    }

    _effectivePrice(unitPrice, priceTiers, quantity) {
        if (!priceTiers || priceTiers.length === 0) return unitPrice;
        let price = unitPrice;
        for (const tier of priceTiers) {
            if (quantity >= tier.fromQty) price = tier.price;
        }
        return price;
    }

    _formatPrice(value) {
        return Number(value).toLocaleString(resolveNumberLocale(this.language), {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('closecart'));
    }

    handleOverlayClick() {
        this.dispatchEvent(new CustomEvent('closecart'));
    }

    handleQtyChange(event) {
        const productId = event.target.dataset.productId;
        const quantity = parseInt(event.target.value, 10);
        if (quantity > 0) {
            this.dispatchEvent(new CustomEvent('cartitemchanged', {
                detail: { productId, quantity }
            }));
        }
    }

    handleRemove(event) {
        const productId = event.currentTarget.dataset.productId;
        this.dispatchEvent(new CustomEvent('removefromcart', {
            detail: { productId }
        }));
    }

    async handlePlaceOrder() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const cartPayload = (this.cartItems || []).map(item => ({
                productId: item.productId,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            }));
            const orderId = await placeOrder({
                cartJson: JSON.stringify(cartPayload),
                dealerAccountId: this.dealerAccountId,
                omitShippingCost: this.omitShippingCost
            });
            this.dispatchEvent(new CustomEvent('orderplaced', {
                detail: { orderId }
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || this.shopLabels.DealerShop_GenericError;
        } finally {
            this.isLoading = false;
        }
    }
}
