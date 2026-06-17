public with sharing class Inv_signOpportunityOffer {
    @InvocableMethod(label='signOpportunityOffer' description='Sends the opportunity offer out for signing' category='SignButler')
    public static List <signOpportunityOfferResults> signOpportunityOffer(List<signOpportunityOfferRequests> requestList) {       
        String returnValue = '';
   
        if (requestList.size() > 0) {
            returnValue = Util_Butler.signOpportunityOffer(requestList[0].opportunityId);
        }
 
        //Create a Results object to hold the return values
        signOpportunityOfferResults response = new signOpportunityOfferResults();

        //Add the return values to the Results object
        response.resultMessage = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<signOpportunityOfferResults> responseWrapper= new List<signOpportunityOfferResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow
    public class signOpportunityOfferRequests{
                
        @InvocableVariable(label='opportunityId' description='input: opportunityId' required=true)
        public String opportunityId;
            
    }

    public class signOpportunityOfferResults{
                
        @InvocableVariable(label='resultMessage' description='output : result message' required=true)
        public String resultMessage;
            
    }
}