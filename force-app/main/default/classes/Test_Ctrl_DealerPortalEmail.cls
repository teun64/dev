@IsTest(SeeAllData=false)
private class Test_Ctrl_DealerPortalEmail {

    @TestSetup
    static void makeData() {
        Test_Svc_DealerUserSetup.createDealerFixture();
    }

    // Portal user on an account with a reseller code: the administration's billing email is used.
    @IsTest
    static void testAdministrationEmail() {
        Contact con = [SELECT Id, AccountId FROM Contact WHERE LastName = 'Test Dealer Contact' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Subscription25__Administration__c(
                Name = 'Test Dealer Admin', Reseller__c = '1',
                Subscription25__Billing_Country__c = 'NL', Subscription25__Invoice_Number_Prefix__c = 'TST',
                Subscription25__Billing_Email_Address__c = 'dealers.test@mvsc.invalid.test'
            );
            update new Account(Id = con.AccountId, Reseller_Name__c = '1');
        }
        Test_Svc_DealerUserSetup.freeCommunitySeat();
        User u = Svc_DealerUserSetup.enableDealerUser(con.Id);

        System.assertEquals('dealers.test@mvsc.invalid.test', Ctrl_DealerPortalEmail.resolveContactEmail(u.Id));
    }

    @IsTest
    static void testFallbacks() {
        System.assertEquals(Ctrl_DealerPortalEmail.FALLBACK_EMAIL, Ctrl_DealerPortalEmail.resolveContactEmail(null));
        // Internal user without contact
        System.assertEquals(Ctrl_DealerPortalEmail.FALLBACK_EMAIL, Ctrl_DealerPortalEmail.resolveContactEmail(UserInfo.getUserId()));

        Ctrl_DealerPortalEmail ctrl = new Ctrl_DealerPortalEmail();
        ctrl.recipientUserId = UserInfo.getUserId();
        System.assertEquals(Ctrl_DealerPortalEmail.FALLBACK_EMAIL, ctrl.getContactEmail());
        System.assert(ctrl.getContactEmailHtml().contains('mailto:' + Ctrl_DealerPortalEmail.FALLBACK_EMAIL), ctrl.getContactEmailHtml());
    }
}
