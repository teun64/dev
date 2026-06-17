@isTest
private class Test_Inv_generateGUID {

    @isTest
    private static void testGenerateGUID() {
        Test.starttest();
        List<Inv_generateGUID.guidResults> res = Inv_generateGUID.generateGUID();
        string sGUID = res[0].Guid;
        Test.stoptest();

        System.assertEquals(36,sGUID.length());
    }
}