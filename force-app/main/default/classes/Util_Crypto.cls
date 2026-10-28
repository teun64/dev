public with sharing class Util_Crypto {

    
    @InvocableMethod(label='generateCryptoString' description='Generates crytpo string based on given string and key' category='String')
    public static List <cryptoStringResults> generateCryptoString(List<cryptoStringRequests> requestList) {
        // 20261028 TRi one result per request, in request order: a bulk flow run (e.g. several payments set up in one transaction)
        // gets one request per interview; returning only one result left the other records without a token
        List<cryptoStringResults> responseWrapper= new List<cryptoStringResults>();

        for (cryptoStringRequests request : requestList) {
            String returnValue = '';

            if ((request.inputString != null) && (request.key != null)) {
                Blob b = Crypto.generateDigest(request.key, Blob.valueOf(request.inputString));

                returnValue = EncodingUtil.convertToHex(b);
                //returnValue = EncodingUtil.base64Encode(b);
            }

            cryptoStringResults responseList = new cryptoStringResults();
            responseList.encryptedString = returnValue;
            responseWrapper.add(responseList);
        }

        return responseWrapper;
    }

    //input details that comes to apex from flow
    public class cryptoStringRequests{
                
        @InvocableVariable(label='inputString' description='The String to Encrypt' required=true)
        public string inputString;

        @InvocableVariable(label='Key' description='The Encryption key f.e. "MD5"' required=true)
        public string key;
            
    }

    public class cryptoStringResults{
                
        @InvocableVariable(label='encryptedString' description='A reandom generated string based ont the given length' required=true)
        public String encryptedString;
            
    }
}