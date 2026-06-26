import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

export default class NpsPage extends LightningElement {
    isReady = false;
    hasError = false;
    errorMessage;
    flowInputs = [];

    _surveyId;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        if (!ref) return;

        const surveyId = ref.state?.survey || ref.state?.c__survey;
        const score    = ref.state?.score   || ref.state?.c__score || '';

        if (!surveyId) {
            this.hasError     = true;
            this.errorMessage = 'Ongeldige link. Gebruik de link uit uw e-mail.';
            return;
        }

        if (surveyId === this._surveyId) return;
        this._surveyId = surveyId;

        this.flowInputs = [
            { name: 'surveyId',   type: 'String', value: surveyId },
            { name: 'inputScore', type: 'String', value: score }
        ];
        this.isReady = true;
    }

    handleStatusChange() {}
}
