// TESTSET step 1 (dev/acc ONLY). Set DRY=true to roll back. Idempotent: stops if the set exists.
Boolean DRY = false;
if (![SELECT Id FROM Account WHERE Name LIKE 'TESTSET %' LIMIT 1].isEmpty()) { System.debug('TS_RESULT=ALREADY EXISTS, run 03_cleanup first'); return; }
if (URL.getOrgDomainUrl().getHost().contains('--prod') || ![SELECT IsSandbox FROM Organization].get(0).IsSandbox) { System.debug('TS_RESULT=NOT A SANDBOX'); return; }
Savepoint sp = Database.setSavepoint();
try {
    Subscription25__Administration__c adm = [SELECT Id, Include_CII_Hybrid_PDF__c FROM Subscription25__Administration__c WHERE Reseller__c = '1' LIMIT 1];
    if (!DRY) { adm.Include_CII_Hybrid_PDF__c = true; update adm; }

    Id rtB2B = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId();
    List<Account> accs = new List<Account>();
    for (String k : new List<String>{'A', 'B'}) {
        accs.add(new Account(Name = 'TESTSET ' + k + ' B.V.', RecordTypeId = rtB2B,
            BillingStreet = 'Teststraat 1' + k, BillingPostalCode = '1011 AB', BillingCity = 'Amsterdam', BillingCountryCode = 'NL',
            ShippingStreet = 'Teststraat 1' + k, ShippingPostalCode = '1011 AB', ShippingCity = 'Amsterdam', ShippingCountryCode = 'NL',
            useInvoiceAddress__c = false, useShippingAddress__c = false,
            Bank_Account__c = 'TESTSET ' + k + ' - Bank', Bank_Account_Number__c = 'NL35INGB0666489106', Bank_BIC__c = 'INGBNL2A',
            Reseller_Name__c = '1', Relation_Type__c = 'End User', Sales_Language__c = 'NL',
            Payment_Method_Opportunities__c = '08', Payment_Method_Contracts__c = '14',
            extID_1__c = 'TESTSET-' + k, FinancialDebtorNumber__c = 'TS' + k, VAT_Number__c = 'NL370528980B92', VAT_Number_Confirmation__c = true,
            CoC_Number__c = '27339223', CoC_Number_Confirmation__c = true));
    }
    insert accs;
    List<Subscription25__Debtor_Number__c> dns = new List<Subscription25__Debtor_Number__c>();
    for (Account a : accs) { dns.add(new Subscription25__Debtor_Number__c(Subscription25__Administration__c = adm.Id, Subscription25__Account__c = a.Id, Subscription25__Debtor_Number__c = 'TS' + a.extID_1__c.right(1))); }
    insert dns;

    // 3 contacts per account: Main, Invoice+Digital, Shipping
    List<Contact> cons = new List<Contact>();
    for (Account a : accs) {
        String k = a.extID_1__c.right(1);
        cons.add(new Contact(AccountId = a.Id, FirstName = 'Main', LastName = 'TESTSET ' + k, Email = 'testset.main.' + k.toLowerCase() + '@testset.invalid', Phone = '0201234567'));
        cons.add(new Contact(AccountId = a.Id, FirstName = 'Invoice', LastName = 'TESTSET ' + k, Email = 'testset.invoice.' + k.toLowerCase() + '@testset.invalid', Phone = '0201234567'));
        cons.add(new Contact(AccountId = a.Id, FirstName = 'Shipping', LastName = 'TESTSET ' + k, Email = 'testset.shipping.' + k.toLowerCase() + '@testset.invalid', Phone = '0201234567'));
    }
    for (Contact c : cons) { insert c; } // one at a time: rab_Contact faults on bulk Contact DML with Email
    Map<Id, Contact> conById = new Map<Id, Contact>(cons);
    List<AccountContactRelation> acrs = new List<AccountContactRelation>();
    for (AccountContactRelation r : [SELECT Id, ContactId FROM AccountContactRelation WHERE ContactId IN :conById.keySet()]) {
        String fn = conById.get(r.ContactId).FirstName;
        r.Roles = fn == 'Main' ? 'Main' : (fn == 'Invoice' ? 'Invoice;Digital' : 'Shipping');
        acrs.add(r);
    }
    update acrs;

    // assets: 2 on account A (one per contract) + 1 on account B (monthly contract); Hardware + Entity per asset
    Id rtHw = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Hardware').getRecordTypeId();
    Id rtEn = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Entity').getRecordTypeId();
    Id hwProd = [SELECT Id FROM Product2 WHERE extID__c = '87-hw-1' LIMIT 1].Id;
    List<List<String>> spec = new List<List<String>>{ new List<String>{'9101', '0'}, new List<String>{'9102', '0'}, new List<String>{'9103', '1'} }; // id, account index
    List<Asset> hws = new List<Asset>();
    for (List<String> s : spec) { hws.add(new Asset(Name = 'TS' + s[0], SerialNumber = 'TS' + s[0], AccountId = accs[Integer.valueOf(s[1])].Id, RecordTypeId = rtHw, Product2Id = hwProd, extId__c = s[0] + '-hw-1')); }
    insert hws;
    List<Asset> ens = new List<Asset>();
    for (Integer i = 0; i < spec.size(); i++) { ens.add(new Asset(Name = 'TSE' + spec[i][0], AccountId = accs[Integer.valueOf(spec[i][1])].Id, RecordTypeId = rtEn, ParentId = hws[i].Id, extId__c = spec[i][0] + '-in-1')); }
    insert ens;

    if (DRY) { Database.rollback(sp); System.debug('TS_RESULT=DRY RUN rolled back'); } else { System.debug('TS_RESULT=CREATED base'); }
} catch (Exception e) {
    Database.rollback(sp);
    System.debug('TS_RESULT=ERROR ' + e.getTypeName() + ': ' + e.getMessage() + ' @ ' + e.getStackTraceString());
}
