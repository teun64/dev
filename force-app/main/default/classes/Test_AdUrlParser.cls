@IsTest
public with sharing class Test_AdUrlParser {

    @IsTest
    private static void testGoogleAdsGetParamValues() {
        Test.startTest();
        Inv_AdUrlParser.Request req = new Inv_AdUrlParser.Request();
        req.baseParams = 'utm_source=googleads&utm_medium=search&utm_campaign=peilzender&utm_id=MI&gad_source=1&ppc_keyword=terugvindsysteem tv01&gclid=12345';
        List<Inv_AdUrlParser.Result> results = Inv_AdUrlParser.execute(new List<Inv_AdUrlParser.Request> { req });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Unexpected amount of responses');
        Inv_AdUrlParser.Result result = results.get(0);
        Assert.areEqual(result.clickId, '12345');
        Assert.areEqual(result.utmSource, 'googleads');
        Assert.areEqual(result.utmMedium, 'search');
        Assert.areEqual(result.utmCampaign, 'peilzender');
        Assert.areEqual(result.utmId, 'MI');
        Assert.areEqual(result.gadSource, '1');
        Assert.areEqual(result.ppcKeyword, 'terugvindsysteem tv01');
    }

    @IsTest
    private static void testBingGetParamValues() {
        Test.startTest();
        Inv_AdUrlParser.Request req = new Inv_AdUrlParser.Request();
        req.baseParams = 'msclkid=12345&utm_source=bing&utm_medium=cpc&utm_campaign=NL - SE - Peilzender&utm_term=peilzender&utm_content=Peilzender';
        List<Inv_AdUrlParser.Result> results = Inv_AdUrlParser.execute(new List<Inv_AdUrlParser.Request> { req });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Unexpected amount of responses');
        Inv_AdUrlParser.Result result = results.get(0);
        Assert.areEqual(result.clickId, '12345');
        Assert.areEqual(result.utmSource, 'bing');
        Assert.areEqual(result.utmMedium, 'cpc');
        Assert.areEqual(result.utmCampaign, 'NL - SE - Peilzender');
        Assert.areEqual(result.utmTerm, 'peilzender');
        Assert.areEqual(result.utmContent, 'Peilzender');
    }
}