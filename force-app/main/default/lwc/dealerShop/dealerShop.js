import { LightningElement, track } from 'lwc';
import BRANDING_URL               from '@salesforce/resourceUrl/Branding';
import getBrandConfig              from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';

const VIEW_GRID         = 'grid';
const VIEW_DETAIL       = 'detail';
const VIEW_CONFIRMATION = 'confirmation';

export default class DealerShop extends LightningElement {

    @track currentView       = VIEW_GRID;
    @track selectedProductId = null;
    @track cartItems         = [];
    @track cartOpen          = false;
    @track activeCategory    = '';
    @track _brandTheme       = null;

    connectedCallback() {
        getBrandConfig()
            .then(config => { this._brandTheme = config; })
            .catch(() => {});
    }

    get isGridView()         { return this.currentView === VIEW_GRID; }
    get isDetailView()       { return this.currentView === VIEW_DETAIL; }
    get isConfirmationView() { return this.currentView === VIEW_CONFIRMATION; }

    get cartCount() {
        const total = this.cartItems.reduce((sum, item) => sum + (item.quantity || 1), 0);
        return total > 0 ? total : null;
    }

    get brandStyle() {
        const primary = this._brandTheme?.primaryColor || '#cc0000';
        const accent  = this._brandTheme?.accentColor  || '#fdf0f0';
        return `--brand-primary: ${primary}; --brand-accent: ${accent}`;
    }

    get logoUrl() {
        if (this._brandTheme?.logoPath) {
            return `${BRANDING_URL}/${this._brandTheme.logoPath}`;
        }
        return `${BRANDING_URL}/2024/img/mi-logo-black-black-rgb.png`;
    }

    handleCategoryChange(event) {
        this.activeCategory = event.detail.category;
        this.currentView    = VIEW_GRID;
    }

    handleProductSelect(event) {
        this.selectedProductId = event.detail.productId;
        this.currentView       = VIEW_DETAIL;
    }

    handleAddToCart(event) {
        const incoming = event.detail;
        const existing = this.cartItems.find(i => i.productId === incoming.productId);
        if (existing) {
            this.cartItems = this.cartItems.map(i =>
                i.productId === incoming.productId
                    ? { ...i, quantity: (i.quantity || 1) + (incoming.quantity || 1) }
                    : i
            );
        } else {
            this.cartItems = [...this.cartItems, { ...incoming, quantity: incoming.quantity || 1 }];
        }
        this.cartOpen = true;
    }

    handleRemoveFromCart(event) {
        const productId  = event.detail.productId;
        this.cartItems   = this.cartItems.filter(i => i.productId !== productId);
    }

    handleCartItemChanged(event) {
        const { productId, quantity } = event.detail;
        this.cartItems = this.cartItems.map(i =>
            i.productId === productId ? { ...i, quantity } : i
        );
    }

    handleOpenCart() {
        this.cartOpen = true;
    }

    handleCloseCart() {
        this.cartOpen = false;
    }

    handleOrderPlaced() {
        this.cartItems   = [];
        this.cartOpen    = false;
        this.currentView = VIEW_CONFIRMATION;
    }

    handleBackToShop() {
        this.currentView       = VIEW_GRID;
        this.selectedProductId = null;
    }
}
