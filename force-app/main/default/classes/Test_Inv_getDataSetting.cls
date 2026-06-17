@isTest
private class Test_Inv_getDataSetting {

    @isTest
    static void TestGetDataSetting() {
        Inv_getDataSetting.getDataSettingRequests inp1 = new Inv_getDataSetting.getDataSettingRequests();
        inp1.setting = 'Contact_UniqueEmailAddresses';
        list<Inv_getDataSetting.getDataSettingRequests> inpList1 = new list<Inv_getDataSetting.getDataSettingRequests>();
        inpList1.add(inp1);
        Inv_getDataSetting.getDataSettingRequests inp2 = new Inv_getDataSetting.getDataSettingRequests();
        inp2.setting = 'Contact_UniqueEmailAddresses';
        list<Inv_getDataSetting.getDataSettingRequests> inpList2 = new list<Inv_getDataSetting.getDataSettingRequests>();
        inpList2.add(inp2);
        Inv_getDataSetting.getDataSettingRequests inp3 = new Inv_getDataSetting.getDataSettingRequests();
        inp3.setting = 'Contact_NoSetting';
        list<Inv_getDataSetting.getDataSettingRequests> inpList3 = new list<Inv_getDataSetting.getDataSettingRequests>();
        inpList3.add(inp3);

        Test.startTest();
        // error sign no document / not ready
        List<Inv_getDataSetting.getDataSettingResults> resList1 = Inv_getDataSetting.getDataSetting(inpList1);
        list<Inv_getDataSetting.getDataSettingResults> resList2 = Inv_getDataSetting.getDataSetting(inpList2);
        list<Inv_getDataSetting.getDataSettingResults> resList3 = Inv_getDataSetting.getDataSetting(inpList3);
        Test.stopTest();


        System.assertEquals(resList1[0].value, resList2[0].value);  
        System.assertEquals(false, resList3[0].value);  
    }
}