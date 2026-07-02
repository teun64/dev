@IsTest
private class Test_Svc_StripeEventProcessor {

    // ── Test data ─────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        Account acc = Test_Data.createAccount('ACME BV', '9001', 'B2B', false);
        insert acc;
        acc.PayProv_CustomerId__c = 'cus_test001';
        update acc;

        Contact c = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jan',
            LastName  = 'Betaler',
            Email     = 'jan@acme.nl'
        );
        insert c;
        AccountContactRelation acr = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :acc.Id AND ContactId = :c.Id LIMIT 1
        ];
        acr.Roles = 'Payment';
        update acr;

        Payment__c pmt = new Payment__c(
            Account__c            = acc.Id,
            Administration__c     = admin.Id,
            externalId__c         = 'tok_test',
            Status__c             = 'Pending',
            CurrencyIsoCode       = 'EUR',
            Amount_Gross__c       = 120.00,
            Request_Date__c       = Date.today(),
            Collection_Date__c    = Date.today().addDays(14),
            Interaction_Status__c = 'Mail Sent',
            Mail_Sent_Date__c     = Date.today()
        );
        Database.insert(pmt, AccessLevel.SYSTEM_MODE);
    }

    // ── setup_intent.succeeded ────────────────────────────────────────────────

    @IsTest
    static void testSetupIntentSucceeded() {
        Account acc = [SELECT Id FROM Account WHERE PayProv_CustomerId__c = 'cus_test001' LIMIT 1];
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'setup_intent.succeeded',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'si_test001',
                        'status'         => 'succeeded',
                        'customer'       => 'cus_test001',
                        'payment_method' => 'pm_test001',
                        'mandate'        => 'mandate_test001',
                        'metadata'       => new Map<String, Object>{ 'PaymentID' => pmt.Id }
                    }
                }
            })
        );
        Test.stopTest();

        Account updAcc = [SELECT PayProv_PaymentMethodId__c, PayProv_MandateId__c FROM Account WHERE Id = :acc.Id];
        Payment__c updPmt = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, Interaction_Status__c, Processed_Date__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];

        System.assertEquals('pm_test001',      updAcc.PayProv_PaymentMethodId__c,  'Payment method set on account');
        System.assertEquals('mandate_test001',  updAcc.PayProv_MandateId__c,        'Mandate ID set on account');
        System.assertEquals('Setup',           updPmt.Status__c,                   'Payment status = Setup');
        System.assertEquals('Request Processed by Customer', updPmt.Interaction_Status__c, 'Interaction status updated');
        System.assertEquals(Date.today(),      updPmt.Processed_Date__c,           'Processed date = today');
    }

    // ── setup_intent.setup_failed ─────────────────────────────────────────────

    @IsTest
    static void testSetupIntentFailed() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'setup_intent.setup_failed',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'si_fail001',
                        'status'         => 'requires_payment_method',
                        'customer'       => 'cus_test001',
                        'payment_method' => 'pm_fail001',
                        'metadata'       => new Map<String, Object>{ 'PaymentID' => pmt.Id },
                        'last_setup_error' => new Map<String, Object>{
                            'code'    => 'card_declined',
                            'message' => 'Your card was declined.'
                        }
                    }
                }
            })
        );
        Test.stopTest();

        Payment__c updPmt = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, Interaction_Status__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Failed',    updPmt.Status__c,             'Payment status = Failed');
        System.assertEquals('Mail Sent', updPmt.Interaction_Status__c, 'Interaction status not changed on failure');

        List<Case> cases = [SELECT Subject FROM Case];
        System.assertEquals(1, cases.size(), 'One failure case created');
        System.assert(cases[0].Subject.contains('Direct Debit failure'), 'Case subject');
    }

    // ── mandate.updated (active) ──────────────────────────────────────────────

    @IsTest
    static void testMandateUpdatedActive() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        acc.PayProv_PaymentMethodId__c = 'pm_mandate001';
        update acc;

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'mandate.updated',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'mandate_active001',
                        'status'         => 'active',
                        'payment_method' => 'pm_mandate001'
                    }
                }
            })
        );
        Test.stopTest();

        Account updAcc = [SELECT PayProv_MandateId__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('mandate_active001', updAcc.PayProv_MandateId__c, 'Mandate ID set from active mandate');
    }

    // ── mandate.updated (inactive — skipped) ─────────────────────────────────

    @IsTest
    static void testMandateUpdatedInactive() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        acc.PayProv_PaymentMethodId__c = 'pm_mandate002';
        acc.PayProv_MandateId__c = null;
        update acc;

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'mandate.updated',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'mandate_inactive001',
                        'status'         => 'inactive',
                        'payment_method' => 'pm_mandate002'
                    }
                }
            })
        );
        Test.stopTest();

        Account updAcc = [SELECT PayProv_MandateId__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals('mandate_inactive001', updAcc.PayProv_MandateId__c, 'Inactive mandate must not be stored');
    }

    // ── payment_intent.succeeded — status Collected, interaction unchanged ────

    @IsTest
    static void testPaymentIntentSucceeded() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'payment_intent.succeeded',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'pi_test001',
                        'status'         => 'succeeded',
                        'customer'       => 'cus_test001',
                        'payment_method' => 'pm_test002',
                        'metadata'       => new Map<String, Object>{ 'PaymentID' => pmt.Id }
                    }
                }
            })
        );
        Test.stopTest();

        Payment__c updPmt = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, Interaction_Status__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Collected', updPmt.Status__c,             'Payment status = Collected');
        System.assertEquals('Mail Sent', updPmt.Interaction_Status__c, 'Interaction status unchanged for payment_intent events');
    }

    // ── already-processed event is skipped ───────────────────────────────────

    @IsTest
    static void testAlreadyProcessedSkipped() {
        List<Payment__c> pmtList = Database.queryWithBinds(
            'SELECT Id, Status__c, Interaction_Status__c FROM Payment__c LIMIT 1',
            new Map<String, Object>(), AccessLevel.SYSTEM_MODE);
        Payment__c pmtBefore = pmtList[0];

        Test.startTest();
        Svc_StripeEventProcessor.process(new List<stripeGC__Stripe_Event__c>{
            new stripeGC__Stripe_Event__c(
                processed__c              = true,
                stripeGC__Event_Name__c   = 'setup_intent.succeeded',
                stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'object' => new Map<String, Object>{
                            'id'       => 'si_skip001',
                            'status'   => 'succeeded',
                            'customer' => 'cus_test001',
                            'metadata' => new Map<String, Object>{ 'PaymentID' => pmtBefore.Id }
                        }
                    }
                })
            )
        });
        Test.stopTest();

        Payment__c pmtAfter = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, Interaction_Status__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmtBefore.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals(pmtBefore.Status__c,             pmtAfter.Status__c,             'Status unchanged — event skipped');
        System.assertEquals(pmtBefore.Interaction_Status__c, pmtAfter.Interaction_Status__c, 'Interaction status unchanged — event skipped');
    }
}
