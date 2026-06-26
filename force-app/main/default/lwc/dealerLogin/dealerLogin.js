import { LightningElement, track } from 'lwc';
import login from '@salesforce/apex/Ctrl_DealerLogin.login';

export default class DealerLogin extends LightningElement {
    @track email = '';
    @track password = '';
    @track errorMessage = '';
    @track isLoading = false;

    get logoUrl() {
        return null; // replace with branded logo static resource path when available
    }

    get startUrl() {
        if (typeof window === 'undefined') return '/dealer';
        const params = new URLSearchParams(window.location.search);
        return params.get('startURL') || '/dealer';
    }

    handleEmailChange(event) {
        this.email = event.target.value;
    }

    handlePasswordChange(event) {
        this.password = event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter') {
            this.handleLogin();
        }
    }

    handleLogin() {
        this.errorMessage = '';

        if (!this.email || !this.password) {
            this.errorMessage = 'Vul uw e-mailadres en wachtwoord in.';
            return;
        }

        this.isLoading = true;
        login({ email: this.email, password: this.password, startUrl: this.startUrl })
            .then(redirectUrl => {
                window.location.href = redirectUrl;
            })
            .catch(error => {
                this.errorMessage = error.body?.message || 'Inloggen mislukt. Probeer het opnieuw.';
                this.isLoading = false;
            });
    }
}
