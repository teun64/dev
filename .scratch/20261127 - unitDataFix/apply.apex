// Unit data fix for Product2.QuantityUnitOfMeasure. Safe groups only; the REVIEW group (NON_RECURRING with Month(s)) is NOT touched.
// DRY = true: only counts, writes nothing. PROD: run only on the user's explicit command (after reading prod_dryrun.txt).
Boolean DRY = true;
List<Product2> upd = new List<Product2>(); Map<String, Integer> n = new Map<String, Integer>();
for (Product2 p : [SELECT Id, Subscription25__Cost_Type__c, QuantityUnitOfMeasure FROM Product2 WHERE QuantityUnitOfMeasure = null OR QuantityUnitOfMeasure IN ('Month', '12', '24')]) {
    String target = null;
    if (p.QuantityUnitOfMeasure == null && p.Subscription25__Cost_Type__c == 'NON_RECURRING') target = 'Piece(s)';
    else if (p.QuantityUnitOfMeasure == null && p.Subscription25__Cost_Type__c == 'RECURRING') target = 'Month(s)';
    else if (p.Subscription25__Cost_Type__c == 'RECURRING' && p.QuantityUnitOfMeasure != null) target = 'Month(s)';
    if (target == null) continue;
    n.put(p.Subscription25__Cost_Type__c + ': ' + p.QuantityUnitOfMeasure + ' -> ' + target, (n.containsKey(p.Subscription25__Cost_Type__c + ': ' + p.QuantityUnitOfMeasure + ' -> ' + target) ? n.get(p.Subscription25__Cost_Type__c + ': ' + p.QuantityUnitOfMeasure + ' -> ' + target) : 0) + 1);
    upd.add(new Product2(Id = p.Id, QuantityUnitOfMeasure = target));
}
for (String k : n.keySet()) System.debug('TS_FIX ' + k + ' x' + n.get(k));
if (!DRY) { Database.SaveResult[] r = Database.update(upd, false); Integer bad = 0; for (Database.SaveResult s : r) if (!s.isSuccess()) { bad++; System.debug('TS_FIX_ERR ' + s.getErrors()[0].getMessage()); } System.debug('TS_FIX updated=' + (upd.size() - bad) + ' failed=' + bad); } else { System.debug('TS_FIX DRY run, would update ' + upd.size()); }
