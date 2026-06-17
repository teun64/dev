public with sharing class Inv_getStateLabel {
    @InvocableMethod(label='getStateLabel' description='gets the state name (label) from state picklist based on ISO2 state code' category='Address')
    public static List <getStateLabelResults> getStateLabel(List<getStateLabelRequests> requestList) {       
        String returnValue = '';
   
        if (requestList.size() > 0) {
            returnValue = Util_AddressLabel.getStateLabel(requestList[0].stateCode);
        }
 
        //Create a Results object to hold the return values
        getStateLabelResults response = new getStateLabelResults();

        //Add the return values to the Results object
        response.stateLabel = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<getStateLabelResults> responseWrapper= new List<getStateLabelResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow test
    public class getStateLabelRequests{
                
        @InvocableVariable(label='stateCode' description='input: State (ISO2) code' required=true)
        public String stateCode;
            
    }

    public class getStateLabelResults{
                
        @InvocableVariable(label='stateLabel' description='output : stateLabel related to given State Code' required=true)
        public String stateLabel;
            
    }
}