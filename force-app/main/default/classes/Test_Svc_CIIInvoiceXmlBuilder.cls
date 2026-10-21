@isTest
private class Test_Svc_CIIInvoiceXmlBuilder {

    @IsTest
    private static void test_buildXml(){
        VAT_Code__c vatCode = new VAT_Code__c(
            Internal_Code__c = 'TESTVAT',
            UNCL5305_Category__c = 'S',
            Percentage__c = 21
        );
        Database.insert(vatCode, AccessLevel.SYSTEM_MODE);

        Subscription25__Administration__c adm = Test_Data.createAdministration(false);
        adm.Subscription25__Billing_Name__c = 'Test Administration BV';
        adm.Subscription25__Billing_Street__c = 'Teststraat 1';
        adm.Subscription25__Billing_City__c = 'Amsterdam';
        adm.Subscription25__Billing_Postal_Code__c = '1000 AA';
        adm.Country_Code__c = 'NL';
        adm.CurrencyIsoCode = 'EUR';
        adm.Subscription25__VAT_Number__c = 'NL123456789B01';
        adm.Subscription25__Chamber_Of_Commerce_Number__c = '12345678';
        Database.insert(adm, AccessLevel.SYSTEM_MODE);

        Account acc = Test_Data.createAccount('CustomerNL', '12345', 'B2B', true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest', '12.MiTest', '1-sv-1', 'Subscription', true);
        prd.QuantityUnitOfMeasure = 'Piece(s)';
        Database.update(prd, AccessLevel.SYSTEM_MODE);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('TestVAT', 21, true, true);
        Subscription25__Administration_Product__c apr = Test_Data.createAdministrationProduct(adm.Id, prd.Id, vatRate.Id, true);

        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', false);
        inv.Subscription25__VAT_Number__c = 'NL987654321B01';
        inv.Cost_Center_invoicing__c = 'CC-001';
        Database.insert(inv, AccessLevel.SYSTEM_MODE);

        Order ord = Test_Data.createOrder(acc.Id, adm.Id, Date.today().addDays(-14), false);
        ord.Subscription25__Invoice__c = inv.Id;
        Database.insert(ord, AccessLevel.SYSTEM_MODE);

        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, false);
        ori.Product2Id = prd.Id;
        ori.Subscription25__VAT_Code__c = 'TESTVAT';
        ori.VAT_Code__c = vatCode.Id; // rbb_OrderItem fills this too, but prod validates against the still-active old flow version
        Database.insert(ori, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(inv.Id);
        Test.stopTest();

        System.assertNotEquals(null, xml, 'Expected XML to be generated');

        Dom.Document doc = new Dom.Document();
        doc.load(xml); // throws if not well-formed XML

        System.assert(xml.contains(inv.Subscription25__Invoice_Number__c == null ? '' : inv.Subscription25__Invoice_Number__c), 'Expected invoice number in XML');
        System.assert(xml.contains('EUR'), 'Expected currency code in XML');
        System.assert(xml.contains('NL'), 'Expected country code in XML');
        System.assert(xml.contains('>S<'), 'Expected VAT category code S in XML');
        System.assert(xml.contains('urn:cen.eu:en16931:2017'), 'Expected EN16931 guideline ID in XML');
    }

    // payment means scheme of a pr invoice: the account's saved method, else the business entity's direct debit method
    @IsTest
    private static void test_paymentMethodType(){
        Account withType = Test_Data.createAccount('CII Card', (String) null, 'B2C', true);
        Database.update(new Account(Id = withType.Id, PayProv_PaymentMethodType__c = 'card'), AccessLevel.SYSTEM_MODE);
        Account withoutType = Test_Data.createAccount('CII Entity', (String) null, 'B2C', true);
        Database.insert(new Business_Entities__c(Name = 'UK Test', Reseller__c = '6', PayProv_DirectDebit_PaymentMethod__c = 'bacs_debit'), AccessLevel.SYSTEM_MODE);

        Test.startTest();
        String fromAccount = Svc_CIIInvoiceXmlBuilder.paymentMethodType(withType.Id, '6');
        String fromEntity = Svc_CIIInvoiceXmlBuilder.paymentMethodType(withoutType.Id, '6');
        String none = Svc_CIIInvoiceXmlBuilder.paymentMethodType(withoutType.Id, '4');
        Test.stopTest();

        System.assertEquals('card', fromAccount, 'Saved method on the account wins');
        System.assertEquals('bacs_debit', fromEntity, 'Business entity direct debit method');
        System.assertEquals(null, none, 'No account type, no business entity');
    }
}
