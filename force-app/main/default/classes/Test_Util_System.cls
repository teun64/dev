@isTest
private class Test_Util_System {

    @isTest
    private static void testUtil_System(){    

        Test.startTest();
        string countryISO2 = Util_System.getISO2CountryCode('BVT');
        string fn = Util_System.sanitizeFileName('000%%%.txt');
        string sGUID = Util_System.generateGUID();
        string sClean = Util_System.cleanString('**//// {S]@i%nt:?,-e$r#k)l(!a^.}a][s //**');
        string sCleanName = Util_System.cleanName('Arjén J.W. Hooiveld & \nSöhne B.V.');
        string sToken = Util_System.generateRandomString(15);
        string salesChannel = Util_System.getSalesChannel('4');
        string salesMarket = Util_System.getSalesMarket('0');
        string purchaseOrigin = Util_System.getPurchaseOrigin('2');
        string terminationOption = Util_System.getTerminationOption('2');
        string productId = Util_System.getReplacedProductId('1083-sv-3');
        string currencySymbol = Util_System.getCurrencySign('EUR');
        string currencyCents1 = Util_System.getCurrencyCents(10.0);
        string currencyCents2 = Util_System.getCurrencyCents(20);
        string email1 = Util_System.sanitizeEmail('SalesForce@MI.com');
        string email2 = Util_System.sanitizeEmail('Sales+Cloud@MI.com');
        string email3 = Util_System.sanitizeEmail('');
        string externalId = Util_System.getPlatformIdField(1);
        string multiPickValue = Util_System.addMultiPicklistValue('1;2','3;4');
        boolean ds1 = Util_System.getDataSetting('Contact_UniqueEmailAddresses');
        boolean ds2 = Util_System.getDataSetting('Contact_UniqueEmailAddresses');
        boolean ds3 = Util_System.getDataSetting('Contact_NoSetting');
        Test.stoptest();
        
        System.assertEquals('BV',countryISO2);
        System.assertEquals('000.txt',fn);
        System.assertEquals('**/ Sinterklaas /**',sClean);
        System.assertEquals('Arjén J.W. Hooiveld & Söhne B.V.',sCleanName);  
        System.assertEquals(36,sGUID.length());
        System.assertEquals(15,sToken.length());
        System.assertEquals('Echoes',salesChannel);
        System.assertEquals('Internal',salesMarket);       
        System.assertEquals('SERVICE_CHANGE',purchaseOrigin);
        System.assertEquals('Full Credit',terminationOption); 
        System.assertEquals('244-sv-3',productId); 
        System.assertEquals('€',currencySymbol);
        System.assertEquals('10.00',currencyCents1);
        System.assertEquals('20.00',currencyCents2);
        System.assertEquals('salesforce@mi.com',email1);
        System.assertEquals('sales@mi.com',email2);
        System.assertEquals(null,email3);
        System.assertEquals('extId_1__c',externalId);
        System.assertEquals('1;2;3;4', multiPickValue);
        System.assertEquals(ds1,ds2);
        System.assertEquals(false,ds3);
    }

    @IsTest
    static void testGetCustomLabels_DefaultLanguage() {
        List<String> labelNames = new List<String>{
            'testGetCustomLabel1',
            'testGetCustomLabel2'
        };

        Test.startTest();
        Map<String, String> results =
            Util_System.getCustomLabels(labelNames, 'en_US');
        Test.stopTest();

        // Assertions:
        System.assertEquals(2, results.size(), 'Should return 2 labels');

        // Validate a real label returns a value
        System.assertNotEquals(
            null,
            results.get('testGetCustomLabel1'),
            'testGetCustomLabel1 - > default language'
        );
    }

    @IsTest
    static void testGetCustomLabels_TranslationNL() {
        List<String> labelNames = new List<String>{ 'testGetCustomLabel1' };

        // Use a non-existent language to force NOT_FOUND path
        String returnLanguage = 'nl_NL';

        Test.startTest();
        Map<String, String> results =
            Util_System.getCustomLabels(labelNames, returnLanguage);
        Test.stopTest();

        // Expect NOT_FOUND indicator
        System.assertEquals(
            'testGetCustomLabel1 - > Taal is NL',
            results.get('testGetCustomLabel1'),
            'Label should return the ' + returnLanguage + ' language as result (\'testGetCustomLabel1 - > Taal is NL\')'
        );
    }

    @IsTest
    static void testGetCustomLabels_TranslationNotFound() {
        List<String> labelNames = new List<String>{ 'testGetCustomLabel1' };

        // Use a non-existent language to force NOT_FOUND path
        String returnLanguage = 'zz_ZZ';

        Test.startTest();
        Map<String, String> results =
            Util_System.getCustomLabels(labelNames, returnLanguage);
        Test.stopTest();

        // Expect NOT_FOUND indicator
        System.assertEquals(
            'testGetCustomLabel1 - > default language',
            results.get('testGetCustomLabel1'),
            'Missing language should produce default language result'
        );
    }

    @IsTest
    static void testGetCustomLabels_InvalidLabelName() {
        List<String> labelNames = new List<String>{ 'LabelThatDoesNotExist' };

        String returnLanguage = 'en_US';        

        Test.startTest();
        Map<String, String> results =
        Util_System.getCustomLabels(labelNames, returnLanguage);
        Test.stopTest();

        // Because label does NOT exist, exception → NOT_FOUND result
        System.assertEquals(
            'LabelThatDoesNotExist_' + returnLanguage + '_NOT_FOUND',
            results.get('LabelThatDoesNotExist'),
            'Missing label should return NOT_FOUND fallback'
        );
    }
}
