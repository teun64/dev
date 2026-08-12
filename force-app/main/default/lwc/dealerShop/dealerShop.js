import { LightningElement, track } from 'lwc';
import BRANDING_URL               from '@salesforce/resourceUrl/Branding';
import getBrandConfig              from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import { getCart, saveCart, clearCart } from 'c/dealerCartStorage';

const VIEW_GRID         = 'grid';
const VIEW_DETAIL       = 'detail';
const VIEW_CONFIRMATION = 'confirmation';

export default class DealerShop extends LightningElement {

    @track currentView       = VIEW_GRID;
    @track selectedProductId = null;
    @track cartItems         = [];
    @track cartOpen          = false;
    @track activeCategory    = '';
    @track activePage        = 1;
    @track _brandTheme       = null;
    @track orderId           = null;

    connectedCallback() {
        getBrandConfig()
            .then(config => { this._brandTheme = config; })
            .catch(() => {});

        this.cartItems = getCart();
        if (typeof window !== 'undefined') {
            const params = new URLSearchParams(window.location.search);
            if (params.get('openCart') === '1') this.cartOpen = true;
        }
    }

    get isGridView()         { return this.currentView === VIEW_GRID; }
    get isDetailView()       { return this.currentView === VIEW_DETAIL; }
    get isConfirmationView() { return this.currentView === VIEW_CONFIRMATION; }

    get cartCount() {
        const total = this.cartItems.reduce((sum, item) => sum + (item.quantity || 1), 0);
        return total > 0 ? total : null;
    }

    get brandStyle() {
        const primary = this._brandTheme?.primaryColor || '#ff0000';
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
        this.activePage     = 1;
        this.currentView    = VIEW_GRID;
    }

    handleGridPageChange(event) {
        this.activePage = event.detail.page;
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
        saveCart(this.cartItems);
    }

    handleRemoveFromCart(event) {
        const productId  = event.detail.productId;
        this.cartItems   = this.cartItems.filter(i => i.productId !== productId);
        saveCart(this.cartItems);
    }

    handleCartItemChanged(event) {
        const { productId, quantity } = event.detail;
        this.cartItems = this.cartItems.map(i =>
            i.productId === productId ? { ...i, quantity } : i
        );
        saveCart(this.cartItems);
    }

    handleOpenCart() {
        this.cartOpen = true;
    }

    handleCloseCart() {
        this.cartOpen = false;
    }

    handleOrderPlaced(event) {
        this.orderId     = event.detail.orderId;
        this.cartItems   = [];
        this.cartOpen    = false;
        this.currentView = VIEW_CONFIRMATION;
        clearCart();
    }

    handleBackToShop() {
        this.currentView       = VIEW_GRID;
        this.selectedProductId = null;
    }
}