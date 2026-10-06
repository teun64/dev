@IsTest
private class Test_Util_StripeEvent {

    @TestSetup
    static void makeData() {
        // rbb_Account wipes PayProv_* ids whenever they're already populated on a brand-new Account -
        // set them via a separate update, same pattern as the other Stripe test fixtures.
        Account byCustomer = Test_Data.createAccount('Resolve By Customer BV', '9041', 'B2B', false);
        insert byCustomer;
        byCustomer.PayProv_CustomerId__c = 'cus_resolve001';
        update byCustomer;

        Account byPaymentMethod = Test_Data.createAccount('Resolve By PM BV', '9042', 'B2B', false);
        insert byPaymentMethod;
        byPaymentMethod.PayProv_PaymentMethodId__c = 'pm_resolve001';
        update byPaymentMethod;
    }

    @IsTest
    static void resolve_prefersCustomerIdOverPaymentMethodId() {
        Util_StripeEvent.AccountResolution resolution = Util_StripeEvent.resolveAccounts(
            new Set<String>{ 'cus_resolve001' }, new Set<String>{ 'pm_resolve001' }
        );

        Account byCustomer = [SELECT Id FROM Account WHERE PayProv_CustomerId__c = 'cus_resolve001'];
        System.assertEquals(byCustomer.Id, resolution.resolve('cus_resolve001', 'pm_resolve001'),
            'CustomerId resolves first, even when a PaymentMethodId match also exists');
    }

    @IsTest
    static void resolve_fallsBackToPaymentMethodId() {
        Util_StripeEvent.AccountResolution resolution = Util_StripeEvent.resolveAccounts(
            new Set<String>(), new Set<String>{ 'pm_resolve001' }
        );

        Account byPaymentMethod = [SELECT Id FROM Account WHERE PayProv_PaymentMethodId__c = 'pm_resolve001'];
        System.assertEquals(byPaymentMethod.Id, resolution.resolve(null, 'pm_resolve001'),
            'Falls back to PaymentMethodId when no customerId is given (e.g. mandate.updated)');
    }

    @IsTest
    static void resolve_noMatchReturnsNull() {
        Util_StripeEvent.AccountResolution resolution = Util_StripeEvent.resolveAccounts(
            new Set<String>{ 'cus_resolve001' }, new Set<String>{ 'pm_resolve001' }
        );

        System.assertEquals(null, resolution.resolve('cus_unknown', 'pm_unknown'), 'No match for either key');
        System.assertEquals(null, resolution.resolve(null, null), 'Blank keys never match');
    }

    @IsTest
    static void resolveAccounts_emptySetsSkipQueries() {
        Util_StripeEvent.AccountResolution resolution = Util_StripeEvent.resolveAccounts(new Set<String>(), new Set<String>());
        System.assertEquals(null, resolution.resolve('cus_resolve001', 'pm_resolve001'),
            'Nothing resolves when the caller passed no ids to look up');
    }
}
