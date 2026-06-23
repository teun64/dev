import { LightningElement, api, track } from 'lwc';
import placeOrder from '@salesforce/apex/Ctrl_DealerShop.placeOrder';

export default class DealerCart extends LightningElement {
    @api cartItems = [];

    @track isLoading = false;
    @track errorMessage = null;

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
        return (this.cartItems || []).map(item => ({
            ...item,
            lineTotal: this._formatPrice(item.quantity * item.unitPrice)
        }));
    }

    get cartTotal() {
        return this._formatPrice(
            (this.cartItems || []).reduce((sum, item) => sum + item.quantity * item.unitPrice, 0)
        );
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
            const orderId = await placeOrder({ cartJson: JSON.stringify(cartPayload) });
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
