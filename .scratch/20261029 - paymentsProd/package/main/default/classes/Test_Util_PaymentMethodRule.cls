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

	@IsTest
	static void prLockBlocksBackToDirectDebitForUiUsers() {
		Database.insert(new Business_Entities__c(Name = 'NL Stripe', Reseller__c = '1', PayProv_Use__c = true), AccessLevel.SYSTEM_MODE);
		Profile sales = [SELECT Id FROM Profile WHERE Name = 'miSales' LIMIT 1];
		User seller = new User(ProfileId = sales.Id, LastName = 'Seller', Alias = 'prlock', Email = 'prlock@example.com',
			Username = 'prlock' + System.currentTimeMillis() + '@example.com', TimeZoneSidKey = 'Europe/Amsterdam',
			LocaleSidKey = 'nl_NL', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
		Database.insert(seller, AccessLevel.SYSTEM_MODE);
		Account acc = Test_Data.createAccount('Lock Test', (String) null, 'B2C', true);
		Database.update(new Account(Id = acc.Id, OwnerId = seller.Id, Reseller_Name__c = '1', Payment_Method_Contracts__c = 'pr'), AccessLevel.SYSTEM_MODE);

		Database.SaveResult blocked;
		Database.SaveResult toOnAccount;
		Test.startTest();
		System.runAs(seller) {
			blocked = Database.update(new Account(Id = acc.Id, Payment_Method_Contracts__c = 'I8'), false, AccessLevel.SYSTEM_MODE);
			toOnAccount = Database.update(new Account(Id = acc.Id, Payment_Method_Contracts__c = '08'), false, AccessLevel.SYSTEM_MODE);
		}
		Test.stopTest();

		System.assertEquals(false, blocked.isSuccess(), 'pr -> I8 blocked for a UI user');
		System.assert(blocked.getErrors()[0].getMessage().contains('pr'), blocked.getErrors()[0].getMessage());
		System.assertEquals(true, toOnAccount.isSuccess(), 'pr -> 08 is not an I-code: allowed ' + toOnAccount.getErrors());
	}

	@IsTest
	static void prLockAllowsFinancePermission() {
		Database.insert(new Business_Entities__c(Name = 'NL Stripe', Reseller__c = '1', PayProv_Use__c = true), AccessLevel.SYSTEM_MODE);
		Profile sales = [SELECT Id FROM Profile WHERE Name = 'miSales' LIMIT 1];
		User finance = new User(ProfileId = sales.Id, LastName = 'Finance', Alias = 'prfin', Email = 'prfin@example.com',
			Username = 'prfin' + System.currentTimeMillis() + '@example.com', TimeZoneSidKey = 'Europe/Amsterdam',
			LocaleSidKey = 'nl_NL', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
		Database.insert(finance, AccessLevel.SYSTEM_MODE);
		PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'ps_miAccountPaymentMethod_Change' LIMIT 1];
		System.runAs(new User(Id = UserInfo.getUserId())) {
			Database.insert(new PermissionSetAssignment(AssigneeId = finance.Id, PermissionSetId = ps.Id), AccessLevel.SYSTEM_MODE);
		}
		Account acc = Test_Data.createAccount('Lock Test', (String) null, 'B2C', true);
		Database.update(new Account(Id = acc.Id, OwnerId = finance.Id, Reseller_Name__c = '1', Payment_Method_Contracts__c = 'pr'), AccessLevel.SYSTEM_MODE);

		Database.SaveResult result;
		Test.startTest();
		System.runAs(finance) {
			result = Database.update(new Account(Id = acc.Id, Payment_Method_Contracts__c = 'I8'), false, AccessLevel.SYSTEM_MODE);
		}
		Test.stopTest();

		System.assertEquals(true, result.isSuccess(), 'cp_AccountPaymentMethod_Change may go back to I8: ' + result.getErrors());
	}

	@IsTest
	static void contractsRejectOneOffAndCreditCodes() {
		Util_PaymentMethodRule.mayOverrule = false;
		System.assertNotEquals(null, Util_PaymentMethodRule.checkContracts('p1'), 'p1 is one-off');
		System.assertNotEquals(null, Util_PaymentMethodRule.checkContracts('pi'), 'pi is one-off');
		System.assertNotEquals(null, Util_PaymentMethodRule.checkContracts('C'), 'C is for credits only');
		System.assertEquals(null, Util_PaymentMethodRule.checkContracts('pr'), 'pr allowed on contracts');

		useProvider(new Map<String, Boolean>{ '6' => true });
		Account contracts = new Account(Id = fakeId(4), Reseller_Name__c = '6', Payment_Method_Contracts__c = 'p1', Payment_Method_Opportunities__c = 'p1');
		Map<Id, Account> oldMap = new Map<Id, Account>{
			contracts.Id => new Account(Id = contracts.Id, Reseller_Name__c = '6', Payment_Method_Contracts__c = '08', Payment_Method_Opportunities__c = '08')
		};
		Util_PaymentMethodRule.validate(new List<Account>{ contracts }, oldMap);

		System.assertEquals(1, contracts.getErrors().size(), 'Only the contract method fails, p1 stays allowed for opportunities: ' + contracts.getErrors());
	}

	@IsTest
	static void contractsAllowCreditCodeForFinance() {
		Util_PaymentMethodRule.mayOverrule = true;
		System.assertEquals(null, Util_PaymentMethodRule.checkContracts('C'), 'C allowed for Finance / admins (free internal subscriptions)');
		System.assertNotEquals(null, Util_PaymentMethodRule.checkContracts('p1'), 'p1 never on contracts, also not for Finance');
		System.assertNotEquals(null, Util_PaymentMethodRule.checkContracts('pi'), 'pi never on contracts, also not for Finance');
	}
}
