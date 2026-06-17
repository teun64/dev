@isTest
private class Test_Rest_UpsertAccount {

    private static testMethod void testRestInsertAccount(){
        // 20200409 - Gen25/Tri paymentMethod replaced by paymentMethodExactCode and value changed to I8 to match picklist value
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3001","salesforceId":null,"accountId":"t30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3002","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"t30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        Util_Rest.RestResult restResult = Rest_UpsertAccount.handleAction();
        Test.stopTest();

        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(6, [SELECT Count() FROM Contact]); //2 from JSON; 2 from @testSetup
    }

    private static testMethod void testRestUpdateAccount(){
        Account acc = Test_Data.createAccount('Foutje Capitals', 't29', 'B2B', true);
        Contact con = Test_Data.createContact( acc.Id, 'Foutje', '0570651470', 'foutje@bedankt.com', true);

        String jsonString1 = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3001","salesforceId":null,"accountId":"t30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3002","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"t30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        String jsonString2 = '{"id":"t31","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3101","salesforceId":null,"accountId":"t31","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3102","salesforceId":null,"accountId":"t31","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t31v","accountId":"t31","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t31b","accountId":"t30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        String jsonString3 = '{"id":"t31","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3101","salesforceId":null,"accountId":"t31","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3102","salesforceId":null,"accountId":"t31","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t31v","accountId":"t31","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t31b","accountId":"t30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1,kickbackId:"t30"}';

        Test.startTest();
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString1);
        Util_Rest.RestResult restResult1 = Rest_UpsertAccount.handleAction();
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString2);
         //adding Account again to simulate the update. 
        Util_Rest.RestResult restResult2 = Rest_UpsertAccount.handleAction();
        Account accUpdated = [SELECT Id FROM Account WHERE extId_1__c = 't31' LIMIT 1];
        accUpdated.Contact_person__c = con.Id;
        accUpdated.Contact_Billing__c = con.Id;
        accUpdated.Contact_Shipping__c = con.Id;
        accUpdated.MI_Administrator__c = con.Id;
        Database.update(accUpdated);
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString3);        
        Util_Rest.RestResult restResult3 = Rest_UpsertAccount.handleAction();
        Test.stopTest();

        System.assertEquals(4, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(11, [SELECT Count() FROM Contact]); //2 from JSON; 2 from @testSetup; 1 billingcontact
    }

    private static testMethod void testAddFinancialContactRestAccount(){
        // 20200409 - Gen25/Tri paymentMethod replaced by paymentMethodExactCode and value changed to I8 to match picklist value
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        Util_Rest.RestResult restResult = Rest_UpsertAccount.handleAction();
        //adding the same contacts again should NOT result in more contacts. 
        Util_Rest.RestResult restResult2 = Rest_UpsertAccount.handleAction();
        Test.stopTest();    

        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.debug([SELECT Name, Email FROM Contact]);
        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']); //2 from JSON; 1 from @testSetup; 1 billingcontact
    }

    private static testMethod void testAddSecondFinancialContactRestAccount(){
        // 20200409 - Gen25/Tri paymentMethod replaced by paymentMethodExactCode and value changed to I8 to match picklist value
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        Util_Rest.RestResult restResult = Rest_UpsertAccount.handleAction();
        Contact financialContact1 = [SELECT Id FROM Contact WHERE LastName = 'Billert' LIMIT 1];
        Account acc1 = [SELECT id, extId_1__c, Contact_Billing__c, Contact_Billing__r.extId_1__c FROM Account WHERE extId_1__c = 't30'];
        AccountContactRelation acr1 = [SELECT Id, AccountId, ContactId, extId_1__c FROM AccountContactRelation WHERE AccountId = :acc1.Id AND isInvoiceContact__c = true];

        
        //adding the same contacts again should NOT result in more contacts. 
        jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Contact","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);
        Util_Rest.RestResult restResult2 = Rest_UpsertAccount.handleAction();
        Test.stopTest();  

        System.assertEquals(acr1.ContactId, financialContact1.Id);
        //get second account + contact
        Contact financialContact2 = [SELECT Id FROM Contact WHERE LastName = 'Billert' LIMIT 1];
        Account acc2 = [SELECT id, extId_1__c, Contact_Billing__c, Contact_Billing__r.extId_1__c FROM Account WHERE extId_1__c = 't30'];
        AccountContactRelation acr2 = [SELECT Id, AccountId, ContactId, extId_1__c FROM AccountContactRelation WHERE AccountId = :acc2.Id AND isInvoiceContact__c = true];
        //check if account billing attendant is updated to the second contact.
        System.assertEquals(acr2.ContactId, financialContact2.Id);

        //check if everything is added 
        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']); //2 from JSON; 1 from @testSetup; 1 billingcontact
    }

    private static testMethod void testDuplicateFinancialContactRestAccount(){
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Contact","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        Util_Rest.RestResult restResult = Rest_UpsertAccount.handleAction();
        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']); //2 from JSON; 1 from @testSetup; 1 billingcontact
            
        //upsert a modified json > check if values are updated.
        jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Karel","insertion":"de","surName":"Administrateur","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"isBlocked":false,"isBankrupt":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Util_Rest.RestResult restResult2 = Rest_UpsertAccount.handleAction();
        Test.stopTest();

        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']); //2 from JSON; 1 from @testSetup; 1 billingcontact

        Account acc1 = [SELECT id, extId_1__c, Contact_Billing__c, Contact_Billing__r.extId_1__c FROM Account WHERE extId_1__c = 't30'];
        AccountContactRelation acr1 = [SELECT Id, AccountId, ContactId, extId_1__c, Contact.FirstName, Contact.LastName, Contact.Email FROM AccountContactRelation WHERE AccountId = :acc1.Id AND isInvoiceContact__c = true];

        Contact updatedContact1 = [
            SELECT AccountId, Firstname, Lastname, Email, Phone
            FROM Contact 
            WHERE LastName = 'Billert'
        ]; 
        //assert that the values have been updated with the second json
        System.assertEquals(acr1.Contact.Firstname, updatedContact1.Firstname);
        System.assertEquals(acr1.Contact.Lastname, updatedContact1.Lastname);
        System.assertEquals(acr1.Contact.Email, updatedContact1.Email);
    }


    @testSetup
    private static void testSetup(){
        Account dealerAcc = Test_Data.createAccount('Dealer', '1', 'B2B', false);
        Database.insert(dealerAcc);
        Product2 hwProd = Test_Data.createProduct('Mi50 (43)', '', '43-hw-1', 'Platform', false);
        Database.insert(hwProd);

        Database.insert(new Contact(FirstName = 'test', LastName = 'dealer', AccountId = dealerAcc.Id, Email = 'test1@test1.nl', extId_1__c = '1', Is_Active__c = true));
        Database.insert(new Contact(FirstName = 'test', AccountId = dealerAcc.Id, LastName = 'Driver', Email = 'test@test2.nl', extId_1__c = '2', Is_Active__c = true));
        Database.insert(new Asset(Name = 'testAsset', AccountId = dealerAcc.Id, extID__c = '123-hw-1', Product2Id = hwProd.Id, RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Hardware').getRecordTypeId()));
        Database.insert(new Asset(Name = 'testAssetEntity', AccountId = dealerAcc.Id, extID__c = '7587-in-1', RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Entity').getRecordTypeId()));
    }
}