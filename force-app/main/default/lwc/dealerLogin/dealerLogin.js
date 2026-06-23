import { LightningElement, track } from 'lwc';
import login from '@salesforce/apex/Ctrl_DealerLogin.login';

export default class DealerLogin extends LightningElement {
    @track username = '';
    @track password = '';
    @track errorMessage = '';
    @track isLoading = false;

    get logoUrl() {
        return null; // replace with branded logo static resource path when available
    }

    get startUrl() {
        const params = new URLSearchParams(window.location.search);
        return params.get('startURL') || '/dealer';
    }

    handleUsernameChange(event) {
        this.username = event.target.value;
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

        if (!this.username || !this.password) {
            this.errorMessage = 'Please enter your username and password.';
            return;
        }

        this.isLoading = true;
        login({ username: this.username, password: this.password, startUrl: this.startUrl })
            .then(redirectUrl => {
                window.location.href = redirectUrl;
            })
            .catch(error => {
                this.errorMessage = error.body?.message || 'Login failed. Please try again.';
                this.isLoading = false;
            });
    }
}
