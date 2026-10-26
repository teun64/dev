@IsTest(SeeAllData=false)
private class Test_Inv_CustomerUser {

    @TestSetup
    static void makeData() {
        Test_Svc_DealerUserSetup.createDealerFixture();
    }

    private static Inv_CustomerUser.Response run(Id contactId, String action) {
        Inv_CustomerUser.Request req = new Inv_CustomerUser.Request();
        req.contactId = contactId;
        req.action    = action;
        return Inv_CustomerUser.run(new List<Inv_CustomerUser.Request>{ req })[0];
    }

    @IsTest
    static void testEnableThenDisable_dealerContact() {
        Contact con = [SELECT Id, Customer_User_Type__c FROM Contact WHERE LastName = 'Test Dealer Contact' LIMIT 1];
        System.assertEquals(Inv_CustomerUser.TYPE_DEALER, con.Customer_User_Type__c, 'Fixture should be a Dealer Portal contact');
        Test_Svc_DealerUserSetup.freeCommunitySeat();

        Test.startTest();
        Inv_CustomerUser.Response enabled  = run(con.Id, Inv_CustomerUser.ACTION_ENABLE);
        Inv_CustomerUser.Response disabled = run(con.Id, Inv_CustomerUser.ACTION_DISABLE);
        Test.stopTest();

        System.assertEquals(true, enabled.success, 'dbg: ' + enabled.message);
        System.assert(enabled.message.contains('is active'), 'dbg: ' + enabled.message);
        System.assertEquals(true, disabled.success, 'dbg: ' + disabled.message);
        System.assert(disabled.message.contains('deactivated'), 'dbg: ' + disabled.message);
    }

    @IsTest
    static void testEnable_endUserContact_fails() {
        Contact con = [SELECT Id, Customer_User_Type__c FROM Contact WHERE LastName = 'Test End User Contact' LIMIT 1];
        System.assertEquals(null, con.Customer_User_Type__c, 'End User account should have no customer user type');

        Inv_CustomerUser.Response res = run(con.Id, Inv_CustomerUser.ACTION_ENABLE);

        System.assertEquals(false, res.success, 'Should fail for a non-dealer contact');
        System.assert(res.message.contains('No customer user type'), 'dbg: ' + res.message);
    }

    @IsTest
    static void testUnknownAction_fails() {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'Test Dealer Contact' LIMIT 1];

        Inv_CustomerUser.Response res = run(con.Id, 'Explode');

        System.assertEquals(false, res.success, 'Should fail for an unknown action');
        System.assert(res.message.contains('Unknown action'), 'dbg: ' + res.message);
    }
}
