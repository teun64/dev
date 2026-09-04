public with sharing class Inv_generateGUID {
    //change to Inv_GenerateGUID
    @InvocableMethod(label='generateGUID' description='Generates a GUID' category='String')
    public static List <guidResults> generateGUID(List<Boolean> requests) {
        //takes a List input (even though unused) so the platform bulkifies this 1 result per flow
        //interview instead of collapsing many concurrent interviews onto a single shared result
        List<guidResults> responseWrapper = new List<guidResults>();
        for (Integer i = 0; i < requests.size(); i++) {
            guidResults response = new guidResults();
            response.guid = Util_System.generateGUID();
            responseWrapper.add(response);
        }
        return responseWrapper;
    }

    public class guidResults{
                
        @InvocableVariable(label='GUID' description='The requested GUID' required=true)
        public String guid;
            
    }
}