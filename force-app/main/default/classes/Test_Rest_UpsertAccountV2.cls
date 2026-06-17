/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class Test_Rest_UpsertAccountV2 {


    @testSetup
    private static void testSetup() {
        Account dealerAcc = Test_Data.createAccount('Dealer', '1', 'B2B', false);
        Database.insert(dealerAcc);
        Product2 hwProd = Test_Data.createProduct('Mi50 (43)', '', '43-hw-1', 'Platform', false);
        Database.insert(hwProd);

        Database.insert(new Contact(FirstName = 'test', LastName = 'dealer', AccountId = dealerAcc.Id, Email = 'test1@test1.nl', extId_1__c = '1', Is_Active__c = true));
        Database.insert(new Contact(FirstName = 'test', AccountId = dealerAcc.Id, LastName = 'Driver', Email = 'test@test2.nl', extId_1__c = '2', Is_Active__c = true));
        Database.insert(new Asset(Name = 'testAsset', AccountId = dealerAcc.Id, extID__c = '123-hw-1', Product2Id = hwProd.Id, RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Hardware').getRecordTypeId()));
        Database.insert(new Asset(Name = 'testAssetEntity', AccountId = dealerAcc.Id, extID__c = '7587-in-1', RecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Entity').getRecordTypeId()));
    }

    private static testMethod void testRestInsertAccount() {
        // 20200409 - Gen25/Tri paymentMethod replaced by paymentMethodExactCode and value changed to I8 to match picklist value
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3001","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3002","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"t30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.response = new RestResponse();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            Rest_UpsertAccountV2.handlePost();
        }
        Test.stopTest();

        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(6, [SELECT Count() FROM Contact]); //2 from JSON; 2 from @testSetup
    }

    private static testMethod void testRestUpdateAccount() {
        // jsonString1 now correctly causes duplicate collision due to same account with different ID for same platform
        // String jsonString1 = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3001","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3002","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"t30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        String jsonString2 = '{"id":"t31","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3101","salesforceId":null,"accountId":"t30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3102","salesforceId":null,"accountId":"t31","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t31v","accountId":"t31","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t31b","accountId":"t30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        String jsonString3 = '{"id":"t31","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t3101","salesforceId":null,"accountId":"t31","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t3102","salesforceId":null,"accountId":"t31","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t31v","accountId":"t31","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t31b","accountId":"t30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1,"kickbackId":"t30"}';

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            // System.RestContext.request = new RestRequest();
            // System.RestContext.response = new RestResponse();
            // System.RestContext.request.requestBody = Blob.valueOf(jsonString1);
            // Rest_UpsertAccountV2.handlePost();
            // System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString2);
            //adding Account again to simulate the update.
            Rest_UpsertAccountV2.handlePost();
            System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString3);
            Rest_UpsertAccountV2.handlePost();
            System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
        }
        Test.stopTest();

        System.assertEquals(2, [SELECT Count() FROM Account]); //2 from JSON; 1 from @testSetup
        System.assertEquals(6, [SELECT Count() FROM Contact]); //4 from JSON; 2 from @testSetup
    }

    private static testMethod void testAddContactRestAccount() {
        // 20200409 - Gen25/Tri paymentMethod replaced by paymentMethodExactCode and value changed to I8 to match picklist value
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.response = new RestResponse();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            Rest_UpsertAccountV2.handlePost();
            //adding the same contacts again should NOT result in more contacts.
            Rest_UpsertAccountV2.handlePost();
        }
        Test.stopTest();

        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']); //2 from JSON; 1 from @testSetup; 1 billingcontact
    }

    private static testMethod void testAddSecondFinancialContactRestAccount(){
        // 20200409 - Gen25/Tri paymentMethod replaced by paymentMethodExactCode and value changed to I8 to match picklist value
        String jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        System.RestContext.request = new RestRequest();
        System.RestContext.response = new RestResponse();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString);

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            Rest_UpsertAccountV2.handlePost();
            System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
            Contact financialContact = [SELECT Id FROM Contact WHERE LastName = 'Billert' LIMIT 1];
            Account acc = [SELECT extId_1__c, Contact_Billing__c, Contact_Billing__r.extId_1__c FROM Account WHERE extId_1__c = 't30'];
            System.assertEquals(acc.Contact_Billing__c, financialContact.Id);

            //adding the same contacts again should NOT result in more contacts.
            jsonString = '{"id":"t30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"het","surName":"Contact","email":"jan.het.Contact@gmail.com","function":null,"phoneNumber":"+31666778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","function":null,"phoneNumber":"+31644556677","language":"nl","street":"Straatnaam ","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t30v","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Particulier","email":"paul.de.particulier@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t30b","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"12","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString);
            Rest_UpsertAccountV2.handlePost();
        }

        Test.stopTest();
        //get second account + contact
        Contact financialContact2 = [SELECT Id FROM Contact WHERE LastName = 'Billert' LIMIT 1];
        Account acc2 = [
            SELECT extId_1__c, Contact_Billing__c,
                Contact_Billing__r.extId_1__c
            FROM Account
            WHERE extId_1__c = 't30'
            LIMIT 1
        ];

        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
        //check if account billing attendant is updated to the second contact.
        System.assertEquals(acc2.Contact_Billing__c, financialContact2.Id);

        //check if everything is added
        System.assertEquals(2, [SELECT Count() FROM Account]); //1 from JSON; 1 from @testSetup
        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']);
    }

    private static testMethod void testExistingContactWithoutExtIdSameAccount() {

        Account sameAccount = Test_Data.createAccount('Business b.v.', 'T30', 'B2B', true);
        Contact paul = new Contact(FirstName = 'Paul', LastName = 'Contact', AccountId = sameAccount.Id, Email = 'paul.het.contact@gmail.com', Is_Active__c = true, MailingPostalCode = '1111 AA', MailingStreet = 'Straatnaam 1');
        Database.insert(paul);
        System.assertEquals(1, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']);// Related to 1 account

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            String jsonString = '{"id":"T30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t31","accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.contact@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t33","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString);
            Rest_UpsertAccountV2.handlePost();
        }
        Test.stopTest();
        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors

        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'paul.het.contact@gmail.com']); // Only 1 Paul
        System.assertEquals(1, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']); // Related to 1 account
        System.assertEquals(sameAccount.Id, [SELECT AccountId FROM Contact WHERE Email = 'paul.het.contact@gmail.com'].AccountId); // Parent account Id unchanged
    }

    private static testMethod void testExistingContactWithExtIdSameAccount() {

        Account sameAccount = Test_Data.createAccount('Business b.v.', 'T30', 'B2B', true);
        Contact paul = new Contact(FirstName = 'Paul', LastName = 'Contact', AccountId = sameAccount.Id, Email = 'paul.het.contact@gmail.com', Is_Active__c = true, MailingPostalCode = '1111 AA', MailingStreet = 'Straatnaam 1');
        Database.insert(paul);
        System.assertEquals(1, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']);// Related to 1 account

        AccountContactRelation rel = [SELECT Id FROM AccountContactRelation WHERE ContactId = :paul.Id];
        rel.ExtId_1__c = 't31';
        Database.update(rel);

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            String jsonString = '{"id":"T30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t31","accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.contact@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t33","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString);
            Rest_UpsertAccountV2.handlePost();
        }
        Test.stopTest();
        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors

        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'paul.het.contact@gmail.com']); // Only 1 Paul
        System.assertEquals(1, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']); // Related to 1 account
        System.assertEquals(sameAccount.Id, [SELECT AccountId FROM Contact WHERE Email = 'paul.het.contact@gmail.com'].AccountId); // Parent account Id unchanged
    }

    private static testMethod void testExistingContactWithoutExtIdDifferentAccount() {

        Account otherAccount = Test_Data.createAccount('Anders B.V.', '2', 'B2B', true);
        Contact paul = new Contact(FirstName = 'Paul', LastName = 'Contact', AccountId = otherAccount.Id, Email = 'paul.het.contact@gmail.com', Is_Active__c = true, MailingPostalCode = '1111 AA', MailingStreet = 'Straatnaam 1');
        Database.insert(paul);
        System.assertEquals(1, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']);// Related to 2 accounts

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            String jsonString = '{"id":"T30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t31","accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.contact@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t33","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString);
            Rest_UpsertAccountV2.handlePost();
        }
        Test.stopTest();
        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors

        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'paul.het.contact@gmail.com']); // Only 1 Paul
        System.assertEquals(2, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']); // Related to 2 accounts
        System.assertEquals(otherAccount.Id, [SELECT AccountId FROM Contact WHERE Email = 'paul.het.contact@gmail.com'].AccountId); // Parent account Id unchanged
    }

    private static testMethod void testExistingContactWithExtIdDifferentAccount() {

        // Create Contact + original Account
        Account otherAccount = Test_Data.createAccount('Anders B.V.', '2', 'B2B', true);
        Contact paul = new Contact(FirstName = 'Paul', LastName = 'Contact', AccountId = otherAccount.Id, Email = 'paul.het.contact@gmail.com', Is_Active__c = true, MailingPostalCode = '1111 AA', MailingStreet = 'Straatnaam 1');
        Database.insert(paul);
        System.assertEquals(1, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']);// Related to 2 accounts

        // Create to update Account and Contact Relation
        Account sameAccount = Test_Data.createAccount('Business b.v.', 'T30', 'B2B', true);
        AccountContactRelation rel = new AccountContactRelation(
            AccountId = sameAccount.Id,
            ContactId = paul.Id,
            ExtId_1__c = 't31'
        );
        Database.insert(rel);

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            String jsonString = '{"id":"T30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","contactDTOs":[{"id":"t31","salesforceId":null,"accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.Contact@gmail.com","function":null,"phoneNumber":"+31655667788","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":true},{"id":"t32","salesforceId":null,"accountId":"T30","firstName":"Anita","insertion":"het","surName":"Contact","email":"anita.het.Contact@gmail.com","function":null,"phoneNumber":"+3166778899","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false},{"id":"t33","salesforceId":null,"accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","function":null,"phoneNumber":"+3144556677","language":"nl","street":"Straatnaam ","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam ","country":"NL","isActive":true,"hasDealerTaskAccess":false,"isAdministrator":false}],"visitAddress":{"id":"t31","accountId":"T30","firstName":"Paul","insertion":"het","surName":"Contact","email":"paul.het.contact@gmail.com","phoneNumber":"+31655667788","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t33","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString);
            Rest_UpsertAccountV2.handlePost();
        }
        Test.stopTest();
        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors

        System.assertEquals(1, [SELECT Count() FROM Contact WHERE Email = 'paul.het.contact@gmail.com']); // Only 1 Paul
        System.assertEquals(2, [SELECT Count() FROM AccountContactRelation WHERE Contact.Email = 'paul.het.contact@gmail.com']); // Related to 2 accounts
        System.assertEquals(otherAccount.Id, [SELECT AccountId FROM Contact WHERE Email = 'paul.het.contact@gmail.com'].AccountId); // Parent account Id unchanged
    }

    private static testMethod void testMergeAddresses() {
        // Create account with 2 different addresses
        String jsonString1 = '{"id":"T30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","visitAddress":{"id":"t31","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Bezoekert","phoneNumber":"+31655667788","email":"visiting@gmail.com","street":"Straatnaam","houseNumber":"2","postalCode":"2222 BB","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t32","accountId":"T30","firstName":"Jan","insertion":"de","surName":"Billert","email":"billing@gmail.com","phoneNumber":"+31644556677","street":"Straatnaam","houseNumber":"1","postalCode":"1111 AA","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';
        // Update account to same address (should have a different ID)
        String jsonString2 = '{"id":"T30","salesforceId":null,"debtorNumber":null,"name":"Business b.v.","isBusiness":true,"isDealer":false,"vatNumber":"NL123456789B01","cocNumber":"12345678","paymentMethodExactCode":"08","bankAccountHolder":"Business b.v.","bankAccountNumber":"NL00BANK0000000001","bankAccountBic":"BICCODE1","visitAddress":{"id":"t31","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Bezoekert","phoneNumber":"+31655667788","email":"visiting@gmail.com","street":"Straatnaam","houseNumber":"2","postalCode":"2222 BB","city":"Plaatsnaam","country":"NL","language":null},"billingAddress":{"id":"t33","accountId":"T30","firstName":"Paul","insertion":"de","surName":"Bezoekert","phoneNumber":"+31655667788","email":"visiting@gmail.com","street":"Straatnaam","houseNumber":"2","postalCode":"2222 BB","city":"Plaatsnaam","country":"NL","language":null},"exactId":null,"isBlocked":false,"resellerId":1,"primarySbiCode":null,"secondarySbiCode1":null,"secondarySbiCode2":null,"platformId":1}';

        // Create
        System.RestContext.request = new RestRequest();
        System.RestContext.response = new RestResponse();
        System.RestContext.request.requestBody = Blob.valueOf(jsonString1);
        Rest_UpsertAccountV2.handlePost();
        System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors

        // Validate created address contacts
        List<AccountContactRelation> rels = [SELECT Id, Contact.Email FROM AccountContactRelation WHERE Account.ExtId_1__c = 'T30' ORDER BY ExtId_1__c DESC];
        System.assertEquals(2, rels.size(), 'Expected 2 ACRs for Account');
        System.assertEquals('billing@gmail.com', rels.get(0).Contact.Email);
        System.assertEquals('visiting@gmail.com', rels.get(1).Contact.Email);

        Test.startTest();
        System.runAs(Test_Data.getIntegrationUser()) {
            // Update
            System.RestContext.request = new RestRequest();
            System.RestContext.response = new RestResponse();
            System.RestContext.request.requestBody = Blob.valueOf(jsonString2);
            Rest_UpsertAccountV2.handlePost();
            System.assertEquals(200, RestContext.response?.statusCode, RestContext.response?.responseBody?.toString()); // Validate no errors
        }
        Test.stopTest();

        // Validate created address contacts
        rels = [SELECT Id, Contact.Email FROM AccountContactRelation WHERE Account.ExtId_1__c = 'T30' ORDER BY ExtId_1__c DESC];
        System.assertEquals(1, rels.size(), 'Expected 1 ACR for Account');
        System.assertEquals('visiting@gmail.com', rels.get(0).Contact.Email);
        System.assertEquals(0, [SELECT Count() FROM Contact WHERE Email = 'billing@gmail.com']);
    }
}