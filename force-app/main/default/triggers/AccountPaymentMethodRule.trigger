trigger AccountPaymentMethodRule on Account (before insert, before update) {
	Util_PaymentMethodRule.validate(Trigger.new, Trigger.oldMap);
}
