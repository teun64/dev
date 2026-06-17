public with sharing class Inv_AdUrlParser {
    public class Request {
        @InvocableVariable(Label='Base Params' Required=true)
        public String baseParams;
    }

    public class Result {
        @InvocableVariable(Label='Click ID')
        public String clickId;
        @InvocableVariable(Label='UTM ID')
        public String utmId;
        @InvocableVariable(Label='UTM Source')
        public String utmSource;
        @InvocableVariable(Label='UTM Campaign')
        public String utmCampaign;
        @InvocableVariable(Label='UTM Medium')
        public String utmMedium;
        @InvocableVariable(Label='UTM Term')
        public String utmTerm;
        @InvocableVariable(Label='UTM Content')
        public String utmContent;
        @InvocableVariable(Label='GAD Source')
        public String gadSource;
        @InvocableVariable(Label='PPC Keyword')
        public String ppcKeyword;
    }

    @InvocableMethod(Description='Parse Base Params')
    public static List<Inv_AdUrlParser.Result> execute(List<Inv_AdUrlParser.Request> requests) {
        List<Inv_AdUrlParser.Result> results = new List<Inv_AdUrlParser.Result>();

        for (Inv_AdUrlParser.Request req : requests) {
            // Create response
            Inv_AdUrlParser.Result result = new Inv_AdUrlParser.Result();
            results.add(result);

            if (String.isBlank(req.baseParams)) {
                // Nothing to parse
                continue;
            }
            // Convert params into key-value pairs
            Map<String, String> valueByParam = Inv_AdUrlParser.mapParams(req.baseParams);
            // Identify click Id field
            String clickIdField = Inv_AdUrlParser.getClickIdField(valueByParam.keySet());
            // Try mapping the values
            result.clickId = valueByParam.get(clickIdField);
            result.utmId = valueByParam.get('utm_id');
            result.utmSource = valueByParam.get('utm_source');
            result.utmCampaign = valueByParam.get('utm_campaign');
            result.utmMedium = valueByParam.get('utm_medium');
            result.utmTerm = valueByParam.get('utm_term');
            result.utmContent = valueByParam.get('utm_content');
            result.gadSource = valueByParam.get('gad_source');
            result.ppcKeyword = valueByParam.get('ppc_keyword');

        }

        return results;
    }

    private static Map<String, String> mapParams(String paramUrl) {
        Map<String, String> valueByParam = new Map<String, String>();
        List<String> parts = paramUrl.split('&');

        for (String pair : parts) {
            List<String> split = pair.split('=');

            if (split.size() == 2) {
                valueByParam.put(split.get(0), split.get(1));
            }
        }
        return valueByParam;
    }

    private static String getClickIdField(Set<String> paramKeys) {
        for (String field : Inv_AdUrlParser.CLICK_ID_FIELDS) {
            if (paramKeys.contains(field)) {
                return field;
            }
        }
        return null;
    }

    // List because order of priority matters, with higher fields having a higher priority (top to bottom)
    private static final List<String> CLICK_ID_FIELDS = new List<String> {
        'gbraid',
        'wbraid',
        'gclid',
        'msclkid',
        'dclid',
        'fbclid',
        'twclid',
        'yclid',
        'zanpid'
    };
}