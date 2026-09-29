public without sharing class Util_AddressLabel {

    private static Map<String, String> countryLabels;
    private static Map<String, String> stateLabels;

    static {
        countryLabels = new Map<String, String>();
        // Describe the CountryCode field on the User object to get picklist values
        for (Schema.PicklistEntry ple : User.CountryCode.getDescribe().getPicklistValues())  {
            countryLabels.put(ple.getValue(), ple.getLabel());
        }

        stateLabels = new Map<String, String>();
        // Describe the CountryCode field on the User object to get picklist values
        for (Schema.PicklistEntry ple : User.StateCode.getDescribe().getPicklistValues())  {
            stateLabels.put(ple.getValue(), ple.getLabel());
        }
    }

    public static String getCountryLabel(String iso) {
        return countryLabels.get(iso);
    }

    public static String getStateLabel(String iso) {
        return stateLabels.get(iso);
    }

}