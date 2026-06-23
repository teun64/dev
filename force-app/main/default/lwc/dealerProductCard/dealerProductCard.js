import { LightningElement, api } from 'lwc';

export default class DealerProductCard extends LightningElement {
    @api product;

    get displayName() {
        return this.product?.displayName || this.product?.name || '';
    }

    get formattedPrice() {
        if (this.product?.unitPrice == null) return '';
        const formatted = Number(this.product.unitPrice).toLocaleString('nl-NL', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
        return `€ ${formatted}`;
    }

    handleClick() {
        this.dispatchEvent(
            new CustomEvent('productselect', {
                detail: { productId: this.product?.id },
                bubbles: true,
                composed: true
            })
        );
    }
}
