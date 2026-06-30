public without sharing class Ctrl_HubPayment {

    public class PaymentData {
        @AuraEnabled public Boolean found;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String paymentId;
        @AuraEnabled public String publishableKey;
        @AuraEnabled public String clientSecret;
        @AuraEnabled public String mode;
        @AuraEnabled public String currency_x;
        @AuraEnabled public Integer amountCents;
        @AuraEnabled public String customer;
        @AuraEnabled public String beneficiary;
        @AuraEnabled public String reference;
        @AuraEnabled public String orderDate;
        @AuraEnabled public String collectionDate;
        @AuraEnabled public String contactFirstName;
        @AuraEnabled public String contactLastName;
        @AuraEnabled public String contactEmail;
    }

    @AuraEnabled(cacheable=false)
    public static PaymentData getPaymentData(String token) {
        PaymentData result = new PaymentData();
        result.found = false;

        if (String.isBlank(token)) {
            result.errorMessage = 'No payment token provided.';
            return result;
        }

        List<Payment__c> payments = [
            SELECT Id, externalId__c, Type__c, CurrencyIsoCode, Request_Date__c, Amount_Gross__c, Collection_Date__c,
                   Account__c,
                   Account__r.Name,
                   Account__r.PayProv_CustomerId__c,
                   Account__r.PayProv_MandateId__c,
                   Account__r.PayProv_PaymentMethodId__c,
                   Administration__r.PayProv_Account__c,
                   Administration__r.PayProv_Account__r.stripeGC__Publishable_Key__c,
                   Administration__r.Subscription25__Billing_Name__c
            FROM Payment__c
            WHERE externalId__c = :token
            AND Status__c != 'Closed'
            LIMIT 1
        ];

        if (payments.isEmpty()) {
            result.errorMessage = 'No open payment found for this link.';
            return result;
        }

        Payment__c p = payments[0];
        result.found         = true;
        result.paymentId     = p.Id;
        result.reference     = p.externalId__c;
        result.currency_x    = p.CurrencyIsoCode;
        result.amountCents   = p.Amount_Gross__c != null ? (Integer)(p.Amount_Gross__c * 100) : 0;
        result.customer      = p.Account__r?.Name;
        result.beneficiary   = p.Administration__r?.Subscription25__Billing_Name__c;
        result.publishableKey = p.Administration__r?.PayProv_Account__r?.stripeGC__Publishable_Key__c;

        List<AccountContactRelation> contactRels = [
            SELECT Contact.FirstName, Contact.LastName, Contact.Email,
                   IsPaymentContact__c, isMainContact__c
            FROM AccountContactRelation
            WHERE AccountId = :p.Account__c
            AND IsActive = true
            AND (IsPaymentContact__c = true OR isMainContact__c = true)
            ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
            LIMIT 1
        ];
        if (!contactRels.isEmpty()) {
            result.contactFirstName = contactRels[0].Contact.FirstName;
            result.contactLastName  = contactRels[0].Contact.LastName;
            result.contactEmail     = contactRels[0].Contact.Email;
        }

        if (p.Request_Date__c != null) {
            result.orderDate = p.Request_Date__c.year()
                + '-' + String.valueOf(p.Request_Date__c.month()).leftPad(2, '0')
                + '-' + String.valueOf(p.Request_Date__c.day()).leftPad(2, '0');
        }

        if (p.Collection_Date__c != null) {
            result.collectionDate = p.Collection_Date__c.year()
                + '-' + String.valueOf(p.Collection_Date__c.month()).leftPad(2, '0')
                + '-' + String.valueOf(p.Collection_Date__c.day()).leftPad(2, '0');
        }

        String stripeAccountId  = p.Administration__r?.PayProv_Account__c;
        String stripeCustomerId = p.Account__r?.PayProv_CustomerId__c;
        String mandateId        = p.Account__r?.PayProv_MandateId__c;
        String paymentMethodId  = p.Account__r?.PayProv_PaymentMethodId__c;

        Boolean setupFinalized = String.isNotBlank(mandateId) && String.isNotBlank(paymentMethodId);

        if (!setupFinalized) {
            // Mandate not in place yet — create a SetupIntent so the customer can authorise direct debit
            result.mode = 'setup';
            try {
                result.clientSecret = createSetupIntent(stripeAccountId, stripeCustomerId);
            } catch (Exception e) {
                result.errorMessage = 'Could not initialise setup: ' + e.getMessage();
            }
        } else {
            // Mandate in place — create PaymentIntent using the stored payment method
            result.mode = 'payment';
            try {
                result.clientSecret = createPaymentIntent(
                    stripeAccountId, stripeCustomerId, paymentMethodId,
                    result.amountCents, result.currency_x, p.Id
                );
            } catch (Exception e) {
                result.errorMessage = 'Could not initialise payment: ' + e.getMessage();
            }
        }

        return result;
    }

    private static String createPaymentIntent(
        String accountId, String customerId, String paymentMethodId,
        Integer amountCents, String currencyCode, String paymentId
    ) {
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method    = 'POST';
        params.endpoint  = '/v1/payment_intents';
        params.accountId = accountId;
        params.requestBody = String.join(new List<String>{
            'amount=' + amountCents,
            'currency=' + currencyCode.toLowerCase(),
            'customer=' + customerId,
            'payment_method=' + paymentMethodId,
            'payment_method_types[]=sepa_debit',
            'metadata[PaymentID]=' + paymentId,
            'metadata[PaymentType]=Direct Debit'
        }, '&');

        return callStripe(params);
    }

    private static String createSetupIntent(String accountId, String customerId) {
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method    = 'POST';
        params.endpoint  = '/v1/setup_intents';
        params.accountId = accountId;
        params.requestBody = String.join(new List<String>{
            'customer=' + customerId,
            'usage=off_session',
            'payment_method_types[]=sepa_debit'
        }, '&');

        return callStripe(params);
    }

    private static String callStripe(stripeGC.RawInvocableParameters params) {
        List<stripeGC.RawInvocableParameters> batch = new List<stripeGC.RawInvocableParameters>{ params };
        List<String> results = stripeGC.AgnosticInvocable.callStripeEndpoint(batch);
        if (results == null || results.isEmpty()) return null;
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(results[0]);
        return (String) parsed.get('client_secret');
    }

    @AuraEnabled(cacheable=false)
    public static void sendSetupEmail(String token) {
        if (String.isBlank(token)) return;

        List<Payment__c> payments = [
            SELECT Id, externalId__c, Account__c,
                   Administration__r.Subscription25__Billing_Name__c
            FROM Payment__c
            WHERE externalId__c = :token
            AND Status__c != 'Closed'
            LIMIT 1
        ];
        if (payments.isEmpty()) return;

        Payment__c p = payments[0];

        List<AccountContactRelation> contactRels = [
            SELECT Contact.FirstName, Contact.Email
            FROM AccountContactRelation
            WHERE AccountId = :p.Account__c
            AND IsActive = true
            AND (IsPaymentContact__c = true OR isMainContact__c = true)
            ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
            LIMIT 1
        ];
        if (contactRels.isEmpty() || String.isBlank(contactRels[0].Contact.Email)) return;

        String contactEmail = contactRels[0].Contact.Email;
        String firstName    = contactRels[0].Contact.FirstName;

        CustomerHub__c hubConfig = CustomerHub__c.getOrgDefaults();
        String baseUrl = hubConfig?.Base_URL__c;
        if (String.isBlank(baseUrl)) {
            baseUrl = URL.getOrgDomainUrl().toExternalForm() + '/customer-hub';
        }
        // Strip trailing slash so the concatenation is always clean
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.removeEnd('/');
        }
        String setupLink = baseUrl + '/payment/' + p.externalId__c;

        String greeting   = String.isNotBlank(firstName) ? 'Dear ' + firstName + ',' : 'Dear Customer,';
        String senderName = p.Administration__r?.Subscription25__Billing_Name__c;
        if (String.isBlank(senderName)) senderName = 'Moving Intelligence';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ contactEmail });
        mail.setSubject('Direct Debit setup request – ' + p.externalId__c);
        mail.setPlainTextBody(
            greeting + '\n\n'
            + 'To enable direct debit payments, please authorise your bank account via the link below:\n\n'
            + setupLink + '\n\n'
            + 'Kind regards,\n' + senderName
        );
        mail.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            // Log but do not surface — email unavailability should not block the caller
            System.debug(LoggingLevel.WARN, 'sendSetupEmail failed: ' + e.getMessage());
        }
    }
}
