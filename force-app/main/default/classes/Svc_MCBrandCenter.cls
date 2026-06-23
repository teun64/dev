/**
 * Svc_MCBrandCenter
 *
 * Fetches brand assets (logo URL, colors) from Marketing Cloud BrandCenter
 * via the MC REST API hub/v1/brands endpoint.
 *
 * Setup required (one-time, in Salesforce Setup):
 *   1. Create a Connected App in Marketing Cloud with API integration enabled.
 *   2. In Salesforce Setup > Named Credentials, create a Named Credential named
 *      'MC_Marketing_Cloud' with:
 *        - URL:           https://<your-MC-subdomain>.rest.marketingcloudapis.com
 *        - Auth Protocol: OAuth 2.0 (JWT Bearer or Client Credentials)
 *        - Scope:         accounts_read content_read
 *   3. Populate McBrandId__c on each BrandThemeConfig__mdt record with the MC brand ID.
 */
public with sharing class Svc_MCBrandCenter {

    private static final String NAMED_CREDENTIAL = 'MC_Marketing_Cloud';

    /**
     * Returns brand assets for a given MC BrandCenter brand ID.
     * Populates BrandThemeData.mcLogoUrl, and optionally primaryColor/accentColor
     * when MC returns color information.
     *
     * Returns null if the Named Credential is not configured or the brand is not found.
     */
    public static Ctrl_PreferenceCenter.BrandThemeData getBrandAssets(String mcBrandId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/hub/v1/brands/' + EncodingUtil.urlEncode(mcBrandId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.WARN,
                'MC BrandCenter returned ' + res.getStatusCode() + ' for brand ' + mcBrandId);
            return null;
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Ctrl_PreferenceCenter.BrandThemeData data = new Ctrl_PreferenceCenter.BrandThemeData();
        data.brand = mcBrandId;

        // Logo URL — MC BrandCenter stores logos under assets.logo.fileURL or similar
        Object assetsObj = body.get('assets');
        if (assetsObj instanceof Map<String, Object>) {
            Map<String, Object> assets = (Map<String, Object>) assetsObj;
            Object logoObj = assets.get('logo');
            if (logoObj instanceof Map<String, Object>) {
                Map<String, Object> logo = (Map<String, Object>) logoObj;
                data.mcLogoUrl = (String) logo.get('fileURL');
                if (String.isBlank(data.mcLogoUrl)) {
                    data.mcLogoUrl = (String) logo.get('url');
                }
            }
        }

        // Colors — MC BrandCenter may include palette information
        Object colorsObj = body.get('colors');
        if (colorsObj instanceof Map<String, Object>) {
            Map<String, Object> colors = (Map<String, Object>) colorsObj;
            Object primary = colors.get('primary');
            if (primary instanceof String) {
                data.primaryColor = (String) primary;
            }
            Object secondary = colors.get('secondary');
            if (secondary instanceof String) {
                data.accentColor = (String) secondary;
            }
        }

        return data;
    }
}
