public with sharing class Util_Crypto {

    
    @InvocableMethod(label='generateCryptoString' description='Generates crytpo string based on given string and key' category='String')
    public static List <cryptoStringResults> generateCryptoString(List<cryptoStringRequests> requestList) {       
        String returnValue = '';

        if (requestList.size() > 0) {

            if ((requestList[0].inputString != null) && (requestList[0].key != null)) {
                Blob b = Crypto.generateDigest(requestList[0].key, Blob.valueOf(requestList[0].inputString));
            
                returnValue = EncodingUtil.convertToHex(b);
                //returnValue = EncodingUtil.base64Encode(b);
            }
        }
   
        //Create a Results object to hold the return values
        cryptoStringResults responseList = new cryptoStringResults();

        //Add the return values to the Results object
        responseList.encryptedString = returnValue;

        //Wrap the Results object in a List container 
        //(an extra step added to allow this interface to also support bulkification)
        List<cryptoStringResults> responseWrapper= new List<cryptoStringResults>();
        responseWrapper.add(responseList);
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