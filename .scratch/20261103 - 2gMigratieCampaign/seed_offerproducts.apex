// Offer mapping rows (CampaignOfferProduct__c), per org by name/product code. Idempotent: skips an existing Hardware+Offer+Campaign row.
// Hardware product = the Product2 the hardware Asset points to (Name below).
String campaignName = 'ZZ 2G Test';   // main (parent) campaign (required; prod: the real main campaign name)
List<List<String>> spec = new List<List<String>>{
  // hardware Product2.Name, offer code, alternative code, filter field, filter value
  new List<String>{ 'Mi50', '3011', '3010', 'Accessories__c', 'Klasse 5 module (intern)' },
  new List<String>{ 'Mi40', '3030', null, null, null },
  new List<String>{ 'MiTracer', '3040', null, null, null }   // Mi01
};
Id campaignId = [SELECT Id FROM Campaign WHERE Name = :campaignName AND ParentId = null LIMIT 1].Id;
Set<String> codes = new Set<String>(); Set<String> names = new Set<String>();
for (List<String> s : spec) { names.add(s[0]); codes.add(s[1]); if (s[2] != null) codes.add(s[2]); }
Map<String, Id> byName = new Map<String, Id>(); Map<String, Id> byCode = new Map<String, Id>();
for (Product2 p : [SELECT Id, Name, ProductCode FROM Product2 WHERE Name IN :names OR ProductCode IN :codes]) { if (names.contains(p.Name)) byName.put(p.Name, p.Id); if (codes.contains(p.ProductCode)) byCode.put(p.ProductCode, p.Id); }
List<CampaignOfferProduct__c> ins = new List<CampaignOfferProduct__c>();
Integer prio = 1;
for (List<String> s : spec) {
  System.assert(byName.containsKey(s[0]), 'hardware product not found: ' + s[0]);
  System.assert(byCode.containsKey(s[1]), 'offer product not found: ' + s[1]);
  if (s[2] != null) System.assert(byCode.containsKey(s[2]), 'alternative not found: ' + s[2]);
  ins.add(new CampaignOfferProduct__c(Campaign__c = campaignId, Hardware__c = byName.get(s[0]), OfferProduct__c = byCode.get(s[1]),
    AlternativeProduct__c = s[2] == null ? null : byCode.get(s[2]), FilterField__c = s[3], FilterValue__c = s[4], Priority__c = prio++, Active__c = true));
}
Set<String> have = new Set<String>();
for (CampaignOfferProduct__c e : [SELECT Hardware__c, OfferProduct__c, Campaign__c FROM CampaignOfferProduct__c]) have.add('' + e.Hardware__c + e.OfferProduct__c + e.Campaign__c);
List<CampaignOfferProduct__c> todo = new List<CampaignOfferProduct__c>();
for (CampaignOfferProduct__c n : ins) if (!have.contains('' + n.Hardware__c + n.OfferProduct__c + n.Campaign__c)) todo.add(n);
insert todo;
System.debug(LoggingLevel.ERROR, 'SEEDRESULT inserted=' + todo.size());
