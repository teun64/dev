/**
 * Admin-triggered sync (run via anonymous Apex whenever Translation Workbench text changes):
 *   Svc_PicklistTranslationSync.syncAll();
 *
 * Reads the live Translation Workbench data for the Communication Preference global value
 * sets via the Metadata API and caches it in PicklistTranslation__c, keyed by
 * ValueSetName|ApiValue|Language. The Experience Cloud site runs under a single fixed-language
 * Guest User, so Apex picklist describe (which resolves translations from the running user's
 * own language) can't serve a per-visitor language there — this cache is what
 * Ctrl_PreferenceCenter reads instead for guest/EC requests.
 */
public without sharing class Svc_PicklistTranslationSync {
    private static final List<String> VALUE_SETS = new List<String>{
        'ComPrev_Brand', 'ComPrev_Catergory', 'ComPrev_CommunicationType', 'ComPref_Channel'
    };

    // Full-language fullName suffix -> short code used by preferenceCenter.js's language switcher.
    // English is never cached: the master picklist label already is English.
    private static final Map<String, String> LANGUAGE_SUFFIX_TO_CODE = new Map<String, String>{
        'nl_NL' => 'nl', 'fr' => 'fr', 'de' => 'de'
    };

    private static final String META_NS = 'http://soap.sforce.com/2006/04/metadata';

    public static void syncAll() {
        Map<String, Map<String, String>> apiValueByLabelPerSet = readGlobalValueSets(VALUE_SETS);

        List<String> translationFullNames = new List<String>();
        for (String vs : VALUE_SETS) {
            for (String suffix : LANGUAGE_SUFFIX_TO_CODE.keySet()) {
                translationFullNames.add(vs + '-' + suffix);
            }
        }
        Map<String, Map<String, String>> translationByLabelPerRecord = readGlobalValueSetTranslations(translationFullNames);

        Map<String, SObject> toUpsert = new Map<String, SObject>();
        for (String vs : VALUE_SETS) {
            Map<String, String> labelToApiValue = apiValueByLabelPerSet.get(vs);
            if (labelToApiValue == null) continue;

            for (String suffix : LANGUAGE_SUFFIX_TO_CODE.keySet()) {
                String langCode = LANGUAGE_SUFFIX_TO_CODE.get(suffix);
                Map<String, String> labelToTranslation = translationByLabelPerRecord.get(vs + '-' + suffix);
                if (labelToTranslation == null) continue;

                for (String masterLabel : labelToTranslation.keySet()) {
                    String translatedText = labelToTranslation.get(masterLabel);
                    String apiValue = labelToApiValue.get(masterLabel);
                    if (String.isBlank(translatedText) || apiValue == null) continue; // placeholder / untranslated (e.g. brand names)

                    String key = vs + '|' + apiValue + '|' + langCode;
                    PicklistTranslation__c rec = new PicklistTranslation__c(
                        Key__c = key,
                        ValueSetName__c = vs,
                        ApiValue__c = apiValue,
                        Language__c = langCode,
                        Label__c = translatedText
                    );
                    toUpsert.put(key, rec);
                }
            }
        }

        if (!toUpsert.isEmpty()) {
            Database.upsert(toUpsert.values(), PicklistTranslation__c.Key__c, true);
        }
        System.debug('Svc_PicklistTranslationSync: upserted ' + toUpsert.size() + ' rows');
    }

    // fullName -> (master label -> API value)
    private static Map<String, Map<String, String>> readGlobalValueSets(List<String> valueSetNames) {
        Dom.Document doc = callReadMetadata('GlobalValueSet', valueSetNames);
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();

        for (Dom.XmlNode recordNode : getRecordNodes(doc)) {
            String fullName = getChildText(recordNode, 'fullName');
            Map<String, String> labelToApiValue = new Map<String, String>();
            for (Dom.XmlNode cv : getChildElements(recordNode, 'customValue')) {
                String apiValue = getChildText(cv, 'fullName');
                String label = getChildText(cv, 'label');
                if (apiValue != null && label != null) labelToApiValue.put(label, apiValue);
            }
            result.put(fullName, labelToApiValue);
        }
        return result;
    }

    // fullName (e.g. ComPrev_Catergory-nl_NL) -> (master label -> translated text)
    private static Map<String, Map<String, String>> readGlobalValueSetTranslations(List<String> fullNames) {
        Map<String, Map<String, String>> result = new Map<String, Map<String, String>>();
        // readMetadata caps at 10 fullNames per call.
        for (Integer i = 0; i < fullNames.size(); i += 10) {
            List<String> batch = new List<String>();
            for (Integer j = i; j < Math.min(i + 10, fullNames.size()); j++) batch.add(fullNames[j]);

            Dom.Document doc = callReadMetadata('GlobalValueSetTranslation', batch);
            for (Dom.XmlNode recordNode : getRecordNodes(doc)) {
                String fullName = getChildText(recordNode, 'fullName');
                Map<String, String> labelToTranslation = new Map<String, String>();
                for (Dom.XmlNode vt : getChildElements(recordNode, 'valueTranslation')) {
                    String masterLabel = getChildText(vt, 'masterLabel');
                    String translation = getChildText(vt, 'translation'); // null/blank for <!-- placeholder --> comments
                    if (masterLabel != null) labelToTranslation.put(masterLabel, translation);
                }
                result.put(fullName, labelToTranslation);
            }
        }
        return result;
    }

    private static Dom.Document callReadMetadata(String metadataType, List<String> fullNames) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/67.0';
        String fullNameTags = '';
        for (String fn : fullNames) {
            fullNameTags += '<met:fullNames>' + escapeXml(fn) + '</met:fullNames>';
        }
        String body =
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:met="' + META_NS + '">' +
            '<soapenv:Header><met:SessionHeader><met:sessionId>' + UserInfo.getSessionId() + '</met:sessionId></met:SessionHeader></soapenv:Header>' +
            '<soapenv:Body><met:readMetadata><met:type>' + metadataType + '</met:type>' +
            fullNameTags +
            '</met:readMetadata></soapenv:Body></soapenv:Envelope>';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', '""');
        req.setBody(body);
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('readMetadata(' + metadataType + ') failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }
        return res.getBodyDocument();
    }

    private static List<Dom.XmlNode> getRecordNodes(Dom.Document doc) {
        Dom.XmlNode envelope = doc.getRootElement();
        Dom.XmlNode soapBody = getChildElements(envelope, 'Body')[0];
        Dom.XmlNode response = getChildElements(soapBody, 'readMetadataResponse')[0];
        Dom.XmlNode result = getChildElements(response, 'result')[0];
        return getChildElements(result, 'records');
    }

    private static List<Dom.XmlNode> getChildElements(Dom.XmlNode node, String name) {
        List<Dom.XmlNode> matches = new List<Dom.XmlNode>();
        for (Dom.XmlNode child : node.getChildElements()) {
            if (child.getName() == name) matches.add(child);
        }
        return matches;
    }

    private static String getChildText(Dom.XmlNode node, String name) {
        List<Dom.XmlNode> matches = getChildElements(node, name);
        if (matches.isEmpty()) return null;
        String text = matches[0].getText();
        return text; // null/empty for <tag/> or a comment-only element
    }

    private static String escapeXml(String s) {
        return s == null ? '' : s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }
}
