@isTest
private class Test_Ctrl_InvoiceEstablishmentAddress {

    // Test_Data account: establishment / billing = Roerdomp 32, 1715 HL Spanbroek; invoice address = Postbus 184, 1715 ZH Spanbroek
    private static Account createAccount() {
        return Test_Data.createAccount('Establishment Test', 'EST1', 'B2B', true);
    }

    @isTest
    static void showsEstablishmentAddressForDifferentInvoiceAddress() {
        Account acc = createAccount();
        Subscription25__Invoice__c inv = new Subscription25__Invoice__c(
            Subscription25__Account__c = acc.Id,
            Subscription25__Billing_Street__c = 'Postbus 184',
            Subscription25__Billing_Postal_Code__c = '1715 ZH',
            Subscription25__Billing_City__c = 'Spanbroek'
        );

        Test.startTest();
        Ctrl_InvoiceEstablishmentAddress ext = new Ctrl_InvoiceEstablishmentAddress(inv, 'NL');
        Test.stopTest();

        Account est = [SELECT Name, BillingStreet, BillingPostalCode, BillingCity FROM Account WHERE Id = :acc.Id];
        System.assertEquals(true, ext.showEstablishmentAddress, 'a different invoice address shows the establishment box');
        System.assertEquals(est.Name, ext.establishmentName);
        System.assertEquals(est.BillingStreet, ext.establishmentStreet);
        System.assertEquals(est.BillingPostalCode, ext.establishmentPostalCode);
        System.assertEquals(est.BillingCity, ext.establishmentCity);
        System.assertEquals(false, ext.showEstablishmentCountry, 'same country code as the administration is not printed');
    }

    @isTest
    static void hidesBoxWhenInvoiceGoesToEstablishmentAddress() {
        Account acc = createAccount();
        Account est = [SELECT BillingStreet, BillingPostalCode, BillingCity FROM Account WHERE Id = :acc.Id];
        // same address, only formatting differs (case / spaces)
        Subscription25__Invoice__c inv = new Subscription25__Invoice__c(
            Subscription25__Account__c = acc.Id,
            Subscription25__Billing_Street__c = est.BillingStreet.toUpperCase(),
            Subscription25__Billing_Postal_Code__c = est.BillingPostalCode.replace(' ', ''),
            Subscription25__Billing_City__c = est.BillingCity
        );

        Ctrl_InvoiceEstablishmentAddress ext = new Ctrl_InvoiceEstablishmentAddress(inv, 'NL');
        System.assertEquals(false, ext.showEstablishmentAddress, 'same address (formatting aside) shows no box');
    }

    @isTest
    static void printsCountryWhenDifferentFromAdministration() {
        Account acc = createAccount();
        Subscription25__Invoice__c inv = new Subscription25__Invoice__c(
            Subscription25__Account__c = acc.Id,
            Subscription25__Billing_Street__c = 'Postbus 184',
            Subscription25__Billing_Postal_Code__c = '1715 ZH',
            Subscription25__Billing_City__c = 'Spanbroek'
        );
        Ctrl_InvoiceEstablishmentAddress ext = new Ctrl_InvoiceEstablishmentAddress(inv, 'DE');
        System.assertEquals(true, ext.showEstablishmentCountry, 'establishment country code NL differs from administration DE -> printed');
    }

    @isTest
    static void noInvoiceNoBox() {
        Ctrl_InvoiceEstablishmentAddress ext = new Ctrl_InvoiceEstablishmentAddress((Subscription25__Invoice__c) null, 'NL');
        System.assertEquals(false, ext.showEstablishmentAddress);
        System.assertEquals('3500ab', Ctrl_InvoiceEstablishmentAddress.normalize('3500 AB'));
    }

    @isTest
    static void invoiceCountryIsCheckedSeparately() {
        Account acc = createAccount();
        // invoice address in Germany, establishment in the Netherlands, administration NL
        Subscription25__Invoice__c inv = new Subscription25__Invoice__c(
            Subscription25__Account__c = acc.Id,
            Subscription25__Billing_Street__c = 'Hauptstrasse 1',
            Subscription25__Billing_Postal_Code__c = '10115',
            Subscription25__Billing_City__c = 'Berlin',
            Subscription25__Billing_Country__c = 'Germany'
        );
        Ctrl_InvoiceEstablishmentAddress ext = new Ctrl_InvoiceEstablishmentAddress(inv, 'NL');
        System.assertEquals(true, ext.showInvoiceCountry, 'invoice address country DE differs from administration NL -> printed');
        System.assertEquals(false, ext.showEstablishmentCountry, 'establishment country NL equals administration NL -> not printed');

        inv.Subscription25__Billing_Country__c = 'Netherlands';
        ext = new Ctrl_InvoiceEstablishmentAddress(inv, 'NL');
        System.assertEquals(false, ext.showInvoiceCountry, 'invoice address country NL equals administration NL -> not printed');
        System.assertEquals('DE', Ctrl_InvoiceEstablishmentAddress.countryCodeFromLabel('Germany'));
    }
}
