@isTest
public with sharing class Test_Util_Crypto {

    @isTest
    private static void testGenerateCryptoString(){

        Util_Crypto.cryptoStringRequests ci = new Util_Crypto.cryptoStringRequests();
       
        ci.inputString = 'TEST';
        ci.key = 'MD5';       
        
        Test.startTest();
        List <Util_Crypto.cryptoStringResults> co = Util_Crypto.generateCryptoString(new List<Util_Crypto.cryptoStringRequests> {ci});
        Test.stopTest();
     
        System.assertEquals(co[0].encryptedString, '033bd94b1168d7e4f0d644c3c95e35bf' );
    }
}