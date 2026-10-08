trigger ContactFinancialSystem on Contact (before delete, after delete) {
	Trigger_ContactFinancialSystem.run();
}
