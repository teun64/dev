import { LightningElement, track } from 'lwc';
import BRANDING_URL               from '@salesforce/resourceUrl/Branding';
import getBrandTheme               from '@salesforce/apex/Ctrl_PreferenceCenter.getBrandTheme';

const VIEW_GRID         = 'grid';
const VIEW_DETAIL       = 'detail';
const VIEW_CONFIRMATION = 'confirmation';

export default class DealerShop extends LightningElement {

    @track currentView       = VIEW_GRID;
    @track selectedProductId = null;
    @track cartItems         = [];
    @track cartOpen          = false;
    @track activeCategory    = 'All';
    @track _brandTheme       = null;

    connectedCallback() {
        getBrandTheme({ brand: 'M' })
            .then(theme => { this._brandTheme = theme; })
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
        const parts = [];
        const primary = this._brandTheme?.primaryColor || '#cc0000';
        const accent  = this._brandTheme?.accentColor  || '#fdf0f0';
        parts.push(`--brand-primary: ${primary}`);
        parts.push(`--brand-accent: ${accent}`);
        parts.push(`--brand-font-url: url('${BRANDING_URL}/2024/fonts')`);
        return parts.join('; ');
    }

    get logoUrl() {
        if (this._brandTheme?.logoStaticResource) {
            return `${BRANDING_URL}/${this._brandTheme.logoStaticResource}`;
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

    handleOpenCart() {
        this.cartOpen = true;
    }

    handleCloseCart() {
        this.cartOpen = false;
    }

    handleOverlayClick() {
        this.cartOpen = false;
    }

    handleSidebarClick(event) {
        event.stopPropagation();
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
