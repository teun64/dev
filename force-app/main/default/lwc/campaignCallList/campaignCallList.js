import { LightningElement, api } from 'lwc';
import getCallList from '@salesforce/apex/Ctrl_CampaignMemberCall.getCallList';

export default class CampaignCallList extends LightningElement {
    @api recordId;
    data;
    error;
    loading = true;

    columns = [
        { label: 'Contact', fieldName: 'url', type: 'url', typeAttributes: { label: { fieldName: 'contactName' } } },
        { label: 'Account', fieldName: 'accountName' },
        { label: 'Phone', fieldName: 'phone', type: 'phone' },
        { label: '2G units', fieldName: 'unitCount', type: 'number', initialWidth: 95 },
        { label: 'Priority', fieldName: 'priority', type: 'number', initialWidth: 90 },
        { label: 'Answer', fieldName: 'response', initialWidth: 110 },
        { label: 'Contact again from', fieldName: 'recontactFrom', type: 'date-local', initialWidth: 150 }
    ];

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getCallList({ campaignId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'The call list could not be loaded.';
        } finally {
            this.loading = false;
        }
    }

    get rows() {
        return (this.data?.rows || []).map((r) => ({ ...r, url: `/lightning/r/CampaignMember/${r.memberId}/view` }));
    }

    get title() {
        return this.data ? `Call list · ${this.data.toCall} to call, ${this.data.waiting} waiting (Not now)` : 'Call list';
    }

    handleRefresh() {
        this.load();
    }
}
