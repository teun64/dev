@IsTest
private class Test_Btch_SetAccountPrimaryBrand {

    @TestSetup
    static void makeData() {
        insert new List<Account>{
            Test_Data.createAccount('Btch PrimaryBrand NL', '9031', 'B2B', false),
            Test_Data.createAccount('Btch PrimaryBrand G4S', '9032', 'B2B', false),
            Test_Data.createAccount('Btch PrimaryBrand BE', '9033', 'B2B', false),
            Test_Data.createAccount('Btch PrimaryBrand Echoes', '9034', 'B2B', false),
            Test_Data.createAccount('Btch PrimaryBrand DE', '9035', 'B2B', false),
            Test_Data.createAccount('Btch PrimaryBrand UK', '9036', 'B2B', false)
        };

        List<Account> accs = [SELECT Id, Name, Reseller_Name__c FROM Account WHERE Name LIKE 'Btch PrimaryBrand%'];
        Map<String, String> nameToReseller = new Map<String, String>{
            'Btch PrimaryBrand NL'     => '1',
            'Btch PrimaryBrand G4S'    => '2',
            'Btch PrimaryBrand BE'     => '3',
            'Btch PrimaryBrand Echoes' => '4',
            'Btch PrimaryBrand DE'     => '5',
            'Btch PrimaryBrand UK'     => '6'
        };
        for (Account acc : accs) {
            acc.Reseller_Name__c = nameToReseller.get(acc.Name);
        }
        update accs;
    }

    @IsTest
    static void testBatch_setsPrimaryBrandFromResellerName() {
        Test.startTest();
        Database.executeBatch(new Btch_SetAccountPrimaryBrand(), 200);
        Test.stopTest();

        Map<String, String> nameToBrand = new Map<String, String>();
        for (Account acc : [SELECT Name, PrimaryBrand__c FROM Account WHERE Name LIKE 'Btch PrimaryBrand%']) {
            nameToBrand.put(acc.Name, acc.PrimaryBrand__c);
        }

        System.assertEquals('M', nameToBrand.get('Btch PrimaryBrand NL'), 'Reseller 1 -> M');
        System.assertEquals('M', nameToBrand.get('Btch PrimaryBrand G4S'), 'Reseller 2 -> M');
        System.assertEquals('M', nameToBrand.get('Btch PrimaryBrand BE'), 'Reseller 3 -> M');
        System.assertEquals('E', nameToBrand.get('Btch PrimaryBrand Echoes'), 'Reseller 4 -> E');
        System.assertEquals('M', nameToBrand.get('Btch PrimaryBrand DE'), 'Reseller 5 -> M');
        System.assertEquals('M', nameToBrand.get('Btch PrimaryBrand UK'), 'Reseller 6 -> M');
    }
}
