import { LightningElement, api, track } from 'lwc';
import getBrandConfig              from '@salesforce/apex/Ctrl_DealerPortal.getBrandConfig';
import getShopLabels                from '@salesforce/apex/Ctrl_DealerShop.getShopLabels';
import { getCart, saveCart, clearCart } from 'c/dealerCartStorage';
import { resolveLanguageFromHostname } from 'c/dealerLanguage';

const VIEW_GRID         = 'grid';
const VIEW_DETAIL       = 'detail';
const VIEW_CONFIRMATION = 'confirmation';

// English defaults - shown until getShopLabels() resolves, and the source of truth for what
// getShopLabels() must return (see the label list on Ctrl_DealerShop.getShopLabels()). Keeps
// every child from ever rendering blank/undefined text on first paint.
const DEFAULT_LABELS = {
    DealerShop_Cart: 'Cart',
    DealerShop_CartCloseAriaLabel: 'Close cart',
    DealerShop_CartEmpty: 'Your cart is empty.',
    DealerShop_SearchPlaceholder: 'Search by product code or name...',
    DealerShop_AllProducts: 'All products',
    DealerShop_MyFavorites: 'My favorites',
    DealerShop_CategoriesAriaLabel: 'Product categories',
    DealerShop_Loading: 'Loading...',
    DealerShop_NoProductsFound: 'No products found',
    DealerShop_Previous: 'Previous',
    DealerShop_Page: 'Page',
    DealerShop_Of: 'of',
    DealerShop_Next: 'Next',
    DealerShop_NoImage: 'No image',
    DealerShop_NoImageAvailable: 'No image available',
    DealerShop_AddToCartShort: 'Add to cart',
    DealerShop_AddToCart: 'Add to cart',
    DealerShop_FromQtyAbbrev: 'from',
    DealerShop_UnitsAbbrev: 'units',
    DealerShop_RemoveFromFavorites: 'Remove from favorites',
    DealerShop_MarkAsFavorite: 'Mark as favorite',
    DealerShop_FavoriteActive: '♥ Favorite',
    DealerShop_FavoriteInactive: '♡ Mark as favorite',
    DealerShop_BackToOverview: 'Back to overview',
    DealerShop_PricePerUnit: 'Price per unit:',
    DealerShop_VolumeDiscounts: 'Volume discounts',
    DealerShop_FromQuantity: 'From quantity',
    DealerShop_Quantity: 'Quantity',
    DealerShop_TotalPrice: 'Total price:',
    DealerShop_ProductDescription: 'Product description',
    DealerShop_ProductLoadError: 'An error occurred while loading the product.',
    DealerShop_GenericError: 'An error occurred. Please try again.',
    DealerShop_ShippingOmitLabel: 'Omit shipping costs for this order (internal use only)',
    DealerShop_ShippingOmitRemark: 'Shipping costs will not be added to this order.',
    DealerShop_ShippingFixedWithFee: 'Orders under {0} incur a shipping fee of {1}.',
    DealerShop_ShippingFixedNoFee: 'Orders under {0} incur a shipping fee.',
    DealerShop_ShippingWeightBased: 'Shipping costs are calculated based on the weight and dimensions of the package.',
    DealerShop_Total: 'Total',
    DealerShop_PlaceOrder: 'Place order',
    DealerShop_RemoveItemAriaLabel: 'Remove item',
    DealerShop_OrderConfirmedTitle: 'Thank you for your order!',
    DealerShop_OrderConfirmedSubtitle: 'Your order has been placed successfully.',
    DealerShop_OrderNumberLabel: 'Order number:',
    DealerShop_BackToShop: 'Back to shop',
    DealerShop_SuccessAriaLabel: 'Success'
};

export default class DealerShop extends LightningElement {

    // Populated automatically when placed on an Account record page / quick action
    // (lightning__RecordPage, lightning__RecordAction); stays undefined for the Experience
    // Cloud usage, where dealer context is instead resolved from the logged-in portal user.
    @api recordId;

    @track currentView       = VIEW_GRID;
    @track selectedProductId = null;
    @track cartItems         = [];
    @track cartOpen          = false;
    @track activeCategory    = '';
    @track activePage        = 1;
    @track searchTerm        = '';
    @track _brandTheme       = null;
    @track orderId           = null;
    @track shopLabels        = DEFAULT_LABELS;

    language = resolveLanguageFromHostname();
    _searchDebounce;

    // Normalizes recordId to an explicit null (never undefined) before it reaches any child's
    // @wire - an undefined reactive wire param never fires at all, which would silently break
    // the Experience Cloud usage where recordId is never set by the framework.
    get dealerAccountId() {
        return this.recordId || null;
    }

    connectedCallback() {
        getBrandConfig()
            .then(config => { this._brandTheme = config; })
            .catch(() => {});

        getShopLabels({ language: this.language })
            .then(labels => { this.shopLabels = { ...DEFAULT_LABELS, ...labels }; })
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

    handleSearchInput(event) {
        const value = event.target.value;
        clearTimeout(this._searchDebounce);
        this._searchDebounce = setTimeout(() => {
            this.searchTerm  = value;
            this.activePage  = 1;
            this.currentView = VIEW_GRID;
        }, 300);
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