public with sharing class Util_System {

    private static Map<Integer, Subscription25__Administration__c> adminMap;
    private static AccessLevel runningMode = AccessLevel.SYSTEM_MODE;

	public static final Set<String> requireBankDetails = new Set<String>{'I0', 'I3', 'I4', 'I8', 'p0'};

    public static final Map<String, String> salesChannels = new Map<String, String> {
        '1' => 'Moving Intelligence'
        ,'2' => 'Europetrack'
        ,'3' => 'SlimmGPS'
        ,'4' => 'Echoes'
        ,'Moving Intelligence' => '1'
        ,'Europetrack' => '2'
        ,'SlimmGPS' => '3'
        ,'Echoes' => '4'
    };

    public static final Map<String, String> salesMarkets = new Map<String, String> {
        '0' => 'Internal'
        ,'1' => 'Security'
        ,'2' => 'Fleet'
        ,'Internal' => '0'
        ,'Security' => '1'
        ,'Fleet' => '2'
    };

    // purchaseOriginId; Possible values: 1=NEW, 2=SERVICE_CHANGE, 3=ENTITY_CHANGE
    public static final Map<String, String> purchaseOrigins = new Map<String, String> {
        '1' => 'NEW'
        ,'2' => 'SERVICE_CHANGE'
        ,'3' => 'ENTITY_CHANGE'
        ,'NEW' => '1'
        ,'SERVICE_CHANGE' => '2'
        ,'ENTITY_CHANGE' => '3'
    };

    // terminationId; 0 = termination reverted, 1 = no credit, 2 = full credit, 3 = partial credit immediate, 4 = partial credit with cancellation term
    public static final Map<String, String> terminationOpions = new Map<String, String> {
        '0' => 'Termination Reverted'
        ,'1' => 'No Credit'
        ,'2' => 'Full Credit'
        ,'3' => 'Partial Credit Immediate'
        ,'4' => 'Partial Credit with Cancellation Term'
        ,'5' => 'Auto renewal off'
        ,'Termination Reverted' => '0'
        ,'No Credit' => '1'
        ,'Full Credit' => '2'
        ,'Partial Credit Immediate' => '3'
        ,'Partial Credit with Cancellation Term' => '4'
        ,'Auto renewal off' => '5'
    };

    private static final Map<String, String> replaceProductIDs = new Map<String, String> {
        '1082-sv-3' => '243-sv-3'
        ,'1083-sv-3' => '244-sv-3'
        ,'1084-sv-3' => '547-sv-3'
        ,'1085-sv-3' => '549-sv-3'
    };

    private static final Map<String, String> paymentProviderConstants = new Map<String, String> {
        'AccountIdKey' => 'sfAccountId'
    };

    public static Subscription25__Administration__c getAdministration(Integer extId){
        if(Util_System.adminMap == null){
            List<Subscription25__Administration__c> adms = [
                SELECT Id, Name, Daily_Limit__c,  CurrencyIsoCode, External_ID__c, Subscription25__Named_Credential__c, Subscription25__Twinfield_Company_Code__c,
                    Subscription25__Active__c, Subscription25__Synchronisation__c, Subscription25__Invoice_Number_Prefix__c, Warehouse_Exact_Id__c, Reseller__c
                FROM Subscription25__Administration__c
                WITH SYSTEM_MODE
            ];
            Util_System.adminMap = new Map<Integer, Subscription25__Administration__c>();
            for(Subscription25__Administration__c admin : adms){
                Util_System.adminMap.put(Integer.valueOf(admin.External_ID__c), admin);
            }
        }
        return Util_System.adminMap.get(extId);
    }

    public static void setIfNotBlank(SObject obj, Schema.SObjectField field, String value) {
        if (!String.isBlank(value)) {
            obj.put(field, value);
        }
    }

    public static void setIfNotNull(SObject obj, Schema.SObjectField field, Object value) {
        if (value != null) {
            obj.put(field, value);
        }
    }

    public static String addMultiPicklistValue(String original, String value) {
        if (String.isBlank(original)) {
            return value;
        }
        Set<String> values = new Set<String>(original.split(';'));
        values.add(value);
        String newValue = String.join(new List<String>(values), ';');
        return newValue;
    }

    public static void setStatusCascadePrevention(Boolean state){
        try {
            Map<String, Subscription25__Subscription25_Settings__c> settMap = Subscription25__Subscription25_Settings__c.getAll();
            settMap.get('PREVENT_CONTRACT_STATUS_CASCADE').Subscription25__BooleanValue__c = state;
            Database.update(settMap.get('PREVENT_CONTRACT_STATUS_CASCADE'), Util_System.runningMode);
        } catch(Exception e){}
    }

    public static void setEruIluvatar(Boolean state){
        try {
            Map<String, Subscription25__Subscription25_Settings__c> settMap = Subscription25__Subscription25_Settings__c.getAll();
            settMap.get('ERU_ILUVATAR').Subscription25__BooleanValue__c = state;
            Database.update(settMap.get('ERU_ILUVATAR'), Util_System.runningMode);
        } catch(Exception e){}
    }

    public static Boolean getEruIluvatar(){
	    Boolean curState = false;
	    try {
            Map<String, Subscription25__Subscription25_Settings__c> settMap = Subscription25__Subscription25_Settings__c.getAll();
            curState = settMap.get('ERU_ILUVATAR').Subscription25__BooleanValue__c;
        } catch(Exception e){}
        return curState;
    }

    public static Integer getAdminExternalId(Long resellerId){
        Map<Long, Integer> resellerAdminMap = new Map<Long, Integer>();
        // 20220126 gen25/tri - disabled belgium reseller to dutch administration - MI - plaform release 26 - 01 - 2022
        resellerAdminMap.put(3, 1);
        //resellerAdminMap.put(2, 0);
        //resellerAdminMap.put(4, 0);
        return resellerAdminMap.containsKey(resellerId) ? resellerAdminMap.get(resellerId) : Integer.valueOf(resellerId);
    }

    public static String formatDate(Date dt, String format){
        return Datetime.newInstance(dt, Time.newInstance(12, 0, 0, 0)).format(format);
    }

    public static String sanitizeFileName(String unsafeName){
        String allowedCharacters = '0-9a-zA-Z-_.';
        String sanitizedName = unsafeName.replaceAll('[^' + allowedCharacters + ']', '');
        // You might also want to check filename length,
        // that the filename ends in '.pdf', etc.
        return (sanitizedName);
    }

	//generate a random string of a given length
	public static String generateRandomString(Integer len) {
		final String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz';
		String returnValue = '';

		while (returnValue.length() < len) {
			Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), 62);
			returnValue += chars.substring(idx, idx + 1);
		}

		return returnValue;
	}

    public static String getParameterString(Map<String, String> parameters){
        if(parameters == null || parameters.size() == 0){
            return '';
        }

        List<String> partialParams = new List<String>();
        for (String key : parameters.keySet()) {
            partialParams.add(key + '=' + parameters.get(key));
            //partialParams.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(parameters.get(key), 'UTF-8'));
        }

        return String.join(partialParams, '&');
    }

    //this function returns true if one of the fields in the given set of fieldsToCheck
    //has a different value on obj1 than on obj2, this'll be mostly called from triggers
    public static Boolean hasFieldChanged(SObject obj1, SObject obj2, Set<String> fieldsToCheck){
        //if one of the objects is null, return true (this usually means this function is called from
        //a trigger in insert or delete context)
        if(obj1 == null || obj2 == null){
            return true;
        }
        for(String fieldName : fieldsToCheck){
            //apparently, the global describe returns updateable fields which turn out not
            //to be valid fields after all, so if that happens we regard is as unchanged
            try {
                if(obj1.get(fieldName) != obj2.get(fieldName)){
                    return true;
                }
            } catch(Exception e){}

        }
        return false;
    }

    //some functions that can be used to collect all values of a certain field of the given list of objects
    public static Set<Id> collectIdValues(SObject[] objects, String fieldName){
        return Util_System.collectIdValues(objects, fieldName, true);
    }
    public static Set<Id> collectIdValues(SObject[] objects, String fieldName, Boolean includeNulls){
        List<Object> objs = Util_System.collectObjectValues(objects, fieldName, includeNulls);
        Set<Id> ids = new Set<Id>();
        for(Object o : objs){
            ids.add((Id) o);
        }
        return ids;
    }

    public static Set<String> collectStringValues(SObject[] objects, String fieldName){
        List<Object> objs = Util_System.collectObjectValues(objects, fieldName);
        Set<String> strs = new Set<String>();
        for(Object o : objs){
            String s = (String)o;
            if(!String.isBlank(s)){
                strs.add(s);
            }
        }
        return strs;
    }

    public static List<Object> collectObjectValues(SObject[] objects, String fieldName){
        return Util_System.collectObjectValues(objects, fieldName, false);
    }

    public static List<Object> collectObjectValues(SObject[] objects, String fieldName, Boolean includeNulls){
        List<String> fieldParts = fieldName.split('\\.');

        if (fieldParts.size() == 1) {
            List<Object> vals = new List<Object>();
            for (SObject obj : objects) {
                if (obj != null && obj.get(fieldName) != null || includeNulls) {
                    vals.add(obj != null ? obj.get(fieldName) : null);
                }
            }
            return vals;
        }

        SObject[] objVals = new SObject[]{};
        String relName = fieldParts[0];
        for (SObject obj : objects) {
            if (obj != null && obj.getSObject(relName) != null || includeNulls) {
                objVals.add(obj != null ? obj.getSObject(relName) : null);
            }
        }
        fieldParts.remove(0);
        String newFieldName = String.join(fieldParts, '.');
        return Util_System.collectObjectValues(objVals, newFieldName, includeNulls);
    }
    /**
     * Legacy wrapper to create GUID methods, now implements the internal UUID class.
     * @return A GUID string.
     */
    public static String generateGUID() {
        return UUID.randomUUID().toString();
    }

    public static String cleanString(String value) {
        if (String.isBlank(value)) {
            return value;
        }
       
        value = value.replaceAll('[^a-zA-Z0-9\\s+/*]', '');

        value = value.replaceAll('//','/');
        value = value.replaceAll('//','/');
        value = value.replaceAll('\\\\','\\');
        //value = value.replaceAll('\\\\','\\');

        return value;
    }

    public static String cleanName(String value) {
        if (String.isBlank(value)) {
            return value;
        }

        value = value.replaceAll('[<>\\{\\}\\[\\]\\|`~^]', '');
        value = value.replaceAll('[\\p{Cc}\\p{Cf}]', '');
        value = value.replaceAll('\\s+', ' ').trim();

        return value;
    }

    public static String getSalesChannel(String inputKey) {
        if (String.isBlank(inputKey)) {
            return null;
        }
        String key = inputKey.toUpperCase();
        return Util_System.salesChannels.containsKey(key) ? Util_System.salesChannels.get(key)  : inputKey;
    }

    public static String getSalesMarket(String inputKey) {
        if (String.isBlank(inputKey)) {
            return null;
        }
        String key = inputKey.toUpperCase();
        return Util_System.salesMarkets.containsKey(key) ? Util_System.salesMarkets.get(key)  : inputKey;
    }

    public static String getPurchaseOrigin(String inputKey) {
        if (String.isBlank(inputKey)) {
            return null;
        }
        String key = inputKey.toUpperCase();
        return Util_System.purchaseOrigins.containsKey(key) ? Util_System.purchaseOrigins.get(key)  : inputKey;
    }

    public static String getTerminationOption(String inputKey) {
        if (String.isBlank(inputKey)) {
            return null;
        }
        String key = inputKey.toUpperCase();
        return Util_System.terminationOpions.containsKey(key) ? Util_System.terminationOpions.get(key)  : inputKey;
    }

    public static String getReplacedProductId(String productId) {
        if (String.isBlank(productId)) {
            return null;
        }
        return Util_System.replaceProductIDs.containsKey(productId) ? Util_System.replaceProductIDs.get(productId)  : productId;
    }

    public static String getPaymentProviderConstant(String ppConst) {
        if ((String.isNotBlank(ppConst)) && (Util_System.paymentProviderConstants.containsKey(ppConst))) {
            return  Util_System.paymentProviderConstants.get(ppConst);
        } 

        return null;
    }

    public static String getISO2CountryCode(String inputName) {
        if (String.isBlank(inputName)) {
            return null;
        }
        String name = inputName.toUpperCase();

        //three letter codes to two letter codes
        Map<String, String> countryMap = new Map<String, String>();
        countryMap.put('AFG', 'AF');
        countryMap.put('ALB', 'AL');
        countryMap.put('DZA', 'DZ');
        countryMap.put('ASM', 'AS');
        countryMap.put('AND', 'AD');
        countryMap.put('AGO', 'AO');
        countryMap.put('AIA', 'AI');
        countryMap.put('ATA', 'AQ');
        countryMap.put('ATG', 'AG');
        countryMap.put('ARG', 'AR');
        countryMap.put('ARM', 'AM');
        countryMap.put('ABW', 'AW');
        countryMap.put('AUS', 'AU');
        countryMap.put('AUT', 'AT');
        countryMap.put('AZE', 'AZ');
        countryMap.put('BHS', 'BS');
        countryMap.put('BHR', 'BH');
        countryMap.put('BGD', 'BD');
        countryMap.put('BRB', 'BB');
        countryMap.put('BLR', 'BY');
        countryMap.put('BEL', 'BE');
        countryMap.put('BLZ', 'BZ');
        countryMap.put('BEN', 'BJ');
        countryMap.put('BMU', 'BM');
        countryMap.put('BTN', 'BT');
        countryMap.put('BOL', 'BO');
        countryMap.put('BES', 'BQ');
        countryMap.put('BIH', 'BA');
        countryMap.put('BWA', 'BW');
        countryMap.put('BVT', 'BV');
        countryMap.put('BRA', 'BR');
        countryMap.put('IOT', 'IO');
        countryMap.put('BRN', 'BN');
        countryMap.put('BGR', 'BG');
        countryMap.put('BFA', 'BF');
        countryMap.put('BDI', 'BI');
        countryMap.put('KHM', 'KH');
        countryMap.put('CMR', 'CM');
        countryMap.put('CAN', 'CA');
        countryMap.put('CPV', 'CV');
        countryMap.put('CYM', 'KY');
        countryMap.put('CAF', 'CF');
        countryMap.put('TCD', 'TD');
        countryMap.put('CHL', 'CL');
        countryMap.put('CHN', 'CN');
        countryMap.put('CXR', 'CX');
        countryMap.put('CCK', 'CC');
        countryMap.put('COL', 'CO');
        countryMap.put('COM', 'KM');
        countryMap.put('COG', 'CG');
        countryMap.put('COD', 'CD');
        countryMap.put('COK', 'CK');
        countryMap.put('CRI', 'CR');
        countryMap.put('HRV', 'HR');
        countryMap.put('CUB', 'CU');
        countryMap.put('CUW', 'CW');
        countryMap.put('CYP', 'CY');
        countryMap.put('CZE', 'CZ');
        countryMap.put('CIV', 'CI');
        countryMap.put('DNK', 'DK');
        countryMap.put('DJI', 'DJ');
        countryMap.put('DMA', 'DM');
        countryMap.put('DOM', 'DO');
        countryMap.put('ECU', 'EC');
        countryMap.put('EGY', 'EG');
        countryMap.put('SLV', 'SV');
        countryMap.put('GNQ', 'GQ');
        countryMap.put('ERI', 'ER');
        countryMap.put('EST', 'EE');
        countryMap.put('ETH', 'ET');
        countryMap.put('FLK', 'FK');
        countryMap.put('FRO', 'FO');
        countryMap.put('FJI', 'FJ');
        countryMap.put('FIN', 'FI');
        countryMap.put('FRA', 'FR');
        countryMap.put('GUF', 'GF');
        countryMap.put('PYF', 'PF');
        countryMap.put('ATF', 'TF');
        countryMap.put('GAB', 'GA');
        countryMap.put('GMB', 'GM');
        countryMap.put('GEO', 'GE');
        countryMap.put('DEU', 'DE');
        countryMap.put('GHA', 'GH');
        countryMap.put('GIB', 'GI');
        countryMap.put('GRC', 'GR');
        countryMap.put('GRL', 'GL');
        countryMap.put('GRD', 'GD');
        countryMap.put('GLP', 'GP');
        countryMap.put('GUM', 'GU');
        countryMap.put('GTM', 'GT');
        countryMap.put('GGY', 'GG');
        countryMap.put('GIN', 'GN');
        countryMap.put('GNB', 'GW');
        countryMap.put('GUY', 'GY');
        countryMap.put('HTI', 'HT');
        countryMap.put('HMD', 'HM');
        countryMap.put('VAT', 'VA');
        countryMap.put('HND', 'HN');
        countryMap.put('HKG', 'HK');
        countryMap.put('HUN', 'HU');
        countryMap.put('ISL', 'IS');
        countryMap.put('IND', 'IN');
        countryMap.put('IDN', 'ID');
        countryMap.put('IRN', 'IR');
        countryMap.put('IRQ', 'IQ');
        countryMap.put('IRL', 'IE');
        countryMap.put('IMN', 'IM');
        countryMap.put('ISR', 'IL');
        countryMap.put('ITA', 'IT');
        countryMap.put('JAM', 'JM');
        countryMap.put('JPN', 'JP');
        countryMap.put('JEY', 'JE');
        countryMap.put('JOR', 'JO');
        countryMap.put('KAZ', 'KZ');
        countryMap.put('KEN', 'KE');
        countryMap.put('KIR', 'KI');
        countryMap.put('PRK', 'KP');
        countryMap.put('KOR', 'KR');
        countryMap.put('KWT', 'KW');
        countryMap.put('KGZ', 'KG');
        countryMap.put('LAO', 'LA');
        countryMap.put('LVA', 'LV');
        countryMap.put('LBN', 'LB');
        countryMap.put('LSO', 'LS');
        countryMap.put('LBR', 'LR');
        countryMap.put('LBY', 'LY');
        countryMap.put('LIE', 'LI');
        countryMap.put('LTU', 'LT');
        countryMap.put('LUX', 'LU');
        countryMap.put('MAC', 'MO');
        countryMap.put('MKD', 'MK');
        countryMap.put('MDG', 'MG');
        countryMap.put('MWI', 'MW');
        countryMap.put('MYS', 'MY');
        countryMap.put('MDV', 'MV');
        countryMap.put('MLI', 'ML');
        countryMap.put('MLT', 'MT');
        countryMap.put('MHL', 'MH');
        countryMap.put('MTQ', 'MQ');
        countryMap.put('MRT', 'MR');
        countryMap.put('MUS', 'MU');
        countryMap.put('MYT', 'YT');
        countryMap.put('MEX', 'MX');
        countryMap.put('FSM', 'FM');
        countryMap.put('MDA', 'MD');
        countryMap.put('MCO', 'MC');
        countryMap.put('MNG', 'MN');
        countryMap.put('MNE', 'ME');
        countryMap.put('MSR', 'MS');
        countryMap.put('MAR', 'MA');
        countryMap.put('MOZ', 'MZ');
        countryMap.put('MMR', 'MM');
        countryMap.put('NAM', 'NA');
        countryMap.put('NRU', 'NR');
        countryMap.put('NPL', 'NP');
        countryMap.put('NLD', 'NL');
        countryMap.put('NCL', 'NC');
        countryMap.put('NZL', 'NZ');
        countryMap.put('NIC', 'NI');
        countryMap.put('NER', 'NE');
        countryMap.put('NGA', 'NG');
        countryMap.put('NIU', 'NU');
        countryMap.put('NFK', 'NF');
        countryMap.put('MNP', 'MP');
        countryMap.put('NOR', 'NO');
        countryMap.put('OMN', 'OM');
        countryMap.put('PAK', 'PK');
        countryMap.put('PLW', 'PW');
        countryMap.put('PSE', 'PS');
        countryMap.put('PAN', 'PA');
        countryMap.put('PNG', 'PG');
        countryMap.put('PRY', 'PY');
        countryMap.put('PER', 'PE');
        countryMap.put('PHL', 'PH');
        countryMap.put('PCN', 'PN');
        countryMap.put('POL', 'PL');
        countryMap.put('PRT', 'PT');
        countryMap.put('PRI', 'PR');
        countryMap.put('QAT', 'QA');
        countryMap.put('ROU', 'RO');
        countryMap.put('RUS', 'RU');
        countryMap.put('RWA', 'RW');
        countryMap.put('REU', 'RE');
        countryMap.put('BLM', 'BL');
        countryMap.put('SHN', 'SH');
        countryMap.put('KNA', 'KN');
        countryMap.put('LCA', 'LC');
        countryMap.put('MAF', 'MF');
        countryMap.put('SPM', 'PM');
        countryMap.put('VCT', 'VC');
        countryMap.put('WSM', 'WS');
        countryMap.put('SMR', 'SM');
        countryMap.put('STP', 'ST');
        countryMap.put('SAU', 'SA');
        countryMap.put('SEN', 'SN');
        countryMap.put('SRB', 'RS');
        countryMap.put('SYC', 'SC');
        countryMap.put('SLE', 'SL');
        countryMap.put('SGP', 'SG');
        countryMap.put('SXM', 'SX');
        countryMap.put('SVK', 'SK');
        countryMap.put('SVN', 'SI');
        countryMap.put('SLB', 'SB');
        countryMap.put('SOM', 'SO');
        countryMap.put('ZAF', 'ZA');
        countryMap.put('SGS', 'GS');
        countryMap.put('SSD', 'SS');
        countryMap.put('ESP', 'ES');
        countryMap.put('LKA', 'LK');
        countryMap.put('SDN', 'SD');
        countryMap.put('SUR', 'SR');
        countryMap.put('SJM', 'SJ');
        countryMap.put('SWZ', 'SZ');
        countryMap.put('SWE', 'SE');
        countryMap.put('CHE', 'CH');
        countryMap.put('SYR', 'SY');
        countryMap.put('TWN', 'TW');
        countryMap.put('TJK', 'TJ');
        countryMap.put('TZA', 'TZ');
        countryMap.put('THA', 'TH');
        countryMap.put('TLS', 'TL');
        countryMap.put('TGO', 'TG');
        countryMap.put('TKL', 'TK');
        countryMap.put('TON', 'TO');
        countryMap.put('TTO', 'TT');
        countryMap.put('TUN', 'TN');
        countryMap.put('TUR', 'TR');
        countryMap.put('TKM', 'TM');
        countryMap.put('TCA', 'TC');
        countryMap.put('TUV', 'TV');
        countryMap.put('UGA', 'UG');
        countryMap.put('UKR', 'UA');
        countryMap.put('ARE', 'AE');
        countryMap.put('GBR', 'GB');
        countryMap.put('USA', 'US');
        countryMap.put('UMI', 'UM');
        countryMap.put('URY', 'UY');
        countryMap.put('UZB', 'UZ');
        countryMap.put('VUT', 'VU');
        countryMap.put('VEN', 'VE');
        countryMap.put('VNM', 'VN');
        countryMap.put('VGB', 'VG');
        countryMap.put('VIR', 'VI');
        countryMap.put('WLF', 'WF');
        countryMap.put('ESH', 'EH');
        countryMap.put('YEM', 'YE');
        countryMap.put('ZMB', 'ZM');
        countryMap.put('ZWE', 'ZW');
        countryMap.put('ALA', 'AX');

        return countryMap.containsKey(name) ? countryMap.get(name) : inputName;
    }

    public static String getCurrencySign(String currencyIsoCode) {
        if (String.isBlank(currencyIsoCode)) {
            return '¤';
        }

        Map<String, String> currencySignMap = new Map<String, String>();
        currencySignMap.put('AUD','A$');
		currencySignMap.put('AWG','ƒ');
		currencySignMap.put('BDT','৳');
		currencySignMap.put('CAD','CAD$');
		currencySignMap.put('CNY','¥');
		currencySignMap.put('CRC','₡');
		currencySignMap.put('DKK','kr');
		currencySignMap.put('EGP','£');
		currencySignMap.put('EUR','€');
		currencySignMap.put('FKP','£');
		currencySignMap.put('GBP','£');
		currencySignMap.put('GIP','£');
		currencySignMap.put('ILS','₪');
		currencySignMap.put('INR','₹');
		currencySignMap.put('ISK','kr');
		currencySignMap.put('JPY','¥');
		currencySignMap.put('KHR','៛');
		currencySignMap.put('KRW','₩');
		currencySignMap.put('KZT','₸');
		currencySignMap.put('LBP','£');
		currencySignMap.put('NGN','₦');
		currencySignMap.put('NOK','kr');
		currencySignMap.put('PHP','₱');
		currencySignMap.put('PYG','₲');
		currencySignMap.put('RUB','₽');
		currencySignMap.put('SDG','£');
		currencySignMap.put('SEK','kr');
		currencySignMap.put('SHP','£');
		currencySignMap.put('SYP','£');
		currencySignMap.put('TRY','₺');
		currencySignMap.put('USD','$');
		currencySignMap.put('','¤'); // The currency sign ¤ is a character used to denote an unspecified currency.

		return currencySignMap.get(currencyIsoCode);
	}

    public static String getCurrencyCents(Decimal x){
		String y = String.valueOf(x);
		String z = '.';
		if(y.contains(',')) z = ',';
        y = y.contains(z) ? y.substring(0, y.indexOf(z)) : y;
		if(x - Decimal.valueOf(y) == 0) {
            return String.valueOf(x.format()) + z + '00';
        }
        return String.valueOf(x.format());
	}

    public static void setRenewalTerms(Contract cont, Account customer) {
        List<Renewal_Term__mdt> terms = [
            SELECT Id, Value__c
            FROM Renewal_Term__mdt
            WHERE Contract_Term__c = :cont.ContractTerm
        ];
        if (!terms.isEmpty()) {
            // Set value mapped in Renewal_Term__mdt
            cont.Subscription25__Renewal_Term__c = terms.get(0).Value__c;
        } else {
            // Set default value
            cont.Subscription25__Renewal_Term__c = 1;
        }

        Integer invoicePeriod = 0;
        if (customer.Invoice_Period__c != null && customer.Invoice_Period__c.isNumeric()) {
            invoicePeriod = Integer.valueOf(customer.Invoice_Period__c);
        }
        if (cont.Subscription25__Renewal_Term__c < invoicePeriod) {
            // Set to minimally invoice term
            cont.Subscription25__Renewal_Term__c = invoicePeriod;
        }
    }

    public static String getPlatformIdField(Long platformId) {
        String externalId = String.format('extId_{0}__c', new List<String> { String.valueOf(platformId) });
        return externalId;
    }

    public static String sanitizeEmail(String email) {
        if (String.isBlank(email)) return null;

        // Remove any white space
        String baseEmail = email.deleteWhitespace();
        baseEmail = baseEmail.toLowerCase();

        // Get local-part from email
        String localEmail = baseEmail.substringBeforeLast('@');
        localEmail = localEmail.substringBefore('+');
        // Remove dots (.) from local
        //localEmail = localEmail.remove('.');
        string domainEmail = baseEmail.substringAfterLast('@');

        // Reconstruct local with domain
        string sanitizedEmail = localEmail + '@' + domainEmail;

        System.debug('Util_System.sanitizeEmail() = ' + sanitizedEmail + ' from ' + email);

        return sanitizedEmail;
    }

    /* =========================================================
        getDataSetting(String setting) {
    ========================================================= */
    public static Boolean getDataSetting(String setting) {
        Boolean result = false;

        if (String.IsNotBlank(setting)) {
            System.Domain d = System.DomainParser.parse(URL.getOrgDomainUrl());

            String devName = d.getSandboxName() ?? 'prod';
            devName = devName.toLowerCase();

            setting = setting.remove('__c') + '__c';

            List<DataSetting__mdt> dataSettingList = new List<DataSetting__mdt>();

            String sSOQL = 'SELECT Id, {0} FROM DataSetting__mdt WHERE DeveloperName = :devName LIMIT 1';
            sSOQL = String.format(sSOQL, new List<String> { setting });

            system.debug('devName = ' + devName);
            system.debug('setting = ' + setting);
            system.debug('sSOQL = ' + sSOQL);

            try {
                dataSettingList = Database.query(sSOQL);
            } catch(System.QueryException e) {
                System.debug('Util_DataValidation.getDataSetting() : The following exception has occurred: ' + e.getMessage());
                return result;
            }

            if (dataSettingList.size() > 0) {
                result = Boolean.valueOf(dataSettingList[0].get(setting));
                system.debug('DataSetting_mdt = ' + result);
            }

        }

        return result;
    }
    /**
     * Retrieves translations for multiple custom labels in a specified language.
     * @param labels List of custom label API names.
     * @param language The target language code (e.g., 'en_US', 'es', 'fr').
     * @return Map of Label API Name -> Translated Value.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getCustomLabels(List<String> labels, String language) {
        Map<String, String> translatedLabels = new Map<String, String>();
        // Using an empty namespace for unmanaged packages
        String namespace = ''; 
        String translation = '';

        system.debug('language -> ' + language);

        for (String labelName : labels) {
            try {
                translation = System.Label.translationExists(namespace, labelName, language) ? System.Label.get(namespace, labelName, language) : System.Label.get(namespace, labelName);
                translatedLabels.put(labelName, translation);
            } catch (Exception e) {
                // Handle cases where a label or specific translation is missing
                translation = labelName + '_' + language + '_NOT_FOUND';
            }

            system.debug(labelName + ' -> ' + translation);

            translatedLabels.put(labelName, translation);
        }
        return translatedLabels;
    }

    public class ConnectionException extends Exception {}
    public class CustomException extends Exception {}
    public class FinancialSyncException extends Exception {}
    // Thrown for errors in definition configurations
    public class IntegrationDefinitionException extends Exception{}
    // Thrown by handlers to define errors that take precedence over the StopOnError=false setting
    public class IntegrationException extends Exception{
        public Boolean isRetryable = false;
    }
    public class UpsertException extends Exception {}

    
}