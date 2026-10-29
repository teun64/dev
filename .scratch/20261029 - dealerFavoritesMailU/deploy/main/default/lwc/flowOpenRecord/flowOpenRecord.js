import { LightningElement, api, wire } from 'lwc';
import { IsConsoleNavigation, openSubtab, openTab, getAllTabInfo } from 'lightning/platformWorkspaceApi';

export default class FlowOpenRecord extends LightningElement {
    @api objectApiName = 'Opportunity';
    @api parentRecordId;

    _recordId;
    _shouldOpen;
    _opened = false;
    // Latest IsConsoleNavigation wire emission. undefined = wire hasn't fired yet.
    _consoleResult;
    _consoleResultReceived = false;

    // recordId/shouldOpen are exposed via explicit getters/setters (instead of
    // plain @api fields) because the wire adapter can fire before Flow finishes
    // assigning these properties. Each setter re-attempts opening, so whichever
    // lands last - the wire emission or the property assignment - is the one
    // that actually triggers it.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.tryOpen();
    }

    @api
    get shouldOpen() {
        return this._shouldOpen;
    }
    set shouldOpen(value) {
        this._shouldOpen = value;
        this.tryOpen();
    }

    // Note: EnclosingTabId returns a bare null (not {data,error}) when this
    // component runs inside a Quick Action flow modal - the modal is an
    // overlay on top of the console, not part of the tab's own content, so
    // there's no enclosing tab to resolve. IsConsoleNavigation only asks
    // "is this a console app at all" and isn't affected by that.
    @wire(IsConsoleNavigation)
    wiredIsConsole(result) {
        this._consoleResult = result;
        this._consoleResultReceived = true;
        this.tryOpen();
    }

    tryOpen() {
        if (this._opened) {
            return;
        }
        if (!this._shouldOpen || !this._recordId) {
            return;
        }
        if (!this._consoleResultReceived) {
            return;
        }

        const isConsole = this.resolveIsConsole(this._consoleResult);
        if (isConsole === undefined) {
            return;
        }

        this._opened = true;

        // Defer to the next microtask so any remaining properties Flow is
        // still assigning in this same batch (objectApiName, parentRecordId)
        // have landed before we read them.
        Promise.resolve().then(() => {
            if (isConsole) {
                this.openInConsole();
            } else {
                this.openInStandardApp();
            }
        });
    }

    // Normalizes the wire result to true/false, or undefined if still pending.
    resolveIsConsole(result) {
        if (typeof result === 'boolean') {
            return result;
        }
        if (result === null || result === undefined) {
            return false;
        }
        const { data, error } = result;
        if (data === undefined && !error) {
            return undefined; // still pending
        }
        return !!data && !error;
    }

    openInStandardApp() {
        const url = `/lightning/r/${this.objectApiName}/${this._recordId}/view`;
        window.open(url, '_blank');
    }

    async openInConsole() {
        try {
            if (this.parentRecordId) {
                const parentTabId = await this.getOrOpenParentTab();
                await openSubtab(parentTabId, { recordId: this._recordId, focus: true });
            } else {
                await openTab({ recordId: this._recordId, focus: true });
            }
        } catch (e) {
            console.error('[flowOpenRecord] failed to open record in console', e);
            this.openInStandardApp();
        }
    }

    async getOrOpenParentTab() {
        const allTabs = await getAllTabInfo();
        const existingParentTab = allTabs.find(
            (tab) => !tab.isSubtab && tab.recordId === this.parentRecordId
        );
        if (existingParentTab) {
            return existingParentTab.tabId;
        }
        const newTabId = await openTab({ recordId: this.parentRecordId, focus: false });
        return newTabId;
    }
}
