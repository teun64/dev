@isTest
private class Test_Svc_CIIInvoiceXmlBuilder {

    @IsTest
    private static void test_buildXml(){
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
        Database.insert(new Subscription25__VAT_Code__c(
            Subscription25__Administration__c = adm.Id, Subscription25__VATRate__c = vatRate.Id,
            Subscription25__VAT_Code__c = 'TESTVAT', UNCL5305_Category__c = 'S'
        ), AccessLevel.SYSTEM_MODE);
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

    // ---- seller from the business entity, buyer reference chain, period + delivery ----------

    private static Id createInvoiceFixture(String costCenter, String paymentRemark, Date lineStart, Date lineEnd){
        Subscription25__Administration__c adm = Test_Data.createAdministration(false);
        adm.Subscription25__Billing_Name__c = 'Admin Fallback BV';
        adm.Subscription25__Billing_Street__c = 'Fallbackstraat 1';
        adm.Subscription25__Billing_City__c = 'Amsterdam';
        adm.Subscription25__Billing_Postal_Code__c = '1000 AA';
        adm.Country_Code__c = 'NL';
        adm.CurrencyIsoCode = 'EUR';
        adm.Subscription25__VAT_Number__c = 'NL000000000B01';
        Database.insert(adm, AccessLevel.SYSTEM_MODE);

        Account acc = Test_Data.createAccount('CustomerCII', '54321', 'B2B', true);
        Database.update(new Account(Id = acc.Id, Cost_Center_invoicing__c = costCenter, Invoice_Payment_Remark__c = paymentRemark, Reseller_Name__c = '1'), AccessLevel.SYSTEM_MODE);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest4', '12.MiTest4', '1-sv-4', 'Subscription', true);
        prd.QuantityUnitOfMeasure = 'Piece(s)';
        Database.update(prd, AccessLevel.SYSTEM_MODE);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vatRate = Test_Data.createVATRate('TestVAT4', 21, true, true);
        Database.insert(new Subscription25__VAT_Code__c(
            Subscription25__Administration__c = adm.Id, Subscription25__VATRate__c = vatRate.Id,
            Subscription25__VAT_Code__c = 'TESTVAT4', UNCL5305_Category__c = 'S'
        ), AccessLevel.SYSTEM_MODE);
        Subscription25__Administration_Product__c apr = Test_Data.createAdministrationProduct(adm.Id, prd.Id, vatRate.Id, true);

        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', false);
        Database.insert(inv, AccessLevel.SYSTEM_MODE);

        Order ord = Test_Data.createOrder(acc.Id, adm.Id, Date.today().addDays(-14), false);
        ord.Subscription25__Invoice__c = inv.Id;
        if (lineEnd != null) {
            ord.EndDate = lineEnd;
        }
        Database.insert(ord, AccessLevel.SYSTEM_MODE);

        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, false);
        ori.Product2Id = prd.Id;
        ori.Subscription25__VAT_Code__c = 'TESTVAT4';
        ori.ServiceDate = lineStart;
        ori.EndDate = lineEnd;
        Database.insert(ori, AccessLevel.SYSTEM_MODE);
        return inv.Id;
    }

    @IsTest
    private static void test_unitCodeFallsBackOnCostType(){
        Map<String, String> m = new Map<String, String>{ 'Month(s)' => 'MON', 'Piece(s)' => 'C62', 'Hour(s)' => 'HUR' };
        System.assertEquals('HUR', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode('Hour(s)', 'RECURRING', m), 'an explicit unit wins');
        System.assertEquals('MON', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode('Month(s)', 'NON_RECURRING', m), 'explicit Month(s) on a prepaid product stays');
        System.assertEquals('C62', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode(null, 'NON_RECURRING', m), 'activation fee without unit = piece');
        System.assertEquals('C62', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode(null, null, m), 'nothing known = piece');
        System.assertEquals('MON', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode(null, 'RECURRING', m), 'recurring without unit = month');
        System.assertEquals('MON', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode('12', 'RECURRING', m), 'junk unit value falls back on the cost type');
        System.assertEquals('DAY', Svc_CIIInvoiceXmlBuilder.resolveUneceUnitCode('', 'RECURRING_DAILY', m), 'daily price = day');
    }

    @IsTest
    private static void test_sellerComesFromBusinessEntity(){
        Id invId = createInvoiceFixture(null, null, null, null);
        String reseller = [SELECT Reseller__c FROM Subscription25__Invoice__c WHERE Id = :invId].Reseller__c;
        System.assertEquals('1', reseller, 'Invoice reseller comes from the account');
        List<Business_Entities__c> existing = [SELECT Id FROM Business_Entities__c WHERE Reseller__c = :reseller];
        Business_Entities__c entity = existing.isEmpty() ? new Business_Entities__c(Name = 'CII Test', Reseller__c = reseller) : existing[0];
        entity.Business_Name__c = 'Entity GmbH';
        entity.VAT_Number__c = 'DE111111111';
        entity.CoC_Number__c = 'HRB 1';
        entity.IBAN__c = 'DE89370400440532013000';
        entity.BIC__c = 'COBADEFFXXX';
        entity.Phone__c = '+49 30 123';
        entity.Email_Finance__c = 'finance@example.com';
        entity.Creditor_Identifier__c = 'DE89ZZZ00000557087';
        Database.upsert(entity, AccessLevel.SYSTEM_MODE);
        System.assertEquals(1, [SELECT COUNT() FROM Business_Entities__c WHERE Reseller__c = :reseller], 'One entity per reseller');

        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(invId);
        Test.stopTest();

        System.assert(xml.contains('<ram:Name>Entity GmbH</ram:Name>'), 'Seller name from the business entity, not the administration');
        System.assert(!xml.contains('Admin Fallback BV'), 'Administration name is only a fallback');
        System.assert(xml.contains('DE111111111'), 'Seller VAT from the business entity');
        System.assert(xml.contains('<ram:URIID>finance@example.com</ram:URIID>'), 'Seller contact email');
        System.assert(xml.contains('<ram:CompleteNumber>+49 30 123</ram:CompleteNumber>'), 'Seller contact phone');
        System.assert(xml.contains('DE89370400440532013000'), 'Seller IBAN as payee account');
    }

    @IsTest
    private static void test_sellerFallsBackToAdministration(){
        Id invId = createInvoiceFixture(null, null, null, null);

        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(invId);
        Test.stopTest();

        System.assert(xml.contains('<ram:Name>Admin Fallback BV</ram:Name>'), 'No business entity: seller data comes from the administration');
        System.assert(xml.contains('NL000000000B01'), 'Administration VAT number');
    }

    @IsTest
    private static void test_buyerReferenceCostCenterWins(){
        Id invId = createInvoiceFixture('CC-9', 'REMARK-9', null, null);
        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(invId);
        Test.stopTest();
        System.assert(xml.contains('<ram:BuyerReference>CC-9</ram:BuyerReference>'), 'Cost center wins');
    }

    @IsTest
    private static void test_buyerReferencePaymentRemarkSecond(){
        Id invId = createInvoiceFixture(null, 'REMARK-9', null, null);
        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(invId);
        Test.stopTest();
        System.assert(xml.contains('<ram:BuyerReference>REMARK-9</ram:BuyerReference>'), 'Payment remark when no cost center');
    }

    @IsTest
    private static void test_noBuyerReferenceWhenBothEmpty(){
        Id invId = createInvoiceFixture(null, null, null, null);
        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(invId);
        Test.stopTest();
        System.assert(!xml.contains('BuyerReference'), 'No reference when both are empty');
        System.assert(xml.contains('<ram:ShipToTradeParty>'), 'Delivery block is never empty');
        System.assert(!xml.contains('BillingSpecifiedPeriod'), 'No period when the lines carry no dates');
    }

    @IsTest
    private static void test_invoicingPeriodFromOrderLines(){
        Id invId = createInvoiceFixture(null, null, Date.newInstance(2026, 11, 14), Date.newInstance(2026, 12, 13));
        Test.startTest();
        String xml = Svc_CIIInvoiceXmlBuilder.buildXml(invId);
        Test.stopTest();
        System.assert(xml.contains('BillingSpecifiedPeriod'), 'Invoicing period element');
        System.assert(xml.contains('20261114') && xml.contains('20261213'), 'Invoicing period from the order lines');
        System.assert(xml.contains('<ram:ShipToTradeParty>'), 'Delivery block present');
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
