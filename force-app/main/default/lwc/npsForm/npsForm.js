import { LightningElement, api, track } from 'lwc';

export default class NpsForm extends LightningElement {
    @api defaultScore = -1;
    @api selectedScore = -1;

    @track _selected = -1;

    connectedCallback() {
        const def = Number(this.defaultScore);
        if (!isNaN(def) && def >= 0 && def <= 10) {
            this._selected = def;
            this.selectedScore = def;
        }
    }

    get scoreButtons() {
        return Array.from({ length: 11 }, (_, i) => ({
            value: i,
            label: String(i),
            cssClass: this._buildCss(i)
        }));
    }

    _buildCss(i) {
        const range = i <= 6 ? 'nps-btn_detractor' : i <= 8 ? 'nps-btn_passive' : 'nps-btn_promoter';
        const active = this._selected === i ? ' nps-btn_selected' : '';
        return `nps-btn ${range}${active}`;
    }

    handleScoreClick(evt) {
        const val = Number(evt.currentTarget.dataset.value);
        this._selected = val;
        this.selectedScore = val;
    }
}
