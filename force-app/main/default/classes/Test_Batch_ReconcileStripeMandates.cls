@IsTest
private class Test_Batch_ReconcileStripeMandates {

    @TestSetup
    static void makeData() {
        // rbb_Account wipes PayProv_* ids whenever they're already populated on a brand-new
        // Account (it assumes a fresh Account must establish its own Stripe linkage) - so these
        // fields must be set via a separate update, same as Test_Svc_StripeEventProcessor's fixture.
        Account orphan = Test_Data.createAccount('Reconcile Orphan BV', '9031', 'B2B', false);
        insert orphan;
        orphan.PayProv_CustomerId__c      = 'cus_orphan001';
        orphan.PayProv_PaymentMethodId__c = 'pm_orphan001';
        update orphan;

        Account alreadyCorrect = Test_Data.createAccount('Reconcile Correct BV', '9032', 'B2B', false);
        insert alreadyCorrect;
        alreadyCorrect.PayProv_CustomerId__c      = 'cus_correct001';
        alreadyCorrect.PayProv_PaymentMethodId__c = 'pm_correct001';
        alreadyCorrect.PayProv_MandateId__c       = 'mandate_correct001';
        update alreadyCorrect;

        Database.insert(new Subscription25__Schedulable_Class__c(
            Name = 'Batch_ReconcileStripeMandates',
            Subscription25__Unique_Name__c = 'Batch_ReconcileStripeMandates'
        ), AccessLevel.SYSTEM_MODE);
    }

    // ── orphaned mandate.updated event gets backfilled onto the matching Account ──
    @IsTest
    static void testBackfillsOrphanedMandate() {
        insert new stripeGC__Stripe_Event__c(
            Type__c            = 'mandate.updated',
            Status__c          = 'active',
            PaymentMethodId__c = 'pm_orphan001',
            MandateId__c       = 'mandate_orphan001',
            Processed__c       = true
        );

        Test.startTest();
        Database.executeBatch(new Batch_ReconcileStripeMandates());
        Test.stopTest();

        Account updated = [SELECT PayProv_MandateId__c FROM Account WHERE PayProv_PaymentMethodId__c = 'pm_orphan001'];
        System.assertEquals('mandate_orphan001', updated.PayProv_MandateId__c, 'Mandate ID backfilled onto the Account');
    }

    // ── Account already holds the correct mandate — idempotent, no error ──
    @IsTest
    static void testAlreadyCorrectIsNoOp() {
        insert new stripeGC__Stripe_Event__c(
            Type__c            = 'mandate.updated',
            Status__c          = 'active',
            PaymentMethodId__c = 'pm_correct001',
            MandateId__c       = 'mandate_correct001',
            Processed__c       = true
        );

        Test.startTest();
        Database.executeBatch(new Batch_ReconcileStripeMandates());
        Test.stopTest();

        Account updated = [SELECT PayProv_MandateId__c FROM Account WHERE PayProv_PaymentMethodId__c = 'pm_correct001'];
        System.assertEquals('mandate_correct001', updated.PayProv_MandateId__c, 'Mandate ID unchanged');
    }

    // ── no Account has this payment method yet — event is retried, not lost ──
    @IsTest
    static void testUnresolvedEventIncrementsRetries() {
        stripeGC__Stripe_Event__c evt = new stripeGC__Stripe_Event__c(
            Type__c            = 'mandate.updated',
            Status__c          = 'active',
            PaymentMethodId__c = 'pm_unknown001',
            MandateId__c       = 'mandate_unknown001',
            Processed__c       = true
        );
        insert evt;

        Test.startTest();
        Database.executeBatch(new Batch_ReconcileStripeMandates());
        Test.stopTest();

        stripeGC__Stripe_Event__c updated = [SELECT Retries__c FROM stripeGC__Stripe_Event__c WHERE Id = :evt.Id];
        System.assertEquals(1, updated.Retries__c, 'Retry count incremented when no Account matches yet');
    }

    // ── inactive mandate.updated events are never picked up ──
    @IsTest
    static void testInactiveMandateIgnored() {
        insert new stripeGC__Stripe_Event__c(
            Type__c            = 'mandate.updated',
            Status__c          = 'inactive',
            PaymentMethodId__c = 'pm_orphan001',
            MandateId__c       = 'mandate_should_not_apply',
            Processed__c       = true
        );

        Test.startTest();
        Database.executeBatch(new Batch_ReconcileStripeMandates());
        Test.stopTest();

        Account updated = [SELECT PayProv_MandateId__c FROM Account WHERE PayProv_PaymentMethodId__c = 'pm_orphan001'];
        System.assertNotEquals('mandate_should_not_apply', updated.PayProv_MandateId__c, 'Inactive mandate must not be applied');
    }

    // ── finishBatch hands off to the dispatcher via Util_JobDispatcher.startNext, and is a
    // harmless no-op as the last (or only) step of a round ──
    @IsTest
    static void testFinishBatchIsNoOpAsLastDispatcherStep() {
        Util_JobDispatcher.testSteps = new List<JobDispatcherStep__mdt>{
            new JobDispatcherStep__mdt(Dispatcher__c = 'TestDispatcher', ApexClass__c = 'Batch_ReconcileStripeMandates', Order__c = 40, IsActive__c = true)
        };

        Batch_ReconcileStripeMandates batch = new Batch_ReconcileStripeMandates();
        batch.setDispatcher('TestDispatcher');

        Test.startTest();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'Batch_ReconcileStripeMandates'],
            'Only the one run - last step of the dispatcher chain starts nothing further');
    }
}
