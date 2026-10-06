/**
 * Shared Account-resolution logic for Stripe events: by PayProv_CustomerId__c first, falling back to
 * PayProv_PaymentMethodId__c for event types that carry no customer reference of their own
 * (e.g. mandate.updated). Used by both Svc_StripeEventProcessor (trigger-time) and
 * Batch_ReconcileStripeMandates (the periodic backfill for cases the trigger couldn't resolve yet).
 */
public without sharing class Util_StripeEvent {

    public class AccountResolution {
        private Map<String, Id> byCustomerId;
        private Map<String, Id> byPaymentMethodId;

        private AccountResolution(Map<String, Id> byCustomerId, Map<String, Id> byPaymentMethodId) {
            this.byCustomerId = byCustomerId;
            this.byPaymentMethodId = byPaymentMethodId;
        }

        public Id resolve(String customerId, String paymentMethodId) {
            if (String.isNotBlank(customerId) && byCustomerId.containsKey(customerId)) {
                return byCustomerId.get(customerId);
            }
            if (String.isNotBlank(paymentMethodId) && byPaymentMethodId.containsKey(paymentMethodId)) {
                return byPaymentMethodId.get(paymentMethodId);
            }
            return null;
        }
    }

    public static AccountResolution resolveAccounts(Set<String> customerIds, Set<String> paymentMethodIds) {
        Map<String, Id> byCustomerId = new Map<String, Id>();
        if (!customerIds.isEmpty()) {
            for (Account a : [SELECT Id, PayProv_CustomerId__c FROM Account
                              WHERE PayProv_CustomerId__c IN :customerIds]) {
                byCustomerId.put(a.PayProv_CustomerId__c, a.Id);
            }
        }

        Map<String, Id> byPaymentMethodId = new Map<String, Id>();
        if (!paymentMethodIds.isEmpty()) {
            for (Account a : [SELECT Id, PayProv_PaymentMethodId__c FROM Account
                              WHERE PayProv_PaymentMethodId__c IN :paymentMethodIds]) {
                byPaymentMethodId.put(a.PayProv_PaymentMethodId__c, a.Id);
            }
        }

        return new AccountResolution(byCustomerId, byPaymentMethodId);
    }
}
