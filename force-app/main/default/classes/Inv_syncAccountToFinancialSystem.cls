public without sharing class Inv_syncAccountToFinancialSystem {
  @InvocableMethod(
    label='syncAccountToFinancialSystem'
    description='Synchronize the account to the Financial System'
    category='FinancialSystem'
  )
  public static List<syncAccountToFinancialSystemResults> syncAccountToFinancialSystem(
    List<syncAccountToFinancialSystemRequests> requestList
  ) {
    String returnValue = '';

    if (requestList.size() > 0) {
      //Util_Exact.syncOrderAsync(accountIds[0]);
      try {
        List<string> returnValues = Util_Exact.syncAccount(
          requestList[0].accountId
        );

        if (returnValues.size() > 0) {
          returnValue = returnValues[0];
        } else {
          returnValue =
            'This account (' +
            requestList[0].accountId +
            ') is synced to the financial system.';
        }
      } catch (Util_System.FinancialSyncException e) {
        returnValue = 'Error: ' + e.getMessage();
      } catch (Exception e) {
        returnValue = 'Error: ' + e.getMessage();
      }
    }

    //Create a Results object to hold the return values
    syncAccountToFinancialSystemResults response = new syncAccountToFinancialSystemResults();

    //Add the return values to the Results object
    response.resultMessage = returnValue;

    //Wrap the Results object in a List container
    //(an extra step added to allow this interface to also support bulkification)
    List<syncAccountToFinancialSystemResults> responseWrapper = new List<syncAccountToFinancialSystemResults>();
    responseWrapper.add(response);
    return responseWrapper;
  }

  //input details that comes to apex from flow
  public class syncAccountToFinancialSystemRequests {
    @InvocableVariable(
      label='accountId'
      description='input: accountId'
      required=true
    )
    public String accountId;
  }

  public class syncAccountToFinancialSystemResults {
    @InvocableVariable(
      label='resultMessage'
      description='output : result message'
      required=true
    )
    public String resultMessage;
  }
}
