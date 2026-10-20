@IsTest
private class Test_rbb_Payment_Type {

	// rbb_Payment fType: the route (Type__c) follows the payment method code; pi / pr explicitly, before the
	// first-letter rules; I + Stripe stays recurring until the Stripe I8 records are migrated to pr
	@IsTest
	static void typeFollowsPaymentMethod() {
		Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Account acc = Test_Data.createAccount('Payment Type BV', '9051', 'B2B', true);

		Map<String, Payment__c> byKey = new Map<String, Payment__c>();
		for (List<String> methodProcessor : new List<List<String>>{
			new List<String>{ 'pi', 'Stripe' }, new List<String>{ 'pr', 'Stripe' }, new List<String>{ 'p0', 'Mollie' },
			new List<String>{ 'I8', 'Stripe' }, new List<String>{ 'I8', 'Bank' }, new List<String>{ '08', 'None' },
			new List<String>{ 'C', 'None' }
		}) {
			byKey.put(methodProcessor[0] + '/' + methodProcessor[1], new Payment__c(
				Account__c = acc.Id, Administration__c = admin.Id, Method__c = methodProcessor[0],
				Processor__c = methodProcessor[1], Status__c = 'New', CurrencyIsoCode = 'EUR', Amount_Gross__c = 13.50,
				Request_Date__c = Date.today(), Due_Date__c = Date.today().addDays(10)));
		}

		Test.startTest();
		Database.insert(byKey.values(), AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		Map<Id, Payment__c> saved = new Map<Id, Payment__c>([SELECT Type__c FROM Payment__c WITH SYSTEM_MODE]);
		Map<String, String> expected = new Map<String, String>{
			'pi/Stripe' => 'psp-immediate', 'pr/Stripe' => 'psp-recurring', 'p0/Mollie' => 'psp-immediate',
			'I8/Stripe' => 'psp-recurring', 'I8/Bank' => 'fs-dd', '08/None' => 'fs-oa', 'C/None' => 'fs-cash'
		};
		for (String key : expected.keySet()) {
			System.assertEquals(expected.get(key), saved.get(byKey.get(key).Id).Type__c, key);
		}
	}
}
