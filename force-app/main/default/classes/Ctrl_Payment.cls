public without sharing class Ctrl_Payment {

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
        @AuraEnabled public String externalId;
        @AuraEnabled public String orderDate;
        @AuraEnabled public String collectionDate;
        @AuraEnabled public String contactFirstName;
        @AuraEnabled public String contactLastName;
        @AuraEnabled public String contactEmail;
        @AuraEnabled public ProductLine productLine;
    }

    public class ProductLine {
        @AuraEnabled public String  lineNumber;
        @AuraEnabled public String  productCode;
        @AuraEnabled public String  productName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Integer periodMonths;
    }

    @AuraEnabled(cacheable=false)
    public static PaymentData getPaymentData(String token, String language) {
        PaymentData result = new PaymentData();
        result.found = false;

        if (String.isBlank(token)) {
            result.errorMessage = 'No payment token provided.';
            return result;
        }
        if (String.isBlank(language)) language = 'en';

        List<Payment__c> payments = Database.queryWithBinds(
            'SELECT Id, externalId__c, Type__c, CurrencyIsoCode, Request_Date__c, Amount_Gross__c, Collection_Date__c,' +
            '       Invoice__c,' +
            '       Account__c,' +
            '       Account__r.Name,' +
            '       Account__r.PayProv_CustomerId__c,' +
            '       Account__r.PayProv_MandateId__c,' +
            '       Account__r.PayProv_PaymentMethodId__c,' +
            '       Administration__c,' +
            '       Administration__r.PayProv_Account__c,' +
            '       Administration__r.PayProv_Account__r.stripeGC__Publishable_Key__c,' +
            '       Administration__r.Subscription25__Billing_Name__c,' +
            '       Administration__r.PayProv_DirectDebit_PaymentMethod__c' +
            ' FROM Payment__c' +
            ' WHERE externalId__c = :token' +
            ' AND Status__c != \'Closed\'' +
            ' LIMIT 1',
            new Map<String, Object>{ 'token' => token },
            AccessLevel.SYSTEM_MODE
        );

        if (payments.isEmpty()) {
            result.errorMessage = 'No open payment found for this link.';
            return result;
        }

        Payment__c p = payments[0];
        result.found         = true;
        result.paymentId     = p.Id;
        result.externalId    = p.externalId__c;
        result.currency_x    = p.CurrencyIsoCode;
        result.amountCents   = p.Amount_Gross__c != null ? (Integer)(p.Amount_Gross__c * 100) : 0;
        result.customer      = p.Account__r?.Name;
        result.beneficiary   = p.Administration__r?.Subscription25__Billing_Name__c;
        result.publishableKey = p.Administration__r?.PayProv_Account__r?.stripeGC__Publishable_Key__c;

        List<AccountContactRelation> contactRels = Database.queryWithBinds(
            'SELECT Contact.FirstName, Contact.LastName, Contact.Email,' +
            '       IsPaymentContact__c, isMainContact__c' +
            ' FROM AccountContactRelation' +
            ' WHERE AccountId = :accountId' +
            ' AND IsActive = true' +
            ' AND (IsPaymentContact__c = true OR isMainContact__c = true)' +
            ' ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC' +
            ' LIMIT 1',
            new Map<String, Object>{ 'accountId' => p.Account__c },
            AccessLevel.SYSTEM_MODE
        );
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

        // Product line: first line ordered by cost type (recurring before NON_RECURRING)
        result.productLine = resolveProductLine(p.Invoice__c, language);

        String stripeAccountId  = p.Administration__r?.PayProv_Account__c;
        String stripeCustomerId = p.Account__r?.PayProv_CustomerId__c;
        String mandateId        = p.Account__r?.PayProv_MandateId__c;
        String paymentMethodId  = p.Account__r?.PayProv_PaymentMethodId__c;
        String ddMethod         = p.Administration__r?.PayProv_DirectDebit_PaymentMethod__c;
        if (String.isBlank(ddMethod)) ddMethod = 'sepa_debit';

        if (String.isBlank(stripeCustomerId)) {
            result.errorMessage = 'Payment account is not yet configured for direct debit. Please contact support.';
            return result;
        }

        if ('bacs_debit'.equals(ddMethod)) {
            // BACS: always PaymentIntent — Payment Element collects bank details and establishes mandate in one step
            result.mode = 'payment';
            try {
                result.clientSecret = createPaymentIntent(
                    stripeAccountId, stripeCustomerId, paymentMethodId, mandateId,
                    result.amountCents, result.currency_x, ddMethod, p.Id
                );
            } catch (Exception e) {
                result.errorMessage = 'Could not initialise payment: ' + e.getMessage();
            }
        } else {
            // SEPA / ACH: SetupIntent first to collect bank details and create mandate; PaymentIntent once mandate is on file
            Boolean setupFinalized = String.isNotBlank(mandateId) && String.isNotBlank(paymentMethodId);
            if (!setupFinalized) {
                result.mode = 'setup';
                try {
                    result.clientSecret = createSetupIntent(stripeAccountId, stripeCustomerId, ddMethod, p.Id);
                } catch (Exception e) {
                    result.errorMessage = 'Could not initialise setup: ' + e.getMessage();
                }
            } else {
                result.mode = 'payment';
                try {
                    result.clientSecret = createPaymentIntent(
                        stripeAccountId, stripeCustomerId, paymentMethodId, mandateId,
                        result.amountCents, result.currency_x, ddMethod, p.Id
                    );
                } catch (Exception e) {
                    result.errorMessage = 'Could not initialise payment: ' + e.getMessage();
                }
            }
        }

        return result;
    }

    // ── Product line resolution ───────────────────────────────────────────────
    // Supports: Invoice → Order → OrderItem (primary path)
    // To add Opportunity support: add Opportunity__c to the Payment SOQL and
    //   call resolveProductLineFromOpportunity(p.Opportunity__c, language).
    private static ProductLine resolveProductLine(Id invoiceId, String lang) {
        if (invoiceId == null) return null;

        List<OrderItem> items = Database.queryWithBinds(
            'SELECT Product_Code__c, Product_Name__c, Amount_Gross__c,' +
            '       InvoiceStartDate__c, InvoiceEndDate__c,' +
            '       Subscription25__Product__c,' +
            '       Subscription25__Product__r.Subscription25__Cost_Type__c' +
            ' FROM OrderItem' +
            ' WHERE Order.Subscription25__Invoice__c = :invoiceId' +
            ' ORDER BY Subscription25__Product__r.Subscription25__Cost_Type__c NULLS FIRST,' +
            '          Product_Code__c ASC' +
            ' LIMIT 1',
            new Map<String, Object>{ 'invoiceId' => invoiceId },
            AccessLevel.SYSTEM_MODE
        );
        if (items.isEmpty()) return null;

        OrderItem item = items[0];
        ProductLine pl = new ProductLine();
        pl.lineNumber  = '1';
        pl.productCode = item.Product_Code__c;
        pl.amount      = item.Amount_Gross__c;
        pl.productName = item.Product_Name__c; // fallback if no translation

        // Period in months between invoice start and end date
        if (item.InvoiceStartDate__c != null && item.InvoiceEndDate__c != null) {
            Integer months = (item.InvoiceEndDate__c.year()  - item.InvoiceStartDate__c.year())  * 12
                           + (item.InvoiceEndDate__c.month() - item.InvoiceStartDate__c.month());
            if (item.InvoiceEndDate__c.day() > item.InvoiceStartDate__c.day()) months++;
            pl.periodMonths = months > 0 ? months : null;
        }

        // Localized product name from Data_Translation__c
        if (item.Subscription25__Product__c != null) {
            Id productId = item.Subscription25__Product__c;
            List<Data_Translation__c> translations = Database.queryWithBinds(
                'SELECT Name__c FROM Data_Translation__c' +
                ' WHERE Product__c = :productId AND Language__c = :lang LIMIT 1',
                new Map<String, Object>{ 'productId' => productId, 'lang' => lang },
                AccessLevel.SYSTEM_MODE
            );
            if (!translations.isEmpty() && String.isNotBlank(translations[0].Name__c)) {
                pl.productName = translations[0].Name__c;
            }
        }

        return pl;
    }

    private static String createPaymentIntent(
        String accountId, String customerId, String paymentMethodId, String mandateId,
        Integer amountCents, String currencyCode, String ddMethod, String paymentId
    ) {
        List<String> body = new List<String>{
            'amount=' + amountCents,
            'currency=' + currencyCode.toLowerCase(),
            'customer=' + customerId,
            'payment_method_types[]=' + ddMethod,
            'metadata[PaymentID]=' + paymentId,
            'metadata[PaymentType]=Direct Debit'
        };
        if (String.isNotBlank(paymentMethodId)) {
            body.add('payment_method=' + paymentMethodId);
        }
        if (String.isNotBlank(mandateId)) {
            body.add('mandate=' + mandateId);
        }
        // BACS first-time: no existing mandate yet — instruct Stripe to create one for future off-session charges
        if ('bacs_debit'.equals(ddMethod) && String.isBlank(mandateId)) {
            body.add('setup_future_usage=off_session');
        }
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method    = 'POST';
        params.endpoint  = '/v1/payment_intents';
        params.accountId = accountId;
        params.requestBody = String.join(body, '&');
        return callStripe(params);
    }

    private static String createSetupIntent(String accountId, String customerId, String ddMethod, String paymentId) {
        stripeGC.RawInvocableParameters params = new stripeGC.RawInvocableParameters();
        params.method    = 'POST';
        params.endpoint  = '/v1/setup_intents';
        params.accountId = accountId;
        params.requestBody = String.join(new List<String>{
            'customer=' + customerId,
            'usage=off_session',
            'payment_method_types[]=' + ddMethod,
            'metadata[PaymentID]=' + paymentId
        }, '&');
        return callStripe(params);
    }

    @AuraEnabled(cacheable=false)
    public static void finalizeCheckout(String token, String intentMode) {
        if (String.isBlank(token)) return;

        List<Payment__c> payments = Database.queryWithBinds(
            'SELECT Id FROM Payment__c' +
            ' WHERE externalId__c = :token' +
            ' AND Status__c != \'Closed\'' +
            ' LIMIT 1',
            new Map<String, Object>{ 'token' => token },
            AccessLevel.SYSTEM_MODE
        );
        if (payments.isEmpty()) return;

        // Payment method and mandate are stored by the Stripe_Event_c trigger (Svc_StripeEventProcessor).
        // Here we only update the Payment status so the customer sees the result immediately.
        String newStatus = ('setup'.equals(intentMode)) ? 'Setup' : 'Processing';
        Database.update(new Payment__c(Id = payments[0].Id, Status__c = newStatus), AccessLevel.SYSTEM_MODE);
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

        List<Payment__c> payments = Database.queryWithBinds(
            'SELECT Id, externalId__c, Account__c,' +
            '       Administration__r.Subscription25__Billing_Name__c' +
            ' FROM Payment__c' +
            ' WHERE externalId__c = :token' +
            ' AND Status__c != \'Closed\'' +
            ' LIMIT 1',
            new Map<String, Object>{ 'token' => token },
            AccessLevel.SYSTEM_MODE
        );
        if (payments.isEmpty()) return;

        Payment__c p = payments[0];

        List<AccountContactRelation> contactRels = Database.queryWithBinds(
            'SELECT Contact.FirstName, Contact.Email' +
            ' FROM AccountContactRelation' +
            ' WHERE AccountId = :accountId' +
            ' AND IsActive = true' +
            ' AND (IsPaymentContact__c = true OR isMainContact__c = true)' +
            ' ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC' +
            ' LIMIT 1',
            new Map<String, Object>{ 'accountId' => p.Account__c },
            AccessLevel.SYSTEM_MODE
        );
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
