@isTest
private class Test_Wrappers {

    @isTest
    private static void Test_Wrappers(){
        account acc = Test_Data.createAccount('DN-Test', 'DN-TEST-01', 'B2C', true);
        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);

        test.startTest();
        Util_Wrappers.AdminWrapper admin = new Util_Wrappers.AdminWrapper(adm);
        Util_Wrappers.DebtorNumberWrapper dnw = new Util_Wrappers.DebtorNumberWrapper(dnr);
        test.stopTest();

        //AdminWrapper
        System.Assert.areEqual(admin.getBillingName(), adm.Subscription25__Billing_Name__c);
        System.Assert.areEqual(admin.getStreet(), adm.Subscription25__Billing_Street__c);
        System.Assert.areEqual(admin.getPostalCode(), adm.Subscription25__Billing_Postal_Code__c);
        System.Assert.areEqual(admin.getCity(), adm.Subscription25__Billing_City__c);
        System.Assert.areEqual(admin.getCountry(), adm.Subscription25__Billing_Country__c);
        System.Assert.areEqual(admin.getPhone(), adm.Subscription25__Phone__c);
        System.Assert.areEqual(admin.getEmail(), adm.Subscription25__Billing_Email_Address__c);
        System.Assert.areEqual(admin.getWebsite(), adm.Subscription25__Website__c);
        System.Assert.areEqual(admin.getVATNumber(), adm.Subscription25__VAT_Number__c);
        System.Assert.areEqual(admin.getCoCNumber(), adm.Subscription25__Chamber_Of_Commerce_Number__c);
        System.Assert.areEqual(admin.getIBAN(), adm.Subscription25__IBAN__c);
        System.Assert.areEqual(admin.getBIC(), adm.Subscription25__BIC__c);
        System.Assert.areEqual(admin.getEmailSales(), adm.Email_Sales__c);
        System.Assert.areEqual(admin.getBankAccountNumber(), adm.Bank_6_Account_Number__c);
        System.Assert.areEqual(admin.getBankSortCode(), adm.Bank_6_Sort_Code__c);
        System.Assert.areEqual(admin.getCreditorIdentifier(), adm.Creditor_Identifier_Mandate__c);
        System.Assert.areEqual(admin.getCurrencySymbol(),adm.Currency_Symbol__c);
        System.Assert.areEqual(admin.getDefaultVatPercentage(), adm.VAT_Rate_Default__c);
        System.Assert.areEqual(admin.getManagingDirectors(), adm.Managing_Directors__c);
        System.Assert.areEqual(admin.getReseller(), adm.Reseller__c);
        System.Assert.areEqual(admin.getInvoiceGeneralRemark(), adm.Invoice_General_Remark__c);
        System.Assert.areEqual(admin.getInvoiceEURemark(), adm.Invoice_EU_Remark__c);
        System.Assert.areEqual(admin.getInvoiceNonEURemark(), adm.Invoice_NonEU_Remark__c);
        //DebtorNumberWrapper
        System.Assert.areEqual(dnw.getDebtorNumber(), dnr.Subscription25__Debtor_Number__c);
        System.Assert.areEqual(dnw.getDirectDebitFormReference(), dnr.Direct_Debit_Form_Reference__c);
    }
}