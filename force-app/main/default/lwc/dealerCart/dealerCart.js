import { LightningElement, api, track, wire } from 'lwc';
import placeOrder from '@salesforce/apex/Ctrl_DealerShop.placeOrder';
import getShippingInfo from '@salesforce/apex/Ctrl_DealerShop.getShippingInfo';

export default class DealerCart extends LightningElement {
    @api cartItems = [];
    @api dealerAccountId = null;

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

    get showShippingRemark() {
        return !!this.shippingInfo?.configured && !this.omitShippingCost;
    }

    get shippingRemarkText() {
        if (!this.shippingInfo?.configured) return '';
        const currency = this.shippingInfo.currencyIsoCode === 'GBP' ? '£' : '€';
        if (this.shippingInfo.method === 'Fixed') {
            const fee = this.shippingInfo.feeAmount != null ? this._formatPrice(this.shippingInfo.feeAmount) : null;
            const threshold = this._formatPrice(this.shippingInfo.freeThreshold);
            return fee != null
                ? `Bij bestellingen onder ${currency} ${threshold} worden verzendkosten van ${currency} ${fee} in rekening gebracht.`
                : `Bij bestellingen onder ${currency} ${threshold} worden verzendkosten in rekening gebracht.`;
        }
        if (this.shippingInfo.method === 'Weight_Based') {
            return 'Verzendkosten worden berekend op basis van gewicht en afmetingen van het pakket.';
        }
        return '';
    }

    get omitShippingRemarkText() {
        return 'Shipping costs will not be added to this order.';
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
        return Number(value).toFixed(2);
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
            this.errorMessage = error?.body?.message || 'Er is een fout opgetreden. Probeer het opnieuw.';
        } finally {
            this.isLoading = false;
        }
    }
}
