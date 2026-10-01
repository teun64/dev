// Rolled-back check of rbb_Account v65 dec_01_FinancialSystemSync on a temporary account.
// Ends with an exception so the whole transaction fails: no async Exact/WSONE job survives.
List<String> out = new List<String>();
Savepoint sp = Database.setSavepoint();
try {
    Account t = new Account(Name = 'RRTEST Exact sync', RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('B2B').getRecordTypeId(),
        BillingStreet = 'Teststraat 1', BillingPostalCode = '1234 AA', BillingCity = 'Teststad', BillingCountryCode = 'NL');
    insert t;
    Id accId = t.Id;
    Map<String, Map<String, Object>> steps = new Map<String, Map<String, Object>>{
        'unrelated (Description)' => new Map<String, Object>{ 'Description' => 'RRTEST' },
        'BillingStreet'           => new Map<String, Object>{ 'BillingStreet' => 'Teststraat 2' },
        'BillingPostalCode'       => new Map<String, Object>{ 'BillingPostalCode' => '1234 AB' },
        'BillingCity'             => new Map<String, Object>{ 'BillingCity' => 'Teststad Oost' },
        'BillingCountryCode'      => new Map<String, Object>{ 'BillingCountryCode' => 'BE' }
    };
    for (String step : steps.keySet()) {
        update new Account(Id = accId, FinancialSystemSync__c = false);
        Account a = new Account(Id = accId);
        for (String f : steps.get(step).keySet()) a.put(f, steps.get(step).get(f));
        update a;
        out.add(step + ' | exactSync=' + [SELECT FinancialSystemSync__c FROM Account WHERE Id = :accId].FinancialSystemSync__c);
    }
} finally {
    Database.rollback(sp);
    out.add('ROLLED BACK');
    throw new System.IllegalArgumentException('RRTEST abort (intended)\n' + String.join(out, '\n'));
}
