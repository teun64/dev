import { LightningElement, api } from 'lwc';

export default class FlowOpenRecord extends LightningElement {
    @api recordId;
    @api shouldOpen;
    @api objectApiName = 'Opportunity';

    connectedCallback() {
        if (this.shouldOpen && this.recordId) {
            window.open(`/lightning/r/${this.objectApiName}/${this.recordId}/view`, '_blank');
        }
    }
}
