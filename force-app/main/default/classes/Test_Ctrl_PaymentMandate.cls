@IsTest
private class Test_Ctrl_PaymentMandate {

    // ── Shared test data ──────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Test_Data.createAdministration(true);

        Account acc = Test_Data.createAccount('ACME BV', '9001', 'B2B', false);
        insert acc;
    }

    // ── getMandateData – edge cases ───────────────────────────────────────────

    @IsTest
    static void testGetMandateData_blankAccountId() {
        Test.startTest();
        Ctrl_PaymentMandate.MandateData d = Ctrl_PaymentMandate.getMandateData('');
        Test.stopTest();

        System.assertEquals(false, d.found, 'No account provided → not found');
        System.assertEquals('No account provided.', d.errorMessage);
    }

    @IsTest
    static void testGetMandateData_nullAccountId() {
        Test.startTest();
        Ctrl_PaymentMandate.MandateData d = Ctrl_PaymentMandate.getMandateData(null);
        Test.stopTest();

        System.assertEquals(false, d.found);
        System.assertEquals('No account provided.', d.errorMessage);
    }

    @IsTest
    static void testGetMandateData_accountNotFound() {
        // Valid-format but non-existent Id: create then delete an Account.
        Account ghost = Test_Data.createAccount('GHOST BV', '9002', 'B2B', false);
        insert ghost;
        Id ghostId = ghost.Id;
        delete ghost;

        Test.startTest();
        Ctrl_PaymentMandate.MandateData d = Ctrl_PaymentMandate.getMandateData(ghostId);
        Test.stopTest();

        System.assertEquals(false, d.found);
        System.assertEquals('Account not found.', d.errorMessage);
    }

    @IsTest
    static void testGetMandateData_noMandateOnFile() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACME BV' LIMIT 1];
        // PayProv_MandateId__c intentionally left blank.

        Test.startTest();
        Ctrl_PaymentMandate.MandateData d = Ctrl_PaymentMandate.getMandateData(acc.Id);
        Test.stopTest();

        System.assertEquals(false, d.found);
        System.assertEquals('No mandate on file for this account.', d.errorMessage);
    }

    // ── getMandateData – mandate present, Stripe callout not mocked ──────────
    // Consistent with Test_Ctrl_Payment: the Stripe callout is not mocked here.
    // PayProv_AccountId__c is actually the Id of a stripeGC__Stripe_Account__c
    // record (see Util_PaymentProvider), not a raw Stripe "acct_..." string, and
    // the managed package validates it before ever attempting a callout — so a
    // fabricated value fails fast here, which getMandateData catches and
    // degrades gracefully. That's the behaviour under test.

    @IsTest
    static void testGetMandateData_stripeCalloutFails() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'ACME BV' LIMIT 1];
        acc.PayProv_MandateId__c = 'mandate_test001';
        acc.PayProv_AccountId__c = 'acct_test001';
        update acc;

        Test.startTest();
        Ctrl_PaymentMandate.MandateData d = Ctrl_PaymentMandate.getMandateData(acc.Id);
        Test.stopTest();

        System.assertEquals(false, d.found, 'Unmocked Stripe callout fails, caught and reported as not found');
        System.assert(d.errorMessage.startsWith('Could not retrieve mandate from Stripe:'), 'Error message');
    }

    // ── applyMandateResponse – response parsing, unit-tested directly ────────
    // getMandateData's success path can't be exercised end-to-end in a portable
    // test: it requires a real stripeGC__Stripe_Account__c record wired to a
    // live Stripe Connect account, which isn't guaranteed to exist (or be safe
    // to call) in every org. The parsing logic is @TestVisible so it can be
    // covered directly against fabricated Stripe response payloads instead.

    @IsTest
    static void testApplyMandateResponse_fullPayload() {
        Ctrl_PaymentMandate.MandateData result = new Ctrl_PaymentMandate.MandateData();

        Ctrl_PaymentMandate.applyMandateResponse(result, new Map<String, Object>{
            'id'             => 'mandate_abc',
            'status'         => 'active',
            'payment_method' => 'pm_abc',
            'payment_method_details' => new Map<String, Object>{
                'sepa_debit' => new Map<String, Object>{
                    'reference' => 'REF123',
                    'url'       => 'https://stripe.com/mandate/REF123'
                }
            },
            'customer_acceptance' => new Map<String, Object>{
                'type'        => 'online',
                'accepted_at' => 1700000000
            }
        });

        System.assertEquals(true, result.found);
        System.assertEquals('mandate_abc', result.mandateId);
        System.assertEquals('active', result.status);
        System.assertEquals('REF123', result.mandateReference);
        System.assertEquals('https://stripe.com/mandate/REF123', result.mandateUrl);
        System.assertEquals('online', result.acceptanceType);
        System.assertEquals(1700000000L, result.acceptedAt);
    }

    @IsTest
    static void testApplyMandateResponse_minimalPayload() {
        Ctrl_PaymentMandate.MandateData result = new Ctrl_PaymentMandate.MandateData();

        // No payment_method_details, no customer_acceptance — both optional
        // blocks must be skipped without throwing.
        Ctrl_PaymentMandate.applyMandateResponse(result, new Map<String, Object>{
            'id'     => 'mandate_minimal',
            'status' => 'pending'
        });

        System.assertEquals(true, result.found);
        System.assertEquals('mandate_minimal', result.mandateId);
        System.assertEquals('pending', result.status);
        System.assertEquals(null, result.mandateReference);
        System.assertEquals(null, result.acceptanceType);
        System.assertEquals(null, result.acceptedAt);
    }

    @IsTest
    static void testApplyMandateResponse_acceptanceWithoutTimestamp() {
        Ctrl_PaymentMandate.MandateData result = new Ctrl_PaymentMandate.MandateData();

        Ctrl_PaymentMandate.applyMandateResponse(result, new Map<String, Object>{
            'id'                   => 'mandate_offline',
            'status'               => 'active',
            'customer_acceptance'  => new Map<String, Object>{ 'type' => 'offline' }
        });

        System.assertEquals('offline', result.acceptanceType);
        System.assertEquals(null, result.acceptedAt, 'accepted_at absent → left null, not defaulted');
    }

    // ── applyPaymentMethodResponse – response parsing, unit-tested directly ──

    @IsTest
    static void testApplyPaymentMethodResponse_sepaDebit() {
        Ctrl_PaymentMandate.MandateData result = new Ctrl_PaymentMandate.MandateData();

        Ctrl_PaymentMandate.applyPaymentMethodResponse(result, new Map<String, Object>{
            'id'         => 'pm_abc',
            'sepa_debit' => new Map<String, Object>{
                'last4'     => '1234',
                'bank_code' => 'ABNANL2A'
            }
        });

        System.assertEquals('1234', result.ibanLast4);
        System.assertEquals('ABNANL2A', result.bankCode);
    }

    @IsTest
    static void testApplyPaymentMethodResponse_nonSepa() {
        Ctrl_PaymentMandate.MandateData result = new Ctrl_PaymentMandate.MandateData();

        // e.g. a card payment method — no sepa_debit block at all.
        Ctrl_PaymentMandate.applyPaymentMethodResponse(result, new Map<String, Object>{
            'id' => 'pm_card'
        });

        System.assertEquals(null, result.ibanLast4);
        System.assertEquals(null, result.bankCode);
    }
}
