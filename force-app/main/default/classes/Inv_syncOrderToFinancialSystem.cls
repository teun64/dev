public with sharing class Inv_syncOrderToFinancialSystem {

    @InvocableMethod(label='syncOrderToFinancialSystem' description='Synchronize the order to the Financial System' category='FinancialSystem')
    public static List <syncOrderToFinancialSystemResults> syncOrderToFinancialSystem(List<syncOrderToFinancialSystemRequests> requestList) {       
        String returnValue = '';
   
        if (requestList.size() > 0) {
            //Util_Exact.syncOrderAsync(orderIds[0]);
            try {
                // the user marks the order; Batch_FinancialSystemOrderSync creates it in Exact and activates it
                Util_FinancialSystem_Order.flagOrders(new Set<Id>{ (Id) requestList[0].orderId });
                returnValue = 'This order (' + requestList[0].orderId + ') is queued for the financial system and is created there within a few minutes.';
            } catch(Exception e) {
                returnValue = 'Error: ' + e.getMessage();
            }
        }
 
        //Create a Results object to hold the return values
        syncOrderToFinancialSystemResults response = new syncOrderToFinancialSystemResults();

        //Add the return values to the Results object
        response.resultMessage = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<syncOrderToFinancialSystemResults> responseWrapper= new List<syncOrderToFinancialSystemResults>();
        responseWrapper.add(response);
        return responseWrapper; 
    }

    //input details that comes to apex from flow
    public class syncOrderToFinancialSystemRequests{
                
        @InvocableVariable(label='orderId' description='input: orderId' required=true)
        public String orderId;
            
    }

    public class syncOrderToFinancialSystemResults{
                
        @InvocableVariable(label='resultMessage' description='output : result message' required=true)
        public String resultMessage;
            
    }

}