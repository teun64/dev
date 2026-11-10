import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getOverview from '@salesforce/apex/Ctrl_StagedCampaignOverview.getOverview';
import release from '@salesforce/apex/Ctrl_StagedCampaignOverview.release';

const DEFAULT_SIZE = 500;
const MAX_SIZE = 2000;

const pct = (n, of) => (of ? `${Math.round((n / of) * 100)}%` : '–');

const TABLE_COLUMNS = [
    { label: 'Members', fieldName: 'members', type: 'number', initialWidth: 95 },
    { label: 'In mail cycle', fieldName: 'inCycle', type: 'number', initialWidth: 115 },
    { label: 'Reacted', fieldName: 'reactedLabel', initialWidth: 105 },
    { label: 'Call me', fieldName: 'callMe', type: 'number', initialWidth: 90 },
    { label: 'Offer', fieldName: 'offer', type: 'number', initialWidth: 80 },
    { label: 'Not now', fieldName: 'notNow', type: 'number', initialWidth: 90 },
    { label: 'Not interested', fieldName: 'notInterested', type: 'number', initialWidth: 120 },
    { label: 'Dealer', fieldName: 'dealer', type: 'number', initialWidth: 85 },
    { label: 'No reaction', fieldName: 'notReacted', type: 'number', initialWidth: 110 }
];

export default class StagedCampaignOverview extends NavigationMixin(LightningElement) {
    @api recordId;
    data;
    error;
    loading = true;
    releasing = false;
    size = DEFAULT_SIZE;

    batchColumns = [
        { label: 'Batch', fieldName: 'label', initialWidth: 90 },
        { label: 'Released', fieldName: 'releasedOn', type: 'date-local', initialWidth: 110 },
        ...TABLE_COLUMNS
    ];
    hardwareColumns = [{ label: 'Hardware (best 2G unit)', fieldName: 'label', initialWidth: 190 }, ...TABLE_COLUMNS];

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getOverview({ campaignId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'The overview could not be loaded.';
        } finally {
            this.loading = false;
        }
    }

    get staged() {
        return this.data?.staged;
    }

    get campaigns() {
        return (this.data?.campaigns || []).map((c) => ({ ...c, key: c.label, missing: !c.recordId }));
    }

    get releasedLabel() {
        return this.data ? this.data.released.toLocaleString('nl-NL') : '0';
    }

    get reactedLabel() {
        return this.data ? `${this.data.reacted.toLocaleString('nl-NL')} (${pct(this.data.reacted, this.data.released)})` : '';
    }

    get reactions() {
        const released = this.data?.released || 0;
        return (this.data?.reactions || []).map((r) => ({ ...r, key: r.label, share: pct(r.count, released) }));
    }

    get mails() {
        return (this.data?.mails || []).map((m) => ({ ...m, key: m.label }));
    }

    get notNow() {
        return (this.data?.notNow || []).map((q) => ({ ...q, key: q.label }));
    }

    get hasNotNow() {
        return this.notNow.length > 0;
    }

    get callbacks() {
        return (this.data?.callbacks || []).map((c) => ({ ...c, key: c.label }));
    }

    get hasCallbacks() {
        return this.callbacks.length > 0;
    }

    get batches() {
        return this.rows(this.data?.batches);
    }

    get hasBatches() {
        return this.batches.length > 0;
    }

    get hardware() {
        return this.rows(this.data?.hardware);
    }

    get sourceByPriority() {
        return (this.data?.sourceByPriority || []).map((p) => ({ ...p, key: p.label }));
    }

    get hasSourceByPriority() {
        return this.sourceByPriority.length > 0;
    }

    get maxSize() {
        return Math.min(MAX_SIZE, this.data?.sourceReady || 0);
    }

    get releaseDisabled() {
        return this.releasing || !this.data?.canRelease || !this.data?.sourceReady || !(this.size > 0);
    }

    get releaseLabel() {
        const n = Math.min(this.size || 0, this.maxSize);
        return `Release ${n.toLocaleString('nl-NL')} and start mail 1`;
    }

    get revenue() {
        return (this.data?.revenue || []).map((r) => ({
            ...r,
            key: r.label,
            amountLabel: new Intl.NumberFormat('nl-NL', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(r.amount || 0)
        }));
    }

    rows(list) {
        return (list || []).map((r) => ({ ...r, key: r.label, reactedLabel: `${r.reacted} (${pct(r.reacted, r.members)})` }));
    }

    handleSize(event) {
        this.size = parseInt(event.target.value, 10);
    }

    openCampaign(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    async handleRelease() {
        const n = Math.min(this.size, this.maxSize);
        const ok = await LightningConfirm.open({
            label: 'Release batch',
            message: `Move the next ${n} members (by priority) from Source to Operational? Their mail cycle starts today with mail 1. This can't be undone.`,
            theme: 'warning'
        });
        if (!ok) return;
        this.releasing = true;
        try {
            const r = await release({ campaignId: this.recordId, size: n });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: r.released ? `Batch ${r.batchNumber} released` : 'Nothing released',
                    message: r.released ? `${r.released} members moved to Operational, mail 1 is due today.` : r.message,
                    variant: r.released ? 'success' : 'warning'
                })
            );
            await this.load();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Release failed', message: e?.body?.message || e?.message, variant: 'error' }));
        } finally {
            this.releasing = false;
        }
    }

    handleRefresh() {
        this.load();
    }
}
