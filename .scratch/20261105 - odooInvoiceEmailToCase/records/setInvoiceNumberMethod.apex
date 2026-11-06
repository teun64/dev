// Business Entity: how the financial system numbers an invoice. UK = Import, NL + DE = Print, others (no Exact) blank.
// Run per org: sf apex run -o <org> -f setInvoiceNumberMethod.apex   (prod only on explicit command)
List<Business_Entities__c> bes = [SELECT Id, Name, Reseller__c, FinSysInvoiceNumberMethod__c FROM Business_Entities__c];
for (Business_Entities__c be : bes) {
	if (be.Reseller__c == '6') { be.FinSysInvoiceNumberMethod__c = 'Import'; }
	else if (be.Reseller__c == '1' || be.Reseller__c == '5') { be.FinSysInvoiceNumberMethod__c = 'Print'; }
}
Database.update(bes);
for (Business_Entities__c be : [SELECT Name, Reseller__c, FinSysInvoiceNumberMethod__c FROM Business_Entities__c ORDER BY Reseller__c]) {
	System.debug('XX ' + be.Reseller__c + ' ' + be.Name + ' = ' + be.FinSysInvoiceNumberMethod__c);
}
