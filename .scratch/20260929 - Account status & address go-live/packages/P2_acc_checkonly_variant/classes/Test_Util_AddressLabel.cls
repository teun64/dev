@isTest
private class Test_Util_AddressLabel {

    @IsTest
    static void testCountryAndStateLabels() {

        Test.startTest();
        // Test country label lookup
        String country = Util_AddressLabel.getCountryLabel('US');
        // Test state label lookup
        String state = Util_AddressLabel.getStateLabel('CA');
        Test.stopTest();

        System.assertNotEquals(null, country, 'Country label should not be null');
        System.assert(country.contains('United') || country.contains('America'),'Expected US to map to a valid country label');
        System.assertNotEquals(null, state, 'State label should not be null');
        System.assert(state.contains('Calif'),'Expected CA to map to a valid state label');
    }
}