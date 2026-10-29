@IsTest
private class Test_Svc_InvoicePaymentBlock {

    @TestSetup
    static void makeData() {
        Subscription25__Administration__c admin = Test_Data.createAdministration(false);
        admin.Subscription25__Invoice_Email_Template__c = 'InvoiceNL';
        admin.Acceptance_Environment_Available__c = true;
        Database.insert(admin, AccessLevel.SYSTEM_MODE);
        // inserting the Administration already creates its Business Entity (reseller 1), which rbb_Payment stamps
        List<Business_Entities__c> entities = [SELECT Id FROM Business_Entities__c WHERE Reseller__c = '1'];
        if (entities.isEmpty()) entities.add(new Business_Entities__c(Name = 'Netherlands (test)', Reseller__c = '1'));
        for (Business_Entities__c be : entities) be.CustomerHub_URL__c = 'https://hub.example.com/hub';
        Database.upsert(entities, AccessLevel.SYSTEM_MODE);

        Account acc = Test_Data.createAccount('Block Test BV', '9061', 'B2B', true);
        Contact con = Test_Data.createContact(acc.Id, 'Block', '0612345678', 'block@example.com', true);
        Subscription25__Invoice__c inv = Test_Data.createInvoice(admin.Id, acc.Id, 'DRAFT', true);
        Database.insert(new Payment__c(
            Account__c        = acc.Id,
            Administration__c = admin.Id,
            Invoice__c        = inv.Id,
            Contact__c        = con.Id,
            Reseller__c       = '1',
            externalId__c     = 'TOKEN-BLOCK',
            Status__c         = 'New',
            Amount_Gross__c   = 13.50,
            Request_Date__c   = Date.today()
        ), AccessLevel.SYSTEM_MODE);
    }

    static Svc_InvoicePaymentBlock.Request req(Id paymentId, String action) {
        Svc_InvoicePaymentBlock.Request r = new Svc_InvoicePaymentBlock.Request();
        r.paymentId = paymentId;
        r.action = action;
        return r;
    }

    static String block() {
        return [SELECT Payment_Setup_Block__c FROM Subscription25__Invoice__c LIMIT 1].Payment_Setup_Block__c;
    }

    @IsTest
    static void testLanguage() {
        System.assertEquals('NL', Svc_InvoicePaymentBlock.language('InvoiceNL'));
        System.assertEquals('DE', Svc_InvoicePaymentBlock.language('InvoiceDE'));
        System.assertEquals('EN', Svc_InvoicePaymentBlock.language('InvoiceUK'));
        System.assertEquals('EN', Svc_InvoicePaymentBlock.language(null));
    }

    @IsTest
    static void testFillAndClear() {
        Payment__c p = [SELECT Id, Setup_URL__c FROM Payment__c LIMIT 1];
        System.assertEquals('https://hub.example.com/hub/payment?token=TOKEN-BLOCK', p.Setup_URL__c, 'Setup_URL__c = Business Entity Customer Hub URL + token');

        Test.startTest();
        List<Svc_InvoicePaymentBlock.Result> filled = Svc_InvoicePaymentBlock.run(new List<Svc_InvoicePaymentBlock.Request>{ req(p.Id, Svc_InvoicePaymentBlock.FILL) });
        System.assertEquals(true, filled[0].done);
        String html = block();
        System.assert(html.contains('https://hub.example.com/hub/payment?token=TOKEN-BLOCK'), html);
        System.assert(html.contains('betaalvoorkeur'), 'NL administration → NL block: ' + html);
        System.assert(!html.containsIgnoreCase('<body'), 'wrapper stripped: ' + html);

        List<Svc_InvoicePaymentBlock.Result> cleared = Svc_InvoicePaymentBlock.run(new List<Svc_InvoicePaymentBlock.Request>{ req(p.Id, Svc_InvoicePaymentBlock.CLEAR) });
        Test.stopTest();
        System.assertEquals(true, cleared[0].done);
        System.assert(String.isBlank(block()));
    }

    @IsTest
    static void testNoLinkNoBlock() {
        Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
        p.externalId__c = null;
        Database.update(p, AccessLevel.SYSTEM_MODE);
        List<Svc_InvoicePaymentBlock.Result> res = Svc_InvoicePaymentBlock.run(new List<Svc_InvoicePaymentBlock.Request>{ req(p.Id, Svc_InvoicePaymentBlock.FILL), req(null, Svc_InvoicePaymentBlock.FILL) });
        System.assertEquals(false, res[0].done, 'without a token there is no link to put in the invoice email');
        System.assertEquals(false, res[1].done);
        System.assert(String.isBlank(block()));
    }
}
