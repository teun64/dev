public without sharing class Ctrl_PaymentCase {

    @AuraEnabled(cacheable=false)
    public static String createPaymentFailureCase(String paymentId, String reason) {
        if (String.isBlank(paymentId)) {
            throw new AuraHandledException('No payment ID provided.');
        }

        List<Payment__c> payments = Database.queryWithBinds(
            'SELECT Id, externalId__c, Amount_Gross__c, CurrencyIsoCode,' +
            '       Account__c,' +
            '       Account__r.Name,' +
            '       Account__r.Reseller_Name__c,' +
            '       Account__r.PayProv_PaymentMethodType__c,' +
            '       Administration__r.Subscription25__Billing_Name__c' +
            ' FROM Payment__c' +
            ' WHERE Id = :paymentId' +
            ' LIMIT 1',
            new Map<String, Object>{ 'paymentId' => paymentId },
            AccessLevel.SYSTEM_MODE
        );
        if (payments.isEmpty()) {
            throw new AuraHandledException('Payment not found: ' + paymentId);
        }

        Payment__c p = payments[0];

        // Resolve payment contact (payment contact role preferred over main contact)
        Id contactId = null;
        List<AccountContactRelation> contactRels = Database.queryWithBinds(
            'SELECT ContactId' +
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
            contactId = contactRels[0].ContactId;
        }

        // Resolve queue by reseller code — e.g. gqPayment1, gqPayment6
        Id queueId = null;
        String resellerCode = p.Account__r?.Reseller_Name__c;
        if (String.isNotBlank(resellerCode)) {
            List<Group> queues = Database.queryWithBinds(
                'SELECT Id' +
                ' FROM Group' +
                ' WHERE Type = \'Queue\'' +
                ' AND DeveloperName = :queueDeveloperName' +
                ' LIMIT 1',
                new Map<String, Object>{ 'queueDeveloperName' => 'gqPayment' + resellerCode },
                AccessLevel.SYSTEM_MODE
            );
            if (!queues.isEmpty()) {
                queueId = queues[0].Id;
            }
        }

        // Support portal URL — from org-wide Custom Setting, fallback to org URL
        CustomerHub__c hubConfig = CustomerHub__c.getOrgDefaults();
        String supportUrl = hubConfig?.Base_URL__c;
        if (String.isBlank(supportUrl)) {
            supportUrl = URL.getOrgDomainUrl().toExternalForm();
        }

        // 20261029 TRi one open Case per payment: a customer who retries on the payment page adds an attempt to it
        // instead of a new Case each time; subject names the method like Svc_StripeEventProcessor's Cases
        String subject = methodLabel(p) + ' failure – ' + p.externalId__c;
        String attempt = System.now().format('yyyy-MM-dd HH:mm') + ' ' + (String.isNotBlank(reason) ? reason : 'payment page error');
        List<Case> open = Database.queryWithBinds(
            'SELECT Id, Description FROM Case' +
            ' WHERE AccountId = :accountId AND Subject = :subject AND IsClosed = false' +
            ' ORDER BY CreatedDate ASC LIMIT 1',
            new Map<String, Object>{ 'accountId' => p.Account__c, 'subject' => subject },
            AccessLevel.SYSTEM_MODE
        );
        if (!open.isEmpty()) {
            Case existing = open[0];
            existing.Description = ((existing.Description == null ? '' : existing.Description) + '\n\nAnother attempt failed: ' + attempt).left(32000);
            Database.update(existing, AccessLevel.SYSTEM_MODE);
            return existing.Id;
        }

        Case c = new Case();
        c.AccountId   = p.Account__c;
        c.ContactId   = contactId;
        c.Subject     = subject;
        c.Description = 'Failed attempt: ' + attempt + '\n\n'
            + 'Payment reference: ' + p.externalId__c + '\n'
            + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c + '\n'
            + 'Support portal: ' + supportUrl;
        c.Origin      = 'Direct Debit';
        c.Status      = 'New';
        if (queueId != null) {
            c.OwnerId = queueId;
        }

        Database.insert(c, AccessLevel.SYSTEM_MODE);
        return c.Id;
    }

    private static String methodLabel(Payment__c p) {
        return Svc_PaymentIntent.CARD.equals(p.Account__r?.PayProv_PaymentMethodType__c) ? 'Card payment' : 'Direct Debit';
    }
}
