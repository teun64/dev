import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference }         from 'lightning/navigation';

export default class HubHeader extends LightningElement {
    @track _brand = 'M';

    connectedCallback() {
        try {
            const b = new URLSearchParams(window.location.search).get('brand');
            if (b) this._brand = b;
        } catch (_) {}
    }

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const b = ref?.state?.brand || ref?.state?.c__brand;
        if (b) this._brand = b;
    }

    get isBrandE() { return this._brand === 'E'; }
    get isBrandT() { return this._brand === 'T'; }
}
