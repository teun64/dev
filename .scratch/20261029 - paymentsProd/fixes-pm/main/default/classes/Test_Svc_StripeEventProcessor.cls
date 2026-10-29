@IsTest
private class Test_Svc_StripeEventProcessor {

    // ── Test data ─────────────────────────────────────────────────────────────

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);

        // Name/number and Contact name deliberately distinct from Test_Ctrl_Payment's
        // 'ACME BV'/'9001'/'Jan Betaler' fixture - prod's active Contact/Account Duplicate
        // Rules block the insert when multiple test classes create the same-named
        // Account/Contact in the same deploy job. Sandboxes don't enforce this, so it never
        // surfaced until a real prod deploy - confirmed 2026-08-27.
        Account acc = Test_Data.createAccount('ACME Stripe BV', '9022', 'B2B', false);
        insert acc;
        acc.PayProv_CustomerId__c = 'cus_test001';
        update acc;

        Contact c = new Contact(
            AccountId = acc.Id,
            FirstName = 'Jan',
            LastName  = 'StripeBetaler',
            Email     = 'jan.stripe@acme.nl'
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
            Interaction_Status__c = 'Mail Sent'
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
            'SELECT Status__c, Interaction_Status__c, Processed_Date__c, PayProv_SetupIntentId__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];

        System.assertEquals('pm_test001',     updAcc.PayProv_PaymentMethodId__c,  'Payment method set on account');
        System.assertEquals('mandate_test001', updAcc.PayProv_MandateId__c,        'Mandate ID set on account');
        System.assertEquals('Setup',          updPmt.Status__c,                   'Payment status = Setup');
        System.assertEquals('Request Processed by Customer', updPmt.Interaction_Status__c, 'Interaction status updated');
        System.assertEquals(Date.today(),     updPmt.Processed_Date__c,           'Processed date = today');
        System.assertEquals('si_test001',     updPmt.PayProv_SetupIntentId__c,            'Setup intent ID stored on payment');
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

    // ── payment_intent.payment_failed with authentication_required: waits for the customer, no Case ──

    @IsTest
    static void testPaymentFailedAuthenticationRequired() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'payment_intent.payment_failed',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'       => 'pi_auth001',
                        'status'   => 'requires_payment_method',
                        'customer' => 'cus_test001',
                        'metadata' => new Map<String, Object>{ 'PaymentID' => pmt.Id },
                        'last_payment_error' => new Map<String, Object>{
                            'code'    => 'authentication_required',
                            'message' => 'This payment requires authentication.'
                        }
                    }
                }
            })
        );
        Test.stopTest();

        Payment__c updPmt = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, PayProv_PaymentIntentId__c, externalId__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Action Required', updPmt.Status__c, 'Waits for the customer to authenticate');
        System.assertEquals('pi_auth001', updPmt.PayProv_PaymentIntentId__c, 'Intent the customer confirms is stored');
        System.assertEquals('tok_test', updPmt.externalId__c, 'Existing payment link token kept');
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Subject LIKE '%failure%'], 'No failure Case while the customer can still confirm');
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

    // ── mandate.updated before the intent event that stores the payment method (BACS, seen in acc) ──

    @IsTest
    static void testMandateBeforePaymentMethodIsLinkedLater() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'mandate.updated',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'mandate_early001',
                        'status'         => 'active',
                        'payment_method' => 'pm_bacs001'
                    }
                }
            })
        );

        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'payment_intent.processing',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'pi_bacs001',
                        'status'         => 'processing',
                        'customer'       => 'cus_test001',
                        'payment_method' => 'pm_bacs001',
                        'metadata'       => new Map<String, Object>{ 'PaymentID' => pmt.Id }
                    }
                }
            })
        );
        Test.stopTest();

        Account updAcc = [SELECT PayProv_PaymentMethodId__c, PayProv_MandateId__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('pm_bacs001',       updAcc.PayProv_PaymentMethodId__c, 'Payment method from the intent event');
        System.assertEquals('mandate_early001', updAcc.PayProv_MandateId__c,       'Earlier mandate linked once the payment method is known');
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

    // ── payment_intent.succeeded — status Paid, interaction unchanged ────────

    // ── payment_intent.processing delivered after the intent's payment_failed (out of order, seen in acc) ──
    @IsTest
    static void testLateProcessingDoesNotUndoFailed() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];
        Test.startTest();
        for (String evt : new List<String>{ 'payment_intent.payment_failed', 'payment_intent.processing' }) {
            insert new stripeGC__Stripe_Event__c(
                stripeGC__Event_Name__c   = evt,
                stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'object' => new Map<String, Object>{
                            'id'                 => 'pi_late001',
                            'status'             => evt.endsWith('processing') ? 'processing' : 'requires_payment_method',
                            'customer'           => 'cus_test001',
                            'payment_method'     => 'pm_late001',
                            'metadata'           => new Map<String, Object>{ 'PaymentID' => pmt.Id },
                            'last_payment_error' => evt.endsWith('processing') ? null : new Map<String, Object>{ 'code' => 'insufficient_funds', 'message' => 'insufficient funds' }
                        }
                    }
                })
            );
        }
        Test.stopTest();

        Payment__c upd = (Payment__c) Database.queryWithBinds('SELECT Status__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Failed', upd.Status__c, 'the late processing event of the same intent is ignored');
    }

    // ── the same failure delivered twice (Stripe retry / reconcile): one open Case, the repeat is appended ──
    @IsTest
    static void testRepeatedFailureOneCase() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];
        Test.startTest();
        for (Integer i = 0; i < 2; i++) {
            insert new stripeGC__Stripe_Event__c(
                stripeGC__Event_Name__c   = 'payment_intent.payment_failed',
                stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                    'data' => new Map<String, Object>{
                        'object' => new Map<String, Object>{
                            'id' => 'pi_rep001', 'status' => 'requires_payment_method', 'customer' => 'cus_test001',
                            'payment_method' => 'pm_rep001', 'metadata' => new Map<String, Object>{ 'PaymentID' => pmt.Id },
                            'last_payment_error' => new Map<String, Object>{ 'code' => 'insufficient_funds', 'message' => 'insufficient funds' }
                        }
                    }
                })
            );
        }
        Test.stopTest();

        List<Case> cases = [SELECT Description FROM Case WHERE Subject LIKE '%failure%'];
        System.assertEquals(1, cases.size(), 'one open Case for the repeated failure');
        System.assert(cases[0].Description.contains(' again: '), cases[0].Description);
    }

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
            'SELECT Status__c, Interaction_Status__c, PayProv_PaymentIntentId__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Paid',        updPmt.Status__c,             'Payment status = Paid');
        System.assertEquals('Request Processed by Customer', updPmt.Interaction_Status__c,
            'BACS payments complete via payment_intent.succeeded (no separate SetupIntent step) - the escalation flow only checks Interaction_Status__c, so this must flip here too or a completed BACS payment keeps getting reminder emails');
        System.assertEquals('pi_test001', updPmt.PayProv_PaymentIntentId__c,    'Payment intent ID stored on payment');
    }

    // ── payment_intent.payment_failed (BACS reversal) — Reversed + Case ────────

    @IsTest
    static void testPaymentIntentReversed() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        insert new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = 'payment_intent.payment_failed',
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'             => 'pi_rev001',
                        'status'         => 'requires_payment_method',
                        'customer'       => 'cus_test001',
                        'payment_method' => 'pm_bacs001',
                        'metadata'       => new Map<String, Object>{ 'PaymentID' => pmt.Id },
                        'last_payment_error' => new Map<String, Object>{
                            'code'    => 'payment_reversed',
                            'message' => 'The payment was reversed by the bank.'
                        }
                    }
                }
            })
        );
        Test.stopTest();

        Payment__c updPmt = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, PayProv_PaymentIntentId__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('Reversed',  updPmt.Status__c,          'Payment status = Reversed after BACS reversal');
        System.assertEquals('pi_rev001', updPmt.PayProv_PaymentIntentId__c, 'Payment intent ID stored on reversal');

        List<Case> cases = [SELECT Subject FROM Case];
        System.assertEquals(1, cases.size(), 'One reversal case created');
        System.assert(cases[0].Subject.contains('reversal'), 'Case subject contains reversal');
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

    // ── a second PaymentIntent charged for a payment that is already debiting → Case, payment untouched ──

    private static stripeGC__Stripe_Event__c piEvent(String eventName, String intentId, String status, Id paymentId) {
        return new stripeGC__Stripe_Event__c(
            stripeGC__Event_Name__c   = eventName,
            stripeGC__Request_Body__c = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'       => intentId,
                        'status'   => status,
                        'customer' => 'cus_test001',
                        'metadata' => new Map<String, Object>{ 'PaymentID' => paymentId }
                    }
                }
            })
        );
    }

    @IsTest
    static void testDuplicateChargeCreatesCase() {
        Payment__c pmt = [SELECT Id, Name FROM Payment__c LIMIT 1];
        Database.update(new Payment__c(Id = pmt.Id, Status__c = 'Processing', PayProv_PaymentIntentId__c = 'pi_first001'), AccessLevel.SYSTEM_MODE);

        Test.startTest();
        insert piEvent('payment_intent.processing', 'pi_dup001', 'processing', pmt.Id);
        Test.stopTest();

        Payment__c upd = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, PayProv_PaymentIntentId__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('pi_first001', upd.PayProv_PaymentIntentId__c, 'Payment stays bound to its own intent');
        System.assertEquals('Processing', upd.Status__c);
        List<Case> cases = [SELECT Subject, Description FROM Case WHERE Subject LIKE 'Direct Debit charged twice%'];
        System.assertEquals(1, cases.size(), 'Duplicate debit flagged');
        System.assert(cases[0].Description.contains('pi_dup001'), cases[0].Description);
    }

    // ── an open (never debited) intent is replaced by a newer one without a Case ──

    @IsTest
    static void testNewerIntentReplacesOpenIntent() {
        Payment__c pmt = [SELECT Id FROM Payment__c LIMIT 1];
        Database.update(new Payment__c(Id = pmt.Id, Status__c = 'Setup', PayProv_PaymentIntentId__c = 'pi_open001'), AccessLevel.SYSTEM_MODE);

        Test.startTest();
        insert piEvent('payment_intent.processing', 'pi_batch001', 'processing', pmt.Id);
        Test.stopTest();

        Payment__c upd = (Payment__c) Database.queryWithBinds(
            'SELECT Status__c, PayProv_PaymentIntentId__c, Interaction_Status__c FROM Payment__c WHERE Id = :pmtId',
            new Map<String, Object>{ 'pmtId' => pmt.Id }, AccessLevel.SYSTEM_MODE)[0];
        System.assertEquals('pi_batch001', upd.PayProv_PaymentIntentId__c);
        System.assertEquals('Processing', upd.Status__c);
        System.assertEquals('Request Processed by Customer', upd.Interaction_Status__c, 'Debit started → reminders stop');
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Subject LIKE 'Direct Debit charged twice%']);
    }
}
