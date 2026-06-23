import { LightningElement, api, track } from 'lwc';
import getProducts from '@salesforce/apex/Ctrl_DealerShop.getProducts';

const PAGE_SIZE = 12;

export default class DealerProductGrid extends LightningElement {
    @api
    get category() {
        return this._category;
    }
    set category(value) {
        this._category = value || 'All';
        this._currentPage = 1;
        this.loadProducts();
    }

    @track products = [];
    @track isLoading = false;
    @track _currentPage = 1;
    @track _total = 0;

    _category = 'All';

    connectedCallback() {
        this.loadProducts();
    }

    loadProducts() {
        this.isLoading = true;
        getProducts({
            category: this._category,
            pageNum: this._currentPage,
            pageSize: PAGE_SIZE
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
        }
    }

    handleNext() {
        if (!this.isNextDisabled) {
            this._currentPage += 1;
            this.loadProducts();
        }
    }

    handleProductSelect(event) {
        this.dispatchEvent(
            new CustomEvent('productselect', {
                detail: event.detail,
                bubbles: true
            })
        );
    }
}
