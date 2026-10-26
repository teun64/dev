@IsTest(SeeAllData=false)
private class Test_Queue_ContactCustomerUser {

    @TestSetup
    static void makeData() {
        Test_Svc_DealerUserSetup.createDealerFixture();
    }

    private static Contact getContact(String lastName) {
        return [SELECT Id, Customer_User_Active__c FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    @IsTest
    static void testEnable_setsFlag() {
        Contact con = getContact('Test Dealer Contact');
        Test_Svc_DealerUserSetup.freeCommunitySeat();

        Test.startTest();
        Svc_DealerUserSetup.enableDealerUser(con.Id);
        Test.stopTest();

        System.assertEquals(true, getContact('Test Dealer Contact').Customer_User_Active__c, 'Flag should be set after enable');
    }

    @IsTest
    static void testDisable_clearsFlag() {
        Contact con = getContact('Test Dealer Contact');
        Test_Svc_DealerUserSetup.freeCommunitySeat();
        Svc_DealerUserSetup.enableDealerUser(con.Id);
        // runAs gives a fresh DML context: a Contact update right after the User insert would be mixed DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new Contact(Id = con.Id, Customer_User_Active__c = true);
        }

        Test.startTest();
        Svc_DealerUserSetup.disableDealerUser(con.Id);
        Test.stopTest();

        System.assertEquals(false, getContact('Test Dealer Contact').Customer_User_Active__c, 'Flag should be cleared after disable');
    }

    // Several contacts in one run: updates go one per DML (rab - Contact bulk fault).
    @IsTest
    static void testRun_bulkWithoutUsers_clearsFlags() {
        List<Contact> cons = [SELECT Id FROM Contact WHERE LastName IN ('Test Dealer Contact', 'Test End User Contact')];
        for (Contact c : cons) {
            update new Contact(Id = c.Id, Customer_User_Active__c = true);
        }
        Set<Id> ids = new Map<Id, Contact>(cons).keySet();

        Test.startTest();
        Queue_ContactCustomerUser.run(ids);
        Test.stopTest();

        for (Contact c : [SELECT Customer_User_Active__c FROM Contact WHERE Id IN :ids]) {
            System.assertEquals(false, c.Customer_User_Active__c, 'Contacts without an active user should not be flagged');
        }
    }
}
