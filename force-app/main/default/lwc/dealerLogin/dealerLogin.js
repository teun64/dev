import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import LOCALE_LANG from '@salesforce/i18n/lang';
import basePath from '@salesforce/community/basePath';
import login from '@salesforce/apex/Ctrl_DealerPortalLogin.login';
import forgotPassword from '@salesforce/apex/Ctrl_DealerPortalLogin.forgotPassword';
import getFooterInfo from '@salesforce/apex/Ctrl_DealerPortal.getFooterInfo';

const DEFAULT_LANG = 'en';

// {email} is replaced by the contact email of the reseller (Administration, as in the footer).
const LABELS = {
    nl: {
        loginTitle: 'Inloggen',
        forgotTitle: 'Wachtwoord vergeten?',
        email: 'E-mailadres',
        password: 'Wachtwoord',
        loginButton: 'Inloggen',
        forgotLink: 'Wachtwoord vergeten?',
        forgotIntro: 'Vul je e-mailadres in. Als het bij ons bekend is, ontvang je een e-mail om je wachtwoord opnieuw in te stellen.',
        forgotButton: 'Verstuur',
        backToLogin: 'Terug naar inloggen',
        forgotSent: 'Als dit e-mailadres bij ons bekend is, ontvang je binnen enkele minuten een e-mail om je wachtwoord opnieuw in te stellen.',
        loginFailed: 'Inloggen is niet gelukt. Controleer je gegevens of neem contact met ons op via {email}.',
        loginFailedNoEmail: 'Inloggen is niet gelukt. Controleer je gegevens of neem contact met ons op.',
        required: 'Vul je e-mailadres en wachtwoord in.'
    },
    en: {
        loginTitle: 'Log in',
        forgotTitle: 'Forgot your password?',
        email: 'Email address',
        password: 'Password',
        loginButton: 'Log in',
        forgotLink: 'Forgot your password?',
        forgotIntro: "Enter your email address. If it is known to us, you'll receive an email to reset your password.",
        forgotButton: 'Send',
        backToLogin: 'Back to log in',
        forgotSent: "If this email address is known to us, you'll receive an email to reset your password within a few minutes.",
        loginFailed: 'Login failed. Check your details or contact us at {email}.',
        loginFailedNoEmail: 'Login failed. Check your details or contact us.',
        required: 'Enter your email address and password.'
    },
    de: {
        loginTitle: 'Anmelden',
        forgotTitle: 'Passwort vergessen?',
        email: 'E-Mail-Adresse',
        password: 'Passwort',
        loginButton: 'Anmelden',
        forgotLink: 'Passwort vergessen?',
        forgotIntro: 'Geben Sie Ihre E-Mail-Adresse ein. Wenn sie uns bekannt ist, erhalten Sie eine E-Mail zum Zurücksetzen Ihres Passworts.',
        forgotButton: 'Senden',
        backToLogin: 'Zurück zur Anmeldung',
        forgotSent: 'Wenn diese E-Mail-Adresse uns bekannt ist, erhalten Sie in wenigen Minuten eine E-Mail zum Zurücksetzen Ihres Passworts.',
        loginFailed: 'Anmeldung fehlgeschlagen. Prüfen Sie Ihre Angaben oder kontaktieren Sie uns unter {email}.',
        loginFailedNoEmail: 'Anmeldung fehlgeschlagen. Prüfen Sie Ihre Angaben oder kontaktieren Sie uns.',
        required: 'Geben Sie Ihre E-Mail-Adresse und Ihr Passwort ein.'
    },
    fr: {
        loginTitle: 'Connexion',
        forgotTitle: 'Mot de passe oublié ?',
        email: 'Adresse e-mail',
        password: 'Mot de passe',
        loginButton: 'Se connecter',
        forgotLink: 'Mot de passe oublié ?',
        forgotIntro: 'Saisissez votre adresse e-mail. Si elle nous est connue, vous recevrez un e-mail pour réinitialiser votre mot de passe.',
        forgotButton: 'Envoyer',
        backToLogin: 'Retour à la connexion',
        forgotSent: 'Si cette adresse e-mail nous est connue, vous recevrez dans quelques minutes un e-mail pour réinitialiser votre mot de passe.',
        loginFailed: 'La connexion a échoué. Vérifiez vos informations ou contactez-nous à {email}.',
        loginFailedNoEmail: 'La connexion a échoué. Vérifiez vos informations ou contactez-nous.',
        required: 'Saisissez votre adresse e-mail et votre mot de passe.'
    }
};
const SUPPORTED_LANGS = Object.keys(LABELS);

export default class DealerLogin extends LightningElement {
    // 'login' on the Login page, 'forgot' on the Forgot Password page.
    @api mode = 'login';

    identifier = '';
    password = '';
    errorMessage = '';
    forgotSent = false;
    isBusy = false;
    contactEmail = '';
    startUrl = '';
    lang = DEFAULT_LANG;

    @wire(CurrentPageReference)
    wiredPageRef(ref) {
        this.startUrl = ref?.state?.startURL || ref?.state?.startUrl || '';
    }

    // The portal domain picks the Administration for visitors without a dealer account.
    hostname = window.location.hostname;

    @wire(getFooterInfo, { hostname: '$hostname' })
    wiredFooter({ data }) {
        if (data) this.contactEmail = data.email || '';
    }

    connectedCallback() {
        const browserLang = (LOCALE_LANG || '').slice(0, 2).toLowerCase();
        this.lang = SUPPORTED_LANGS.includes(browserLang) ? browserLang : DEFAULT_LANG;
    }

    get labels() {
        return LABELS[this.lang] || LABELS[DEFAULT_LANG];
    }

    get isForgot() {
        return this.mode === 'forgot';
    }

    get title() {
        return this.isForgot ? this.labels.forgotTitle : this.labels.loginTitle;
    }

    get forgotUrl() {
        return `${basePath}/ForgotPassword`;
    }

    get loginUrl() {
        return `${basePath}/login`;
    }

    get failedMessage() {
        return this.contactEmail
            ? this.labels.loginFailed.replace('{email}', this.contactEmail)
            : this.labels.loginFailedNoEmail;
    }

    handleIdentifier(event) {
        this.identifier = event.target.value;
    }

    handlePassword(event) {
        this.password = event.target.value;
    }

    handleKeyUp(event) {
        if (event.key === 'Enter') {
            if (this.isForgot) this.handleForgot();
            else this.handleLogin();
        }
    }

    async handleLogin() {
        if (this.isBusy) return;
        this.errorMessage = '';
        if (!this.identifier || !this.password) {
            this.errorMessage = this.labels.required;
            return;
        }
        this.isBusy = true;
        try {
            const url = await login({ identifier: this.identifier, password: this.password, startUrl: this.startUrl });
            window.location.href = url;
        } catch (e) {
            // Every failure looks the same on purpose (no hint whether an account exists or is disabled).
            this.errorMessage = this.failedMessage;
            this.isBusy = false;
        }
    }

    async handleForgot() {
        if (this.isBusy || !this.identifier) return;
        this.isBusy = true;
        try {
            await forgotPassword({ identifier: this.identifier });
        } catch (e) {
            // Same outcome as success: never tell whether the address is known.
        }
        this.forgotSent = true;
        this.isBusy = false;
    }
}
