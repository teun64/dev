public with sharing class Inv_sanitizeEmail {
    @InvocableMethod(label='sanitizeEmail' description='cleans an email address and removes + part in user name' category='Email')
    public static List <sanitizeEmailResults> sanitizeEmail(List<sanitizeEmailRequests> requestList) {       
        String returnValue = '';
   
        if (requestList.size() > 0) {
            returnValue = Util_System.sanitizeEmail(requestList[0].email);
        }
 
        //Create a Results object to hold the return values
        sanitizeEmailResults response = new sanitizeEmailResults();

        //Add the return values to the Results object
        response.email = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<sanitizeEmailResults> responseWrapper= new List<sanitizeEmailResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow test
    public class sanitizeEmailRequests{
                
        @InvocableVariable(label='email' description='input: Email Address' required=true)
        public String email;
            
    }

    public class sanitizeEmailResults{
                
        @InvocableVariable(label='email' description='output : cleaned Email Address' required=true)
        public String email;
            
    }
}