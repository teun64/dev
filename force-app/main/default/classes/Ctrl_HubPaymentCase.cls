public without sharing class Ctrl_HubPaymentCase {

    @AuraEnabled(cacheable=false)
    public static String createPaymentFailureCase(String paymentId, String reason) {
        if (String.isBlank(paymentId)) {
            throw new AuraHandledException('No payment ID provided.');
        }

        List<Payment__c> payments = [
            SELECT Id, externalId__c, Amount_Gross__c, CurrencyIsoCode,
                   Account__c,
                   Account__r.Name,
                   Account__r.Reseller_Name__c,
                   Administration__r.Subscription25__Billing_Name__c
            FROM Payment__c
            WHERE Id = :paymentId
            LIMIT 1
        ];
        if (payments.isEmpty()) {
            throw new AuraHandledException('Payment not found: ' + paymentId);
        }

        Payment__c p = payments[0];

        // Resolve payment contact (payment contact role preferred over main contact)
        Id contactId = null;
        List<AccountContactRelation> contactRels = [
            SELECT ContactId
            FROM AccountContactRelation
            WHERE AccountId = :p.Account__c
            AND IsActive = true
            AND (IsPaymentContact__c = true OR isMainContact__c = true)
            ORDER BY IsPaymentContact__c DESC, isMainContact__c DESC
            LIMIT 1
        ];
        if (!contactRels.isEmpty()) {
            contactId = contactRels[0].ContactId;
        }

        // Resolve queue by reseller code — e.g. gqPayment1, gqPayment6
        Id queueId = null;
        String resellerCode = p.Account__r?.Reseller_Name__c;
        if (String.isNotBlank(resellerCode)) {
            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName = :('gqPayment' + resellerCode)
                LIMIT 1
            ];
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

        Case c = new Case();
        c.AccountId   = p.Account__c;
        c.ContactId   = contactId;
        c.Subject     = 'Direct Debit failure – ' + p.externalId__c;
        c.Description = (String.isNotBlank(reason) ? reason + '\n\n' : '')
            + 'Payment reference: ' + p.externalId__c + '\n'
            + 'Amount: ' + p.CurrencyIsoCode + ' ' + p.Amount_Gross__c + '\n'
            + 'Support portal: ' + supportUrl;
        c.Origin      = 'Direct Debit';
        c.Status      = 'New';
        if (queueId != null) {
            c.OwnerId = queueId;
        }

        insert c;
        return c.Id;
    }
}
