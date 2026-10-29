@IsTest(SeeAllData=false)
private class Test_Util_OrderConfirmation {

    // Account ready for Closed Won (rbu_Opportunity: debtor number, invoice + shipping address, bank details
    // for the default I8 payment method), a business entity for reseller 1 and a Webshop order with one line.
    @TestSetup
    static void makeData() {
        Account acc = new Account(
            Name = 'Order Confirmation Dealer',
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId(),
            BillingStreet = 'Teststraat 1', BillingPostalCode = '1234AB', BillingCity = 'Amsterdam', BillingCountryCode = 'NL',
            ShippingStreet = 'Magazijnweg 2', ShippingPostalCode = '5678CD', ShippingCity = 'Utrecht', ShippingCountryCode = 'NL',
            Reseller_Name__c = '1', Sales_Language__c = 'nl', FinancialDebtorNumber__c = 'TEST-ORDCONF-1',
            // the default payment method is I8, which needs bank details to be financial-ready
            Bank_Account__c = 'Order Confirmation Dealer', Bank_Account_Number__c = 'NL91ABNA0417164300'
        );
        acc.InvoiceAddress__Street__s = 'Teststraat 1';
        acc.InvoiceAddress__PostalCode__s = '1234AB';
        acc.InvoiceAddress__City__s = 'Amsterdam';
        acc.InvoiceAddress__CountryCode__s = 'NL';
        insert acc;

        insert new Contact(AccountId = acc.Id, FirstName = 'Order', LastName = 'Contact',
            Email = 'order.contact@mvsc.invalid.test', Language__c = 'NL');

        insert new Business_Entities__c(Name = 'Netherlands', Reseller__c = '1', Email_Sales__c = 'sales@mvsc.invalid.test');

        Product2 prod = new Product2(Name = 'Order Confirmation Product', ProductCode = 'OC-001', IsActive = true);
        insert prod;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = prod.Id, UnitPrice = 10, IsActive = true);
    }

    private static Opportunity makeOrder() {
        Account acc = [SELECT Id, CurrencyIsoCode FROM Account WHERE Name = 'Order Confirmation Dealer' LIMIT 1];
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
        Opportunity opp = new Opportunity(
            AccountId = acc.Id, Name = 'Order', StageName = 'Webshop', CloseDate = Date.today().addDays(30),
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Webshop').getRecordTypeId(),
            Sales_Contact__c = con.Id
        );
        insert opp;
        // rbc_Opportunity resolves its own pricebook on create; use the standard one for the test line.
        update new Opportunity(Id = opp.Id, Pricebook2Id = Test.getStandardPricebookId(), CurrencyIsoCode = acc.CurrencyIsoCode);
        PricebookEntry pbe = [SELECT Id, Product2Id FROM PricebookEntry WHERE Product2.ProductCode = 'OC-001' AND Pricebook2Id = :Test.getStandardPricebookId() AND CurrencyIsoCode = :acc.CurrencyIsoCode LIMIT 1];
        insert new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = pbe.Id, Quantity = 3, UnitPrice = 10);
        return opp;
    }

    @IsTest
    static void testClosedWon_stampsProcessedAndSendsConfirmation() {
        Opportunity opp = makeOrder();

        // Order_Process__e is published after commit: in a test that is at stopTest, then deliver() runs it.
        Test.startTest();
        update new Opportunity(Id = opp.Id, StageName = 'Closed Won');
        Test.stopTest();
        Test.getEventBus().deliver();

        Opportunity after = [SELECT Order_Processed_At__c, Order_Confirmation_Sent__c, Order_Process_Error__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, after.Order_Processed_At__c, 'Closed Won stamps the processing moment');
        System.assertEquals(null, after.Order_Process_Error__c, 'No error expected: ' + after.Order_Process_Error__c);
        System.assertNotEquals(null, after.Order_Confirmation_Sent__c, 'The confirmation is sent on Closed Won; error ' + after.Order_Process_Error__c);
    }

    @IsTest
    static void testProcessButton_closesOpenOrder_andResendsWonOrder() {
        Opportunity opp = makeOrder();

        Test.startTest();
        List<String> first = Util_OrderConfirmation.processOrResend(new List<Id>{ opp.Id });
        Test.stopTest();
        System.assert(first[0].contains('Closed Won'), first[0]);

        // process -> Closed Won, which publishes send (and starts order creation, which fails here - the test
        // account has no Exact id - and puts the stage back on Administration; existing behaviour).
        Test.getEventBus().deliver();
        Test.getEventBus().deliver();
        Opportunity after = [SELECT Order_Processed_At__c, Order_Confirmation_Sent__c, Order_Process_Error__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, after.Order_Processed_At__c, 'The button set the order to Closed Won; error ' + after.Order_Process_Error__c);
        System.assertNotEquals(null, after.Order_Confirmation_Sent__c, 'The confirmation follows the processing; error ' + after.Order_Process_Error__c);

        update new Opportunity(Id = opp.Id, StageName = 'Closed Won');
        List<String> second = Util_OrderConfirmation.processOrResend(new List<Id>{ opp.Id });
        System.assert(second[0].contains('sent again'), second[0]);
    }

    @IsTest
    static void testClosedWon_stampsShippingDay_andTemplateRenders() {
        Opportunity opp = makeOrder();
        update new Opportunity(Id = opp.Id, Use_ShippingAddress__c = true,
            ShippingAddress__Street__s = 'Afleverstraat 9', ShippingAddress__PostalCode__s = '9999ZZ',
            ShippingAddress__City__s = 'Groningen', ShippingAddress__CountryCode__s = 'NL');

        update new Opportunity(Id = opp.Id, StageName = 'Closed Won');

        Opportunity after = [SELECT Order_Shipping_Date__c, Order_Shipping_Cutoff__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, after.Order_Shipping_Date__c, 'Closed Won stamps the shipping day');
        System.assertEquals('15:00', after.Order_Shipping_Cutoff__c, 'Default cut-off');

        Contact con = [SELECT Id FROM Contact WHERE Email = 'order.contact@mvsc.invalid.test' LIMIT 1];
        Id templateId = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :Util_OrderConfirmation.TEMPLATE_NAME].Id;
        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templateId, con.Id, opp.Id);
        String html = rendered.getHtmlBody();
        System.assert(html.contains('Order Confirmation Product'), 'The order line is listed');
        System.assert(html.contains('Afleverstraat 9'), 'Use_ShippingAddress__c = the opportunity address');
        System.assert(!html.contains('10.00') && !html.contains('10,00'), 'No prices in the confirmation');
        System.assert(rendered.getSubject().startsWith('Bedankt voor uw bestelling'), 'Dutch for a contact with Language__c NL: ' + rendered.getSubject());
    }

    // 2026-11-02 is a Monday; November = CET (UTC+1). No business hours = Monday to Friday, Europe/Amsterdam.
    @IsTest
    static void testShippingDay_cutoffAndWeekend() {
        Time cut = Time.newInstance(15, 0, 0, 0);
        Util_OrderConfirmation.ShippingDay mondayMorning = Util_OrderConfirmation.shippingDay(Datetime.newInstanceGmt(2026, 11, 2, 9, 0, 0), null, cut);
        System.assert(mondayMorning.sameDay, 'Monday 10:00 = shipped the same day');
        System.assertEquals(Date.newInstance(2026, 11, 2), mondayMorning.day);

        Util_OrderConfirmation.ShippingDay mondayLate = Util_OrderConfirmation.shippingDay(Datetime.newInstanceGmt(2026, 11, 2, 15, 30, 0), null, cut);
        System.assert(!mondayLate.sameDay, 'Monday 16:30 = next working day');
        System.assertEquals(Date.newInstance(2026, 11, 3), mondayLate.day);

        Util_OrderConfirmation.ShippingDay fridayLate = Util_OrderConfirmation.shippingDay(Datetime.newInstanceGmt(2026, 11, 6, 15, 30, 0), null, cut);
        System.assertEquals(Date.newInstance(2026, 11, 9), fridayLate.day, 'Friday after the cut-off = Monday');

        Util_OrderConfirmation.ShippingDay saturday = Util_OrderConfirmation.shippingDay(Datetime.newInstanceGmt(2026, 11, 7, 9, 0, 0), null, cut);
        System.assert(!saturday.sameDay, 'Saturday is not a working day');
        System.assertEquals(Date.newInstance(2026, 11, 9), saturday.day, 'Saturday morning = Monday');

        // London: 14:30 UTC = 14:30 local (before 15:00), but 15:30 in Amsterdam.
        Util_OrderConfirmation.ShippingDay unknownHours = Util_OrderConfirmation.shippingDay(Datetime.newInstanceGmt(2026, 11, 2, 14, 30, 0), 'No Such Hours', cut);
        System.assert(!unknownHours.sameDay, 'Unknown business hours fall back to Europe/Amsterdam (15:30 there)');
    }

    @IsTest
    static void testPickSender_prefersFirstVerifiedCandidate() {
        Id billing = '0D2000000000001';
        Map<String, Id> verified = new Map<String, Id>{ 'billing@x.test' => billing };
        System.assertEquals(billing, Util_OrderConfirmation.pickSender(verified, new List<String>{ 'Sales@x.test', 'Billing@X.test', 'last@x.test' }),
            'Sales is not verified, so the billing address is used');
        System.assertEquals(null, Util_OrderConfirmation.pickSender(verified, new List<String>{ null, 'other@x.test' }), 'Nothing verified');
    }
}
