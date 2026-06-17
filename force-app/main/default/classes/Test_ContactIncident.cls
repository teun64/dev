@isTest
private class Test_ContactIncident {

    @IsTest
    private static void test_Ctrl_ContactIncident() {
        Account testAccount = Test_Data.createAccount('testAcc', '123', 'B2B', true);
        Contact testContact = Test_Data.createContact(testAccount.Id, 'Test', '0612345678', 'dont@email.me', true);

        PageReference pageRef = new PageReference('/' + testContact.Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('id', testContact.Id);
        ApexPages.StandardController sc = new ApexPages.StandardController(testContact);

        List<Ctrl_ContactIncident.Mail> responseEmails = new List<Ctrl_ContactIncident.Mail>();
        Ctrl_ContactIncident.Mail incidentEmail = new Ctrl_ContactIncident.Mail();
        incidentEmail.id = '1';
        incidentEmail.toContactId = testContact.Id;
        incidentEmail.toAddress = testContact.Email;
        incidentEmail.subject = 'This is a subject';
        incidentEmail.sentDate = System.now().getTime() / 1000;
        responseEmails.add(incidentEmail);


        Test.startTest();
        Test_Mocks mock = new Test_Mocks(JSON.serialize(responseEmails), 200);
        Test.setMock(HttpCalloutMock.class, mock);

        Ctrl_ContactIncident testController = new Ctrl_ContactIncident(sc);
        Test.stopTest();

        Assert.areEqual(1, testController.miMsgs.size(), 'Emails not set on controller');
        Assert.areEqual('1', testController.miMsgs[0].Id, 'Email Id not set on controller');
    }
    @IsTest
    private static void test_Ctrl_ContactIncident_TestSorting() {
        Long currentDt = System.now().getTime();

        Ctrl_ContactIncident.Mail incidentEmail = new Ctrl_ContactIncident.Mail();
        incidentEmail.id = '1';
        incidentEmail.toContactId = '003ContactId';
        incidentEmail.toAddress = 'to@address.nl';
        incidentEmail.ccAddresses = 'anemail, anotheremail';
        incidentEmail.subject = 'This is a subject';
        incidentEmail.body = 'Dear sir/ madame, thank you. Bye.';
        incidentEmail.sentDate = currentDt / 1000;

        Ctrl_ContactIncident.Mail incidentEmail2 = new Ctrl_ContactIncident.Mail();
        incidentEmail2.id = '2';
        incidentEmail2.toContactId = '003ContactId';
        incidentEmail2.toAddress = 'to@address.nl';
        incidentEmail2.ccAddresses = 'anemail, anotheremail';
        incidentEmail2.subject = 'This is a subject';
        incidentEmail2.body = 'Dear sir/ madame, thank you. Bye.';
        incidentEmail2.sentDate = (currentDt + 1000) / 1000;

        Assert.areEqual(1, incidentEmail.compareTo(incidentEmail2), 'compareTo() not correctly implemented');
        Assert.areEqual(-1, incidentEmail2.compareTo(incidentEmail), 'compareTo() not correctly implemented');

        Assert.areEqual(Datetime.newInstance(currentDt), incidentEmail.getConvertedDate(), 'Date Conversion not correctly implemented');
        Assert.areEqual(Datetime.newInstance(currentDt + 1000), incidentEmail2.getConvertedDate(), 'Date Conversion not correctly implemented');
    }

}