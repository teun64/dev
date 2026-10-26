@IsTest(SeeAllData=false)
private class Test_Ctrl_DealerPortalEmail {

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
