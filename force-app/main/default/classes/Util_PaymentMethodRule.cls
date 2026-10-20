/**
 * Allowed payment methods per reseller (Payment_Method_Rule__mdt), checked on the Account payment methods
 * (Payment_Method_Contracts__c / Payment_Method_Opportunities__c) before insert / update. Only a new or changed
 * payment method or reseller is checked, so an existing wrong combination never blocks an unrelated save.
 * A code without a rule is allowed everywhere. Requires_Payment_Provider__c: only when the reseller's business
 * entity uses the payment provider (Business_Entities__c.PayProv_Use__c), so a Stripe code goes live per entity
 * by switching that flag, without a deploy.
 */
public without sharing class Util_PaymentMethodRule {
	private static final List<SObjectField> CHECKED_FIELDS = new List<SObjectField>{
		Account.Payment_Method_Contracts__c, Account.Payment_Method_Opportunities__c
	};

	@TestVisible
	private static Map<String, Payment_Method_Rule__mdt> rulesByCode {
		get {
			if (rulesByCode == null) {
				rulesByCode = new Map<String, Payment_Method_Rule__mdt>();
				for (Payment_Method_Rule__mdt rule : Payment_Method_Rule__mdt.getAll().values()) {
					rulesByCode.put(rule.Payment_Method_Code__c, rule);
				}
			}
			return rulesByCode;
		}
		set;
	}

	@TestVisible
	private static Map<String, Boolean> providerByReseller {
		get {
			if (providerByReseller == null) {
				providerByReseller = new Map<String, Boolean>();
				for (Business_Entities__c entity : [SELECT Reseller__c, PayProv_Use__c FROM Business_Entities__c WITH SYSTEM_MODE]) {
					providerByReseller.put(String.valueOf(entity.Reseller__c), entity.PayProv_Use__c == true);
				}
			}
			return providerByReseller;
		}
		set;
	}

	/** Before insert / update of Accounts: adds an error to each payment method field that is not allowed. */
	public static void validate(List<Account> newAccounts, Map<Id, Account> oldMap) {
		for (Account acc : newAccounts) {
			Account old = oldMap?.get(acc.Id);
			Boolean resellerChanged = old == null || acc.Reseller_Name__c != old.Reseller_Name__c;
			for (SObjectField field : CHECKED_FIELDS) {
				String code = (String) acc.get(field);
				if (String.isBlank(code) || (!resellerChanged && code == (String) old.get(field))) {
					continue;
				}
				String error = Util_PaymentMethodRule.check(code, acc.Reseller_Name__c);
				if (error != null) {
					acc.addError(field, error);
				}
			}
		}
	}

	/** Null when the payment method is allowed for the reseller, else the reason. */
	public static String check(String code, String reseller) {
		Payment_Method_Rule__mdt rule = Util_PaymentMethodRule.rulesByCode.get(code);
		if (rule == null) {
			return null;
		}
		if (String.isNotBlank(rule.Allowed_Resellers__c)) {
			Set<String> allowed = new Set<String>();
			for (String value : rule.Allowed_Resellers__c.split(',')) {
				allowed.add(value.trim());
			}
			if (!allowed.contains(reseller)) {
				return 'Payment method ' + code + ' is not allowed for reseller ' + reseller + '.';
			}
		}
		if (rule.Requires_Payment_Provider__c && Util_PaymentMethodRule.providerByReseller.get(reseller) != true) {
			return 'Payment method ' + code + ' needs the payment provider, which is not active for reseller ' + reseller + '.';
		}
		return null;
	}
}
