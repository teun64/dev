Business_Entities__c be = [SELECT Reseller__c, FinSysStripeFeeVATCode__c, FinSysStripeJournalCode__c FROM Business_Entities__c WHERE Id = 'a3ETx000000cQ9ZMAU'];
Subscription25__Administration__c admin = [SELECT Id, Name, Reseller__c, CurrencyIsoCode, Daily_Limit__c, FinancialRateLimitMaxPercentage__c, FinancialRateLimitRemaining__c,
  FinancialRateLimitResetOn__c, Acceptance_Environment_Available__c, Subscription25__Named_Credential__c, Subscription25__Twinfield_Company_Code__c
  FROM Subscription25__Administration__c WHERE Reseller__c = :be.Reseller__c LIMIT 1];
System.assertEquals('112143', admin.Subscription25__Twinfield_Company_Code__c);
System.assertEquals('28', be.FinSysStripeJournalCode__c);
String gl = 'f7372f57-64d9-42c5-af00-410d61b89ce9'; // 470700
Map<String, Object[]> plan = new Map<String, Object[]>{
  '2026-11-03' => new Object[]{ 'po_1UXVVdGliYpbpuQB6Ho9NuPM', 0.40, new Map<String, Decimal>{
      'Stripe processing fees po_1UXVVdGliYpbpuQB6Ho9NuPM' => 0.20,
      'Stripe Radar (2026-10-24): Standard' => 0.04, 'Stripe Radar (2026-10-28): Standard' => 0.04,
      'Stripe Radar (2026-10-30): Standard' => 0.04, 'Stripe Radar (2026-11-01): Standard' => 0.08 } },
  '2026-11-04' => new Object[]{ 'po_1UXsHUGliYpbpuQBWOzhRTpK', 0.24, new Map<String, Decimal>{
      'Stripe processing fees po_1UXsHUGliYpbpuQBWOzhRTpK' => 0.20,
      'Stripe Radar (2026-11-02): Standard' => 0.04 } }
};
for (String day : plan.keySet()) {
  Object[] x = plan.get(day);
  List<Object> lines = new List<Object>();
  lines.add(new Map<String, Object>{ 'Date' => day, 'GLAccount' => gl, 'AmountFC' => -(Decimal) x[1], 'Description' => 'Split Stripe fees ' + x[0] });
  Decimal sum = 0;
  Map<String, Decimal> split = (Map<String, Decimal>) x[2];
  for (String d : split.keySet()) {
    Map<String, Object> l = new Map<String, Object>{ 'Date' => day, 'GLAccount' => gl, 'AmountFC' => split.get(d), 'Description' => d };
    if (String.isNotBlank(be.FinSysStripeFeeVATCode__c)) l.put('VATCode', be.FinSysStripeFeeVATCode__c);
    lines.add(l); sum += split.get(d);
  }
  System.assertEquals((Decimal) x[1], sum);
  Map<String, Object> body = new Map<String, Object>{ 'JournalCode' => '28', 'Currency' => 'GBP', 'FinancialYear' => 2026, 'FinancialPeriod' => 11, 'GeneralJournalEntryLines' => lines };
  String r = Util_FinancialSystem.doRequest(admin, 'api/v1/112143/generaljournalentry/GeneralJournalEntries', null, 'POST', JSON.serialize(body), null);
  Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(r);
  if (m.containsKey('d')) m = (Map<String, Object>) m.get('d');
  System.debug(LoggingLevel.ERROR, 'POSTED ' + x[0] + ' entry ' + m.get('EntryNumber') + ' id ' + m.get('EntryID'));
}
Map<String, String> descByTxn = new Map<String, String>{
  'txn_1UUJghGliYpbpuQBtMkBE1Mh' => 'Stripe Radar (2026-10-24): Standard', 'txn_1UVnuBGliYpbpuQBYlPPpOoL' => 'Stripe Radar (2026-10-28): Standard',
  'txn_1UWUbQGliYpbpuQB98lSRtzZ' => 'Stripe Radar (2026-10-30): Standard', 'txn_1UXDO0GliYpbpuQBIDlY0Gun' => 'Stripe Radar (2026-11-01): Standard',
  'txn_1UXaCNGliYpbpuQBMLEHX59y' => 'Stripe Radar (2026-11-02): Standard' };
List<FinSysPostingLine__c> fl = [SELECT Id, StripeBalanceTransactionId__c FROM FinSysPostingLine__c WHERE StripeBalanceTransactionId__c IN :descByTxn.keySet()];
for (FinSysPostingLine__c l : fl) l.Description__c = descByTxn.get(l.StripeBalanceTransactionId__c);
update fl;
System.debug(LoggingLevel.ERROR, 'LINES UPDATED ' + fl.size());
