import { LightningElement, api, track } from 'lwc';
import getMandateData from '@salesforce/apex/Ctrl_HubMandate.getMandateData';

export default class StripeMandateView extends LightningElement {
    @api recordId;

    @track mandate;
    @track isLoading = false;

    connectedCallback() {
        this._load();
    }

    async _load() {
        if (!this.recordId) return;
        this.isLoading = true;
        try {
            this.mandate = await getMandateData({ accountId: this.recordId });
        } catch (e) {
            this.mandate = { found: false, errorMessage: e.body?.message ?? e.message };
        } finally {
            this.isLoading = false;
        }
    }

    get hasError() {
        return this.mandate && !this.mandate.found;
    }

    get hasMandate() {
        return this.mandate?.found === true;
    }

    get hasIban() {
        return !!this.mandate?.ibanLast4;
    }

    get statusBadgeClass() {
        const s = this.mandate?.status;
        if (s === 'active')   return 'slds-badge slds-theme_success';
        if (s === 'inactive') return 'slds-badge slds-theme_error';
        return 'slds-badge';
    }

    get acceptedAtFormatted() {
        const epoch = this.mandate?.acceptedAt;
        if (!epoch) return null;
        return new Date(epoch * 1000).toLocaleString();
    }
}
