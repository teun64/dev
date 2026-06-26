import { LightningElement, api } from 'lwc';

export default class DealerProductCard extends LightningElement {
    @api product;

    get displayName() {
        return this.product?.displayName || this.product?.name || '';
    }

    get formattedPrice() {
        if (this.product?.unitPrice == null) return '';
        return this._fmt(this.product.unitPrice);
    }

    get hasTiers() {
        return this.product?.priceTiers && this.product.priceTiers.length > 0;
    }

    get enrichedTiers() {
        if (!this.product?.priceTiers) return [];
        return this.product.priceTiers.map((tier, idx) => ({
            key: idx,
            fromQty: tier.fromQty,
            formattedPrice: this._fmt(tier.price)
        }));
    }

    _fmt(price) {
        if (price == null) return '';
        const formatted = Number(price).toLocaleString('nl-NL', {
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

    handleAddToCart(event) {
        event.stopPropagation();
        this.dispatchEvent(
            new CustomEvent('addtocart', {
                detail: {
                    productId: this.product?.id,
                    quantity: 1,
                    unitPrice: this.product?.unitPrice,
                    priceTiers: this.product?.priceTiers || [],
                    productName: this.displayName,
                    imageUrl: this.product?.imageUrl
                },
                bubbles: true,
                composed: true
            })
        );
    }
}
