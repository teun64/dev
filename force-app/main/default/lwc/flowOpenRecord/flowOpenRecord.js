import { LightningElement, api, wire } from 'lwc';
import { EnclosingTabId, openSubtab } from 'lightning/platformWorkspaceApi';

export default class FlowOpenRecord extends LightningElement {
    @api recordId;
    @api shouldOpen;
    @api objectApiName = 'Opportunity';

    // Guard against the wire handler firing more than once
    _opened = false;

    @wire(EnclosingTabId)
    wiredTabId(result) {
        if (this._opened || !this.shouldOpen || !this.recordId) return;

        // In a standard (non-console) app the adapter may call back with null
        // instead of { data, error } — treat that as "not a console".
        if (result === null || result === undefined) {
            this._opened = true;
            window.open(
                `/lightning/r/${this.objectApiName}/${this.recordId}/view`,
                '_blank'
            );
            return;
        }

        const { data, error } = result;

        // Wait until the adapter resolves (both undefined means still pending).
        if (data === undefined && !error) return;

        this._opened = true;

        if (data && !error) {
            // Console app: open as a subtab of the current workspace tab so
            // omni-channel presence is not disrupted by a full navigation.
            openSubtab(data, { recordId: this.recordId, focus: true })
                .catch(e => console.error('[flowOpenRecord] openSubtab failed', e));
        } else {
            // Standard app (or fallback): open in a new browser tab.
            window.open(
                `/lightning/r/${this.objectApiName}/${this.recordId}/view`,
                '_blank'
            );
        }
    }
}
