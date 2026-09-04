@isTest
private class Test_Inv_generateGUID {

    @isTest
    private static void testGenerateGUID() {
        Test.starttest();
        List<Inv_generateGUID.guidResults> res = Inv_generateGUID.generateGUID(new List<Boolean>{true});
        string sGUID = res[0].Guid;
        Test.stoptest();

        System.assertEquals(36,sGUID.length());
    }

    @isTest
    private static void testGenerateGUID_Bulk() {
        Test.startTest();
        List<Inv_generateGUID.guidResults> res = Inv_generateGUID.generateGUID(new List<Boolean>{true, true, true});
        Test.stopTest();

        System.assertEquals(3, res.size(), 'Expected one GUID per bulk request');
        Set<String> guids = new Set<String>();
        for (Inv_generateGUID.guidResults r : res) {
            System.assertEquals(36, r.guid.length());
            guids.add(r.guid);
        }
        System.assertEquals(3, guids.size(), 'GUIDs should be unique per request');
    }
}