import { LightningElement, api, track } from 'lwc';

import getPreferences from '@salesforce/apex/Ctrl_CommunicationPreference.getPreferences';
import getPreferencesAdmin from '@salesforce/apex/Ctrl_CommunicationPreference.getPreferencesAdmin';

import savePreferences from '@salesforce/apex/Ctrl_CommunicationPreference.savePreferences';
import savePreferencesAdmin from '@salesforce/apex/Ctrl_CommunicationPreference.savePreferencesAdmin';

export default class CommunicationPreference extends LightningElement {

    @api contactId;
    @api brand;
    @api isAdminMode = false;

    @track preferences = [];
    @track isLoading = true;

    overrideReason = '';

    requestId;
    sessionId;

    connectedCallback() {
        this.initContext();
        this.loadPreferences();
    }

    // =========================
    // Context
    // =========================
    initContext() {
        this.requestId = 'req-' + Date.now();
        this.sessionId = this.getSessionId();
    }

    getSessionId() {
        let sessionId = sessionStorage.getItem('cp_session_id');
        if (!sessionId) {
            sessionId = 'sess-' + Math.random().toString(36).substring(2, 10);
            sessionStorage.setItem('cp_session_id', sessionId);
        }
        return sessionId;
    }

    // =========================
    // Load
    // =========================
    loadPreferences() {
        this.isLoading = true;

        const method = this.isAdminMode ? getPreferencesAdmin : getPreferences;

        method({
            contactId: this.contactId,
            brand: this.brand
        })
        .then(result => {
            this.preferences = result.map(p => ({
                ...p,
                isChanged: false
            }));
        })
        .catch(error => {
            console.error('Error loading preferences', error);
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // =========================
    // Toggle
    // =========================
    handleToggle(event) {
        const prefId = event.target.dataset.id;
        const checked = event.target.checked;

        this.preferences = this.preferences.map(p => {
            if (p.Id === prefId) {
                return {
                    ...p,
                    Is_Enabled__c: checked,
                    isChanged: true
                };
            }
            return p;
        });
    }

    // =========================
    // Override reason (admin)
    // =========================
    handleReasonChange(event) {
        this.overrideReason = event.target.value;
    }

    // =========================
    // Save
    // =========================
    handleSave() {

        const changed = this.preferences.filter(p => p.isChanged);
        if (changed.length === 0) return;

        const inputs = changed.map(p => ({
            preferenceId: p.Id,
            isEnabled: p.Is_Enabled__c
        }));

        this.isLoading = true;

        const context = {
            requestId: this.requestId,
            sessionId: this.sessionId
        };

        const method = this.isAdminMode ? savePreferencesAdmin : savePreferences;

        const params = this.isAdminMode
            ? {
                contactId: this.contactId,
                brand: this.brand,
                inputs: inputs,
                overrideReason: this.overrideReason,
                context: context
            }
            : {
                contactId: this.contactId,
                brand: this.brand,
                inputs: inputs,
                context: context
            };

        method(params)
        .then(() => {
            this.resetChanges();
            this.overrideReason = '';
        })
        .catch(error => {
            console.error('Error saving preferences', error);
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    resetChanges() {
        this.preferences = this.preferences.map(p => ({
            ...p,
            isChanged: false
        }));
    }

    // =========================
    // UI helpers
    // =========================
    get hasChanges() {
        return this.preferences.some(p => p.isChanged);
    }

    get isSaveDisabled() {
        if (!this.hasChanges) return true;
        if (this.isAdminMode && !this.overrideReason) return true;
        return this.isLoading;
    }
}