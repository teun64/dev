public with sharing class Util_DataValidation {
    //=========================================================
    //  PUBLIC METHODS
    // Country = DeveloperName in metadata
    //========================================================= 
    //  CoC (Chamber of Commerce) Number validation
    public static FieldData validateCoC(String country, String input) {
        return Util_DataValidation.validate(input, country, 'CoC');
    }
    //  VAT (Value Added Tax) Number validation
    public static FieldData validateVAT(String country, String input) {
        return Util_DataValidation.validate(input, country, 'VAT');
    }
    //  IBAN (International Bank Account Number) Number validation
    public static FieldData validateIBAN(String input) {
        return Util_DataValidation.validate( input, input.left(2).toUpperCase(), 'IBAN');
    }
    public class FieldData {
        public String value;
        public Boolean isValid;
        public String errorMessage;
    }
    public class AddressData {
        public String street;
        public String houseNumber;
        public String postalCode;
        public String city;
        public String countryCode; // ISO 2-letter code, e.g., "NL", "BE"
        public Boolean isValid;
        public String errorMessage;
    }
    //  Normalize and validate address based on LocalSetting__mdt
    public static AddressData normalizeAddress(AddressData input) {
        if (input == null) return null;

        String countryCode = ((String.IsBlank(input.countryCode)) ? 'XXX' : input.countryCode);
        // Load country settings from metadata
        LocalSetting__mdt locSet = LocalSetting__mdt.getInstance(countryCode);
        if (locSet == null) return null;

        AddressData ret = new AddressData();

        // ----------------------
        // Street normalization
        // ----------------------
        String street = input.street == null ? '' : input.street;
        // Apply StreetCase from metadata
        if (locSet.Address_Street_Case__c == 'UPPER') {
            street = street.toUpperCase();
        } else if (locSet.Address_Street_Case__c == 'TITLE'){
            street = street.toLowerCase();
            List<String> exceptions = locSet.Address_Street_LowerWords__c == null
                ? new List<String>()
                : locSet.Address_Street_LowerWords__c.split(';');

            List<String> parts = street.split('\\s+');
            for (Integer i = 0; i < parts.size(); i++) {
                if (!exceptions.contains(parts[i])) {
                    if (parts[i].length() > 0) {
                        parts[i] = parts[i].substring(0, 1).toUpperCase() + parts[i].substring(1);
                    }
                }
            }
            street = String.join(parts, ' ');
        }

        ret.street = street;
        ret.isValid = true;
        ret.errorMessage = null;

        // ----------------------
        // City normalization
        // ----------------------
        String city = (input.city == null) ? '' : input.city;
        if (!String.isBlank(locSet.Address_City_Case__c)) {
            if (locSet.Address_City_Case__c == 'UPPER') city = city.toUpperCase();
            if (locSet.Address_City_Case__c == 'TITLE') city = titleCase(city);
        }
        ret.city = city;
        //system.debug(ret);
        // ----------------------
        // Postal code validation
        // ----------------------
        String postal = (input.postalCode == null) ? '' : input.postalCode.toUpperCase().replaceAll('[^A-Z0-9]', '');

        ret.isValid = ((locSet.Address_PostalCode_Length__c > 0) && (postal.length() == locSet.Address_PostalCode_Length__c));
        ret.errorMessage = (ret.isValid) ? null : 'The Postal Code provided, does not match the required length (' + String.valueOf(locSet.Address_PostalCode_Length__c.format()) + ') for the chosen country (' + countryCode + ')';       
        //system.debug(ret);
        if ((ret.isValid) && (!String.isBlank(locSet.Address_PostalCode_Pattern__c))) {
            ret.isValid = Util_DataValidation.matchesPattern(postal, locSet.Address_PostalCode_Pattern__c);
            ret.errorMessage = (ret.isValid) ? null : 'The Postal Code provided, does not match the required format (' +  locSet.Address_PostalCode_Pattern__c + ') for the chosen country (' + countryCode + ')';
        }
        //system.debug(ret);
        // Special formatting for NL postal codes (4 digits + 2 letters with space)
        if ((ret.isValid) && (!String.isBlank(postal)) && (input.countryCode == 'NL')) {
            postal = postal.substring(0,4) + ' ' + postal.substring(4,6);
        }
        ret.postalCode = postal;
        //system.debug(ret);
        // ----------------------
        // House number validation
        // ----------------------
        String house = (input.houseNumber == null) ? '' : input.houseNumber.toUpperCase().replaceAll('[^A-Z0-9\\s\\-\\/]', '');
        if ((ret.isValid) && !String.isBlank(house) && !String.isBlank(locSet.Address_HouseNumber_Pattern__c)) {
            ret.isValid = Util_DataValidation.matchesPattern(house, locSet.Address_HouseNumber_Pattern__c);
            ret.errorMessage = (ret.isValid) ? null : 'The House Number provided, does not match the required format (' +  locSet.Address_PostalCode_Pattern__c + ') for the chosen country (' + countryCode + ')';
        }
        ret.houseNumber = house;
        //system.debug(ret);
        return ret;
    }
    //=========================================================
    //  PRIVATE METHODS - Shared helpers (used everywhere)
    //========================================================= 
    //  Core validator (shared)
    private static FieldData validate(String input, String country, String type) {
        FieldData ret = new FieldData();
        ret.value = input;
        //system.debug(ret.value);
        ret.isValid = true;
        ret.errorMessage = null;
        if (String.isBlank(ret.value)) return ret;

        ret.value = input.toUpperCase().replaceAll('[^A-Z0-9]', '');
        //system.debug(ret.value);
        LocalSetting__mdt locSet = LocalSetting__mdt.getInstance(country);
        if (locSet == null) return null;

        Integer len = Integer.valueOf(locSet.get(type + '_Length__c'));
        String pattern = (String) locSet.get(type + '_Pattern__c');
        String checksum = (String) locSet.get(type + '_Checksum__c');

        ret.isValid = (len > 0 && ret.value.length() == len);
        ret.errorMessage = (ret.isValid) ? null : 'The ' + type + ' provided, does not match the required length (' + String.valueOf(len.format()) + ') for the chosen country (' + country + ')';

        if (ret.isValid && !String.isBlank(pattern)) {
            //system.debug(ret.value);
            ret.isValid = Util_DataValidation.matchesPattern(ret.value, pattern);
            //system.debug(ret.value);
            ret.errorMessage = (ret.isValid) ? null : 'The ' + type + ' provided, does not match the required format (' + pattern + ') for the chosen country (' + country + ')';
        }

        if (ret.isValid && !String.isBlank(checksum)) {
            String retValue = ret.value;
            if ((checksum == 'MOD10') && (country == 'SE') && (type == 'CoC')) retValue = retValue.left(9);
            ret.isValid = Util_DataValidation.validateChecksum(type, checksum, retValue);
            ret.errorMessage = (ret.isValid) ? null : 'The ' + type + ' provided, is not valid for the chosen country (' + country + ')';
        }

        //system.debug('ret -> ' + ret);

        return ret;
    }
    //  Checksum router
    private static Boolean validateChecksum(String type, String algo, String value) {
    if (algo == null || algo == 'NONE') return true;

        switch on algo {
            when 'MOD10'  { return Util_DataValidation.isValidLuhn(value); }
            when 'MOD11'  { return Util_DataValidation.isValidMod11(value); }
            when 'MOD37'  { return Util_DataValidation.isValidMod37(value); }
            when 'MOD97'  { return Util_DataValidation.isValidMod97(value); }
            when 'LUHN'   { return Util_DataValidation.isValidLuhn(value); }
            when 'AT_VAT' { return Util_DataValidation.isValidATVat(value); }
            when 'BA_VAT' { return Util_DataValidation.isValidBAVat(value); }
            when 'BE_VAT' { return Util_DataValidation.isValidBEVat(value); }
            when 'BG_VAT' { return Util_DataValidation.isValidBGVat(value); }
            when 'CH_VAT' { return Util_DataValidation.isValidCHVat(value); }
            when 'CZ_VAT' { return Util_DataValidation.isValidCZVat(value); }
            when 'ES_VAT' { return Util_DataValidation.isValidESVat(value); }
            when 'FR_VAT' { return Util_DataValidation.isValidFRVat(value); }
            when 'GB_VAT' { return Util_DataValidation.isValidGBVat(value); }
            when 'HR_VAT' { return Util_DataValidation.isValidHRVat(value); }
            when 'IE_VAT' { return Util_DataValidation.isValidIEVat(value); }
            when 'IS_VAT' { return Util_DataValidation.isValidISVat(value); }
            when 'NL_VAT' { return Util_DataValidation.isValidNLVat(value); }
            when 'NO_VAT' { return Util_DataValidation.isValidNOVat(value); }
            when else     { return true; }
        }
    }

    //=========================================================
    //  PRIVATE METHODS - Shared helpers (used everywhere)
    //========================================================= 
    //  Checksum MOD-97 (IBAN + BE CoC)
    public static Boolean isValidMod97(String digits) {
        if (String.isBlank(digits) || digits.length() < 5) return false;

        // Move first 4 chars to the end
        String rearranged = digits.substring(4) + digits.substring(0, 4);
        String numeric = '';

        //System.debug('digits -> ' + digits);
        //System.debug('rearranged -> ' + rearranged);


        for (Integer i = 0; i < rearranged.length(); i++) {
            String ch = rearranged.substring(i, i + 1);

            if (ch >= '0' && ch <= '9') {
                numeric += ch;
            } else {
                // A-Z → 10-35
                Integer ascii = (Integer)ch.charAt(0); // char → int
                numeric += String.valueOf(ascii - 55); // 'A' = 65 → 10
            }
        }
        
        //system.debug('numeric -> ' + numeric);

        Integer remainder = 0;
        for (Integer i = 0; i < numeric.length(); i++) {
            remainder = Math.mod(
                remainder * 10 + Integer.valueOf(numeric.substring(i, i + 1)),
                97
            );
        }

        //System.debug('remainder -> ' + remainder);

        return remainder == 1;
    }

    //  Checksum Mod11
    public static Boolean isValidMod11(String input) {
        if (String.isBlank(input)) return false;
        //remove all non-numeric characters
        String digits = input.replaceAll('[^0-9]', '');

        if (String.isBlank(digits) || digits.length() < 2) {
            return false;
        }

        Integer sum = 0;
        Integer weight = 2;

        // Exclude check digit (rightmost)
        for (Integer i = digits.length() - 2; i >= 0; i--) {
            sum += Integer.valueOf(digits.substring(i, i + 1)) * weight;
            weight = (weight == 7) ? 2 : weight + 1;
        }

        Integer check = Math.mod(11 - Math.mod(sum, 11), 11);
        Integer expected = Integer.valueOf(digits.right(1));

        return check == expected;
    }
    public static Boolean isValidMod37(String digits) {
        return true;
    }
    
    //  Checksum Luhn (FR SIREN)
    public static Boolean isValidLuhn(String digits) {
        if (String.isBlank(digits)) return false;

        Integer sum = 0;
        Boolean doubleDigit = false;

        for (Integer i = digits.length() - 1; i >= 0; i--) {
            Integer d = Integer.valueOf(digits.substring(i, i + 1));

            if (doubleDigit) {
                d = d * 2;
                if (d > 9) {
                    d = d - 9;
                }
            }

            sum += d;
            doubleDigit = !doubleDigit;
        }

        return Math.mod(sum, 10) == 0;
    }
    public static Boolean isValidLuhn2(String digits) {
        Integer sum = 0;
        Boolean alternate = false;

        for (Integer i = digits.length() - 1; i >= 0; i--) {
            Integer n = Integer.valueOf(digits.substring(i, i + 1));

            if (alternate) {
                n *= 2;
                if (n > 9) {
                    n -= 9;
                }
            }

            sum += n;
            alternate = !alternate;
        }

        return Math.mod(sum, 10) == 0;
    }
    // ----------------------
    // Helper: Apex-safe regex match
    // ----------------------
    public static Boolean matchesPattern(String value, String pattern) {
        if (String.isBlank(pattern)) return true; // no pattern → always valid
        if (String.isBlank(value)) return false;  // empty value → invalid

        //system.debug(pattern);
        //system.debug(value);

        String effectivePattern = pattern;
        if (!effectivePattern.startsWith('^')) effectivePattern = '^' + effectivePattern;
        if (!effectivePattern.endsWith('$')) effectivePattern = effectivePattern + '$';
        //system.debug(effectivePattern);
        try {
            Boolean retValue = System.Pattern.matches(effectivePattern, value);
            //system.debug(retValue);
            return retValue;
        } catch (Exception e) {
            return false;
        }
    }

    // ----------------------
    // Helper: Title-case for city
    // ----------------------
    private static String titleCase(String value) {
        if (String.isBlank(value)) return value;
        List<String> parts = value.toLowerCase().split('\\s+');
        for (Integer i = 0; i < parts.size(); i++) {
            if (parts[i].length() > 0) {
                parts[i] = parts[i].substring(0, 1).toUpperCase() + parts[i].substring(1);
            }
        }
        return String.join(parts, ' ');
    }

        public static Map<String, String> formatAddress(
        String street,
        String postalCode,
        String city,
        String countryCode
    ) {
        if (String.isBlank(countryCode)) {
            return new Map<String, String>();
        }

        countryCode = countryCode.trim().toUpperCase();

        Map<String, String> resultAddress = new Map<String, String>();
        resultAddress.put('Street', Util_DataValidation.formatStreet(street));
        resultAddress.put('PostalCode', Util_DataValidation.formatPostalCode(postalCode, countryCode));
        resultAddress.put('City', city != null ? city.trim().toUpperCase() : null);
        resultAddress.put('CountryCode', countryCode);

        return resultAddress;
    }

    /* -------------------------
       Street formatting
       ------------------------- */
    private static String formatStreet(String street) {
        if (String.isBlank(street)) return null;

        Set<String> lowercaseWords = new Set<String>{
            'van', 'de', 'der', 'den', 'ten', 'ter', 'von', 'aan', '\'t',
            'of', 'and', 'the', 'la', 'le', 'du', 'des'
        };

        List<String> words = street.trim().toLowerCase().split('\\s+');
        List<String> formattedWords = new List<String>();

        for (Integer i = 0; i < words.size(); i++) {
            String word = words[i];

            if (i > 0 && lowercaseWords.contains(word)) {
                formattedWords.add(word);
            } else {
                formattedWords.add(
                    word.substring(0, 1).toUpperCase() + word.substring(1)
                );
            }
        }

        return String.join(formattedWords, ' ');
    }

    /* -------------------------
       Postal code formatting
       ------------------------- */
    private static String formatPostalCode(String postalCode, String countryCode) {
        if (String.isBlank(postalCode)) return null;

        String pc = postalCode.replaceAll('\\s+', '').toUpperCase();

        switch on countryCode {
            when 'NL' {
                // 1234AB → 1234 AB
                if (pc.length() == 6) {
                    return pc.substring(0, 4) + ' ' + pc.substring(4);
                }
                return pc;
            }
            when 'GB' {
                // Space before last 3 characters
                if (pc.length() > 3) {
                    return pc.substring(0, pc.length() - 3) + ' ' + pc.substring(pc.length() - 3);
                }
                return pc;
            }
            when 'AT', 'BE', 'CH', 'DE', 'FR' {
                // Numeric only
                return pc.replaceAll('[^0-9]', '');
            }
            when else {
                return pc;
            }
        }
    }

    /* =========================================================
       CoC NORMALIZATION (NO STRICT CHECKSUM ENFORCEMENT)
       ========================================================= */
    public static String normalizeCoC(String coc, String countryCode) {
        if (String.isBlank(coc) || String.isBlank(countryCode)) return null;

        countryCode = countryCode.toUpperCase();
        String digits = coc.replaceAll('[^0-9A-Z]', '');

        switch on countryCode {
            when 'NL' {
                return digits.replaceAll('[^0-9]', '').leftPad(9, '0');
            }
            when 'BE' {
                return digits.replaceAll('[^0-9]', '').leftPad(10, '0');
            }
            when 'FR' {
                return Util_DataValidation.isValidLuhn(digits) ? digits : null;
            }
            when else {
                return digits;
            }
        }
    }

    /* =========================================================
       VAT NORMALIZATION + VALIDATION
       ========================================================= */
    public static String normalizeVAT(String vat, String countryCode) {
     if (String.isBlank(vat) || String.isBlank(countryCode)) return null;

        countryCode = countryCode.toUpperCase();
        String cleaned = vat.toUpperCase().replaceAll('[^A-Z0-9]', '');
        system.debug('cleaned - ' + cleaned);

        switch on countryCode {

            /* ---------------- NL ---------------- */
            when 'NL' {
                // NL123456789B01
                if (!cleaned.startsWith('NL')) cleaned = 'NL' + cleaned;
                if (cleaned.length() != 14) return null;

                // Structure: NL + 9 digits + B + 2 digits
                String core = cleaned.substring(2, 11);
                String bChar = cleaned.substring(11, 12);
                String suffix = cleaned.substring(12, 14);
                system.debug('core - ' + core);
                system.debug('bChar - ' + bChar);
                system.debug('suffix - ' + suffix);

                // Structural checks
                if (bChar != 'B') return null;
                if (!Pattern.matches('\\d{9}', core)) return null;
                if (!Pattern.matches('\\d{2}', suffix)) return null;
                system.debug(Util_DataValidation.isValidNLVat(core));
                if (!Util_DataValidation.isValidNLVat(core)) return null;

                return  cleaned;
            }

            /* ---------------- BE ---------------- */
            when 'BE' {
                String digits = cleaned.replaceAll('[^0-9]', '').leftPad(10, '0');
                if (!Util_DataValidation.isValidBEVAT(digits)) return null;
                return 'BE' + digits;
            }
            /* ---------------- DE ---------------- */
            when 'DE' {
                String digits = cleaned.replaceAll('[^0-9]', '');
                if (!Util_DataValidation.isValidDEVat(digits)) return null;
                return 'DE' + digits;
            }

            /* ---------------- AT ---------------- */
            when 'AT' {
                String digits = cleaned.replaceAll('[^0-9]', '');
                if (!isValidATVat(digits)) return null;
                return 'ATU' + digits;
            }

            /* ---------------- FR ---------------- */
            when 'FR' {
                if (cleaned.length() != 13) return null;

                String key = cleaned.substring(2, 4);
                String siren = cleaned.substring(4);

                if (!Util_DataValidation.isValidFRVat(key, siren)) return null;
                return cleaned;
            }

            /* ---------------- CH ---------------- */
            when 'CH' {
                // CHE123456789MWST
                return cleaned.startsWith('CHE') ? cleaned : null;
            }

            /* ---------------- GB ---------------- */
            when 'GB' {
                String digits = cleaned.replaceAll('[^0-9]', '');
                if (!Util_DataValidation.isValidGBVat(digits)) return null;
                return 'GB' + digits;
            }

            when else {
                return null;
            }
        }
    }

    /* =========================================================
       VAT - CHECKSUM IMPLEMENTATIONS
    ========================================================= */
    private static Boolean isValidBAVat(String core) {
        return true; //Math.mod(sum, 11) == 0;
    }

    private static Boolean isValidBGVat(String core) {
        return true; //Math.mod(sum, 11) == 0;
    }

    private static Boolean isValidCZVat(String core) {
        return true; //Math.mod(sum, 11) == 0;
    }
    private static Boolean isValidISVat(String core) {
        return true; //Math.mod(sum, 11) == 0;
    }
    
    private static Boolean isValidHRVat(String core) {
        return true; //Math.mod(sum, 11) == 0;
    }
    
    private static Boolean isValidNOVat(String core) {
        return true; //Math.mod(sum, 11) == 0;
    }

    // NL: 11-proef
    private static Boolean isValidNLVat2(String core) {
        Integer sum = 0;
        for (Integer i = 0; i < 9; i++) {
            Integer digit = Integer.valueOf(core.substring(i, i + 1));
            sum += digit * (9 - i);
        }
        system.debug(sum);
        system.debug(Math.mod(sum, 11));
        return Math.mod(sum, 11) == 0;
    }

        //  Checksum 🇳🇱 Netherlands — isValidNLVAT
    private static Boolean isValidNLVAT(String vat) {
        // strip NL + Bxx
        String digits = vat.substring(2, 11);

        Integer sum = 0;
        Integer[] weights = new Integer[] {9,8,7,6,5,4,3,2};

        for (Integer i = 0; i < 8; i++) {
            sum += Integer.valueOf(digits.substring(i, i+1)) * weights[i];
        }

        Integer check = 11 - Math.mod(sum, 11);
        if (check == 10) return false;
        if (check == 11) check = 0;

        return check == Integer.valueOf(digits.substring(8,9));
    }
    // BE: mod 97
    private static Boolean isValidBEVat2(String tenDigits) {
        Long base = Long.valueOf(tenDigits.substring(0, 8));
        Integer check = Integer.valueOf(tenDigits.substring(8));
        return (97 - Math.mod(base, 97)) == check;
    }
    //  🇧🇪 Belgium — isValidBEVAT
    private static Boolean isValidBEVAT(String vat) {
        String digits = vat.substring(2);

        Long base = Long.valueOf(digits.substring(0,8));
        Integer checksum = Integer.valueOf(digits.substring(8,10));

        Integer expected = 97 - (Integer)Math.mod(base, 97);
        if (expected == 0) expected = 97;

        return checksum == expected;
    }
    //  Checksum 🇫🇷 France — isValidFRVAT
    private static Boolean isValidFRVAT(String vat) {
        Integer key = Integer.valueOf(vat.substring(2,4));
        Long siren = Long.valueOf(vat.substring(4));

        Integer expected =
            (Integer)(Math.mod(12 + 3 * Math.mod(siren, 97), 97));

        return key == expected;
    }
    //  Checksum 🇦🇹 Austria — isValidATVAT
    private static Boolean isValidATVAT(String vat) {
        // Expecting ATU + 8 digits
        if (vat == null || vat.length() != 11 || !vat.startsWith('ATU')) {
            return false;
        }

        String digits = vat.substring(3); // 8 digits after ATU

        Integer sum = 0;
        Integer[] weights = new Integer[] {1, 2, 1, 2, 1, 2, 1};

        for (Integer i = 0; i < 7; i++) {
            Integer product =
                Integer.valueOf(digits.substring(i, i + 1)) * weights[i];

            // Luhn-style reduction
            if (product > 9) {
                product -= 9;
            }

            sum += product;
        }

        Integer check = Math.mod(10 - Math.mod(sum, 10), 10);
        Integer expected = Integer.valueOf(digits.substring(7, 8));

        return check == expected;
    }
    // AT: weighted mod 11
    private static Boolean isValidATVat2(String digits) {
        // digits = 8 digits AFTER the "U"
        Integer[] weights = new Integer[]{1, 2, 1, 2, 1, 2, 1};
        Integer sum = 0;

        for (Integer i = 0; i < 7; i++) {
            Integer value = Integer.valueOf(digits.substring(i, i + 1)) * weights[i];

            // If > 9, subtract 9 (Luhn-style step)
            sum += (value > 9) ? value - 9 : value;
        }

        Integer checkDigit = Math.mod(
            10 - Math.mod(sum, 10),
            10
        );

        return checkDigit == Integer.valueOf(digits.substring(7));
    }
    //  Checksum 🇬🇧 United Kingdom — isValidGBVAT
    private static Boolean isValidGBVAT(String vat) {
        String digits = vat.substring(2);

        Integer sum = 0;
        Integer[] weights = new Integer[] {8,7,6,5,4,3,2};

        for (Integer i = 0; i < 7; i++) {
            sum += Integer.valueOf(digits.substring(i,i+1)) * weights[i];
        }

        Integer check = 97 - Math.mod(sum, 97);
        return check == Integer.valueOf(digits.substring(7,9));
    }
    // GB: standard mod 97 (simplified)
    private static Boolean isValidGBVat2(String digits) {
        if (digits.length() != 9) return false;
        return Math.mod(Long.valueOf(digits.substring(0, 7)), 97) ==
               Integer.valueOf(digits.substring(7));
    }
    //  Checksum 🇪🇸 Spain — isValidESVAT
    private static Boolean isValidESVAT(String vat) {
        String controlChars = 'TRWAGMYFPDXBNJZSQVHLCKE';

        String digits = vat.substring(2,10);
        String control = vat.substring(10,11);

        Integer idx = (Integer)Math.mod(Integer.valueOf(digits), 23);
        return control == controlChars.substring(idx, idx+1);
    }
    //  Checksum 🇮🇪 Ireland — isValidIEVAT
    private static Boolean isValidIEVAT(String vat) {
        String digits = vat.substring(2,9);
        String letter = vat.substring(9,10);

        Integer sum = 0;
        Integer[] weights = new Integer[] {8,7,6,5,4,3,2};

        for (Integer i = 0; i < 7; i++) {
            sum += Integer.valueOf(digits.substring(i,i+1)) * weights[i];
        }

        Integer idx = Math.mod(sum, 23);
        String expected = idx == 0 ? 'W' : String.fromCharArray(
            new Integer[] {64 + idx}
        );

        return expected == letter;
    }
    //  Checksum 🇨🇭 Switzerland — isValidCHVAT
    private static Boolean isValidCHVAT(String vat) {
        String digits = vat.substring(3,12);
        return Util_DataValidation.isValidMod11(digits);
    }



    // DE: iterative mod 11
    private static Boolean isValidDEVat(String digits) {
        Integer product = 10;

        for (Integer i = 0; i < 8; i++) {
            Integer sum = Math.mod(
                Integer.valueOf(digits.substring(i, i + 1)) + product,
                10
            );

            if (sum == 0) {
                sum = 10;
            }

            product = Math.mod(sum * 2, 11);
        }

        Integer check = 11 - product;
        if (check == 10 || check == 11) {
            check = 0;
        }

        return check == Integer.valueOf(digits.substring(8));
    }



    // FR: key = (12 + 3 × (SIREN mod 97)) mod 97
    private static Boolean isValidFRVat(String key, String siren) {
        Integer expected = (Integer)Math.mod((12 + 3 * Math.mod(Long.valueOf(siren), 97)), 97);
        return Integer.valueOf(key) == expected;
    }





    public static Boolean isValidMod97(String digits, Integer checksum) {
        Long value = Long.valueOf(digits);
        return Math.mod(value, 97) == checksum;
    }

}
