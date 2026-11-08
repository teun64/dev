import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getResponse from '@salesforce/apex/Ctrl_CampaignResponseGuest.getResponse';
import submit from '@salesforce/apex/Ctrl_CampaignResponseGuest.submit';

const LANG_EVENTS = ['mi:languagechange', 'echoes:languagechange', 'tds:languagechange'];
const CODES = ['callme', 'offer', 'notnow', 'notinterested'];

const I18N = {
    nl: {
        hello: (name) => (name ? `Beste ${name},` : 'Beste klant,'),
        intro: (label) => `Uw keuze voor: ${label}`,
        pick: 'Wat wilt u?',
        answers: {
            callme: 'Bel mij terug',
            offer: 'Stuur mij een aanbieding',
            notnow: 'Nu niet, neem later contact op',
            notinterested: 'Geen interesse'
        },
        quarter: 'Wanneer mogen wij contact opnemen?',
        quarterLabel: (d) => `Q${Math.floor(d.getMonth() / 3) + 1} ${d.getFullYear()}`,
        confirm: 'Bevestigen',
        change: 'Andere keuze',
        saving: 'Bezig met opslaan…',
        done: {
            callme: 'Bedankt. Een medewerker belt u binnen 2 werkdagen.',
            offer: 'Bedankt. Een medewerker neemt binnen 2 werkdagen contact met u op over de aanbieding.',
            notnow: 'Bedankt. Wij nemen in het gekozen kwartaal weer contact met u op.',
            notinterested: 'Bedankt voor uw antwoord. Wij sturen u hierover geen berichten meer.'
        },
        already: 'Wij hebben uw keuze al ontvangen:',
        invalid: 'Deze link is niet (meer) geldig. Neem contact op met onze klantenservice.',
        error: 'Uw keuze kon niet worden opgeslagen. Probeer het later opnieuw.'
    },
    en: {
        hello: (name) => (name ? `Dear ${name},` : 'Dear customer,'),
        intro: (label) => `Your choice for: ${label}`,
        pick: 'What would you like?',
        answers: {
            callme: 'Call me back',
            offer: 'Send me an offer',
            notnow: 'Not now, contact me later',
            notinterested: 'Not interested'
        },
        quarter: 'When may we contact you?',
        quarterLabel: (d) => `Q${Math.floor(d.getMonth() / 3) + 1} ${d.getFullYear()}`,
        confirm: 'Confirm',
        change: 'Other choice',
        saving: 'Saving…',
        done: {
            callme: 'Thank you. One of our staff will call you within 2 working days.',
            offer: 'Thank you. One of our staff will contact you about the offer within 2 working days.',
            notnow: 'Thank you. We will contact you again in the chosen quarter.',
            notinterested: 'Thank you for your answer. We will not send you further messages about this.'
        },
        already: 'We have already received your choice:',
        invalid: 'This link is not (or no longer) valid. Please contact our customer service.',
        error: 'Your choice could not be saved. Please try again later.'
    }
};

export default class CampaignResponse extends LightningElement {
    token;
    answer;          // chosen answer code
    quarter;         // yyyy-MM-dd, Not now
    data;
    isLoading = true;
    isSaving = false;
    isDone = false;
    hasError = false;
    lang = 'nl';

    _langHandler = (e) => {
        const l = e.detail?.language;
        if (l) this.lang = l;
    };

    connectedCallback() {
        LANG_EVENTS.forEach((n) => window.addEventListener(n, this._langHandler));
    }

    disconnectedCallback() {
        LANG_EVENTS.forEach((n) => window.removeEventListener(n, this._langHandler));
    }

    @wire(CurrentPageReference)
    pageRef(ref) {
        const state = ref?.state || {};
        this.token = state.token;
        const a = (state.a || '').toLowerCase();
        if (CODES.includes(a)) this.answer = a;
    }

    @wire(getResponse, { token: '$token' })
    wired({ data, error }) {
        if (data) {
            this.data = data;
            this.isLoading = false;
            if (data.quarters?.length && !this.quarter) this.quarter = data.recontactFrom || data.quarters[0];
        } else if (error) {
            this.hasError = true;
            this.isLoading = false;
        }
    }

    get t() {
        return I18N[this.lang] || I18N.nl;
    }

    get isValid() {
        return !this.isLoading && this.data?.valid;
    }

    get isInvalid() {
        return !this.isLoading && !this.hasError && !this.data?.valid;
    }

    get hello() {
        return this.t.hello(this.data?.firstName);
    }

    get intro() {
        return this.t.intro(this.data?.campaignLabel);
    }

    get alreadyAnswered() {
        return !this.isDone && this.data?.currentAnswer && !this.answer;
    }

    get currentAnswerLabel() {
        return this.t.answers[this.data?.currentAnswer];
    }

    // a choice from the mail link, or picked here
    get showConfirm() {
        return this.isValid && !this.isDone && !!this.answer;
    }

    get showChoices() {
        return this.isValid && !this.isDone && !this.answer;
    }

    get choices() {
        return CODES.map((code) => ({ code, label: this.t.answers[code] }));
    }

    get answerLabel() {
        return this.t.answers[this.answer];
    }

    get isNotNow() {
        return this.answer === 'notnow';
    }

    get quarterOptions() {
        return (this.data?.quarters || []).map((q) => ({
            label: this.t.quarterLabel(new Date(q + 'T00:00:00')),
            value: q
        }));
    }

    get doneText() {
        return this.t.done[this.answer];
    }

    handleChoice(event) {
        this.answer = event.currentTarget.dataset.code;
    }

    handleChange() {
        this.answer = null;
    }

    handleQuarter(event) {
        this.quarter = event.detail.value;
    }

    async handleConfirm() {
        this.isSaving = true;
        this.hasError = false;
        try {
            const outcome = await submit({
                token: this.token,
                answerCode: this.answer,
                recontactFrom: this.isNotNow ? this.quarter : null
            });
            if (outcome === 'invalid') {
                this.hasError = true;
            } else {
                this.isDone = true;
            }
        } catch (e) {
            this.hasError = true;
        } finally {
            this.isSaving = false;
        }
    }
}
