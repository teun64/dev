public with sharing class Inv_generateRandomString {
    //change to Inv_GenerateRandomString
    @InvocableMethod(label='generateRandomString' description='Generates a random string based on given lentgh' category='String')
    public static List <randomStringResults> generateRandomString(List<randomStringRequests> requestList) {       
        String returnValue = '';
    
        if (requestList.size() > 0) {
            returnValue = Util_System.generateRandomString(requestList[0].length);
        }
    
        //Create a Results object to hold the return values
        randomStringResults response = new randomStringResults();

        //Add the return values to the Results object
        response.code = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<randomStringResults> responseWrapper= new List<randomStringResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow
    public class randomStringRequests{
                
        @InvocableVariable(label='Length' description='The lenght of the requested string' required=true)
        public Integer length;
            
    }

    public class randomStringResults{
                
        @InvocableVariable(label='Code' description='A reandom generated string based ont the given length' required=true)
        public String code;
            
    }
}