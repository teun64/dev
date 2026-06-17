@isTest
private class Test_Util_Rest {
    private static testMethod void testCheckDebtorNumbers(){

        Subscription25__Administration__c admin = Test_Data.createAdministration(false);
        admin.Subscription25__Synchronisation__c = null;
        admin.Reseller__c = '4';
        Database.insert(admin); 
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'AccountContact', '1234567890', 'lex@123.com', true);
        acct.Contact_person__c = cont.Id;
        acct.MI_Administrator__c = cont.Id;
        acct.Contact_Billing__c = cont.Id;
        // force reseller to 4, means debtornumber =- account id
        acct.Reseller_Name__c = '4';
        acct.FinancialDebtorNumber__c = '';
        Database.update(acct);

        Test.startTest();
        Util_Rest.checkDebtorNumber('12', '1');
        Test.stopTest();
        
        Subscription25__Debtor_Number__c debNr = [select 
                            Id
                            , Subscription25__Debtor_Number__c 
                        from 
                            Subscription25__Debtor_Number__c 
                        where 
                            Subscription25__Account__c = :acct.Id and
                            Subscription25__Administration__c = :admin.Id
                            ];

        string debtorNumber = String.valueOf(acct.Id).left(15).right(9);                   
        System.assertEquals(debtorNumber, debNr.Subscription25__Debtor_Number__c); //1 from JSON       
    }

    private static testMethod void testHandleSend(){
        Test.setMock(HttpCalloutMock.class, new Test_Mocks.HandleSendResponseMock());
        
        Test.startTest();
        Map<Id, Account> idToAccount = new Map<Id, Account>([SELECT Id FROM Account]);
        Util_Rest.handleSend(new List<Id>(idToAccount.keySet()), 'Account');
        Map<Id, Contact> idToContact = new Map<Id, Contact>([SELECT Id FROM Contact]);
        Util_Rest.handleSend(new List<Id>(idToContact.keySet()), 'Contact');
        Test.stopTest();
    }

    @IsTest
    static void testGetAccountContactRelations() {

        Account customerAcc = Test_Data.createAccount('Customer', 'c1', 'B2B', false);
        insert customerAcc;

        Database.insert(new Contact(FirstName = 'test', LastName = 'dealer', AccountId = customerAcc.Id, Email = 'test1@customer.invalid', extId_1__c = 'c1', Is_Active__c = true));
        Database.insert(new Contact(FirstName = 'test', AccountId = customerAcc.Id, LastName = 'Driver', Email = 'test2@customer.invalid', extId_1__c = null, Is_Active__c = true));

        Test.startTest();

        Boolean exceptionThrown = false;

        System.assertEquals(
            2,
            Util_Rest.getAccountContactRelations(customerAcc.Id).size(),
            'Number of relations should be two when queried without field'
        );

        System.assertEquals(
            1,
            Util_Rest.getAccountContactRelations(customerAcc.Id,'extId_1__c').size(),
            'Number of relations should be one less when queried by ContactId or extId_1__c'
        );

        try {

            Util_Rest.getAccountContactRelations(customerAcc.Id, 'InvalidField__c');

        } catch(Exception e) {

            exceptionThrown = true;

            System.assert(
                e.getMessage().contains('InvalidField__c'),
                'Expected invalid field exception'
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Expected exception to be thrown'
        );
    }

     @IsTest
    static void testGetAccountContactRelations_EmptyResult() {

        Account customerAcc = Test_Data.createAccount('Customer', 'c1', 'B2B', false);
        insert customerAcc;

        System.assertEquals(
            0,
            Util_Rest.getAccountContactRelations(customerAcc.Id).size(),
            'Expected no relations for account with no contacts'
        );
    }

    @testSetup
    private static void testSetup(){
        Account dealerAcc = Test_Data.createAccount('Dealer', '1', 'B2B', false);
        Database.insert(dealerAcc);
        Product2 hwProd = Test_Data.createProduct('Mi50 (43)', '', '43-hw-1', 'Platform', false);
        Database.insert(hwProd);

        Database.insert(new Contact(FirstName = 'test', LastName = 'dealer', AccountId = dealerAcc.Id, Email = 'test1@dealer.invalid', extId_1__c = '1', Is_Active__c = true));
        Database.insert(new Contact(FirstName = 'test', AccountId = dealerAcc.Id, LastName = 'Driver', Email = 'test2@dealer.invalid', extId_1__c = '2', Is_Active__c = true));
        Database.insert(new Asset(Name = 'testAsset', AccountId = dealerAcc.Id, extID__c = '123-hw-1', Product2Id = hwProd.Id, RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Hardware').getRecordTypeId()));
        Database.insert(new Asset(Name = 'testAssetEntity', AccountId = dealerAcc.Id, extID__c = '7587-in-1', RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Entity').getRecordTypeId()));
    }
}