@IsTest(SeeAllData=false)
private class Test_Ctrl_DealerPortalLogin {

    @IsTest
    static void testResolveUsername_email() {
        String username = Ctrl_DealerPortalLogin.resolveUsername(' Teun.Rietman+acc@Outlook.com ');
        System.assertEquals(Svc_DealerUserSetup.buildUsername('teun.rietman@outlook.com').toLowerCase(), username);
        System.assert(!username.contains('+'), 'dbg: ' + username);
    }

    @IsTest
    static void testResolveUsername_fullDealerUsername() {
        String full = Svc_DealerUserSetup.buildUsername('dealer@example.com').toLowerCase();
        System.assertEquals(full, Ctrl_DealerPortalLogin.resolveUsername(full));
    }

    @IsTest
    static void testResolveUsername_refused() {
        System.assertEquals(null, Ctrl_DealerPortalLogin.resolveUsername(null));
        System.assertEquals(null, Ctrl_DealerPortalLogin.resolveUsername('no-at-sign'));
        System.assertEquals(null, Ctrl_DealerPortalLogin.resolveUsername('dealer@example.com.midealer.othersandbox'),
            'A dealer username of another org should not be passed on');
    }

    @IsTest
    static void testSafeStartUrl() {
        System.assertEquals('/shop', Ctrl_DealerPortalLogin.safeStartUrl('/shop'));
        System.assertEquals(null, Ctrl_DealerPortalLogin.safeStartUrl('https://evil.example.com'));
        System.assertEquals(null, Ctrl_DealerPortalLogin.safeStartUrl('//evil.example.com'));
        System.assertEquals(null, Ctrl_DealerPortalLogin.safeStartUrl('javascript:alert(1)'));
        System.assertEquals(null, Ctrl_DealerPortalLogin.safeStartUrl(''));
    }

    @IsTest
    static void testLogin_failureIsGeneric() {
        for (String identifier : new List<String>{ 'unknown@example.com', 'no-at-sign', null }) {
            try {
                Ctrl_DealerPortalLogin.login(identifier, 'wrong', '/shop');
                System.assert(false, 'Expected a failure for ' + identifier);
            } catch (AuraHandledException e) {
                System.assertEquals(Ctrl_DealerPortalLogin.LOGIN_FAILED, e.getMessage());
            }
        }
    }

    @IsTest
    static void testForgotPassword_neverThrows() {
        Ctrl_DealerPortalLogin.forgotPassword('unknown@example.com');
        Ctrl_DealerPortalLogin.forgotPassword('no-at-sign');
        Ctrl_DealerPortalLogin.forgotPassword(null);
        System.assert(true);
    }
}
