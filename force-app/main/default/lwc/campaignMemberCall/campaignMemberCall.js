import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getMember from '@salesforce/apex/Ctrl_CampaignMemberCall.getMember';
import answer from '@salesforce/apex/Ctrl_CampaignMemberCall.answer';

const OFFER = 'Offer';
const NOT_NOW = 'Not now';
const NOT_INTERESTED = 'Not interested';

export default class CampaignMemberCall extends NavigationMixin(LightningElement) {
    @api recordId;
    data;
    error;
    loading = true;
    saving = false;
    showNotNow = false;
    quarter;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getMember({ memberId: this.recordId });
            this.quarter = this.data?.quarters?.[0]?.value;
            this.error = this.data ? undefined : 'This campaign member no longer exists: it moved to another sub-campaign.';
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'The campaign member could not be loaded.';
        } finally {
            this.loading = false;
        }
    }

    get disabled() {
        return this.saving || !this.data?.canAnswer;
    }

    get phoneOnly() {
        return this.data?.largeAccount;
    }

    get answered() {
        if (!this.data?.response) return 'No answer yet';
        return this.data.recontactFrom ? `${this.data.response} (from ${this.data.recontactFrom})` : this.data.response;
    }

    openRecord(event) {
        event.preventDefault();
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    handleQuarter(event) {
        this.quarter = event.detail.value;
    }

    toggleNotNow() {
        this.showNotNow = !this.showNotNow;
    }

    async handleOffer() {
        const ok = await LightningConfirm.open({
            label: 'Offer',
            message: `Make an offer for ${this.data.accountName}? An Opportunity is created with you as owner, and the customer gets the confirmation mail.`,
            theme: 'default'
        });
        if (ok) this.save(OFFER, null);
    }

    async handleNotInterested() {
        const ok = await LightningConfirm.open({
            label: 'Not interested',
            message: `Record that ${this.data.accountName} is not interested? The member moves to the Not interested campaign.`,
            theme: 'warning'
        });
        if (ok) this.save(NOT_INTERESTED, null);
    }

    handleNotNowSave() {
        this.save(NOT_NOW, this.quarter);
    }

    async save(value, recontactFrom) {
        this.saving = true;
        try {
            const res = await answer({ memberId: this.recordId, answer: value, recontactFrom });
            const label = value === NOT_NOW ? `${value}: contact again from ${recontactFrom}` : value;
            this.dispatchEvent(new ShowToastEvent({
                title: res.outcome === 'applied' ? 'Saved' : 'Nothing changed',
                message: res.outcome === 'applied' ? label : 'This answer was already recorded.',
                variant: res.outcome === 'applied' ? 'success' : 'info'
            }));
            this.showNotNow = false;
            // Offer: continue on the Opportunity; otherwise the member (a move gives it a new Id)
            const target = res.opportunityId || res.campaignMemberId;
            if (target && target !== this.recordId) {
                this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: target, actionName: 'view' } });
            } else {
                await this.load();
            }
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Not saved',
                message: e?.body?.message || e?.message || 'The answer could not be saved.',
                variant: 'error'
            }));
        } finally {
            this.saving = false;
        }
    }
}
