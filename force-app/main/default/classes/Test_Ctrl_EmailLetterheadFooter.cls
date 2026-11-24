@IsTest
private class Test_Ctrl_EmailLetterheadFooter {
    @IsTest
    static void resolvesEntityByLanguageAndBuildsAddress() {
        Business_Entities__c be = new Business_Entities__c(Name = 'ZZ Footer NL', Reseller__c = '1', Business_Name__c = 'ZZ B.V.');
        be.put('Address__Street__s', 'Teststraat 1');
        be.put('Address__PostalCode__s', '1234 AB');
        be.put('Address__City__s', 'Testdorp');
        be.put('Address__CountryCode__s', 'NL');
        insert be;
        Ctrl_EmailLetterheadFooter c = new Ctrl_EmailLetterheadFooter();
        c.emailLanguage = 'nl_NL';
        System.assertEquals('ZZ B.V.', c.entity.Business_Name__c);
        System.assertEquals('Teststraat 1, 1234 AB Testdorp, Netherlands', c.addressLine);
    }

    @IsTest
    static void unknownLanguageFallsBackWithoutError() {
        Ctrl_EmailLetterheadFooter c = new Ctrl_EmailLetterheadFooter();
        c.emailLanguage = null;
        System.assertNotEquals(null, c.entity);
        System.assertNotEquals(null, c.addressLine);
    }
}
