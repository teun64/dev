public with sharing class Inv_getDataSetting {
    @InvocableMethod(label='getDataSetting' description='Get a data setting' category='Data Setting')
    public static List <getDataSettingResults> getDataSetting(List<getDataSettingRequests> requestList) {       
        Boolean returnValue = false;
   
        if (requestList.size() > 0) {
            returnValue = Util_System.getDataSetting(requestList[0].setting);
        }
 
        //Create a Results object to hold the return values
        getDataSettingResults response = new getDataSettingResults();

        //Add the return values to the Results object
        response.value = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<getDataSettingResults> responseWrapper= new List<getDataSettingResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow test
    public class getDataSettingRequests{
                
        @InvocableVariable(label='setting' description='input: Requested Setting' required=true)
        public String setting;
            
    }

    public class getDataSettingResults{
                
        @InvocableVariable(label='value' description='output : the setting value' required=true)
        public Boolean value;
            
    }
}