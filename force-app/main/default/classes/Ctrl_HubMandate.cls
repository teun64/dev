public without sharing class Ctrl_HubMandate {

    public class MandateData {
        @AuraEnabled public Boolean found;
        @AuraEnabled public String  errorMessage;
        @AuraEnabled public String  mandateId;
        @AuraEnabled public String  status;
        @AuraEnabled public String  mandateReference;
        @AuraEnabled public String  mandateUrl;
        @AuraEnabled public Long    acceptedAt;     // epoch seconds — formatted in JS
        @AuraEnabled public String  acceptanceType; // 'online' | 'offline'
        @AuraEnabled public String  ibanLast4;
        @AuraEnabled public String  bankCode;
    }

    @AuraEnabled(cacheable=false)
    public static MandateData getMandateData(String accountId) {
        MandateData result = new MandateData();
        result.found = false;

        if (String.isBlank(accountId)) {
            result.errorMessage = 'No account provided.';
            return result;
        }

        List<Account> accounts = [
            SELECT PayProv_MandateId__c, PayProv_AccountId__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            result.errorMessage = 'Account not found.';
            return result;
        }

        Account acc = accounts[0];

        if (String.isBlank(acc.PayProv_MandateId__c)) {
            result.errorMessage = 'No mandate on file for this account.';
            return result;
        }

        try {
            // 1. Fetch mandate from Stripe
            Map<String, Object> mandate = callStripeGet(
                acc.PayProv_AccountId__c,
                '/v1/mandates/' + acc.PayProv_MandateId__c
            );

            result.found     = true;
            result.mandateId = (String) mandate.get('id');
            result.status    = (String) mandate.get('status');

            Map<String, Object> pmd = (Map<String, Object>) mandate.get('payment_method_details');
            if (pmd != null) {
                Map<String, Object> sepa = (Map<String, Object>) pmd.get('sepa_debit');
                if (sepa != null) {
                    result.mandateReference = (String) sepa.get('reference');
                    result.mandateUrl       = (String) sepa.get('url');
                }
            }

            Map<String, Object> acceptance = (Map<String, Object>) mandate.get('customer_acceptance');
            if (acceptance != null) {
                result.acceptanceType = (String) acceptance.get('type');
                Object raw = acceptance.get('accepted_at');
                if (raw != null) {
                    result.acceptedAt = Long.valueOf(String.valueOf(raw));
                }
            }

            // 2. Fetch payment method for IBAN last4 + bank code
            String pmId = (String) mandate.get('payment_method');
            if (String.isNotBlank(pmId)) {
                Map<String, Object> pm = callStripeGet(acc.PayProv_AccountId__c, '/v1/payment_methods/' + pmId);
                Map<String, Object> sepaDebit = (Map<String, Object>) pm.get('sepa_debit');
                if (sepaDebit != null) {
                    result.ibanLast4 = (String) sepaDebit.get('last4');
                    result.bankCode  = (String) sepaDebit.get('bank_code');
                }
            }

        } catch (Exception e) {
            result.found         = false;
            result.errorMessage  = 'Could not retrieve mandate from Stripe: ' + e.getMessage();
        }

        return result;
    }

    private static Map<String, Object> callStripeGet(String stripeAccountId, String endpoint) {
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method    = 'GET';
        params.endpoint  = endpoint;
        params.accountId = stripeAccountId;

        List<stripeGC.RawInvocableParameters> batch = new List<stripeGC.RawInvocableParameters>{ params };
        List<String> results = stripeGC.AgnosticInvocable.callStripeEndpoint(batch);
        if (results == null || results.isEmpty()) return new Map<String, Object>();
        return (Map<String, Object>) JSON.deserializeUntyped(results[0]);
    }
}
