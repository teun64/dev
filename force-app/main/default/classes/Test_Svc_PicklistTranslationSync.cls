@isTest
private class Test_Svc_PicklistTranslationSync {

    // Mocks the two readMetadata call shapes syncAll() makes: one for GlobalValueSet (to get
    // API value <-> master label), and one or more for GlobalValueSetTranslation (batched by 10).
    private class ReadMetadataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String body = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'text/xml');

            if (body.contains('<met:type>GlobalValueSet</met:type>')) {
                res.setBody(soapWrap(
                    '<records xsi:type="GlobalValueSet"><fullName>ComPrev_Catergory</fullName>' +
                    '<customValue><fullName>MARKETING</fullName><label>Marketing communications</label></customValue>' +
                    '<customValue><fullName>SERVICE</fullName><label>Service &amp; operational notifications</label></customValue>' +
                    '</records>' +
                    '<records xsi:type="GlobalValueSet"><fullName>ComPrev_CommunicationType</fullName>' +
                    '<customValue><fullName>PROMOTIONS</fullName><label>Promotions</label></customValue>' +
                    '</records>' +
                    '<records xsi:type="GlobalValueSet"><fullName>ComPref_Channel</fullName>' +
                    '<customValue><fullName>EMAIL</fullName><label>EMAIL</label></customValue>' +
                    '</records>' +
                    '<records xsi:type="GlobalValueSet"><fullName>ComPrev_Brand</fullName>' +
                    '<customValue><fullName>M</fullName><label>Moving Intelligence</label></customValue>' +
                    '</records>'
                ));
            } else {
                // GlobalValueSetTranslation batch — cover a real translation, a placeholder
                // (comment-only, no text), and a value set (Brand) that should never carry text.
                res.setBody(soapWrap(
                    '<records><fullName>ComPrev_Catergory-nl_NL</fullName>' +
                    '<valueTranslation><masterLabel>Marketing communications</masterLabel><translation>Marketingcommunicatie</translation></valueTranslation>' +
                    '<valueTranslation><masterLabel>Service &amp; operational notifications</masterLabel><translation></translation></valueTranslation>' +
                    '</records>' +
                    '<records><fullName>ComPrev_CommunicationType-fr</fullName>' +
                    '<valueTranslation><masterLabel>Promotions</masterLabel><translation>Promotions</translation></valueTranslation>' +
                    '</records>' +
                    '<records><fullName>ComPref_Channel-de</fullName>' +
                    '<valueTranslation><masterLabel>EMAIL</masterLabel><translation></translation></valueTranslation>' +
                    '</records>' +
                    '<records><fullName>ComPrev_Brand-nl_NL</fullName>' +
                    '<valueTranslation><masterLabel>Moving Intelligence</masterLabel><translation></translation></valueTranslation>' +
                    '</records>'
                ));
            }
            return res;
        }

        private String soapWrap(String recordsXml) {
            return '<?xml version="1.0" encoding="UTF-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
                '<soapenv:Body><readMetadataResponse><result>' + recordsXml + '</result></readMetadataResponse></soapenv:Body>' +
                '</soapenv:Envelope>';
        }
    }

    @isTest
    static void syncAll_upsertsRealTranslationsOnly() {
        Test.setMock(HttpCalloutMock.class, new ReadMetadataMock());

        Test.startTest();
        Svc_PicklistTranslationSync.syncAll();
        Test.stopTest();

        Map<String, PicklistTranslation__c> byKey = new Map<String, PicklistTranslation__c>();
        for (PicklistTranslation__c row : [
            SELECT Key__c, ValueSetName__c, ApiValue__c, Language__c, Label__c FROM PicklistTranslation__c
        ]) {
            byKey.put(row.Key__c, row);
        }

        System.assertEquals(2, byKey.size(), 'Only the two real (non-blank) translations should be cached');
        System.assertEquals(
            'Marketingcommunicatie',
            byKey.get('ComPrev_Catergory|MARKETING|nl').Label__c
        );
        System.assertEquals(
            'Promotions',
            byKey.get('ComPrev_CommunicationType|PROMOTIONS|fr').Label__c
        );
        System.assert(
            !byKey.containsKey('ComPrev_Catergory|SERVICE|nl'),
            'Placeholder (empty) translation must not be cached'
        );
        System.assert(
            !byKey.containsKey('ComPref_Channel|EMAIL|de'),
            'Placeholder (empty) translation must not be cached'
        );
        for (String key : byKey.keySet()) {
            System.assert(!key.startsWith('ComPrev_Brand'), 'Brand names must never be cached as translations');
        }
    }

    // Re-running syncAll() in the same transaction right after its own DML isn't a real usage
    // pattern (it's an admin-triggered, occasional operation) and Apex disallows a callout
    // immediately after uncommitted DML in one transaction anyway. Idempotency itself is
    // structurally guaranteed by Database.upsert(..., Key__c, true) — re-syncing the same
    // (value set, API value, language) always resolves to the same Key__c row.
}
