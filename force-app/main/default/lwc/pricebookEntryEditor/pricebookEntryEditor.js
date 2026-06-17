import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import updateListPrice from '@salesforce/apex/Ctrl_PricebookEntryEditor.updateListPrice';

const FIELDS = [
    'PricebookEntry.UnitPrice',
    'PricebookEntry.CurrencyIsoCode'
];

export default class PricebookEntryEditor extends LightningElement {
    @api recordId;

    oldPrice;
    newPrice;
    currencyIsoCode;
    
    @track isOpen = true;
    @track showSuccess = false;
    @track errorMessage;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredPbe({ data, error }) {
        if (data) {
            this.oldPrice = data.fields.UnitPrice.value;
            this.newPrice = this.oldPrice;
            this.currencyIsoCode = data.fields.CurrencyIsoCode.value;
        }
        if (error) {
            // optional: handle error
            console.error(error);
        }
    }

    toggleSection() {
        this.isOpen = !this.isOpen;
        this.template
            .querySelector('.slds-section')
            .classList.toggle('slds-is-open', this.isOpen);
    }

    handleChange(event) {
        const value = Number(event.target.value);

        if (value < 0) {
            event.target.setCustomValidity('Price cannot be negative');
        } else {
            event.target.setCustomValidity('');
        }
        
        this.newPrice = value;
        event.target.reportValidity();
    }

    get isUpdateDisabled() {
        return (
            this.newPrice === null ||
            this.newPrice < 0 ||
            this.newPrice === this.oldPrice
        );
    }

    get newLabel() {
        return this.currencyIsoCode ? `New Price (${this.currencyIsoCode})`: 'New Price';
    }

    handleUpdate() {
        updateListPrice({
            pricebookEntryId: this.recordId,
            newPrice: this.newPrice
        })
        .then(() => {
            // Sync prices → disables button
            this.oldPrice = Number(this.newPrice);
            this.newPrice = this.oldPrice;

            // Inline success
            this.showSuccess = true;

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.showSuccess = false;
            }, 3000);
        })
        .catch(error => {
            this.errorMessage = this.extractErrorMessage(error);
            console.error(error);
        });
    }

    extractErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
            
        return 'An unexpected error occurred, please try again later.';
    }
}
