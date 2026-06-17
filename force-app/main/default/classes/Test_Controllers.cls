@IsTest
private class Test_Controllers {
    
    @IsTest
    private static void testCtrl_SyncWithExact(){
        Account acc = Test_Data.createAccount('Test', '11', 'B2B', true);
        Contact con = Test_Data.createContact(acc.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        acc.Contact_Person__c = con.id;
        acc.Bank_Account_Number__c = 'NL29KNAB0598718206';
        Database.update(acc);
        Subscription25__Administration__c admin = test_data.createAdministration(true);
        Subscription25__Debtor_Number__c debNr = new Subscription25__Debtor_Number__c();
        debNr.Subscription25__Account__c = acc.id;
        debNr.Subscription25__Administration__c = admin.Id;
        debNr.Subscription25__Debtor_Number__c = acc.id;
        debNr.Exact_Id__c = '123';
        debNr.Exact_Contact_Id__c = '123';
        debNr.Exact_Bank_Account_Id__c = '123';
        debNr.Exact_Mandate_Id__c = '123';
        Database.insert(debNr);
        Order ord = test_data.createOrder(acc.Id, admin.Id, Date.today().addDays(-7), True);
        

        Test.startTest();
		string msgA = Ctrl_SyncWithExact.getSyncInformation(acc.id);
		string msgD = Ctrl_SyncWithExact.getSyncInformation(debNr.id);
		string msgO = Ctrl_SyncWithExact.getSyncInformation(ord.id);
        List<String> lstA = Ctrl_SyncWithExact.doSync(acc.id);
        List<String> lstD = Ctrl_SyncWithExact.doSync(debNr.id);
        List<String> lstO = Ctrl_SyncWithExact.doSync(ord.id);
        Test.stopTest();

        System.assertEquals('This action creates/updates a Relation in Exact!<br/><br/>When you want to continue, press "Synchronise".', msgA);
        System.assertEquals('This action creates/updates a Relation in Exact!<br/><br/>When you want to continue, press "Synchronise".', msgD);
        System.assertEquals('This action creates an Order in Exact!<br/><br/>When you want to continue, press "Synchronise".', msgO);
        System.assertEquals(1, lstA.size());
        System.assertEquals(1, lstD.size());
        System.assertEquals(1, lstO.size());
    }
    @IsTest
    private static void test_Ctrl_Email(){
        Account acc = new Account(Name = 'testAcc');
        Database.insert(acc);
        Contact cont = new Contact(FirstName = 'testName1', LastName = 'testName2', AccountId = acc.Id);
        Database.insert(cont);

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.MailResponseMock());
 
        ApexPages.StandardController sc = new ApexPages.StandardController(cont);

        Test.startTest();
        Ctrl_Email controller = new Ctrl_Email(sc);
        Test.stopTest();

        System.assertEquals('7905', controller.miMsgs[0].id);
        System.assertEquals('15469', controller.miMsgs[0].toContactId);
        System.assertEquals('theowolfshaar@hetnet.nl', controller.miMsgs[0].toAddress);
        System.assertEquals(null, controller.miMsgs[0].ccAddresses);
        System.assertEquals('Uw Moving Intelligence diensten verlopen bijna', controller.miMsgs[0].subject);
        System.assertEquals('testtest', controller.miMsgs[0].body);
        //System.assertEquals('Tue 21-10-2014 07:22:32', controller.miMsgs[0].getConvertedDate());
        System.assertEquals('7905', controller.miMsgs[1].id);
        System.assertEquals('15469', controller.miMsgs[1].toContactId);
        System.assertEquals('theowolfshaar@hetnet.nl', controller.miMsgs[1].toAddress);
        System.assertEquals(null, controller.miMsgs[1].ccAddresses);
        System.assertEquals('Uw Moving Intelligence diensten verlopen bijna', controller.miMsgs[1].subject);
        System.assertEquals('testtest', controller.miMsgs[1].body);
        //System.assertEquals('Tue 21-10-2014 07:22:32', controller.miMsgs[1].getConvertedDate());
    }
    @IsTest
    private static void test_Ctrl_Voucher(){
        Account acc = new Account(Name = 'testAcc', extId_1__c = '1');
        Database.insert(acc);
        Contact cont = new Contact(FirstName = 'testName1', LastName = 'testName2', AccountId = acc.Id, extId_1__c = '17492');
        Database.insert(cont);


        Test.setMock(HttpCalloutMock.class, new Test_Mocks.VoucherResponseMock());
 
        ApexPages.StandardController sc = new ApexPages.StandardController(acc);
        Test.startTest();
        Ctrl_Voucher controller = new Ctrl_Voucher(sc);
        Test.stopTest();

        System.assertEquals('1615', controller.voucherList[0].id);
        System.assertEquals('T21C67A', controller.voucherList[0].voucherCode);
        System.assertEquals(1357081200, controller.voucherList[0].createDate);
        System.assertEquals(1372802400, controller.voucherList[0].endDate);
        System.assertEquals('17492', controller.voucherList[0].createdByContactId);
        System.assertEquals('15498', controller.voucherList[0].requestedByContactId);
        System.assertEquals(7.89, controller.voucherList[0].value);
        System.assertEquals(null, controller.voucherList[0].spent);
        System.assertEquals('1', controller.voucherList[0].accountId);
        System.assertEquals('33', controller.voucherList[0].installationId);
        System.assertEquals('449', controller.voucherList[0].hardwareId);
        System.assertEquals('Uitbouw', controller.voucherList[0].dealerTaskType);
        System.assertEquals(null, controller.voucherList[0].reason);
        System.assertEquals('Verlopen', controller.voucherList[0].status);
        //System.assertEquals('Tue 01-01-2013 23:00:00', controller.voucherList[0].getConvertedCreatedDate());
        //System.assertEquals('Tue 02-07-2013 22:00:00', controller.voucherList[0].getConvertedEndDate());
        System.assertEquals(cont.Id, controller.voucherList[0].getCreatedByContactSFId().Id);
        System.assertEquals(new Contact(), controller.voucherList[0].getRequestedByContactSFId());
        System.assertEquals(acc.Id, controller.voucherList[0].getAccountSFId().Id);
        System.assertEquals(new Asset(), controller.voucherList[0].getHardwareSFId());
        System.assertEquals(new Asset(), controller.voucherList[0].getInstallationSFId());
    }
    @IsTest
    private static void test_Ctrl_AlarmContact(){
       Account acc = new Account(Name = 'testAcc');
       Database.insert(acc);
       Contact cont = new Contact(FirstName = 'testName1', LastName = 'testName2', AccountId = acc.Id, extId_1__c = '17516');
       Database.insert(cont);
       Asset ass = new Asset(Name = 'test', AccountId = acc.Id, extId__c = '7587-in-1');
       Database.insert(ass);

       Test.setMock(HttpCalloutMock.class, new Test_Mocks.AlarmContactResponseMock());

       PageReference pageRef = new PageReference('/' + ass.Id);
       Test.setCurrentPage(pageRef);

       ApexPages.currentPage().getParameters().put('id', ass.Id);
       ApexPages.StandardController sc = new ApexPages.StandardController(ass);

       Test.startTest();
       Ctrl_AlarmContact controller = new Ctrl_AlarmContact(sc);
       Test.stopTest();

       System.assertEquals('3428', controller.miAlarmCont[0].id);
       System.assertEquals('7587', controller.miAlarmCont[0].installationId);
       System.assertEquals('17516', controller.miAlarmCont[0].contactId);
       System.assertEquals('Stefan', controller.miAlarmCont[0].firstName);
       System.assertEquals('', controller.miAlarmCont[0].insertion);
       System.assertEquals('Nicodem', controller.miAlarmCont[0].surName);
       System.assertEquals('+31615903586', controller.miAlarmCont[0].phoneNumber1);
       System.assertEquals('+31627064628', controller.miAlarmCont[0].phoneNumber2);
       System.assertEquals('jessica', controller.miAlarmCont[0].alarmCode);
       System.assertEquals('', controller.miAlarmCont[0].alarmCodeHint);
       System.assertEquals('1', controller.miAlarmCont[0].sortOrder);
       //System.assertEquals('Wed 05-02-2014 19:39:39', controller.miAlarmCont[0].getConvertedDate());
     }
    @IsTest
    private static void test_Ctrl_Location(){
        Account acc = new Account(Name = 'testAcc');
        Database.insert(acc);
        Asset ass = new Asset(Name = 'test', AccountId = acc.Id, extId__c = '1234-in-1');
        Database.insert(ass);

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.LocationResponseMock());

        PageReference pageRef = new PageReference('/' + ass.Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('id', ass.Id);
        ApexPages.StandardController sc = new ApexPages.StandardController(ass);
        Ctrl_Location controller = new Ctrl_Location(sc); 
           
        Test.startTest();
        controller.callLocation();
        Test.stopTest(); 

        System.assertEquals(1465205084, controller.location.gpsDate);
        System.assertEquals(0, controller.location.speed);
        System.assertEquals(128, controller.location.direction);
        System.assertEquals(6, controller.location.altitude);
        System.assertEquals('Lindonk', controller.location.road);
        System.assertEquals('2', controller.location.houseNumber);
        System.assertEquals('4761CT', controller.location.postalCode);
        System.assertEquals('Zevenbergen|m:Moerdijk', controller.location.city);
        System.assertEquals('Nederland', controller.location.country);
    }
    @IsTest
    private static void test_Ctrl_Incident(){
        Account acc = new Account(Name = 'testAcc');
        Database.insert(acc);
        Asset ass = new Asset(Name = 'test', AccountId = acc.Id, extId__c = '1234-in-1');
        Asset ass2 = new Asset(Name = 'test2', AccountId = acc.Id, extId__c = '1234-hw-1');
        Database.insert(ass);

        Test.setMock(HttpCalloutMock.class, new Test_Mocks.IncidentResponseMock());

        PageReference pageRef = new PageReference('/' + ass.Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('id', ass.Id);
        ApexPages.StandardController sc = new ApexPages.StandardController(ass);

        Test.startTest();
        Ctrl_Incident controller = new Ctrl_Incident(sc);
        Test.stopTest();

        System.assertEquals(40130, controller.miIncs[0].id);
        System.assertEquals(1234, controller.miIncs[0].installationId);
        System.assertEquals(1234, controller.miIncs[0].hardwareId);
        System.assertEquals('Motorcontact', controller.miIncs[0].test);
        System.assertEquals('Geen motorcontact in testperiode, maar wel 64 verschillende GSM-cellen. Vermoeden op beweging zonder motorcontact bestaat.', controller.miIncs[0].descriptionDetected);
        System.assertEquals('-', controller.miIncs[0].descriptionSolved);
        //System.assertEquals('Wed 29-01-2014 07:55:12', controller.miIncs[0].getConvertedStartDate());
        //System.assertEquals('Wed 05-02-2014 19:39:39', controller.miIncs[0].getConvertedEndDate());
        System.assertEquals(ass.Id, controller.miIncs[0].getInstallationSFID().Id);
    }
    @IsTest
    private static void test_Ctrl_InvoicePrevious(){
        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
        Account acc = Test_Data.createAccount('CustomerNL', '12345', 'B2B', true);
        Subscription25__Debtor_Number__c dnr = Test_Data.createDebtorNumber(adm.Id, acc.Id, true);
        Product2 prd = Test_Data.createProduct('MiTest', '12.MiTest', '1-sv-1', 'Subscription', true);
        Data_Translation__c dt = Test_Data.createProductTranslation(prd.Id, 'nl', 'Test-NL', 'Description-NL', true);
        PricebookEntry pbe = Test_Data.createPricebookEntry(prd.Id, 100.50, true);
        Subscription25__VATRate__c vat = Test_Data.createVATRate('TestVAT', 19.5, true, true);
        Subscription25__Administration_Product__c apr = Test_Data.createAdministrationProduct(adm.Id, prd.Id, vat.Id, true);
        system.debug(apr.id);
        Subscription25__Invoice__c inv = Test_Data.createInvoice(adm.Id, acc.Id, 'DRAFT', true);
        system.debug(inv.id);
        Order ord = Test_Data.createOrder(acc.Id, adm.Id, date.today().addDays(-14) , false);
        ord.Subscription25__Invoice__c = inv.Id;
        Database.insert(ord);
        OrderItem ori = Test_Data.createOrderItem2(ord.Id, pbe.Id, prd.Id, 89.5, true);

        PageReference pageRef = new PageReference('/apex/InvoiceNL?renderType=PDF&amp;id=' + inv.Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('id', inv.Id);
        ApexPages.StandardController sc = new ApexPages.StandardController(inv);
        Ctrl_InvoicePrevious controller = new Ctrl_InvoicePrevious(sc);

        Test.startTest();
        controller.getTest();
        Test.stopTest();
    }
    @IsTest
    private static void test_Ctrl_SyncAccountToMI(){
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.PlatformMock());

        Subscription25__Administration__c adm = Test_Data.createAdministration(true);
    
        Exact_Relation_Setting__c ers = new Exact_Relation_Setting__c(Administration__c = adm.Id, Relation_Type__c = 'End User', Exact_ID__c = '5d8b7622-25d2-4c08-ab57-7b02810ad56b');
        Database.insert(ers);
    
        Account acct = Test_Data.createAccount('Test', '78729', 'B2B', true);
        Subscription25__Debtor_Number__c debNr1 = new Subscription25__Debtor_Number__c(Subscription25__Debtor_Number__c = 'TEST_11', Subscription25__Account__c = acct.Id, Subscription25__Administration__c = adm.id);
    
        Database.insert(debNr1);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        acct.Contact_person__c = cont.Id;
        acct.MI_Administrator__c = cont.Id;
        acct.Contact_Shipping__c = cont.Id;
        acct.Contact_Billing__c = cont.Id;
    
        acct.FinancialDebtorNumber__c = 'TEST_11';
    
        Database.update(acct);

        PageReference pageRef = new PageReference('/' + acct.Id);
        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put('Id', acct.Id);
        ApexPages.StandardController sc = new ApexPages.StandardController(acct);
        Ctrl_SyncAccountToMI controller = new Ctrl_SyncAccountToMI(sc); 
           
        Test.startTest();
        controller.callMiSync();
        Test.stopTest(); 
        
        account accResult = [Select id, extId_1__c from Account where id = :acct.id];
    
        System.assertEquals('78729', accResult.extId_1__c);        
    }
}