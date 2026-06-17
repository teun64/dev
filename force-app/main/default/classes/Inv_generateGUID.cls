public with sharing class Inv_generateGUID {
    //change to Inv_GenerateGUID
    @InvocableMethod(label='generateGUID' description='Generates a GUID' category='String')
    public static List <guidResults> generateGUID() {       
        String returnValue = Util_System.generateGUID();

        //Create a Results object to hold the return values
        guidResults response = new guidResults();

        //Add the return values to the Results object
        response.guid = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<guidResults> responseWrapper= new List<guidResults>();
        responseWrapper.add(response);
        return responseWrapper;
    }

    public class guidResults{
                
        @InvocableVariable(label='GUID' description='The requested GUID' required=true)
        public String guid;
            
    }
}