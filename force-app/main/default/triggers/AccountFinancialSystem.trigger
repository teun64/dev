trigger AccountFinancialSystem on Account (after insert, after update) {
	Trigger_AccountFinancialSystem.run();
}
