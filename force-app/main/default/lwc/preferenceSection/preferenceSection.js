import { LightningElement, api } from 'lwc';

export default class PreferenceSection extends LightningElement {
    @api sectionKey;
    @api label;
    @api description;
    @api iconName = 'utility:check';
    @api brandLabel;
    @api isEssential = false;
    @api items = [];

    get allChecked() {
        const optIn = this.items.filter(i => !i.isEssential);
        return optIn.length > 0 && optIn.every(i => i.checked);
    }
    get toggleIcon()  { return this.allChecked ? 'utility:close' : 'utility:check'; }
    get toggleTitle() { return this.allChecked ? 'Deselect all in section' : 'Select all in section'; }

    handleCheckboxChange(event) {
        const compositeKey = event.target.dataset.key;
        const checked      = event.target.checked;
        this.dispatchEvent(new CustomEvent('preferencechange', {
            detail: { compositeKey, checked },
            bubbles: true,
            composed: true
        }));
    }

    toggleSection() {
        const newVal = !this.allChecked;
        this.items.filter(i => !i.isEssential).forEach(item => {
            this.dispatchEvent(new CustomEvent('preferencechange', {
                detail: { compositeKey: item.compositeKey, checked: newVal },
                bubbles: true,
                composed: true
            }));
        });
    }
}
