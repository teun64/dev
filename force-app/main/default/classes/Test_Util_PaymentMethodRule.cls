@IsTest
private class Test_Util_PaymentMethodRule {

	private static Id fakeId(Integer n) {
		return Id.valueOf('001' + String.valueOf(n).leftPad(12, '0') + 'AAA');
	}

	private static void useProvider(Map<String, Boolean> byReseller) {
		Util_PaymentMethodRule.providerByReseller = byReseller;
	}

	@IsTest
	static void checkFollowsTheRules() {
		useProvider(new Map<String, Boolean>{ '1' => true, '5' => false, '6' => true });

		System.assertEquals(null, Util_PaymentMethodRule.check('I8', '1'), 'I8 allowed for NL');
		System.assertNotEquals(null, Util_PaymentMethodRule.check('I8', '6'), 'I8 blocked for UK');
		System.assertNotEquals(null, Util_PaymentMethodRule.check('I3', '6'), 'I3 blocked for UK');
		System.assertEquals(null, Util_PaymentMethodRule.check('I0', '6'), 'I0 allowed for UK');
		System.assertNotEquals(null, Util_PaymentMethodRule.check('I0', '1'), 'I0 is UK only');
		System.assertNotEquals(null, Util_PaymentMethodRule.check('GR', '1'), 'GR is Greece only');
		System.assertEquals(null, Util_PaymentMethodRule.check('08', '6'), 'On account allowed everywhere');
		System.assertEquals(null, Util_PaymentMethodRule.check('pr', '1'), 'pr allowed: NL uses the payment provider');
		System.assertEquals(null, Util_PaymentMethodRule.check('pi', '6'), 'pi allowed: UK uses the payment provider');
		System.assertNotEquals(null, Util_PaymentMethodRule.check('pr', '5'), 'pr blocked: DE does not use the payment provider');
		System.assertNotEquals(null, Util_PaymentMethodRule.check('pi', '2'), 'pi blocked: no business entity setting');
		System.assertEquals(null, Util_PaymentMethodRule.check('p0', '6'), 'No rule for p0: allowed');
	}

	@IsTest
	static void validateOnlyChecksNewOrChangedValues() {
		useProvider(new Map<String, Boolean>());
		Account unchanged = new Account(Id = fakeId(1), Reseller_Name__c = '6', Payment_Method_Contracts__c = 'I8', Payment_Method_Opportunities__c = '08');
		Account changed = new Account(Id = fakeId(2), Reseller_Name__c = '6', Payment_Method_Contracts__c = 'I8', Payment_Method_Opportunities__c = '08');
		Account resellerMoved = new Account(Id = fakeId(3), Reseller_Name__c = '6', Payment_Method_Contracts__c = '08', Payment_Method_Opportunities__c = 'I8');
		Map<Id, Account> oldMap = new Map<Id, Account>{
			unchanged.Id => new Account(Id = unchanged.Id, Reseller_Name__c = '6', Payment_Method_Contracts__c = 'I8', Payment_Method_Opportunities__c = '14'),
			changed.Id => new Account(Id = changed.Id, Reseller_Name__c = '6', Payment_Method_Contracts__c = 'I0', Payment_Method_Opportunities__c = '08'),
			resellerMoved.Id => new Account(Id = resellerMoved.Id, Reseller_Name__c = '1', Payment_Method_Contracts__c = '08', Payment_Method_Opportunities__c = 'I8')
		};

		Util_PaymentMethodRule.validate(new List<Account>{ unchanged, changed, resellerMoved }, oldMap);

		System.assertEquals(false, unchanged.hasErrors(), 'Existing wrong combination does not block an unrelated change: ' + unchanged.getErrors());
		System.assertEquals(true, changed.hasErrors(), 'Changed to I8 for UK');
		System.assertEquals(true, resellerMoved.hasErrors(), 'Reseller moved to UK with I8');
	}

	@IsTest
	static void triggerBlocksNotAllowedMethod() {
		Account acc = Test_Data.createAccount('Rule Test', (String) null, 'B2C', true);
		Database.update(new Account(Id = acc.Id, Reseller_Name__c = '1', Payment_Method_Contracts__c = 'I8'), AccessLevel.SYSTEM_MODE);

		Test.startTest();
		Database.SaveResult result = Database.update(new Account(Id = acc.Id, Payment_Method_Contracts__c = 'GR'), false, AccessLevel.SYSTEM_MODE);
		Test.stopTest();

		System.assertEquals(false, result.isSuccess(), 'GR is Greece only');
		System.assert(result.getErrors()[0].getMessage().contains('GR'), result.getErrors()[0].getMessage());
	}
}
