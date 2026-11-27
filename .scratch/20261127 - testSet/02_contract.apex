// TESTSET step 2: ONE contract per run (the REST handler needs most of the SOQL limit). WHICH = A1 | A2 | B1 | B_AIO
String WHICH = '@@WHICH@@';
if (![SELECT IsSandbox FROM Organization].get(0).IsSandbox) { System.debug('TS_RESULT=NOT A SANDBOX'); return; }
try {
    RestContext.request = new RestRequest(); RestContext.response = new RestResponse();
    RestContext.request.requestURI = '/UpsertContract'; RestContext.request.httpMethod = 'POST';
    Map<String, Map<String, Object>> reqs = new Map<String, Map<String, Object>>{
        'A1' => new Map<String, Object>{'id' => 'TS-A-1', 'accountId' => 'TESTSET-A', 'installationId' => '9101', 'productId' => '392', 'unitPrice' => 25.0, 'contractTerm' => 12, 'invoiceTerm' => 12},
        'A2' => new Map<String, Object>{'id' => 'TS-A-2', 'accountId' => 'TESTSET-A', 'installationId' => '9102', 'productId' => '418', 'unitPrice' => 15.0, 'contractTerm' => 12, 'invoiceTerm' => 12},
        'B1' => new Map<String, Object>{'id' => 'TS-B-1', 'accountId' => 'TESTSET-B', 'installationId' => '9103', 'productId' => '431', 'unitPrice' => 12.5, 'contractTerm' => 12, 'invoiceTerm' => 1}
    };
    if (reqs.containsKey(WHICH)) {
        Map<String, Object> r = reqs.get(WHICH);
        r.put('platformId', 1); r.put('startDate', '2026-10-01'); r.put('renewalTerm', 12); r.put('noticeTerm', 1);
        r.put('orderOffsetTerm', 0); r.put('isBaseService', true); r.put('quantity', 1); r.put('prepaid', false); r.put('salesChannelId', '1');
        System.debug('TS_REST ' + r.get('id') + ' => ' + JSON.serialize(Rest_UpsertContract.handleAction(JSON.serialize(r))));
    }
    if (WHICH == 'B_AIO') {
    // 2 x All-in-one on the monthly contract, cloned from the MiBlack-R contract product (all-in-one is a platform-5 product id, so not via REST)
    Map<String, Schema.SObjectField> cpFields = Schema.SObjectType.Subscription25__Contract_Product__c.fields.getMap();
    List<String> cols = new List<String>();
    for (String f : cpFields.keySet()) { if (cpFields.get(f).getDescribe().isCreateable()) { cols.add(f); } }
    Subscription25__Contract_Product__c base = Database.query('SELECT ' + String.join(cols, ',') + ' FROM Subscription25__Contract_Product__c WHERE extId__c LIKE \'TS-B-1%\' LIMIT 1');
    Id aioProd = [SELECT Id FROM Product2 WHERE ProductCode = '1.1000.01' LIMIT 1].Id;
    List<Subscription25__Contract_Product__c> aio = new List<Subscription25__Contract_Product__c>();
    for (Integer i = 1; i <= 2; i++) {
        Subscription25__Contract_Product__c c = base.clone(false, true, false, false);
        c.Subscription25__Product__c = aioProd; c.Subscription25__Price__c = 19.95; c.Subscription25__Recurring_Order__c = null; c.Parent__c = null;
        if (cpFields.containsKey('extid__c')) { c.put('extId__c', 'TS-B-AIO' + i + '-1'); }
        aio.add(c);
    }
    insert aio;
    }
    System.debug('TS_RESULT=DONE ' + WHICH);
} catch (Exception e) {
    System.debug('TS_RESULT=ERROR ' + e.getTypeName() + ': ' + e.getMessage() + ' @ ' + e.getStackTraceString());
}
