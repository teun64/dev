import { LightningElement, api, track, wire } from 'lwc';
import placeOrder from '@salesforce/apex/Ctrl_DealerShop.placeOrder';
import getShippingInfo from '@salesforce/apex/Ctrl_DealerShop.getShippingInfo';
import getOrderOptionsData from '@salesforce/apex/Ctrl_DealerShop.getOrderOptions';
import { getOrderOptions, saveOrderOptions } from 'c/dealerCartStorage';
import { resolveNumberLocale } from 'c/dealerLanguage';

const NEW_ADDRESS = 'new';

export default class DealerCart extends LightningElement {
    @api cartItems = [];
    @api dealerAccountId = null;
    @api shopLabels = {};
    @api language = 'en';

    @track isLoading = false;
    @track errorMessage = null;
    @track shippingInfo = null;
    // Internal-only (dealerAccountId set) - lets a Salesforce user waive the shipping fee for this
    // specific order. Defaults off; a portal dealer never sees this control and the server ignores
    // the flag entirely when dealerAccountId is null, regardless of what a client sends.
    @track omitShippingCost = false;

    // Order options panel: customer reference (blank = the order number, filled in server-side)
    // and the delivery address - the account's shipping address, or a different one picked from
    // earlier orders or entered new. Kept in sessionStorage so it survives page navigation.
    @track optionsOpen = false;
    @track customerReference = '';
    @track useDifferentAddress = false;
    @track selectedAddress = NEW_ADDRESS;
    @track newAddress = { street: '', postalCode: '', city: '', countryCode: '' };
    @track orderOptionsData = null;
    // Contact person on the order (Sales_Contact__c, the signer): default the account's Main role contact.
    @track selectedContactId = '';

    connectedCallback() {
        const stored = getOrderOptions(this.dealerAccountId);
        if (stored) {
            this.customerReference   = stored.customerReference || '';
            this.useDifferentAddress = !!stored.useDifferentShippingAddress;
            this.selectedContactId   = stored.contactId || '';
            if (stored.shippingAddress) this.newAddress = { ...this.newAddress, ...stored.shippingAddress };
            // A reorder hands over its options - show them instead of hiding them behind the toggle.
            this.optionsOpen = !!stored.openOptions;
            if (stored.openOptions) saveOrderOptions({ ...stored, openOptions: false }, this.dealerAccountId);
        }
        getOrderOptionsData({ dealerAccountId: this.dealerAccountId })
            .then((data) => {
                this.orderOptionsData = data;
                this._matchStoredAddress();
                this._matchStoredContact();
            })
            .catch(() => {
                this.orderOptionsData = { previousAddresses: [], countries: [], contacts: [] };
            });
    }

    // A stored address that equals one of the earlier addresses selects that one; anything else
    // stays in the new-address form, prefilled.
    _matchStoredAddress() {
        const previous = this.orderOptionsData?.previousAddresses || [];
        const index = previous.findIndex((a) => this._addressKey(a) === this._addressKey(this.newAddress));
        if (index >= 0) {
            this.selectedAddress = String(index);
        } else {
            this.selectedAddress = NEW_ADDRESS;
            if (!this.newAddress.countryCode) {
                this.newAddress = { ...this.newAddress, countryCode: this.orderOptionsData?.defaultAddress?.countryCode || '' };
            }
        }
    }

    // A stored contact that is no longer on the account's list falls back to the default.
    _matchStoredContact() {
        const contacts = this.orderOptionsData?.contacts || [];
        if (!contacts.some((c) => c.value === this.selectedContactId)) {
            this.selectedContactId = this.orderOptionsData?.defaultContactId || '';
        }
    }

    get hasContacts() {
        return (this.orderOptionsData?.contacts || []).length > 0;
    }

    get contactChoices() {
        return (this.orderOptionsData?.contacts || []).map((c) => ({
            ...c,
            selected: c.value === this.selectedContactId
        }));
    }

    handleContactSelect(event) {
        this.selectedContactId = event.target.value;
        this._persistOptions();
    }

    _addressKey(a) {
        if (!a) return '';
        return [a.street, a.postalCode, a.city, a.countryCode]
            .map((v) => (v || '').toLowerCase().replace(/\s/g, ''))
            .join('|');
    }

    _countryLabel(code) {
        const match = (this.orderOptionsData?.countries || []).find((c) => c.value === code);
        return match ? match.label : (code || '');
    }

    _formatAddress(a) {
        if (!a) return '';
        const place = [a.postalCode, a.city].filter((v) => v).join(' ');
        return [a.street, place, this._countryLabel(a.countryCode)].filter((v) => v).join(', ');
    }

    get optionsOpenString() {
        return String(this.optionsOpen);
    }

    get optionsBodyClass() {
        return 'order-options-body' + (this.optionsOpen ? ' order-options-body--open' : '');
    }

    get chevronClass() {
        return 'order-options-chevron' + (this.optionsOpen ? ' order-options-chevron--open' : '');
    }

    // One-line recap on the collapsed toggle, so the dealer sees what will be used without opening it.
    get optionsSummary() {
        const parts = [];
        if (this.customerReference) parts.push(this.customerReference);
        if (this.selectedContactId && this.selectedContactId !== this.orderOptionsData?.defaultContactId) {
            const contact = (this.orderOptionsData?.contacts || []).find((c) => c.value === this.selectedContactId);
            if (contact) parts.push(contact.label);
        }
        if (this.useDifferentAddress) {
            const address = this._formatAddress(this.effectiveShippingAddress);
            if (address) parts.push(address);
        }
        return parts.join(' · ');
    }

    get defaultAddressText() {
        if (!this.orderOptionsData) return '';
        return this.orderOptionsData.defaultAddress
            ? this._formatAddress(this.orderOptionsData.defaultAddress)
            : this.shopLabels.DealerShop_NoDefaultAddress;
    }

    get hasPreviousAddresses() {
        return (this.orderOptionsData?.previousAddresses || []).length > 0;
    }

    get isNewAddress() {
        return this.selectedAddress === NEW_ADDRESS;
    }

    get addressChoices() {
        const previous = (this.orderOptionsData?.previousAddresses || []).map((a, i) => ({
            value: String(i),
            label: this._formatAddress(a),
            selected: this.selectedAddress === String(i)
        }));
        return [
            ...previous,
            { value: NEW_ADDRESS, label: this.shopLabels.DealerShop_NewAddress, selected: this.isNewAddress }
        ];
    }

    get countryChoices() {
        const countries = (this.orderOptionsData?.countries || []).map((c) => ({
            ...c,
            selected: c.value === this.newAddress.countryCode
        }));
        return [{ value: '', label: this.shopLabels.DealerShop_Country, selected: !this.newAddress.countryCode }, ...countries];
    }

    get effectiveShippingAddress() {
        if (!this.useDifferentAddress) return null;
        if (this.isNewAddress) return this.newAddress;
        return (this.orderOptionsData?.previousAddresses || [])[Number(this.selectedAddress)] || null;
    }

    _persistOptions() {
        saveOrderOptions({
            customerReference: this.customerReference,
            useDifferentShippingAddress: this.useDifferentAddress,
            shippingAddress: this.effectiveShippingAddress,
            contactId: this.selectedContactId
        }, this.dealerAccountId);
    }

    handleToggleOptions() {
        this.optionsOpen = !this.optionsOpen;
    }

    handleReferenceInput(event) {
        this.customerReference = event.target.value;
        this._persistOptions();
    }

    handleUseDifferentChange(event) {
        this.useDifferentAddress = event.target.checked;
        this._persistOptions();
    }

    handleAddressSelect(event) {
        this.selectedAddress = event.target.value;
        this._persistOptions();
    }

    handleAddressInput(event) {
        const field = event.target.dataset.field;
        this.newAddress = { ...this.newAddress, [field]: event.target.value };
        this._persistOptions();
    }

    _isAddressComplete(a) {
        return !!(a && a.street && a.street.trim() && a.postalCode && a.postalCode.trim()
            && a.city && a.city.trim() && a.countryCode);
    }

    @wire(getShippingInfo, { dealerAccountId: '$dealerAccountId' })
    wiredShippingInfo({ data }) {
        if (data) this.shippingInfo = data;
    }

    // Only an internal user (Account-embedded quick action) may waive shipping - never a portal dealer.
    get isInternalUser() {
        return !!this.dealerAccountId;
    }

    get currencySymbol() {
        return this.shippingInfo?.currencyIsoCode === 'GBP' ? '£' : '€';
    }

    get showShippingRemark() {
        return !!this.shippingInfo?.configured && !this.omitShippingCost;
    }

    get shippingRemarkText() {
        if (!this.shippingInfo?.configured) return '';
        const currency = this.currencySymbol;
        if (this.shippingInfo.method === 'Fixed') {
            const threshold = `${currency} ${this._formatPrice(this.shippingInfo.freeThreshold)}`;
            if (this.shippingInfo.feeAmount != null) {
                const fee = `${currency} ${this._formatPrice(this.shippingInfo.feeAmount)}`;
                return this.shopLabels.DealerShop_ShippingFixedWithFee
                    .replace('{0}', threshold)
                    .replace('{1}', fee);
            }
            return this.shopLabels.DealerShop_ShippingFixedNoFee.replace('{0}', threshold);
        }
        if (this.shippingInfo.method === 'Weight_Based') {
            return this.shopLabels.DealerShop_ShippingWeightBased;
        }
        return '';
    }

    get omitShippingRemarkText() {
        return this.shopLabels.DealerShop_ShippingOmitRemark;
    }

    get omitShippingLabelText() {
        return this.shopLabels.DealerShop_ShippingOmitLabel;
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
        return Number(value).toLocaleString(resolveNumberLocale(this.language), {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
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
        this.errorMessage = null;
        if (this.useDifferentAddress && !this._isAddressComplete(this.effectiveShippingAddress)) {
            this.optionsOpen = true;
            this.errorMessage = this.shopLabels.DealerShop_AddressIncomplete;
            return;
        }
        this.isLoading = true;
        try {
            const cartPayload = (this.cartItems || []).map(item => ({
                productId: item.productId,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            }));
            const orderId = await placeOrder({
                cartJson: JSON.stringify(cartPayload),
                dealerAccountId: this.dealerAccountId,
                omitShippingCost: this.omitShippingCost,
                orderOptionsJson: JSON.stringify({
                    customerReference: this.customerReference,
                    useDifferentShippingAddress: this.useDifferentAddress,
                    shippingAddress: this.effectiveShippingAddress,
                    contactId: this.selectedContactId || null
                })
            });
            this.dispatchEvent(new CustomEvent('orderplaced', {
                detail: { orderId }
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || this.shopLabels.DealerShop_GenericError;
        } finally {
            this.isLoading = false;
        }
    }
}
