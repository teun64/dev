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

    //bulk flow run: every request gets its own result, in request order
    @isTest
    private static void testGenerateCryptoStringBulk(){
        List<Util_Crypto.cryptoStringRequests> requests = new List<Util_Crypto.cryptoStringRequests>();
        for (String s : new List<String>{'TEST', 'TEST2', 'TEST3'}) {
            Util_Crypto.cryptoStringRequests ci = new Util_Crypto.cryptoStringRequests();
            ci.inputString = s;
            ci.key = 'MD5';
            requests.add(ci);
        }

        Test.startTest();
        List <Util_Crypto.cryptoStringResults> co = Util_Crypto.generateCryptoString(requests);
        Test.stopTest();

        System.assertEquals(3, co.size());
        System.assertEquals('033bd94b1168d7e4f0d644c3c95e35bf', co[0].encryptedString);
        System.assertNotEquals(co[0].encryptedString, co[1].encryptedString);
        System.assertNotEquals(co[1].encryptedString, co[2].encryptedString);
    }
}