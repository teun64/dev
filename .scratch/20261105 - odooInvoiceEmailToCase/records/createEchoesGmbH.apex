// Reseller 7 = Echoes GmbH: Business Entity + Administration, definition copied from the Germany records (reseller 5),
// without Exact / Stripe / PayProv / warehouse settings (no Exact sync, like France (echoes)). Legal + bank data from the
// Echoes GmbH invoice PDF (03251903). Idempotent: does nothing for a part that already exists (Reseller__c = '7').
// Run per org: sf apex run -o <org> -f createEchoesGmbH.apex   (prod only on explicit command)
Boolean DRY = false;
List<String> beCopy = new List<String>{ 'CurrencyIsoCode', 'Currency_Symbol__c', 'CustomerHub_URL__c', 'CustomerHub_Site_URL__c', 'Date_New_Branding__c', 'Email_Sales__c',
	'Invoice_EU_Remark__c', 'Invoice_General_Remark__c', 'Invoice_NonEU_Remark__c', 'Language_Default__c', 'Managing_directors__c',
	'Offer_Term_1__c', 'Offer_Term_2__c', 'Offer_Term_3__c', 'Offer_Term_4__c', 'Offer_Term_5__c', 'Offer_Term_6__c', 'Offer_Term_7__c',
	'Privacy_Policy_URL__c', 'Terms_Conditions_URL__c', 'Business_Hours_Shipping__c', 'Shipping_Cutoff_Time__c', 'Shipping_Free_Threshold__c', 'Shipping_Product__c',
	'Available_System_Platforms__c', 'Daily_Limit__c', 'CustomerHub_Opportunity_AutoProcess__c', 'DealerPortal_Opportunity_AutoProcess__c',
	'CustomerHub_Opportunity_SendConfirm__c', 'DealerPortal_Opportunity_SendConfirm__c' };
List<String> admCopy = new List<String>{ 'CurrencyIsoCode', 'Currency_Symbol__c', 'Subscription25__Active__c', 'Subscription25__Account_Synchronisation_Policy__c',
	'Subscription25__Accounting_Record_Type__c', 'Subscription25__ICP_Performance_Type__c', 'Subscription25__Send_Invoices_From__c',
	'Subscription25__Compress_Invoice_Number_Prefix__c', 'Subscription25__Invoice_Number_Length__c', 'Language_Default__c', 'Country_Code__c',
	'Subscription25__Billing_Country__c', 'Subscription25__Phone__c', 'Subscription25__Website__c', 'Subscription25__Billing_Email_Address__c',
	'Email_Sales__c', 'Managing_directors__c', 'Daily_Limit__c', 'Invoice_EU_Remark__c', 'Invoice_General_Remark__c', 'Invoice_NonEU_Remark__c',
	'Offer_Term_1__c', 'Offer_Term_2__c', 'Offer_Term_3__c', 'Offer_Term_4__c', 'Offer_Term_5__c', 'Offer_Term_6__c', 'Offer_Term_7__c',
	'Privacy_Policy_URL__c', 'Terms_Conditions_URL__c', 'CustomerHub_URL__c', 'CustomerHub_Site_URL__c', 'Date_New_Branding__c', 'Available_System_Platforms__c' };

Savepoint sp = Database.setSavepoint();
Map<String, Schema.SObjectField> beFields = Schema.SObjectType.Business_Entities__c.fields.getMap();
Map<String, Schema.SObjectField> admFields = Schema.SObjectType.Subscription25__Administration__c.fields.getMap();

// --- Business Entity
Id beId;
List<Business_Entities__c> existingBe = [SELECT Id FROM Business_Entities__c WHERE Reseller__c = '7'];
if (!existingBe.isEmpty()) {
	beId = existingBe[0].Id;
	System.debug('XX business entity exists ' + beId);
} else {
	List<String> beQuery = new List<String>{ 'Id' };
	for (String f : beCopy) { if (beFields.containsKey(f) && !beQuery.contains(f)) { beQuery.add(f); } }
	Business_Entities__c src = (Business_Entities__c) Database.query('SELECT ' + String.join(beQuery, ',') + ' FROM Business_Entities__c WHERE Reseller__c = \'5\' LIMIT 1');
	Business_Entities__c be = new Business_Entities__c(Name = 'Germany (echoes)', Reseller__c = '7', External_ID__c = 7);
	for (String f : beCopy) {
		if (beFields.containsKey(f) && beFields.get(f).getDescribe().isCreateable() && src.get(f) != null) { be.put(f, src.get(f)); }
	}
	Database.SaveResult r = Database.insert(be, false);
	System.debug('XX business entity ' + r.isSuccess() + ' ' + (r.isSuccess() ? '' : String.valueOf(r.getErrors())));
	if (!r.isSuccess()) { Database.rollback(sp); return; }
	beId = be.Id;
}

// --- Administration
List<Subscription25__Administration__c> existingAdm = [SELECT Id FROM Subscription25__Administration__c WHERE Reseller__c = '7'];
if (!existingAdm.isEmpty()) {
	System.debug('XX administration exists ' + existingAdm[0].Id);
} else {
	List<String> admQuery = new List<String>{ 'Id', 'VAT_Rate_Default__c' };
	for (String f : admCopy) { if (admFields.containsKey(f) && !admQuery.contains(f)) { admQuery.add(f); } }
	Subscription25__Administration__c src = (Subscription25__Administration__c) Database.query('SELECT ' + String.join(admQuery, ',') + ' FROM Subscription25__Administration__c WHERE Reseller__c = \'5\' LIMIT 1');
	Subscription25__Administration__c adm = new Subscription25__Administration__c(
		Name = 'Germany (echoes)', Reseller__c = '7', Business_Entity__c = beId, External_ID__c = 7,
		Subscription25__Billing_Name__c = 'Echoes GmbH',
		Subscription25__Billing_Street__c = 'Gubener Straße 47', Subscription25__Billing_Postal_Code__c = '10243', Subscription25__Billing_City__c = 'Berlin',
		Subscription25__Bank__c = 'Deutsche Bank', Subscription25__IBAN__c = 'DE24 5907 0070 0037 0098 00', Subscription25__BIC__c = 'DEUTDEDB595',
		Subscription25__VAT_Number__c = 'DE352676584', Subscription25__Chamber_Of_Commerce_Number__c = 'Berlin-Charlottenburg - HRB 280681B',
		Subscription25__Invoice_Number_Prefix__c = 'EG', Subscription25__Default__c = false
	);
	for (String f : admCopy) {
		if (admFields.containsKey(f) && admFields.get(f).getDescribe().isCreateable() && src.get(f) != null) { adm.put(f, src.get(f)); }
	}
	// VAT definition of Germany: same shared VAT rate records (DE high 19% / low 7%)
	adm.VAT_Rate_Default__c = src.VAT_Rate_Default__c;
	Database.SaveResult r = Database.insert(adm, false);
	System.debug('XX administration ' + r.isSuccess() + ' ' + (r.isSuccess() ? adm.Id : String.valueOf(r.getErrors())));
	if (!r.isSuccess()) { Database.rollback(sp); return; }
}
if (DRY) { Database.rollback(sp); System.debug('XX dry run, rolled back'); }
