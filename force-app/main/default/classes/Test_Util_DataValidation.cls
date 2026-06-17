@IsTest(SeeAllData=true)
private class Test_Util_DataValidation {

    // ------------------------------------------------------------
    // CoC validation
    // ------------------------------------------------------------
    @IsTest
    static void testValidateCoC_NL_Valid() {
        // Example NL KvK number (8 digits, MOD11)
        Util_DataValidation.FieldData result =
            Util_DataValidation.validateCoC('NL', '12345678');

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.isValid, result.errorMessage);
    }

    @IsTest
    static void testValidateCoC_SE_Mod10() {
        // Sweden CoC where MOD10 is applied to first 9 digits
        Util_DataValidation.FieldData result =
            Util_DataValidation.validateCoC('SE', '5560160680');

        System.assertNotEquals(null, result);
        System.assertEquals(true, result.isValid, result.errorMessage);
    }

    // ------------------------------------------------------------
    // VAT validation
    // ------------------------------------------------------------
    @IsTest
    static void testValidateVAT_NL_Valid() {
        // NL VAT example: NL123456782B01
        Util_DataValidation.FieldData result =
            Util_DataValidation.validateVAT('NL', 'NL123456782B01');

        System.assertNotEquals(null, result);
        System.assertEquals(true, result.isValid, result.errorMessage);
    }

    @IsTest
    static void testValidateVAT_BE_Valid() {
        // Belgium VAT: BE0123456749
        Util_DataValidation.FieldData result =
            Util_DataValidation.validateVAT('BE', 'BE0123456749');

        System.assertNotEquals(null, result);
        System.assertEquals(true, result.isValid, result.errorMessage);
    }

    @IsTest
    static void testValidateVAT_InvalidChecksum() {
        Util_DataValidation.FieldData result =
            Util_DataValidation.validateVAT('BE', 'BE0123456700');

        System.assertEquals(false, result.isValid);
        System.assert(result.errorMessage != null);
    }

    // ------------------------------------------------------------
    // IBAN validation
    // ------------------------------------------------------------
    @IsTest
    static void testValidateIBAN_Valid() {
        // Valid NL IBAN
        String expectedValue = 'NL91ABNA0417164300';
        String input = expectedValue.toLowerCase(); // 'nl91abna0417164300';
        Test.startTest();
        Util_DataValidation.FieldData result = Util_DataValidation.validateIBAN(input);
        Test.stopTest();
   
        System.assertEquals(expectedValue, result.value, 'Value should be normalized');
        System.assertEquals(true, result.isValid,  'IBAN should be valid, no error expected');
    }
    @IsTest
    static void testValidateIBAN_Invalid_Pattern() {
        // Valid NL IBAN
        String expectedValue = 'NL91ANA0417164300';
        String input = expectedValue.toLowerCase(); // 'nl91ana0417164300';
        Test.startTest();
        Util_DataValidation.FieldData result = Util_DataValidation.validateIBAN(input);
        Test.stopTest();
   
        System.assertEquals(expectedValue, result.value, 'Value should be normalized');
        System.assertEquals(false, result.isValid,  result.errorMessage + '');
    }

    @IsTest
    static void testValidateIBAN_Invalid_CheckSum() {
        String expectedValue = 'NL00ABNA0417164300';
        String input = expectedValue.toLowerCase(); // 'nl00abna0417164300';

        Test.startTest();
        Util_DataValidation.FieldData result = Util_DataValidation.validateIBAN(input);
        Test.stopTest();

        System.assertEquals(expectedValue, result.value, 'Value should be normalized');
        System.assertEquals(false, result.isValid, result.errorMessage + '');
    }

    // ------------------------------------------------------------
    // Address normalization & validation
    // ------------------------------------------------------------
    @IsTest
    static void testNormalizeAddress_NL() {
        Util_DataValidation.AddressData input = new Util_DataValidation.AddressData();

        input.street      = 'van den korte straat';
        input.houseNumber = '12-a';
        input.postalCode  = '1234ab';
        input.city        = 'amsterdam';
        input.countryCode = 'NL';

        Test.startTest();
        Util_DataValidation.AddressData result = Util_DataValidation.normalizeAddress(input);
        Test.stopTest();

        System.assertEquals('Van den Korte Straat', result.street);
        System.assertEquals('12-A', result.houseNumber);
        System.assertEquals('1234 AB', result.postalCode);
        System.assertEquals(input.city.toUpperCase(), result.city);
        System.assertEquals(true, result.isValid, 'Address should be normalized and validated');
    }

    @IsTest
    static void testNormalizeAddress_InvalidPostal() {
        Util_DataValidation.AddressData input = new Util_DataValidation.AddressData();

        input.street      = 'Main street';
        input.houseNumber = '1';
        input.postalCode  = 'ABCDE';
        input.city        = 'Test';
        input.countryCode = 'NL';

        Test.startTest();   
        Util_DataValidation.AddressData result = Util_DataValidation.normalizeAddress(input);
        Test.stopTest();

        System.assertEquals(false, result.isValid, result.errorMessage);
        System.assert(result.errorMessage != null);
    }

    // ------------------------------------------------------------
    // Pattern helper
    // ------------------------------------------------------------
    @IsTest
    static void testMatchesPattern_WrappedAndUnwrapped() {
        // Should match regardless of ^ $
        System.assertEquals(
            true,
            Util_DataValidation.matchesPattern('1234AB', '[0-9]{4}[A-Z]{2}')
        );

        System.assertEquals(
            true,
            Util_DataValidation.matchesPattern('1234AB', '^[0-9]{4}[A-Z]{2}$')
        );
    }

    // ------------------------------------------------------------
    // Checksum helpers (direct)
    // ------------------------------------------------------------
    @IsTest
    static void testLuhn() {
        // Valid Luhn
        System.assertEquals(true,
            Util_DataValidation.isValidLuhn('79927398713')
        );
    }

    @IsTest
    static void testMod11() {
        // Example MOD11 number
        System.assertEquals(true,
            Util_DataValidation.isValidMod11('123455')
        );
    }

    @IsTest
    static void testMod97() {
        // Valid IBAN mod97 remainder = 1
        System.assertEquals(true,
            Util_DataValidation.isValidMod97('NL91ABNA0417164300')
        );
    }
}
