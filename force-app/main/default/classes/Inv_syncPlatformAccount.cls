public without sharing  class Inv_syncPlatformAccount {
    @InvocableMethod(label='syncPlatformAccount' description='Synchronizes the Account to the given Platform' category='Platform')
    public static void syncPlatformAccount(List<syncPlatformAccountRequests> requestList) {  

        if (requestList.size() >= 1) {
            Util_Platform.syncAccount(requestList[0].accountId, requestList[0].platformId);
        }
 
    }

    //input details that comes to apex from flow
    public class syncPlatformAccountRequests{
                
        @InvocableVariable(label='accountId' description='The requested account Id' required=true)
        public id accountId; 

        @InvocableVariable(label='platformId' description='the platform to send the request to' required=true)
        public string platformId;            
    }
    
}