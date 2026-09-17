import { LightningElement, api } from 'lwc';

export default class DealerOrderConfirmation extends LightningElement {
    @api orderId;
    @api shopLabels = {};

    handleBackToShop() {
        this.dispatchEvent(new CustomEvent('backtoshop'));
    }
}
