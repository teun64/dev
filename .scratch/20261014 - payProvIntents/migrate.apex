// Moves the Stripe intent ids to PayProv_PaymentIntentId__c. DRY = true: run, compare every field, roll back.
// rbb_Payment rewrites Processing_Date__c on every save → old value + 1 s keeps it (approved 2026-10-13).
Boolean DRY = true;
Map<String, String> overrideByName = new Map<String, String>{
    'PM#000201568' => 'pi_3UNEnbGliYpbpuQB1OgEokZV'   // Marc Stone: the real 05-10 checkout, not a refunded duplicate
};
List<Payment__c> src = [SELECT Id, Name, Processing_Date__c, PaymentIntentId__c, ProviderPaymentIntentID__c, PayProv_PaymentIntentId__c
                        FROM Payment__c WHERE (PaymentIntentId__c != null OR ProviderPaymentIntentID__c != null) AND PayProv_PaymentIntentId__c = null];
Set<String> skip = new Set<String>{'lastmodifieddate','systemmodstamp','lastmodifiedbyid','payprov_paymentintentid__c','lastvieweddate','lastreferenceddate'};
List<String> fields = new List<String>(Schema.SObjectType.Payment__c.fields.getMap().keySet());
Set<Id> ids = new Map<Id, Payment__c>(src).keySet();
String q = 'SELECT ' + String.join(fields, ',') + ' FROM Payment__c WHERE Id IN :ids';
Map<Id, Payment__c> before = new Map<Id, Payment__c>((List<Payment__c>) Database.query(q));
Savepoint sp = Database.setSavepoint();
List<Payment__c> ups = new List<Payment__c>();
for (Payment__c p : src) {
    String pi = overrideByName.containsKey(p.Name) ? overrideByName.get(p.Name)
              : (p.PaymentIntentId__c != null ? p.PaymentIntentId__c : p.ProviderPaymentIntentID__c);
    ups.add(new Payment__c(Id = p.Id, PayProv_PaymentIntentId__c = pi,
        Processing_Date__c = p.Processing_Date__c == null ? null : p.Processing_Date__c.addSeconds(1)));
}
Integer ok = 0;
for (Database.SaveResult r : Database.update(ups, false)) { if (r.isSuccess()) ok++; else System.debug('MIG ERR ' + r.getErrors()[0].getMessage()); }
Map<Id, Payment__c> after = new Map<Id, Payment__c>((List<Payment__c>) Database.query(q));
Integer diffs = 0;
for (Id i : before.keySet()) {
    Payment__c b = before.get(i), a = after.get(i);
    System.debug('MIG ' + b.Name + ' -> ' + a.PayProv_PaymentIntentId__c);
    for (String f : fields) {
        if (skip.contains(f) || b.get(f) == a.get(f)) continue;
        if (f == 'processing_date__c' && b.Processing_Date__c != null && a.Processing_Date__c == b.Processing_Date__c.addSeconds(1)) continue;
        diffs++; System.debug('MIG DIFF ' + b.Name + ' ' + f + ': ' + b.get(f) + ' -> ' + a.get(f));
    }
}
System.debug('MIG updated ' + ok + ' of ' + ups.size() + ', other field diffs ' + diffs + (DRY ? ' (DRY RUN, rolled back)' : ''));
if (DRY) Database.rollback(sp);
