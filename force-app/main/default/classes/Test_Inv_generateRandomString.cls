@isTest
private class Test_Inv_generateRandomString {

    @isTest
    private static void testGenerateRandomString() {
        Test.starttest();
        Inv_generateRandomString.randomStringRequests inp = new Inv_generateRandomString.randomStringRequests();
        inp.Length = 15;
        List<Inv_generateRandomString.randomStringResults> res = Inv_generateRandomString.generateRandomString(new List<Inv_generateRandomString.randomStringRequests> {inp});
        string sKey = res[0].Code;
        Test.stoptest();

        System.assertEquals(15,sKey.length());
    }
}