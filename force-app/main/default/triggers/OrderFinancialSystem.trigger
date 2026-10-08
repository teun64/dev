trigger OrderFinancialSystem on Order (after insert) {
	Trigger_OrderFinancialSystem.run();
}
