trigger AccountContactRelation on AccountContactRelation (before delete) {
	Trigger_AccountContactRelation.run();
}
