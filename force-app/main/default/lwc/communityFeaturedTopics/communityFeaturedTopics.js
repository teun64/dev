import { LightningElement, wire, track } from 'lwc';
import getFeaturedTopics from '@salesforce/apex/Ctrl_CommunityFeaturedTopics.getFeaturedTopics';
import BADGEICON from '@salesforce/contentAssetUrl/badgeicon';
import REDARROWICON from '@salesforce/contentAssetUrl/arrowred';

export default class CommunityFeaturedTopics extends LightningElement {
    @track featuredTopics = [];
    error;
    badgeIconUrl = BADGEICON;
    redarrowIconUrl = REDARROWICON;
    get isPartialRow() {
        return this.featuredTopics.length % 3 !== 0;
    }

    get isSingleItemInRow() {
        return this.featuredTopics.length % 3 === 1;
    }

    @wire(getFeaturedTopics)
    wiredTopics({ error, data }) {
        if (data) {
            this.featuredTopics = data.map(topic => ({
                ...topic,
                iconUrl: topic.iconUrl || this.badgeIconUrl,
                Url: `/support/s/topic/${topic.id}/${topic.name.replace(/ /g, '-').toLowerCase()}`
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error.body.message;
            this.featuredTopics = undefined;
        }
    }
    }