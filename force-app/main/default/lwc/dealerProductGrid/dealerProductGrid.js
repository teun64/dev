import { LightningElement, api, track } from 'lwc';
import getProducts from '@salesforce/apex/Ctrl_DealerShop.getProducts';

const PAGE_SIZE = 12;

export default class DealerProductGrid extends LightningElement {
    @api initialPage = 1;

    @api
    get category() {
        return this._category;
    }
    set category(value) {
        const newValue = value != null ? value : '';
        const changed = this._connected && newValue !== this._category;
        this._category = newValue;
        if (changed) {
            this._currentPage = 1;
            this.notifyPageChange();
        }
        if (this._connected) {
            this.loadProducts();
        }
    }

    @api
    get searchTerm() {
        return this._searchTerm;
    }
    set searchTerm(value) {
        const newValue = value != null ? value : '';
        const changed = this._connected && newValue !== this._searchTerm;
        this._searchTerm = newValue;
        if (changed) {
            this._currentPage = 1;
            this.notifyPageChange();
        }
        if (this._connected) {
            this.loadProducts();
        }
    }

    @track products = [];
    @track isLoading = false;
    @track _currentPage = 1;
    @track _total = 0;

    _category = '';
    _searchTerm = '';
    _connected = false;

    connectedCallback() {
        this._connected = true;
        this._currentPage = this.initialPage > 0 ? this.initialPage : 1;
        this.loadProducts();
    }

    loadProducts() {
        this.isLoading = true;
        getProducts({
            category: this._category,
            pageNum: this._currentPage,
            pageSize: PAGE_SIZE,
            searchTerm: this._searchTerm
        })
            .then((result) => {
                this.products = result.products || [];
                this._total = result.total || 0;
            })
            .catch(() => {
                this.products = [];
                this._total = 0;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get isEmpty() {
        return !this.products || this.products.length === 0;
    }

    get currentPage() {
        return this._currentPage;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this._total / PAGE_SIZE));
    }

    get isPrevDisabled() {
        return this._currentPage <= 1;
    }

    get isNextDisabled() {
        return this._currentPage >= this.totalPages;
    }

    handlePrev() {
        if (!this.isPrevDisabled) {
            this._currentPage -= 1;
            this.loadProducts();
            this.notifyPageChange();
        }
    }

    handleNext() {
        if (!this.isNextDisabled) {
            this._currentPage += 1;
            this.loadProducts();
            this.notifyPageChange();
        }
    }

    handlePageInputChange(event) {
        this.goToPage(event.target, event.target.value);
    }

    handlePageInputKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.goToPage(event.target, event.target.value);
            event.target.blur();
        }
    }

    goToPage(inputEl, rawValue) {
        let parsed = parseInt(rawValue, 10);
        if (isNaN(parsed)) {
            parsed = this._currentPage;
        }
        const clamped = Math.min(Math.max(parsed, 1), this.totalPages);
        if (clamped !== this._currentPage) {
            this._currentPage = clamped;
            this.loadProducts();
            this.notifyPageChange();
        } else if (inputEl) {
            inputEl.value = clamped;
        }
    }

    notifyPageChange() {
        this.dispatchEvent(
            new CustomEvent('pagechange', {
                detail: { page: this._currentPage }
            })
        );
    }

    handleProductSelect(event) {
        this.dispatchEvent(
            new CustomEvent('productselect', {
                detail: event.detail,
                bubbles: true
            })
        );
    }

    handleAddToCart(event) {
        event.stopPropagation();
        this.dispatchEvent(
            new CustomEvent('addtocart', {
                detail: event.detail,
                bubbles: true,
                composed: true
            })
        );
    }
}