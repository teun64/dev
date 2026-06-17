public with sharing class Inv_getPaymentProviderConstant {

    //change to Inv_GenerateRandomString
    @InvocableMethod(label='getPaymentProviderConstant' description='Get the value of a (pp)Constant' category='Payment Provider')
    public static List<ppConstantResult> getPaymentProviderConstant(List<ppConstantRequest> requestList) {       
        String returnValue = '';
    
        if (requestList.size() > 0) {
            returnValue = Util_System.GetPaymentProviderConstant(requestList[0].ppConstantKey);
        }
    
        //Create a Results object to hold the return values
        ppConstantResult response = new ppConstantResult();

        //Add the return values to the Results object
        response.ppConstantValue = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<ppConstantResult> responseWrapper= new List<ppConstantResult>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow
    public class ppConstantRequest{
                
        @InvocableVariable(label='ppConstantKey' description='The Payment Provider Key to retrieve' required=true)
        public String ppConstantKey;
            
    }

    public class ppConstantResult{
                
        @InvocableVariable(label='ppConstantValue' description='The Payment Provider Value result' required=true)
        public String ppConstantValue;
            
    }
}