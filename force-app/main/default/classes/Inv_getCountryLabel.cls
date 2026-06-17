public with sharing class Inv_getCountryLabel {
    @InvocableMethod(label='getCountryLabel' description='gets the country name (label) from country picklist based on ISO2 country code' category='Address')
    public static List <getCountryLabelResults> getCountryLabel(List<getCountryLabelRequests> requestList) {       
        String returnValue = '';
   
        if (requestList.size() > 0) {
            returnValue = Util_AddressLabel.getCountryLabel(requestList[0].countryCode);
        }
 
        //Create a Results object to hold the return values
        getCountryLabelResults response = new getCountryLabelResults();

        //Add the return values to the Results object
        response.countryLabel = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<getCountryLabelResults> responseWrapper= new List<getCountryLabelResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow test
    public class getCountryLabelRequests{
                
        @InvocableVariable(label='countryCode' description='input: Country (ISO2) code' required=true)
        public String countryCode;
            
    }

    public class getCountryLabelResults{
                
        @InvocableVariable(label='countryLabel' description='output : countryLabel related to given Country Code' required=true)
        public String countryLabel;
            
    }
}